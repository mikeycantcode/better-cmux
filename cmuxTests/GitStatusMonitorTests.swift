import Combine
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

private let base = "/repo"

private func porcelain(
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

// MARK: - Flattening (pure)

struct GitStatusFlatteningTests {
    /// Attention ordering: conflict > deleted > added/untracked > modified > renamed.
    @Test func severityOrdering() {
        let deleted = GitStatusFlattening.severity(.deleted)
        let added = GitStatusFlattening.severity(.added)
        let untracked = GitStatusFlattening.severity(.untracked)
        let modified = GitStatusFlattening.severity(.modified)
        let renamed = GitStatusFlattening.severity(.renamed)
        #expect(deleted > added)
        #expect(added == untracked)
        #expect(added > modified)
        #expect(modified > renamed)
    }

    @Test func worseIsSymmetricAndStableOnTies() {
        #expect(GitStatusFlattening.worse(.modified, .deleted) == .deleted)
        #expect(GitStatusFlattening.worse(.deleted, .modified) == .deleted)
        #expect(GitStatusFlattening.worse(.renamed, .modified) == .modified)
        #expect(GitStatusFlattening.worse(.added, .untracked) == .added)
    }

    /// A file staged as added and modified in the worktree must paint one color.
    @Test func statusByPathFlattensIndexAndWorktreeToTheWorstStatus() {
        let map = GitStatusFlattening.statusByPath(
            porcelain(
                staged: [entry("src/a.swift", .added)],
                modified: [entry("src/a.swift", .modified)]
            ),
            base: base
        )
        #expect(map == ["/repo/src/a.swift": .added])
    }

    @Test func statusByPathPrefersDeletedOverModified() {
        let map = GitStatusFlattening.statusByPath(
            porcelain(
                staged: [entry("a.txt", .modified)],
                modified: [entry("a.txt", .deleted)]
            ),
            base: base
        )
        #expect(map == ["/repo/a.txt": .deleted])
    }

    /// A rename keys only its new path: the original path has no row left to decorate.
    @Test func renameKeysOnlyTheNewPath() {
        let map = GitStatusFlattening.statusByPath(
            porcelain(staged: [entry("new/b.swift", .renamed, original: "old/a.swift")]),
            base: base
        )
        #expect(map == ["/repo/new/b.swift": .renamed])
        #expect(map["/repo/old/a.swift"] == nil)
    }

    @Test func untrackedDirectoryEntryLosesItsTrailingSlash() {
        let map = GitStatusFlattening.statusByPath(
            porcelain(untracked: [entry("build/", .untracked)]),
            base: base
        )
        #expect(map == ["/repo/build": .untracked])
    }

    /// Every ancestor up to and including the repo root is marked; siblings are not.
    @Test func directoryRollupMarksEveryAncestorIncludingRepoRoot() {
        let dirs = GitStatusFlattening.directoryHasChanges(
            paths: ["/repo/a/b/c/file.txt"], base: base
        )
        #expect(dirs == ["/repo", "/repo/a", "/repo/a/b", "/repo/a/b/c"])
    }

    @Test func directoryRollupExcludesUnrelatedDirectories() {
        let dirs = GitStatusFlattening.directoryHasChanges(
            paths: ["/repo/a/file.txt"], base: base
        )
        #expect(!dirs.contains("/repo/b"))
        #expect(!dirs.contains("/"))
    }

    @Test func directoryRollupIncludesAnUntrackedDirectoryItself() {
        let dirs = GitStatusFlattening.directoryHasChanges(
            paths: ["/repo/a/build/"], base: base
        )
        #expect(dirs.contains("/repo/a/build"))
        #expect(dirs.contains("/repo/a"))
        #expect(dirs.contains("/repo"))
    }

    /// `rev-parse --show-toplevel` resolves symlinks; explorer paths do not.
    /// Keying by the resolved spelling would make every decoration miss.
    @Test func repoRootSpellingKeepsTheRequestedSpelling() {
        #expect(
            GitStatusFlattening.repoRootSpelling(
                requestedRoot: "/tmp/work",
                toplevel: "/private/tmp/work",
                resolvedRequested: "/private/tmp/work"
            ) == "/tmp/work"
        )
    }

    @Test func repoRootSpellingPeelsSubdirectorySuffix() {
        #expect(
            GitStatusFlattening.repoRootSpelling(
                requestedRoot: "/tmp/work/src/deep",
                toplevel: "/private/tmp/work",
                resolvedRequested: "/private/tmp/work/src/deep"
            ) == "/tmp/work"
        )
    }

    @Test func repoRootSpellingFallsBackToToplevel() {
        #expect(
            GitStatusFlattening.repoRootSpelling(
                requestedRoot: "", toplevel: "/x/y", resolvedRequested: ""
            ) == "/x/y"
        )
    }
}

