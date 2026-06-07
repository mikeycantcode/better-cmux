import Foundation

/// Reads the `codeEditor` preference (which editor opens files from the sidebar).
///
/// Mirrors ``EditorPreferenceSettings``: the value is stored under a `UserDefaults`
/// key (also written from `cmux.json` via `KeyboardShortcutSettingsFileStore`).
/// Unset or unrecognized values resolve to ``CodeEditorChoice/monaco``.
enum CodeEditorPreferenceSettings {
    /// The `UserDefaults` key backing the preference.
    static let key = "codeEditor"

    /// Resolves the configured editor choice, defaulting to ``CodeEditorChoice/monaco``.
    static func resolved(defaults: UserDefaults = .standard) -> CodeEditorChoice {
        guard let raw = defaults.string(forKey: key), let choice = CodeEditorChoice(rawValue: raw) else {
            return .monaco
        }
        return choice
    }
}
