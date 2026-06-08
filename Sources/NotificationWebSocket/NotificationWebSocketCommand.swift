import Foundation

/// An inbound action command parsed from a WebSocket text frame.
///
/// Parsing is pure (no app state), so it is unit-tested without a live
/// connection. ``NotificationWebSocketCommandRouter`` maps a parsed command to
/// the existing notification/focus handlers.
enum NotificationWebSocketCommand: Equatable, Sendable {
    /// Mark a single notification read by its id.
    case markRead(id: String)
    /// Mark notifications read for a tab, optionally scoped to one surface.
    case markReadSurface(tabId: String, surfaceId: String?)
    /// Mark every notification read.
    case markAllRead
    /// Clear all notifications when `id` is `nil`. A non-nil `id` is parsed but
    /// rejected by the router (no single-notification clear primitive exists —
    /// use ``markRead(id:)`` to dismiss one notification).
    case clear(id: String?)
    /// Focus a surface and/or pane WITHOUT activating the app (focus policy).
    case focus(surfaceId: String?, paneId: String?)

    /// Parses a decoded JSON object into a command, or `nil` when the `type` is
    /// unknown or required fields are missing.
    init?(json: [String: Any]) {
        guard let type = json["type"] as? String else { return nil }
        switch type {
        case "mark_read":
            if let id = json["id"] as? String, !id.isEmpty {
                self = .markRead(id: id)
            } else if let tabId = json["tabId"] as? String, !tabId.isEmpty {
                self = .markReadSurface(tabId: tabId, surfaceId: json["surfaceId"] as? String)
            } else {
                return nil
            }
        case "mark_all_read":
            self = .markAllRead
        case "clear":
            self = .clear(id: json["id"] as? String)
        case "focus":
            let surfaceId = json["surfaceId"] as? String
            let paneId = json["paneId"] as? String
            guard surfaceId != nil || paneId != nil else { return nil }
            self = .focus(surfaceId: surfaceId, paneId: paneId)
        default:
            return nil
        }
    }

    /// Parses raw frame text (`{"type":…}`) into a command.
    /// - Returns: the parsed command, or a ``NotificationWebSocketCommandError``.
    static func parse(text: String) -> Result<NotificationWebSocketCommand, NotificationWebSocketCommandError> {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            return .failure(.invalidJSON)
        }
        guard let command = NotificationWebSocketCommand(json: json) else {
            return .failure(.unrecognized)
        }
        return .success(command)
    }
}

/// Errors from parsing an inbound WebSocket command frame. Small helper bound to
/// ``NotificationWebSocketCommand/parse(text:)``.
enum NotificationWebSocketCommandError: Error, Equatable {
    /// The frame was not a JSON object.
    case invalidJSON
    /// The frame was valid JSON but not a recognized command.
    case unrecognized
}