// MARK: - Monitor

@MainActor
struct GitStatusMonitorTests {
    /// A canned git runner: answers `rev-parse` with `toplevel` and `status` with
    /// successive canned porcelain outputs.
    private final class FakeGit: @unchecked Sendable {
        let toplevel: String
        var statusOutputs: [String]
        private(set) var statusCallCount = 0
        private(set) var revParseCallCount = 0
        /// Status call indices that should fail instead of returning output.
        var failStatusCalls: Set<Int> = []
        /// When true, the first status read blocks until ``openGate()``.
        var gateFirstCall = false
        private var gateIsOpen = false

        init(toplevel: String, statusOutputs: [String]) {
            self.toplevel = toplevel
            self.statusOutputs = statusOutputs
        }

        func openGate() { gateIsOpen = true }

        func runner() -> GitStatusMonitor.GitRunner {
            { [self] args, _ in
                if args.first == "rev-parse" {
                    revParseCallCount += 1
                    return .success(toplevel + "\n")
                }
                let index = statusCallCount
                statusCallCount += 1
                if failStatusCalls.contains(index) { return .failure("fatal: read \(index) failed") }
                if gateFirstCall, index == 0 {
                    while !gateIsOpen { try? await Task.sleep(nanoseconds: 10_000_000) }
                }
                return .success(statusOutputs[min(index, statusOutputs.count - 1)])
            }
        }
    }

    private static func porcelainOutput(_ lines: [String]) -> String {
        (["# branch.head main"] + lines).joined(separator: "\n") + "\n"
    }

    @Test func sharedReturnsOneInstancePerNormalizedRoot() {
        let a = GitStatusMonitor.shared(forRepoRoot: "/tmp/shared-root")
        let b = GitStatusMonitor.shared(forRepoRoot: "/tmp/shared-root/")
        #expect(a === b)
        let other = GitStatusMonitor.shared(forRepoRoot: "/tmp/shared-root-2")
        #expect(a !== other)
    }

    /// The cache holds monitors weakly: a workspace root re-points on every
    /// shell `cd`, so a strong cache would retain one monitor per directory
    /// ever visited.
    @Test func sharedDropsMonitorsWithNoLiveConsumer() {
        let root = "/tmp/evictable-root-" + UUID().uuidString
        weak var weakMonitor: GitStatusMonitor?
        do {
            let monitor = GitStatusMonitor.shared(forRepoRoot: root)
            weakMonitor = monitor
        }
        // The cache holding it would keep this alive. (Deliberately not an
        // ObjectIdentifier comparison against a rebuilt instance: the allocator
        // reuses the freed address often enough to make that check meaningless.)
        #expect(weakMonitor == nil, "no consumer holds it, so the cache must not retain it")

        // A later request for the same root still works — it builds a fresh one.
        let rebuilt = GitStatusMonitor.shared(forRepoRoot: root)
        #expect(rebuilt.repoRoot == root)
    }

