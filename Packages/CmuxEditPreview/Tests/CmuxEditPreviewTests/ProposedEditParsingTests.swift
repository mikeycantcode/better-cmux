import Testing
@testable import CmuxEditPreview

@Suite struct ProposedEditParsingTests {
    @Test func parsesWrite() {
        let json = #"{"file_path":"/a/b.swift","content":"hello"}"#
        let edit = ProposedEdit.from(toolName: "Write", toolInputJSON: json)
        #expect(edit == ProposedEdit(filePath: "/a/b.swift", kind: .write(content: "hello")))
    }

    @Test func parsesEditWithReplaceAllDefaultFalse() {
        let json = #"{"file_path":"/a/b.swift","old_string":"foo","new_string":"bar"}"#
        let edit = ProposedEdit.from(toolName: "Edit", toolInputJSON: json)
        #expect(edit == ProposedEdit(filePath: "/a/b.swift",
                                     kind: .edit(SingleEdit(oldString: "foo", newString: "bar", replaceAll: false))))
    }

    @Test func parsesMultiEditInOrder() {
        let json = #"{"file_path":"/a/b.swift","edits":[{"old_string":"a","new_string":"b"},{"old_string":"c","new_string":"d","replace_all":true}]}"#
        let edit = ProposedEdit.from(toolName: "MultiEdit", toolInputJSON: json)
        #expect(edit == ProposedEdit(filePath: "/a/b.swift", kind: .multiEdit([
            SingleEdit(oldString: "a", newString: "b", replaceAll: false),
            SingleEdit(oldString: "c", newString: "d", replaceAll: true),
        ])))
    }

    @Test func rejectsUnsupportedTool() {
        let json = #"{"file_path":"/a/b.swift","content":"x"}"#
        #expect(ProposedEdit.from(toolName: "Bash", toolInputJSON: json) == nil)
    }

    @Test func rejectsMalformedJSON() {
        #expect(ProposedEdit.from(toolName: "Write", toolInputJSON: "not json") == nil)
    }

    @Test func parsesToolNameCaseInsensitively() {
        let write = ProposedEdit.from(toolName: "write", toolInputJSON: #"{"file_path":"/a","content":"x"}"#)
        #expect(write == ProposedEdit(filePath: "/a", kind: .write(content: "x")))
        let multi = ProposedEdit.from(toolName: "MULTIEDIT", toolInputJSON: #"{"file_path":"/a","edits":[{"old_string":"a","new_string":"b"}]}"#)
        #expect(multi == ProposedEdit(filePath: "/a", kind: .multiEdit([SingleEdit(oldString: "a", newString: "b", replaceAll: false)])))
    }
}
