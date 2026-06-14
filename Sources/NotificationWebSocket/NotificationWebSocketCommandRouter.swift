import Foundation

/// Routes a parsed ``NotificationWebSocketCommand`` to the app's existing
/// notification and focus handlers, returning a JSON-safe reply object.
///
/// The router holds no state of its own: it resolves the live
/// `TerminalNotificationStore` and `TabManager` from `AppDelegate.shared` at
/// call time, mirroring how `Workspace` reaches the notification store
/// (`AppDelegate.shared?.notificationStore`). All work runs on the main actor
/// because the notification store and tab manager are main-actor state.
///
/// Replies follow a small, stable envelope:
///
/// ```json
/// {"kind":"ack","type":"mark_read"}
/// {"kind":"error","message":"invalid notification id"}
/// ```
@MainActor
final class NotificationWebSocketCommandRouter {
    /// Creates a router. The router is composition-root constructed (one per
    /// connection) and carries no configuration.
    init() {}

    /// Handles a parsed command and returns the reply envelope.
    ///
    /// - Parameter command: The inbound command to apply.
    /// - Returns: An `ack` envelope on success, or an `error` envelope when a
    ///   required dependency is missing, an id is malformed, or the action is
    ///   not supported.
    func handle(_ command: NotificationWebSocketCommand) -> [String: Any] {
        switch command {
        case let .markRead(id):
            guard let uuid = UUID(uuidString: id) else {
                return Self.error("invalid notification id")
            }
            guard let store = Self.notificationStore else {
                return Self.error("notification store unavailable")
            }
            store.markRead(id: uuid)
            return Self.ack("mark_read")

        case let .markReadSurface(tabId, surfaceId):
            guard let tabUUID = UUID(uuidString: tabId) else {
                return Self.error("invalid tab id")
            }
            let surfaceUUID: UUID?
            if let surfaceId {
                guard let parsed = UUID(uuidString: surfaceId) else {
                    return Self.error("invalid surface id")
                }
                surfaceUUID = parsed
            } else {
                surfaceUUID = nil
            }
            guard let store = Self.notificationStore else {
                return Self.error("notification store unavailable")
            }
            store.markRead(forTabId: tabUUID, surfaceId: surfaceUUID)
            return Self.ack("mark_read")

        case .markAllRead:
            guard let store = Self.notificationStore else {
                return Self.error("notification store unavailable")
            }
            store.markAllRead()
            return Self.ack("mark_all_read")

        case let .clear(id):
            guard let store = Self.notificationStore else {
                return Self.error("notification store unavailable")
            }
            guard id == nil else {
                // There is no single-notification clear primitive — clearing by a
                // resolved tab/surface scope would also wipe sibling notifications
                // on that surface (silent data loss). Reject single-id clear and
                // point callers at `mark_read` for dismissing one notification.
                return Self.error("clear by id is not supported; use mark_read with the id to dismiss a single notification, or clear with no id to clear all")
            }
            store.clearAll()
            return Self.ack("clear")

        case let .focus(surfaceId, paneId):
            return Self.focus(surfaceId: surfaceId, paneId: paneId)
        }
    }

    /// Parses raw frame text, handles the resulting command, and serializes the
    /// reply to UTF-8 JSON `Data`.
    ///
    /// - Parameter text: The raw inbound WebSocket text frame.
    /// - Returns: The serialized reply, or `nil` if the reply could not be
    ///   encoded (which should not happen for the small JSON-safe envelopes).
    func handle(text: String) -> Data? {
        let reply: [String: Any]
        switch NotificationWebSocketCommand.parse(text: text) {
        case let .success(command):
            reply = handle(command)
        case let .failure(error):
            switch error {
            case .invalidJSON:
                reply = Self.error("invalid JSON")
            case .unrecognized:
                reply = Self.error("unrecognized command")
            }
        }
        guard JSONSerialization.isValidJSONObject(reply) else { return nil }
        return try? JSONSerialization.data(withJSONObject: reply)
    }

    /// The live notification store, resolved from the app delegate.
    private static var notificationStore: TerminalNotificationStore? {
        AppDelegate.shared?.notificationStore
    }

    /// Focuses the given surface and/or pane on the selected tab WITHOUT
    /// activating the app or raising a window, matching the socket focus policy.
    ///
    /// Uses `TabManager.focusSurface(tabId:surfaceId:)`, the same non-activating
    /// selection path the `surface.focus` socket command uses. Both `surfaceId`
    /// and `paneId` are resolved as surface-or-panel ids on the selected tab.
    private static func focus(surfaceId: String?, paneId: String?) -> [String: Any] {
        guard let tabManager = AppDelegate.shared?.tabManager else {
            return error("tab manager unavailable")
        }
        guard let tabId = tabManager.selectedTabId else {
            return error("no selected tab")
        }
        // Prefer the explicit surface id; fall back to the pane id. Both resolve
        // through the same surface-or-panel lookup inside `focusSurface`.
        let target = surfaceId ?? paneId
        guard let target, let targetUUID = UUID(uuidString: target) else {
            return error("invalid focus target")
        }
        tabManager.focusSurface(tabId: tabId, surfaceId: targetUUID)
        return ack("focus")
    }

    /// Builds an `ack` reply envelope for a command `type`.
    private static func ack(_ type: String) -> [String: Any] {
        ["kind": "ack", "type": type]
    }

    /// Builds an `error` reply envelope carrying a human-readable `message`.
    private static func error(_ message: String) -> [String: Any] {
        ["kind": "error", "message": message]
    }
}
