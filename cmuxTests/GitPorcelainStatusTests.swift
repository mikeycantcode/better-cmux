import Testing

#if canImport(cmux_DEV)
    @testable import cmux_DEV
#elseif canImport(cmux)
    @testable import cmux
#endif

struct GitPorcelainStatusTests {
    @Test func parsesBranchHeadersAndAheadBehind() {
        let out = """
        # branch.oid 1234567deadbeef
        # branch.head big-cleanup
        # branch.upstream origin/big-cleanup
        # branch.ab +3 -1
        """
        let s = GitPorcelainStatus.parse(out)
        #expect(s.branch == "big-cleanup")
        #expect(s.upstream == "origin/big-cleanup")
        #expect(s.ahead == 3)
        #expect(s.behind == 1)
    }

    @Test func parsesDetachedHead() {
        let s = GitPorcelainStatus.parse("# branch.head (detached)\n")
        #expect(s.branch == nil)
    }

    @Test func bucketsOrdinaryRecords() {
        // "1 XY sub mH mI mW hH hI path"
        let out = """
        1 M. N... 100644 100644 100644 aaa bbb staged_only.swift
        1 .M N... 100644 100644 100644 aaa aaa worktree_only.swift
        1 MM N... 100644 100644 100644 aaa bbb both.swift
        1 A. N... 000000 100644 100644 000 bbb newly_added.swift
        1 .D N... 100644 100644 000000 aaa aaa gone.swift
        ? scratch.txt
        """
        let s = GitPorcelainStatus.parse(out)
        #expect(s.staged.map(\.path) == ["staged_only.swift", "both.swift", "newly_added.swift"])
        #expect(s.staged.map(\.status) == [.modified, .modified, .added])
        #expect(s.modified.map(\.path) == ["worktree_only.swift", "both.swift", "gone.swift"])
        #expect(s.modified.map(\.status) == [.modified, .modified, .deleted])
        #expect(s.untracked.map(\.path) == ["scratch.txt"])
        #expect(s.untracked.allSatisfy { $0.status == .untracked })
    }

    @Test func parsesRenameRecordsWithTabSeparator() {
        // "2 XY sub mH mI mW hH hI Xscore path<TAB>origPath"
        let out = "2 R. N... 100644 100644 100644 aaa aaa R100 new_name.swift\told_name.swift\n"
        let s = GitPorcelainStatus.parse(out)
        #expect(s.staged.count == 1)
        #expect(s.staged[0].status == .renamed)
        #expect(s.staged[0].path == "new_name.swift")
        #expect(s.staged[0].originalPath == "old_name.swift")
    }

    @Test func unquotesQuotedPaths() {
        let out = "? \"has space\\ttab.txt\"\n"
        let s = GitPorcelainStatus.parse(out)
        #expect(s.untracked.first?.path == "has space\ttab.txt")
    }
}
