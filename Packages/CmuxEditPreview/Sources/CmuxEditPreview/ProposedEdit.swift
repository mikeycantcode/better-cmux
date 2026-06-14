import Foundation

/// A parsed, file-targeted edit proposed by a Claude tool call (`Write`/`Edit`/`MultiEdit`).
///
/// Build one with ``ProposedEdit/from(toolName:toolInputJSON:)``; feed it to
/// ``EditPreviewComputer`` together with the file's current contents to get an ``EditDiff``.
public struct ProposedEdit: Equatable, Sendable {
    /// What kind of mutation the tool proposes.
    public enum Kind: Equatable, Sendable {
        /// `Write`: replace the whole file (or create it) with `content`.
        case write(content: String)
        /// `Edit`: a single `old→new` replacement.
        case edit(SingleEdit)
        /// `MultiEdit`: apply replacements in order.
        case multiEdit([SingleEdit])
    }

    /// Absolute path of the file the tool will write.
    public let filePath: String
    /// The proposed mutation.
    public let kind: Kind

    /// Creates a proposed edit from already-parsed parts.
    public init(filePath: String, kind: Kind) {
        self.filePath = filePath
        self.kind = kind
    }

    /// Parses Claude's `tool_input` JSON for a supported file-edit tool.
    ///
    /// - Parameters:
    ///   - toolName: The tool name (`"Write"`, `"Edit"`, or `"MultiEdit"`; case-insensitive).
    ///   - toolInputJSON: The raw `tool_input` JSON object string from the hook payload.
    /// - Returns: A ``ProposedEdit``, or `nil` if the tool is unsupported or the JSON is malformed
    ///   / missing required fields.
    public static func from(toolName: String, toolInputJSON: String) -> ProposedEdit? {
        guard let data = toolInputJSON.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let filePath = obj["file_path"] as? String, !filePath.isEmpty
        else { return nil }

        switch toolName.lowercased() {
        case "write":
            guard let content = obj["content"] as? String else { return nil }
            return ProposedEdit(filePath: filePath, kind: .write(content: content))
        case "edit":
            guard let edit = Self.singleEdit(from: obj) else { return nil }
            return ProposedEdit(filePath: filePath, kind: .edit(edit))
        case "multiedit":
            guard let rawEdits = obj["edits"] as? [[String: Any]], !rawEdits.isEmpty else { return nil }
            var edits: [SingleEdit] = []
            for raw in rawEdits {
                guard let edit = Self.singleEdit(from: raw) else { return nil }
                edits.append(edit)
            }
            return ProposedEdit(filePath: filePath, kind: .multiEdit(edits))
        default:
            return nil
        }
    }

    /// Reads `old_string` / `new_string` / `replace_all` out of one JSON object.
    private static func singleEdit(from obj: [String: Any]) -> SingleEdit? {
        guard let oldString = obj["old_string"] as? String,
              let newString = obj["new_string"] as? String
        else { return nil }
        let replaceAll = (obj["replace_all"] as? Bool) ?? false
        return SingleEdit(oldString: oldString, newString: newString, replaceAll: replaceAll)
    }
}
