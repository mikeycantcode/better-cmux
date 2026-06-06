import Foundation

/// Reads the terminal-editor preference used by the sidebar "open file" action
/// and the bottom-bar editor indicator.
///
/// Stored as a single command string under ``key``. An empty/unset value means
/// "auto": prefer `micro` if it is on `PATH`, else `vim`. A non-empty value is
/// used verbatim as the editor command. This is intentionally separate from
/// `app.preferredEditor` (the GUI/preview fallback editor).
enum EditorPreferenceSettings {
    /// The `UserDefaults` key backing the terminal-editor command.
    static let key = "terminalEditor"

    /// The stored editor command, or `nil` when unset/empty (→ auto).
    /// - Parameter defaults: the store to read (injected for tests).
    static func storedCommand(defaults: UserDefaults = .standard) -> String? {
        guard let raw = defaults.string(forKey: key) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
