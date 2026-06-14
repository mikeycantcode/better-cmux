import Foundation
@preconcurrency import Network
import OSLog

private let notificationWebSocketLog = Logger(subsystem: "dev.cmux", category: "notification-websocket")

/// A single accepted loopback WebSocket connection.
///
/// On `.ready` it sends a `hello` frame, opens a ``CmuxEventBus`` subscription,
/// and drains that subscription on a background `Task`, forwarding every event
/// as a WebSocket text frame. Inbound text frames are parsed into
/// ``NotificationWebSocketCommand`` values and routed through
/// ``NotificationWebSocketCommandRouter``; the reply (ack/error) is sent back as
/// a text frame.
///
/// The per-connection bus subscription is torn down on ``cancel()`` so a closed
/// connection cannot leak a subscription or apply backpressure to the bus.
@MainActor
final class NotificationWebSocketConnection {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private weak var server: NotificationWebSocketServer?
    private let router = NotificationWebSocketCommandRouter()
    private var drainTask: Task<Void, Never>?
    private var isClosed = false

    /// Stable identity used as the server registry key.
    var identifier: ObjectIdentifier { ObjectIdentifier(self) }

    /// Creates a connection wrapper.
    ///
    /// - Parameters:
    ///   - connection: The accepted `NWConnection` (already verified loopback).
    ///   - queue: The serial queue the listener uses; all NW callbacks run here.
    ///   - server: The owning server, used to deregister on close.
    init(connection: NWConnection, queue: DispatchQueue, server: NotificationWebSocketServer) {
        self.connection = connection
        self.queue = queue
        self.server = server
    }

    /// Starts the connection: wires the state handler and begins the NW state
    /// machine. The `hello` frame, subscription drain, and receive loop start
    /// once the connection reaches `.ready`.
    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleState(state)
            }
        }
        connection.start(queue: queue)
    }

    private func handleState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            onReady()
        case let .failed(error):
            notificationWebSocketLog.error("notification websocket connection failed: \(String(describing: error), privacy: .public)")
            cancel()
        case .cancelled:
            cancel()
        default:
            break
        }
    }

    private func onReady() {
        guard !isClosed else { return }
        sendHello()
        startEventDrain()
        receiveNext()
    }

    private func sendHello() {
        guard let data = NotificationWebSocketEventFrame.helloData(
            protocolName: CmuxEventBus.protocolName,
            version: CmuxEventBus.protocolVersion,
            latestSequence: CmuxEventBus.shared.latestSequence
        ) else { return }
        send(text: data)
    }

    /// The event categories this server streams. Scoped to notifications, agent
    /// state, and report events (git branch / PR / ports / pwd / shell state) —
    /// deliberately NOT the whole bus, so the unauthenticated loopback endpoint
    /// does not leak browser URLs, workspace cwds, etc.
    private static let streamedCategories: Set<String> = ["notification", "agent", "report"]

    /// Opens a bus subscription scoped to ``streamedCategories`` and drains it on
    /// a background task, sending each event as a text frame.
    private func startEventDrain() {
        // `afterSequence: nil` means the subscription delivers from the latest
        // sequence onward (no historical replay), matching the `hello` frame's
        // `latest_sequence`. Categories are filtered to the streamed set.
        let snapshot = CmuxEventBus.shared.subscribe(
            afterSequence: nil,
            names: [],
            categories: Self.streamedCategories
        )
        let subscription = snapshot.subscription

        drainTask = Task.detached(priority: .utility) { [weak self] in
            // The bus subscription uses a blocking semaphore (`next(timeout:)`),
            // so it is drained off the main actor on a detached task. The task is
            // cancelled and the subscription unsubscribed in `cancel()`.
            defer { CmuxEventBus.shared.unsubscribe(subscription) }
            while !Task.isCancelled {
                if subscription.isClosed { return }
                guard let event = subscription.next(timeout: 1.0) else {
                    // Timeout with no event, or the subscription closed; loop to
                    // re-check cancellation/closed state.
                    if subscription.isClosed { return }
                    continue
                }
                guard let data = NotificationWebSocketEventFrame.jsonData(forEvent: event) else { continue }
                await self?.send(text: data)
            }
        }
    }

    /// Arms a single inbound receive; re-arms itself after each text frame.
    private func receiveNext() {
        guard !isClosed else { return }
        connection.receiveMessage { [weak self] data, context, isComplete, error in
            Task { @MainActor in
                self?.handleReceive(data: data, context: context, isComplete: isComplete, error: error)
            }
        }
    }

    private func handleReceive(
        data: Data?,
        context: NWConnection.ContentContext?,
        isComplete: Bool,
        error: NWError?
    ) {
        if let error {
            notificationWebSocketLog.error("notification websocket receive error: \(String(describing: error), privacy: .public)")
            cancel()
            return
        }

        // A peer close frame, or a complete message with no payload, ends the
        // connection.
        if Self.isCloseMessage(context) || (isComplete && data == nil) {
            cancel()
            return
        }

        if let data, !data.isEmpty, Self.isTextMessage(context) {
            if let text = String(data: data, encoding: .utf8),
               let reply = router.handle(text: text) {
                send(text: reply)
            }
        }

        receiveNext()
    }

    /// Sends `data` as a WebSocket text frame on the connection queue.
    private func send(text data: Data) {
        guard !isClosed else { return }
        let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "send", metadata: [metadata])
        connection.send(
            content: data,
            contentContext: context,
            isComplete: true,
            completion: .contentProcessed { _ in }
        )
    }

    /// Whether the received message's WebSocket metadata marks it as a text frame.
    private static func isTextMessage(_ context: NWConnection.ContentContext?) -> Bool {
        webSocketMetadata(context)?.opcode == .text
    }

    /// Whether the received message is a WebSocket close frame.
    private static func isCloseMessage(_ context: NWConnection.ContentContext?) -> Bool {
        webSocketMetadata(context)?.opcode == .close
    }

    /// Extracts the WebSocket protocol metadata from a receive context, if any.
    private static func webSocketMetadata(_ context: NWConnection.ContentContext?) -> NWProtocolWebSocket.Metadata? {
        context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
    }

    /// Tears down the connection: cancels the drain task (which unsubscribes the
    /// bus subscription), cancels the NW connection, and deregisters from the
    /// server. Idempotent.
    func cancel() {
        guard !isClosed else { return }
        isClosed = true
        drainTask?.cancel()
        drainTask = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        server?.remove(self)
    }
}
