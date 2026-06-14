import Testing
@testable import CmuxEditPreview

@Suite struct EditPreviewComputerTests {
    let computer = EditPreviewComputer()

    @Test func writeOverwriteUsesDiskAsOriginal() {
        let edit = ProposedEdit(filePath: "/a.txt", kind: .write(content: "new"))
        let diff = computer.compute(edit, originalText: "old")
        #expect(diff == EditDiff(filePath: "/a.txt", originalText: "old", modifiedText: "new", isNewFile: false))
    }

    @Test func writeNewFileHasEmptyOriginalAndFlag() {
        let edit = ProposedEdit(filePath: "/a.txt", kind: .write(content: "new"))
        let diff = computer.compute(edit, originalText: nil)
        #expect(diff == EditDiff(filePath: "/a.txt", originalText: "", modifiedText: "new", isNewFile: true))
    }

    @Test func editReplacesFirstOccurrence() {
        let edit = ProposedEdit(filePath: "/a.txt",
                                kind: .edit(SingleEdit(oldString: "x", newString: "y", replaceAll: false)))
        let diff = computer.compute(edit, originalText: "x and x")
        #expect(diff?.modifiedText == "y and x")
    }

    @Test func editReplaceAllReplacesEvery() {
        let edit = ProposedEdit(filePath: "/a.txt",
                                kind: .edit(SingleEdit(oldString: "x", newString: "y", replaceAll: true)))
        let diff = computer.compute(edit, originalText: "x and x")
        #expect(diff?.modifiedText == "y and y")
    }

    @Test func multiEditAppliesSequentially() {
        let edit = ProposedEdit(filePath: "/a.txt", kind: .multiEdit([
            SingleEdit(oldString: "1", newString: "2", replaceAll: false),
            SingleEdit(oldString: "2", newString: "3", replaceAll: false),
        ]))
        // "1" -> "2" makes "2 2"; next replaces first "2" -> "3" => "3 2".
        let diff = computer.compute(edit, originalText: "1 2")
        #expect(diff?.modifiedText == "3 2")
    }

    @Test func nonApplicableWhenOldStringMissing() {
        let edit = ProposedEdit(filePath: "/a.txt",
                                kind: .edit(SingleEdit(oldString: "zzz", newString: "y", replaceAll: false)))
        #expect(computer.compute(edit, originalText: "abc") == nil)
    }

    @Test func editOnMissingFileIsNonApplicable() {
        let edit = ProposedEdit(filePath: "/a.txt",
                                kind: .edit(SingleEdit(oldString: "x", newString: "y", replaceAll: false)))
        #expect(computer.compute(edit, originalText: nil) == nil)
    }

    @Test func multiEditPartialFailureIsNonApplicable() {
        // Second edit's old_string is absent in the original AND not produced by the first edit.
        let edit = ProposedEdit(filePath: "/a.txt", kind: .multiEdit([
            SingleEdit(oldString: "a", newString: "b", replaceAll: false),
            SingleEdit(oldString: "zzz", newString: "c", replaceAll: false),
        ]))
        #expect(computer.compute(edit, originalText: "a") == nil)
    }

    @Test func editWithEmptyOldStringIsNonApplicable() {
        let edit = ProposedEdit(filePath: "/a.txt",
                                kind: .edit(SingleEdit(oldString: "", newString: "y", replaceAll: false)))
        #expect(computer.compute(edit, originalText: "abc") == nil)
    }
}
