/// The original-vs-proposed text pair to render in a two-pane diff.
///
/// `languageId` is intentionally absent: the app maps `filePath` to a Monaco language at render
/// time via its existing `MonacoLanguageMap`, keeping this package free of presentation concerns.
public struct EditDiff: Equatable, Sendable {
    /// Absolute path of the edited file (used by the app for the title and language id).
    public let filePath: String
    /// The file's current on-disk text (empty when creating a new file).
    public let originalText: String
    /// The text the file would have after the edit is applied.
    public let modifiedText: String
    /// Whether the file does not yet exist (the original side is empty).
    public let isNewFile: Bool

    /// Creates a diff pair.
    public init(filePath: String, originalText: String, modifiedText: String, isNewFile: Bool) {
        self.filePath = filePath
        self.originalText = originalText
        self.modifiedText = modifiedText
        self.isNewFile = isNewFile
    }
}
