import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct GitScmViewModelTests {
    private func status(
        staged: [GitStatusEntry] = [],
        modified: [GitStatusEntry] = [],
        untracked: [GitStatusEntry] = []
    ) -> GitPorcelainStatus {
        GitPorcelainStatus(
            branch: "main", upstream: nil, ahead: 0, behind: 0,
            staged: staged, modified: modified, untracked: untracked
        )
    }

    private func entry(_ path: String, _ status: GitEntryStatus, original: String? = nil) -> GitStatusEntry {
        GitStatusEntry(path: path, originalPath: original, status: status)
    }

    @Test func untrackedMergesIntoChangesMarkedU() {
        let rows = GitPanelView.scmRows(
            from: status(
                modified: [entry("a.swift", .modified)],
                untracked: [entry("b.swift", .untracked)]
            )
        )
        #expect(rows.staged.isEmpty)
        #expect(rows.changes.map(\.fileName) == ["a.swift", "b.swift"])
        #expect(rows.changes.map(\.statusLetter) == ["M", "U"])
        #expect(rows.changes.allSatisfy { $0.section == .changes })
    }

    @Test func stagedBucketIsSeparate() {
        let rows = GitPanelView.scmRows(
            from: status(
                staged: [entry("src/added.swift", .added)],
                modified: [entry("src/added.swift", .modified)]
            )
        )
        #expect(rows.staged.map(\.statusLetter) == ["A"])
        #expect(rows.staged.map(\.section) == [.staged])
        #expect(rows.changes.map(\.statusLetter) == ["M"])
    }

    @Test func sortIsByFileNameCaseInsensitive() {
        let rows = GitPanelView.scmRows(
            from: status(
                modified: [
                    entry("z/Beta.swift", .modified),
                    entry("a/alpha.swift", .modified),
                    entry("m/Charlie.swift", .modified),
                ]
            )
        )
        #expect(rows.changes.map(\.fileName) == ["alpha.swift", "Beta.swift", "Charlie.swift"])
    }

    @Test func directoryTextIsParentPathOrEmptyAtRoot() {
        let rows = GitPanelView.scmRows(
            from: status(
                modified: [
                    entry("neetcode/problems/two_sum.py", .modified),
                    entry("README.md", .modified),
                ]
            )
        )
        let byName = Dictionary(uniqueKeysWithValues: rows.changes.map { ($0.fileName, $0) })
        #expect(byName["two_sum.py"]?.directoryText == "neetcode/problems")
        #expect(byName["README.md"]?.directoryText == "")
    }

    @Test func renameShowsRAtTheNewPath() {
        let rows = GitPanelView.scmRows(
            from: status(staged: [entry("new/name.swift", .renamed, original: "old/name.swift")])
        )
        #expect(rows.staged.map(\.path) == ["new/name.swift"])
        #expect(rows.staged.map(\.statusLetter) == ["R"])
    }

    @Test func idsAreStableAndDistinctAcrossSections() {
        let rows = GitPanelView.scmRows(
            from: status(
                staged: [entry("a.swift", .modified)],
                modified: [entry("a.swift", .modified)]
            )
        )
        #expect(rows.staged[0].id == "staged" + "a.swift")
        #expect(rows.changes[0].id == "changes" + "a.swift")
        #expect(rows.staged[0].id != rows.changes[0].id)
    }

    @Test func statusColorsMatchTheExplorerVSCodePalette() {
        let rows = GitPanelView.scmRows(
            from: status(
                modified: [entry("m.swift", .modified), entry("d.swift", .deleted)],
                untracked: [entry("u.swift", .untracked)]
            )
        )
        let byName = Dictionary(uniqueKeysWithValues: rows.changes.map { ($0.fileName, $0) })
        #expect(byName["m.swift"]?.statusColorHex == "E2C08D")
        #expect(byName["d.swift"]?.statusColorHex == "C74E39")
        #expect(byName["u.swift"]?.statusColorHex == "73C991")
    }
}