    /// While a consumer holds its monitor, the cache must keep vending it.
    @Test func sharedKeepsVendingWhileAConsumerHoldsIt() {
        let root = "/tmp/held-root-" + UUID().uuidString
        let held = GitStatusMonitor.shared(forRepoRoot: root)
        #expect(GitStatusMonitor.shared(forRepoRoot: root) === held)
    }

    /// A failed read drops the cached repo-root resolution, so a worktree that
    /// moved (or a nested `git init`) is re-resolved instead of mis-keying every
    /// path for the rest of the session.
    @Test func failedReadReresolvesTheRepoRoot() async {
        let git = FakeGit(toplevel: "/repo", statusOutputs: [Self.porcelainOutput(["? a.txt"])])
        git.failStatusCalls = [0]
        let monitor = GitStatusMonitor(repoRoot: "/repo", runGit: git.runner())

        await monitor.refreshNow()
        #expect(git.revParseCallCount == 1)
        #expect(monitor.lastErrorLine != nil)

        await monitor.refreshNow()
        #expect(git.revParseCallCount == 2, "the failed read must invalidate the cached base")
        #expect(monitor.statusByPath["/repo/a.txt"] == .untracked)
        #expect(monitor.lastErrorLine == nil)
    }

    /// A successful read caches the resolution: one burst, one `rev-parse`.
    @Test func successfulReadsReuseTheResolvedRoot() async {
        let git = FakeGit(toplevel: "/repo", statusOutputs: [Self.porcelainOutput(["? a.txt"])])
        let monitor = GitStatusMonitor(repoRoot: "/repo", runGit: git.runner())
        await monitor.refreshNow()
        await monitor.refreshNow()
        #expect(git.revParseCallCount == 1)
    }

    /// `@Published` emits in `willSet`, so a `$porcelain` subscriber sees every
    /// other property at its *new* value only if the error was assigned first.
    @Test func errorLineIsVisibleToAPorcelainSubscriber() async {
        let git = FakeGit(toplevel: "/repo", statusOutputs: [Self.porcelainOutput(["? a.txt"])])
        let monitor = GitStatusMonitor(repoRoot: "/repo", runGit: git.runner())
        await monitor.refreshNow()  // populate, so the failure actually changes porcelain

        var seenAlongsidePorcelain: [String?] = []
        let token = monitor.$porcelain.sink { _ in seenAlongsidePorcelain.append(monitor.lastErrorLine) }
        defer { token.cancel() }
        seenAlongsidePorcelain.removeAll()  // drop the subscribe-time replay

        git.failStatusCalls = [1]
        await monitor.refreshNow()
        #expect(seenAlongsidePorcelain == ["fatal: read 1 failed"])
    }

    @Test func refreshPublishesStatusAndDirectoryRollup() async {
        let git = FakeGit(
            toplevel: "/repo",
            statusOutputs: [Self.porcelainOutput([
                "1 .M N... 100644 100644 100644 aaa bbb src/a.swift",
                "? build/",
            ])]
        )
        let monitor = GitStatusMonitor(repoRoot: "/repo", runGit: git.runner())
        await monitor.refreshNow()

        #expect(monitor.statusByPath["/repo/src/a.swift"] == .modified)
        #expect(monitor.statusByPath["/repo/build"] == .untracked)
        #expect(monitor.directoryHasChanges.contains("/repo/src"))
        #expect(monitor.directoryHasChanges.contains("/repo"))
        #expect(monitor.porcelain.branch == "main")
        #expect(monitor.lastErrorLine == nil)
    }

    /// An unchanged status must not emit: every consumer of this publisher
    /// invalidates a view tree.
    @Test func identicalStatusPublishesOnce() async {
        let output = Self.porcelainOutput(["1 .M N... 100644 100644 100644 aaa bbb a.txt"])
        let git = FakeGit(toplevel: "/repo", statusOutputs: [output, output])
        let monitor = GitStatusMonitor(repoRoot: "/repo", runGit: git.runner())

        var emissions = 0
        let token = monitor.$statusByPath.sink { _ in emissions += 1 }
        defer { token.cancel() }
        #expect(emissions == 1)  // @Published replays the current value on subscribe

        await monitor.refreshNow()
        #expect(emissions == 2)
        await monitor.refreshNow()
        #expect(emissions == 2, "identical status must not republish")
        #expect(git.statusCallCount == 2)
    }

