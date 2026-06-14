import Foundation

/// Settings under the dotted-id prefix `notifications.*`.
public struct NotificationsCatalogSection: SettingCatalogSection {
    public let dockBadge = DefaultsKey<Bool>(
        id: "notifications.dockBadge",
        defaultValue: true,
        userDefaultsKey: "notificationDockBadgeEnabled"
    )

    public let showInMenuBar = DefaultsKey<Bool>(
        id: "notifications.showInMenuBar",
        defaultValue: true,
        userDefaultsKey: "showMenuBarExtra"
    )

    public let unreadPaneRing = DefaultsKey<Bool>(
        id: "notifications.unreadPaneRing",
        defaultValue: true,
        userDefaultsKey: "notificationPaneRingEnabled"
    )

    public let paneFlash = DefaultsKey<Bool>(
        id: "notifications.paneFlash",
        defaultValue: true,
        userDefaultsKey: "notificationPaneFlashEnabled"
    )

    public let sound = DefaultsKey<String>(
        id: "notifications.sound",
        defaultValue: "default",
        userDefaultsKey: "notificationSound"
    )

    public let customSoundFilePath = DefaultsKey<String>(
        id: "notifications.customSoundFilePath",
        defaultValue: "",
        userDefaultsKey: "notificationSoundCustomFilePath"
    )

    public let command = DefaultsKey<String>(
        id: "notifications.command",
        defaultValue: "",
        userDefaultsKey: "notificationCustomCommand"
    )

    public let hooks = JSONKey<[String: String]>(
        id: "notifications.hooks",
        defaultValue: [:]
    )

    public let hooksMode = JSONKey<String>(
        id: "notifications.hooksMode",
        defaultValue: "merge"
    )

    /// Whether the loopback notification WebSocket server is enabled.
    ///
    /// When `true`, cmux runs a loopback-only WebSocket server (see the
    /// `NotificationWebSocket` module) that exposes notifications and accepts
    /// actions. The server has **no authentication**, so any local process can
    /// read notifications and send actions while it is enabled.
    public let webSocketEnabled = DefaultsKey<Bool>(
        id: "notifications.webSocket.enabled",
        defaultValue: false,
        userDefaultsKey: "notifications.webSocket.enabled"
    )

    /// The loopback TCP port the notification WebSocket server listens on.
    ///
    /// Only meaningful when ``webSocketEnabled`` is `true`. Valid values are in
    /// the range `1...65535`; out-of-range values are clamped to the default
    /// by the server reader.
    public let webSocketPort = DefaultsKey<Int>(
        id: "notifications.webSocket.port",
        defaultValue: 51763,
        userDefaultsKey: "notifications.webSocket.port"
    )

    public init() {}
}
