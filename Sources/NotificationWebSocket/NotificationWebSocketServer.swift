import Foundation
@preconcurrency import Network
import OSLog

private let notificationWebSocketServerLog = Logger(subsystem: "dev.cmux", category: "notification-websocket")

/// A loopback-only WebSocket server that streams ``CmuxEventBus`` events to
/// local clients and routes inbound action commands back into the app.
///
/// The server is **loopback-only** and has **no authentication**: while
/// ``NotificationWebSocketSettings/isEnabled(defaults:)`` is `true`, any local
/// process can read notifications and send actions. It mirrors
/// `MobileHostService`'s `Network` patterns: a dedicated serial callback queue,
/// an `NWParameters(tls:nil, tcp:)` stack restricted to loopback, and a pure
/// reconciliation decision (`MobileHostService.syncDecision`) for
/// ``syncToSettings()``.
///
/// Construct it once at the app's composition root and inject it; there is no
/// shared singleton.
///
/// ```swift
/// let server = NotificationWebSocketServer()
/// server.start()
/// ```
@MainActor
final class NotificationWebSocketServer {
    private let callbackQueue = DispatchQueue(label: "dev.cmux.notification-websocket-listener")
    private let defaults: UserDefaults
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NotificationWebSocketConnection] = [:]
    private var listenerPort: Int?
    /// The preferred port the running listener targeted, used to decide whether a
    /// settings change needs a restart. `nil` while stopped.
    private var appliedPort: Int?
    /// Upper bound on concurrently-accepted connections (mirrors
    /// `MobileHostService`). Bounds the resource cost of abandoned/half-open
    /// loopback peers since there is no authentication gate.
    private let maximumActiveConnectionCount = 16

    /// The port the listener is currently bound to, for diagnostics. `nil` while
    /// stopped or before the listener reaches `.ready`.
    var boundPort: Int? { listenerPort }

    /// Creates a server.
    ///
    /// - Parameter defaults: The defaults suite the server reads its enabled
    ///   state and port from. Defaults to `.standard`; tests inject a scoped
    ///   suite.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Starts the listener if it is enabled in settings and not already running.
    ///
    /// On a bind failure (e.g. the port is in use) the server logs and stops; it
    /// does **not** fall back to a random ephemeral port, so the loopback port
    /// stays predictable for v1 clients.
    func start() {
        guard NotificationWebSocketSettings.isEnabled(defaults: defaults) else {
            notificationWebSocketServerLog.info("notification websocket disabled; not binding")
            return
        }
        guard listener == nil else { return }

        let port = NotificationWebSocketSettings.port(defaults: defaults)
        guard let endpointPort = NWEndpoint.Port(rawValue: UInt16(port)) else {
            notificationWebSocketServerLog.error("notification websocket port \(port) is out of range; not binding")
            return
        }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        // Detect silently-dead/half-open peers so the connection transitions to
        // `.failed` and its `cancel()` runs (tearing down the bus subscription +
        // drain task). Without this, an abandoned peer would leak both forever.
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 30
        tcpOptions.keepaliveInterval = 10
        tcpOptions.keepaliveCount = 3
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        // Bind loopback only so the listener never accepts off-host peers; the
        // per-connection check below is defense in depth.
        parameters.requiredInterfaceType = .loopback
        let webSocketOptions = NWProtocolWebSocket.Options()
        webSocketOptions.autoReplyPing = true
        // Inbound command frames are tiny; cap inbound message size so a local
        // client cannot force a large per-message buffer.
        webSocketOptions.maximumMessageSize = 64 * 1024
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocketOptions, at: 0)

        let nextListener: NWListener
        do {
            nextListener = try NWListener(using: parameters, on: endpointPort)
        } catch {
            notificationWebSocketServerLog.error("notification websocket failed to create listener on port \(port): \(String(describing: error), privacy: .public)")
            return
        }

        appliedPort = port
        nextListener.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleListenerState(state, port: port)
            }
        }
        nextListener.newConnectionHandler = { [weak self] connection in
            Task { @MainActor in
                self?.accept(connection)
            }
        }
        listener = nextListener
        nextListener.start(queue: callbackQueue)
    }

    private func handleListenerState(_ state: NWListener.State, port: Int) {
        switch state {
        case .ready:
            listenerPort = port
            notificationWebSocketServerLog.info("notification websocket listening on loopback port \(port)")
        case let .failed(error):
            notificationWebSocketServerLog.error("notification websocket listener failed on port \(port): \(String(describing: error), privacy: .public)")
            // Predictable port for v1: do not rebind on an ephemeral port; stop.
            stop()
        case let .waiting(error):
            if MobileHostService.isAddressUnavailable(error) {
                notificationWebSocketServerLog.error("notification websocket port \(port) unavailable: \(String(describing: error), privacy: .public); stopping")
                stop()
            }
        default:
            break
        }
    }

    private func accept(_ connection: NWConnection) {
        guard listener != nil else {
            connection.cancel()
            return
        }
        // Loopback enforcement: reject any peer that is not on the loopback
        // interface, reusing MobileHostService's address classifier.
        guard MobileHostService.isLoopbackConnection(connection) else {
            notificationWebSocketServerLog.error("notification websocket rejected non-loopback connection")
            connection.cancel()
            return
        }
        guard connections.count < maximumActiveConnectionCount else {
            notificationWebSocketServerLog.error("notification websocket at connection cap (\(self.maximumActiveConnectionCount)); rejecting")
            connection.cancel()
            return
        }
        let wrapped = NotificationWebSocketConnection(
            connection: connection,
            queue: callbackQueue,
            server: self
        )
        connections[wrapped.identifier] = wrapped
        wrapped.start()
    }

    /// Deregisters a connection that has closed. Called by the connection on
    /// close; safe to call for an unknown connection.
    func remove(_ connection: NotificationWebSocketConnection) {
        connections.removeValue(forKey: connection.identifier)
    }

    /// Stops the listener and tears down every active connection.
    ///
    /// Idempotent: safe to call when already stopped.
    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        listenerPort = nil
        appliedPort = nil
        let active = Array(connections.values)
        connections.removeAll()
        for connection in active {
            connection.cancel()
        }
    }

    /// Reconciles the live listener with the current settings.
    ///
    /// Reuses `MobileHostService.syncDecision` so the enable/disable and
    /// restart-on-port-change logic stays a single, unit-tested pure function:
    /// disabled → stop; enabled and not running → start; enabled and the
    /// configured port changed → restart; otherwise no-op.
    func syncToSettings() {
        let enabled = NotificationWebSocketSettings.isEnabled(defaults: defaults)
        let desiredPort = NotificationWebSocketSettings.port(defaults: defaults)
        switch MobileHostService.syncDecision(
            enabled: enabled,
            listenerRunning: listener != nil,
            desiredPort: desiredPort,
            appliedPort: appliedPort
        ) {
        case .noop:
            break
        case .start:
            start()
        case .stop:
            stop()
        case .restart:
            stop()
            start()
        }
    }
}