    /// A slow read that finishes after a newer one must be discarded — this is
    /// the explorer's old stale-overwrite race.
    @Test func staleResultIsDiscarded() async {
        let git = FakeGit(
            toplevel: "/repo",
            statusOutputs: [
                Self.porcelainOutput(["? stale.txt"]),
                Self.porcelainOutput(["? fresh.txt"]),
            ]
        )
        // Gate the *first* read to arrive, whichever task that is, so the test
        // does not depend on how the two refreshes interleave.
        git.gateFirstCall = true
        let monitor = GitStatusMonitor(repoRoot: "/repo", runGit: git.runner())

        async let slow: Void = monitor.refreshNow()
        // Wait until the gated read is genuinely in flight before starting the
        // newer one — otherwise "stale" and "fresh" can swap roles.
        for _ in 0..<200 where git.statusCallCount == 0 {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(git.statusCallCount == 1)

        await monitor.refreshNow()
        git.openGate()
        await slow

        #expect(monitor.statusByPath["/repo/fresh.txt"] == .untracked)
        #expect(monitor.statusByPath["/repo/stale.txt"] == nil)
    }

    /// End-to-end through the real consumer: a watcher-style `scheduleRefresh()`
    /// whose read fails must surface the error on the model, not swallow it.
    /// Lives here rather than in `GitWorkingTreeModelTests` because it is a
    /// monitor-contract test.
    @Test func modelSurfacesAFailedScheduledReadsErrorLine() async throws {
        let dir = NSTemporaryDirectory() + "cmux-monitor-err-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: dir) }
        func git(_ args: [String]) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.currentDirectoryURL = URL(fileURLWithPath: dir)
            p.arguments = args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            try? p.run()
            p.waitUntilExit()
        }
        git(["init", "-b", "main"])

        let model = GitWorkingTreeModel(repoPath: dir)
        await model.refresh()
        #expect(model.lastErrorLine == nil)

        // A corrupt index fails `git status` while `rev-parse` still resolves.
        try Data(repeating: 0x41, count: 8).write(to: URL(fileURLWithPath: dir + "/.git/index"))

        model.scheduleDebouncedRefresh()
        for _ in 0..<200 where model.lastErrorLine == nil {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        #expect(model.lastErrorLine != nil)
    }

    @Test func notARepoPublishesEmpty() async {
        let monitor = GitStatusMonitor(repoRoot: "/repo", runGit: { _, _ in .failure("not a git repository") })
        await monitor.refreshNow()
        #expect(monitor.statusByPath.isEmpty)
        #expect(monitor.directoryHasChanges.isEmpty)
        #expect(monitor.porcelain == .empty)
    }

    @Test func emptyRootPublishesEmpty() async {
        let monitor = GitStatusMonitor(repoRoot: "", runGit: { _, _ in .success("boom") })
        await monitor.refreshNow()
        #expect(monitor.statusByPath.isEmpty)
        #expect(monitor.porcelain == .empty)
    }

    /// One burst of watcher events must cost one `git status`.
    @Test func scheduleRefreshCoalescesABurst() async {
        let git = FakeGit(toplevel: "/repo", statusOutputs: [Self.porcelainOutput(["? a.txt"])])
        let monitor = GitStatusMonitor(repoRoot: "/repo", runGit: git.runner())
        for _ in 0..<10 { monitor.scheduleRefresh() }
        // The main actor is contended when the suite runs in parallel, so wait
        // for the debounce to land rather than assuming a fixed slack.
        for _ in 0..<100 where git.statusCallCount == 0 {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        #expect(git.statusCallCount == 1)
        #expect(monitor.statusByPath["/repo/a.txt"] == .untracked)
    }
}
