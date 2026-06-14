import Foundation

/// Reads the loopback notification WebSocket server settings from `UserDefaults`.
///
/// The server (built in later tasks) is loopback-only and has **no
/// authentication**: while ``isEnabled(defaults:)`` is `true`, any local
/// process can read notifications and send actions. Mirrors the style of the
/// existing notification settings readers such as `MenuBarExtraSettings` and
/// `NotificationBadgeSettings`.
enum NotificationWebSocketSettings {
    /// The `UserDefaults` key backing `notifications.webSocket.enabled`.
    static let enabledKey = "notifications.webSocket.enabled"
    /// The `UserDefaults` key backing `notifications.webSocket.port`.
    static let portKey = "notifications.webSocket.port"

    /// Whether the WebSocket server is enabled. Defaults to `false`.
    static let defaultEnabled = false
    /// The default loopback port used when none is set or the stored value is out of range.
    static let defaultPort = 51763

    /// Whether the loopback notification WebSocket server is enabled.
    ///
    /// - Parameter defaults: The defaults suite to read from.
    /// - Returns: The stored value, or ``defaultEnabled`` when unset.
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: enabledKey) == nil {
            return defaultEnabled
        }
        return defaults.bool(forKey: enabledKey)
    }

    /// The loopback TCP port the WebSocket server listens on.
    ///
    /// - Parameter defaults: The defaults suite to read from.
    /// - Returns: The stored port when it is in the range `1...65535`;
    ///   otherwise ``defaultPort``.
    static func port(defaults: UserDefaults = .standard) -> Int {
        if defaults.object(forKey: portKey) == nil {
            return defaultPort
        }
        let value = defaults.integer(forKey: portKey)
        guard value >= 1, value <= 65535 else {
            return defaultPort
        }
        return value
    }
}
