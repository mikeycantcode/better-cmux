import Foundation

/// Turns a ``ProposedEdit`` plus the file's current text into an ``EditDiff``.
///
/// Returns `nil` ("not applicable") when the edit cannot be represented as a clean before/after —
/// e.g. an `Edit`/`MultiEdit` whose `old_string` is absent from the original, or an `Edit` on a
/// file that does not exist. Callers fall back to the raw permission UI in that case.
///
/// ```swift
/// let computer = EditPreviewComputer()
/// if let diff = computer.compute(edit, originalText: onDiskText) {
///     // render diff.originalText vs diff.modifiedText
/// }
/// ```
public struct EditPreviewComputer: Sendable {
    /// Creates a computer. Stateless; cheap to make per call.
    public init() {}

    /// Computes the before/after pair, or `nil` when the edit is not cleanly applicable.
    ///
    /// - Parameters:
    ///   - edit: The parsed proposed edit.
    ///   - originalText: The file's current on-disk text, or `nil` if the file does not exist.
    /// - Returns: An ``EditDiff``, or `nil` when not applicable.
    public func compute(_ edit: ProposedEdit, originalText: String?) -> EditDiff? {
        switch edit.kind {
        case let .write(content):
            return EditDiff(filePath: edit.filePath,
                            originalText: originalText ?? "",
                            modifiedText: content,
                            isNewFile: originalText == nil)
        case let .edit(single):
            guard let original = originalText,
                  let modified = Self.apply([single], to: original) else { return nil }
            return EditDiff(filePath: edit.filePath, originalText: original,
                            modifiedText: modified, isNewFile: false)
        case let .multiEdit(edits):
            guard let original = originalText,
                  let modified = Self.apply(edits, to: original) else { return nil }
            return EditDiff(filePath: edit.filePath, originalText: original,
                            modifiedText: modified, isNewFile: false)
        }
    }

    /// Applies replacements in order; returns `nil` if any `old_string` is absent (or empty) at its turn.
    private static func apply(_ edits: [SingleEdit], to original: String) -> String? {
        var text = original
        for edit in edits {
            guard !edit.oldString.isEmpty else { return nil }
            if edit.replaceAll {
                guard text.contains(edit.oldString) else { return nil }
                text = text.replacingOccurrences(of: edit.oldString, with: edit.newString)
            } else {
                guard let range = text.range(of: edit.oldString) else { return nil }
                text.replaceSubrange(range, with: edit.newString)
            }
        }
        return text
    }
}
