import Foundation

/// Reads the "compact sidebar rows" preference (one-line workspace rows).
///
/// Mirrors ``SidebarWorkspaceDetailSettings`` — a stateless reader over an
/// injected `UserDefaults` so it is testable without touching
/// `UserDefaults.standard`. Defaults to `true`: compact rows are the default
/// presentation; users opt back into the detailed multi-line row.
enum SidebarCompactRowModeSettings {
    /// The `UserDefaults` key backing the compact-row preference.
    static let key = "sidebarCompactRowMode"
    /// The value used when the key has never been written.
    static let defaultValue = true

    /// Whether compact one-line rows are enabled.
    /// - Parameter defaults: the store to read (injected for tests).
    /// - Returns: `true` when compact rows should render.
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }
}
