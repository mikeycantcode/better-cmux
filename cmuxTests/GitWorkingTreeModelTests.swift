import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Creates a throwaway git repo and returns its path.
private func makeFixtureRepo() throws -> String {
    let dir = NSTemporaryDirectory() + "cmux-gitmodel-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    func git(_ args: [String]) throws {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.currentDirectoryURL = URL(fileURLWithPath: dir)
        p.arguments = args
        p.environment = ProcessInfo.processInfo.environment.merging([
            "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
            "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t",
        ]) { _, new in new }
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
    }
    try git(["init", "-b", "main"])
    try "hello\n".write(toFile: dir + "/a.txt", atomically: true, encoding: .utf8)
    try git(["add", "."])
    try git(["commit", "-m", "init"])
    return dir
}

@MainActor
struct GitWorkingTreeModelTests {
    @Test func refreshSeesWorktreeAndUntracked() async throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        try "changed\n".write(toFile: repo + "/a.txt", atomically: true, encoding: .utf8)
        try "new\n".write(toFile: repo + "/b.txt", atomically: true, encoding: .utf8)

        let model = GitWorkingTreeModel(repoPath: repo)
        await model.refresh()
        #expect(model.status.branch == "main")
        #expect(model.status.modified.map(\.path) == ["a.txt"])
        #expect(model.status.untracked.map(\.path) == ["b.txt"])
    }

    @Test func stageUnstageRoundTrip() async throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        try "changed\n".write(toFile: repo + "/a.txt", atomically: true, encoding: .utf8)

        let model = GitWorkingTreeModel(repoPath: repo)
        await model.stageFile("a.txt")
        #expect(model.status.staged.map(\.path) == ["a.txt"])
        #expect(model.status.modified.isEmpty)
        await model.unstageFile("a.txt")
        #expect(model.status.staged.isEmpty)
        #expect(model.status.modified.map(\.path) == ["a.txt"])
    }

    @Test func discardRestoresTrackedAndDeletesUntracked() async throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        try "changed\n".write(toFile: repo + "/a.txt", atomically: true, encoding: .utf8)
        try "junk\n".write(toFile: repo + "/junk.txt", atomically: true, encoding: .utf8)

        let model = GitWorkingTreeModel(repoPath: repo)
        await model.refresh()
        let tracked = model.status.modified[0]
        let untracked = model.status.untracked[0]
        await model.discardFile(tracked)
        await model.discardFile(untracked)
        #expect(try String(contentsOfFile: repo + "/a.txt", encoding: .utf8) == "hello\n")
        #expect(!FileManager.default.fileExists(atPath: repo + "/junk.txt"))
        #expect(model.status.modified.isEmpty && model.status.untracked.isEmpty)
    }

    @Test func commitClearsStagedAndBumpsAheadless() async throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        try "changed\n".write(toFile: repo + "/a.txt", atomically: true, encoding: .utf8)

        let model = GitWorkingTreeModel(repoPath: repo)
        await model.stageAll()
        let ok = await model.commit(message: "test commit")
        #expect(ok)
        #expect(model.status.staged.isEmpty && model.status.modified.isEmpty)
    }

    /// A fast workspace switch must converge on the *last* repoPath — an
    /// uncancellable per-didSet refresh could land the first repo's status last.
    @Test func rapidRepoPathSwitchLandsOnLastRepo() async throws {
        let repoA = try makeFixtureRepo()
        let repoB = try makeFixtureRepo()
        defer {
            try? FileManager.default.removeItem(atPath: repoA)
            try? FileManager.default.removeItem(atPath: repoB)
        }
        try "onlyA\n".write(toFile: repoA + "/a-only.txt", atomically: true, encoding: .utf8)
        try "onlyB\n".write(toFile: repoB + "/b-only.txt", atomically: true, encoding: .utf8)

        let model = GitWorkingTreeModel(repoPath: "")
        model.repoPath = repoA
        model.repoPath = repoB

        var untracked: [String] = []
        for _ in 0..<40 {
            try await Task.sleep(nanoseconds: 100_000_000)
            untracked = model.status.untracked.map(\.path)
            if !untracked.isEmpty { break }
        }
        #expect(untracked == ["b-only.txt"])

        // And it stays settled: no queued stale refresh overwrites it.
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(model.status.untracked.map(\.path) == ["b-only.txt"])
    }

    // MARK: - Batch actions

    @Test func stageFilesStagesOnlyTheGivenPaths() async throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        try "changed\n".write(toFile: repo + "/a.txt", atomically: true, encoding: .utf8)
        try "one\n".write(toFile: repo + "/b.txt", atomically: true, encoding: .utf8)
        try "two\n".write(toFile: repo + "/c.txt", atomically: true, encoding: .utf8)

        let model = GitWorkingTreeModel(repoPath: repo)
        await model.stageFiles(["b.txt", "c.txt"])

        #expect(model.status.staged.map(\.path).sorted() == ["b.txt", "c.txt"])
        // a.txt was deliberately left out of the pathspec and must stay dirty.
        #expect(model.status.modified.map(\.path) == ["a.txt"])
        #expect(model.lastErrorLine == nil)
    }

    @Test func unstageFilesUnstagesOnlyTheGivenPaths() async throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        try "one\n".write(toFile: repo + "/b.txt", atomically: true, encoding: .utf8)
        try "two\n".write(toFile: repo + "/c.txt", atomically: true, encoding: .utf8)

        let model = GitWorkingTreeModel(repoPath: repo)
        await model.stageFiles(["b.txt", "c.txt"])
        await model.unstageFiles(["b.txt"])

        #expect(model.status.staged.map(\.path) == ["c.txt"])
        #expect(model.status.untracked.map(\.path) == ["b.txt"])
    }

    @Test func discardFilesHandlesMixedTrackedAndUntrackedInOneShot() async throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        try "changed\n".write(toFile: repo + "/a.txt", atomically: true, encoding: .utf8)
        try "junk\n".write(toFile: repo + "/junk.txt", atomically: true, encoding: .utf8)
        try "keep\n".write(toFile: repo + "/keep.txt", atomically: true, encoding: .utf8)

        let model = GitWorkingTreeModel(repoPath: repo)
        await model.refresh()
        let toDiscard = model.status.modified + model.status.untracked.filter { $0.path == "junk.txt" }
        #expect(toDiscard.count == 2)
        await model.discardFiles(toDiscard)

        #expect(try String(contentsOfFile: repo + "/a.txt", encoding: .utf8) == "hello\n")
        #expect(!FileManager.default.fileExists(atPath: repo + "/junk.txt"))
        // Not in the batch: untouched.
        #expect(FileManager.default.fileExists(atPath: repo + "/keep.txt"))
        #expect(model.status.modified.isEmpty)
        #expect(model.status.untracked.map(\.path) == ["keep.txt"])
        #expect(model.lastErrorLine == nil)
    }

    @Test func batchActionsWithEmptyInputAreNoOps() async throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        try "changed\n".write(toFile: repo + "/a.txt", atomically: true, encoding: .utf8)

        let model = GitWorkingTreeModel(repoPath: repo)
        await model.refresh()
        await model.stageFiles([])
        await model.unstageFiles([])
        await model.discardFiles([])

        // Empty input must not run git at all, so nothing changed and no error.
        #expect(model.status.modified.map(\.path) == ["a.txt"])
        #expect(model.lastErrorLine == nil)
    }

    /// A failing command in a batch must leave its error visible — the single
    /// trailing refresh must not clear it.
    @Test func batchFailureSurfacesErrorLine() async throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(atPath: repo) }

        let model = GitWorkingTreeModel(repoPath: repo)
        await model.stageFiles(["does-not-exist.txt"])
        #expect(model.lastErrorLine != nil)
    }

    @Test func commitWithNothingStagedFails() async throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        let model = GitWorkingTreeModel(repoPath: repo)
        let ok = await model.commit(message: "empty")
        #expect(!ok)
        #expect(model.lastErrorLine != nil)
    }
}
