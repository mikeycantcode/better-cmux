/// One `old_string` → `new_string` replacement, as proposed by a Claude `Edit`/`MultiEdit` tool call.
public struct SingleEdit: Equatable, Sendable {
    /// The text to find in the file.
    public let oldString: String
    /// The text to replace it with.
    public let newString: String
    /// Whether every occurrence is replaced (Claude's `replace_all`); when `false`, only the first.
    public let replaceAll: Bool

    /// Creates a single replacement.
    public init(oldString: String, newString: String, replaceAll: Bool) {
        self.oldString = oldString
        self.newString = newString
        self.replaceAll = replaceAll
    }
}
