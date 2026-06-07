import Foundation

/// Which editor opens when a file is opened from the sidebar / preview path.
enum CodeEditorChoice: String, Sendable, CaseIterable {
    /// The built-in Monaco web editor (default).
    case monaco
    /// A terminal editor (micro → vim, or a custom command) launched in a new tab.
    case terminal
}
