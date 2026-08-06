# Files + Git Right Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the right sidebar's six-mode switcher with a single beautiful Files | Git panel (restyled tree + real git status/commit tab) plus a main-area Changes diff-review panel.

**Architecture:** Keep the AppKit `NSOutlineView` + `FileExplorerStore` tree and re-skin it (new `codika` style + gitignore dimming + in-tree filter). Add a new git data layer (`GitPorcelainStatus` parser + `GitWorkingTreeModel` actions) consumed by a new SwiftUI Git tab and by a new `GitChangesPanel` main-area panel that hosts stacked Monaco inline-diff cards in one WKWebView. Delete the old right-sidebar modes (find/sessions/feed/dock/customSidebar).

**Tech Stack:** Swift 6 (SwiftUI + AppKit), XCTest/Swift Testing in `cmuxTests`, bundled Monaco in `Resources/monaco/`, git via `Process`.

**Spec:** `docs/superpowers/specs/2026-08-05-files-git-panel-design.md`

## Global Constraints

- Every user-facing string uses `String(localized: "key", defaultValue: "…")` and gets **en + ja** entries in `Resources/Localizable.xcstrings`. Never bare literals in `Text()`/`Button()`.
- Every **new file** (source or test) must be wired into `cmux.xcodeproj/project.pbxproj` with 4 entries (PBXBuildFile, PBXFileReference, group child, Sources phase). Use the entries for `TabManagerUnitTests.swift` (tests) / `TabManager.swift` (sources) as templates. Verify with `plutil -lint cmux.xcodeproj/project.pbxproj` and `./scripts/lint-pbxproj-test-wiring.sh`.
- Compile check command (app): `CMUX_SKIP_ZIG_BUILD=1 xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-files-git build 2>&1 | grep -E 'error:|BUILD'`
- Test compile check: same command with `-scheme cmux-unit build-for-testing`. **Do not run the full suite** (per Mike's standing instruction); run only the specific new test class via `-only-testing:cmuxTests/<Class>` when a step says to.
- No `@Published` writes from view `body` (including via helpers). No `@ObservedObject`/`@EnvironmentObject` below `List`/`ForEach` boundaries — rows get value snapshots + closure bundles (see `IndexSectionActions` in `Sources/SessionIndexView.swift`).
- Do not touch typing-latency paths: `WindowTerminalHostView.hitTest()`, `TabItemView`, `TerminalSurface.forceRefresh()`.
- Commit after each task ends with:
  `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: `GitPorcelainStatus` parser

**Files:**
- Create: `Sources/Git/GitPorcelainStatus.swift`
- Create: `cmuxTests/GitPorcelainStatusTests.swift`
- Modify: `cmux.xcodeproj/project.pbxproj` (wire both files; new `Git` group under Sources)

**Interfaces:**
- Consumes: nothing (pure parser).
- Produces (later tasks rely on these exact names):

```swift
enum GitEntryStatus: Character, Sendable {
    case modified = "M", added = "A", deleted = "D", renamed = "R", untracked = "U"
}

struct GitStatusEntry: Identifiable, Hashable, Sendable {
    let path: String            // repo-relative, unquoted
    let originalPath: String?   // for renames
    let status: GitEntryStatus
    var id: String { path }
}

struct GitPorcelainStatus: Sendable, Equatable {
    let branch: String?         // nil when detached
    let upstream: String?
    let ahead: Int
    let behind: Int
    let staged: [GitStatusEntry]
    let modified: [GitStatusEntry]   // worktree changes incl. deletions
    let untracked: [GitStatusEntry]
    static let empty = GitPorcelainStatus(branch: nil, upstream: nil, ahead: 0, behind: 0, staged: [], modified: [], untracked: [])
    static func parse(_ output: String) -> GitPorcelainStatus
}
```

- [ ] **Step 1: Write the failing test**

`cmuxTests/GitPorcelainStatusTests.swift`:

```swift
import Testing
@testable import cmux

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
```

- [ ] **Step 2: Wire both new files into pbxproj** (4 entries each; create a `Git` group folder reference under the Sources group mirroring `Sources/Git/`). Run `plutil -lint cmux.xcodeproj/project.pbxproj` — must print OK.

- [ ] **Step 3: Run test to verify it fails**

Run: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild -project cmux.xcodeproj -scheme cmux-unit -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-files-git build-for-testing 2>&1 | grep -E 'error:' | head`
Expected: errors "cannot find 'GitPorcelainStatus' in scope" (test compiles against missing type).

- [ ] **Step 4: Write the parser**

`Sources/Git/GitPorcelainStatus.swift`:

```swift
import Foundation

enum GitEntryStatus: Character, Sendable {
    case modified = "M", added = "A", deleted = "D", renamed = "R", untracked = "U"
}

struct GitStatusEntry: Identifiable, Hashable, Sendable {
    let path: String
    let originalPath: String?
    let status: GitEntryStatus
    var id: String { path }
}

/// Parses `git status --porcelain=v2 --branch` output.
struct GitPorcelainStatus: Sendable, Equatable {
    let branch: String?
    let upstream: String?
    let ahead: Int
    let behind: Int
    let staged: [GitStatusEntry]
    let modified: [GitStatusEntry]
    let untracked: [GitStatusEntry]

    static let empty = GitPorcelainStatus(
        branch: nil, upstream: nil, ahead: 0, behind: 0,
        staged: [], modified: [], untracked: []
    )

    static func parse(_ output: String) -> GitPorcelainStatus {
        var branch: String?
        var upstream: String?
        var ahead = 0, behind = 0
        var staged: [GitStatusEntry] = []
        var modified: [GitStatusEntry] = []
        var untracked: [GitStatusEntry] = []

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("# branch.head ") {
                let value = String(line.dropFirst("# branch.head ".count))
                branch = value == "(detached)" ? nil : value
            } else if line.hasPrefix("# branch.upstream ") {
                upstream = String(line.dropFirst("# branch.upstream ".count))
            } else if line.hasPrefix("# branch.ab ") {
                // "# branch.ab +3 -1"
                let parts = line.dropFirst("# branch.ab ".count).split(separator: " ")
                for part in parts {
                    if part.hasPrefix("+") { ahead = Int(part.dropFirst()) ?? 0 }
                    if part.hasPrefix("-") { behind = Int(part.dropFirst()) ?? 0 }
                }
            } else if line.hasPrefix("1 ") {
                // "1 XY sub mH mI mW hH hI path"
                let fields = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
                guard fields.count >= 9 else { continue }
                let xy = fields[1]
                let path = unquote(String(fields[8]))
                appendEntry(xy: xy, path: path, originalPath: nil,
                            staged: &staged, modified: &modified)
            } else if line.hasPrefix("2 ") {
                // "2 XY sub mH mI mW hH hI Xscore path\torigPath"
                let fields = line.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                guard fields.count >= 10 else { continue }
                let xy = fields[1]
                let pathField = String(fields[9])
                let tabSplit = pathField.split(separator: "\t", maxSplits: 1)
                let path = unquote(String(tabSplit.first ?? ""))
                let orig = tabSplit.count > 1 ? unquote(String(tabSplit[1])) : nil
                appendEntry(xy: xy, path: path, originalPath: orig,
                            staged: &staged, modified: &modified)
            } else if line.hasPrefix("? ") {
                let path = unquote(String(line.dropFirst(2)))
                untracked.append(GitStatusEntry(path: path, originalPath: nil, status: .untracked))
            }
            // "u " (unmerged) and "! " (ignored) records intentionally skipped in v1.
        }

        return GitPorcelainStatus(
            branch: branch, upstream: upstream, ahead: ahead, behind: behind,
            staged: staged, modified: modified, untracked: untracked
        )
    }

    private static func appendEntry(
        xy: Substring, path: String, originalPath: String?,
        staged: inout [GitStatusEntry], modified: inout [GitStatusEntry]
    ) {
        let index = xy.first ?? "."
        let worktree = xy.dropFirst().first ?? "."
        if index != ".", let status = entryStatus(for: index) {
            staged.append(GitStatusEntry(path: path, originalPath: originalPath, status: status))
        }
        if worktree != ".", let status = entryStatus(for: worktree) {
            modified.append(GitStatusEntry(path: path, originalPath: originalPath, status: status))
        }
    }

    private static func entryStatus(for char: Character) -> GitEntryStatus? {
        switch char {
        case "M", "T": return .modified
        case "A", "C": return .added
        case "D": return .deleted
        case "R": return .renamed
        default: return nil
        }
    }

    /// Git C-style quoting: paths with specials arrive as "..." with backslash escapes.
    private static func unquote(_ raw: String) -> String {
        guard raw.hasPrefix("\""), raw.hasSuffix("\""), raw.count >= 2 else { return raw }
        let inner = raw.dropFirst().dropLast()
        var result = ""
        var iterator = inner.makeIterator()
        while let ch = iterator.next() {
            guard ch == "\\", let escaped = iterator.next() else {
                result.append(ch)
                continue
            }
            switch escaped {
            case "t": result.append("\t")
            case "n": result.append("\n")
            case "\\": result.append("\\")
            case "\"": result.append("\"")
            default: result.append(escaped)
            }
        }
        return result
    }
}
```

- [ ] **Step 5: Run the new test class only**

Run: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild -project cmux.xcodeproj -scheme cmux-unit -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-files-git test -only-testing:cmuxTests/GitPorcelainStatusTests 2>&1 | tail -5`
Expected: all 5 tests pass. If "Executed 0 tests", the pbxproj wiring is wrong — fix Step 2.

- [ ] **Step 6: Commit**

```bash
git add Sources/Git/GitPorcelainStatus.swift cmuxTests/GitPorcelainStatusTests.swift cmux.xcodeproj/project.pbxproj
git commit -m "Git panel: porcelain v2 status parser" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: `GitWorkingTreeModel` (refresh + actions)

**Files:**
- Create: `Sources/Git/GitWorkingTreeModel.swift`
- Create: `cmuxTests/GitWorkingTreeModelTests.swift`
- Modify: `cmux.xcodeproj/project.pbxproj` (wire both)

**Interfaces:**
- Consumes: `GitPorcelainStatus.parse(_:)`, `GitStatusEntry`, `GitEntryStatus` (Task 1).
- Produces:

```swift
@MainActor
final class GitWorkingTreeModel: ObservableObject {
    @Published private(set) var status: GitPorcelainStatus = .empty
    @Published private(set) var isBusy: Bool = false
    @Published var lastErrorLine: String?          // inline error UI reads this
    var repoPath: String                            // workspace root; settable on workspace switch
    init(repoPath: String)
    func refresh() async
    func scheduleDebouncedRefresh()                 // 300ms coalesced; safe from watchers
    func stageFile(_ path: String) async
    func unstageFile(_ path: String) async
    func discardFile(_ entry: GitStatusEntry) async // checkout -- / clean -f for untracked
    func stageAll() async
    func discardAll() async
    func commit(message: String) async -> Bool
    func push() async -> Bool                       // -u origin <branch> when no upstream
    var publishCount: Int { get }                   // ahead count, or total entries when no upstream
    var hasUpstream: Bool { get }
}
```

- [ ] **Step 1: Write the failing tests (fixture repo)**

`cmuxTests/GitWorkingTreeModelTests.swift`:

```swift
import Foundation
import Testing
@testable import cmux

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
        try p.run(); p.waitUntilExit()
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

    @Test func commitWithNothingStagedFails() async throws {
        let repo = try makeFixtureRepo()
        defer { try? FileManager.default.removeItem(atPath: repo) }
        let model = GitWorkingTreeModel(repoPath: repo)
        let ok = await model.commit(message: "empty")
        #expect(!ok)
        #expect(model.lastErrorLine != nil)
    }
}
```

- [ ] **Step 2: Wire both files into pbxproj; `plutil -lint` OK.**

- [ ] **Step 3: Verify tests fail to compile** (`cannot find 'GitWorkingTreeModel'`), same build-for-testing command as Task 1.

- [ ] **Step 4: Implement the model**

`Sources/Git/GitWorkingTreeModel.swift`:

```swift
import Foundation

/// Working-tree git state + actions for one repository root.
/// All git invocations run off-main; published state mutates on the main actor.
@MainActor
final class GitWorkingTreeModel: ObservableObject {
    @Published private(set) var status: GitPorcelainStatus = .empty
    @Published private(set) var isBusy: Bool = false
    @Published var lastErrorLine: String?

    var repoPath: String {
        didSet { if repoPath != oldValue { Task { await refresh() } } }
    }

    private var debounceTask: Task<Void, Never>?

    init(repoPath: String) {
        self.repoPath = repoPath
    }

    // MARK: - Refresh

    func refresh() async {
        let path = repoPath
        guard !path.isEmpty else { status = .empty; return }
        let result = await Self.runGit(["status", "--porcelain=v2", "--branch"], in: path)
        switch result {
        case .success(let output):
            status = GitPorcelainStatus.parse(output)
            lastErrorLine = nil
        case .failure(let message):
            // Not a repo (or git missing): show empty state, keep the reason.
            status = .empty
            lastErrorLine = message.isEmpty ? nil : message
        }
    }

    /// Coalesces watcher bursts into one refresh ~300 ms after the last event.
    func scheduleDebouncedRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    // MARK: - Actions

    func stageFile(_ path: String) async { await runAction(["add", "--", path]) }
    func unstageFile(_ path: String) async { await runAction(["restore", "--staged", "--", path]) }

    func discardFile(_ entry: GitStatusEntry) async {
        if entry.status == .untracked {
            await runAction(["clean", "-f", "--", entry.path])
        } else {
            await runAction(["checkout", "--", entry.path])
        }
    }

    func stageAll() async { await runAction(["add", "-A"]) }

    func discardAll() async {
        await runAction(["checkout", "--", "."])
        await runAction(["clean", "-fd"])
    }

    @discardableResult
    func commit(message: String) async -> Bool {
        await runAction(["commit", "-m", message]) != nil
    }

    @discardableResult
    func push() async -> Bool {
        let args: [String]
        if hasUpstream {
            args = ["push"]
        } else if let branch = status.branch {
            args = ["push", "-u", "origin", branch]
        } else {
            lastErrorLine = String(localized: "gitPanel.error.detachedPush", defaultValue: "Cannot push: detached HEAD.")
            return false
        }
        return await runAction(args) != nil
    }

    var hasUpstream: Bool { status.upstream != nil }

    /// Count shown on the green Publish/Push button.
    var publishCount: Int {
        hasUpstream ? status.ahead
                    : status.staged.count + status.modified.count + status.untracked.count
    }

    // MARK: - Plumbing

    /// Runs a mutating git command, surfaces stderr's first line on failure,
    /// then re-reads status. Returns stdout on success, nil on failure.
    @discardableResult
    private func runAction(_ args: [String]) async -> String? {
        isBusy = true
        defer { isBusy = false }
        let result = await Self.runGit(args, in: repoPath)
        switch result {
        case .success(let output):
            lastErrorLine = nil
            await refresh()
            return output
        case .failure(let message):
            lastErrorLine = message
            await refresh()
            return nil
        }
    }

    private enum GitResult {
        case success(String)
        case failure(String)
    }

    private nonisolated static func runGit(_ args: [String], in directory: String) async -> GitResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.currentDirectoryURL = URL(fileURLWithPath: directory)
                process.arguments = args
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: .failure(String(describing: error)))
                    return
                }
                let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: .success(stdout))
                } else {
                    let firstLine = stderr.split(separator: "\n").first.map(String.init)
                        ?? stdout.split(separator: "\n").first.map(String.init)
                        ?? "git \(args.first ?? "") failed (\(process.terminationStatus))"
                    continuation.resume(returning: .failure(firstLine))
                }
            }
        }
    }
}
```

- [ ] **Step 5: Run only the new test class** (`-only-testing:cmuxTests/GitWorkingTreeModelTests`). Expected: 5 pass. Watch for "Executed 0 tests" (wiring bug).

- [ ] **Step 6: Commit**

```bash
git add Sources/Git/GitWorkingTreeModel.swift cmuxTests/GitWorkingTreeModelTests.swift cmux.xcodeproj/project.pbxproj
git commit -m "Git panel: working-tree model with stage/discard/commit/push" -m "Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Gitignore dimming in the file tree

**Files:**
- Modify: `Sources/FileExplorerStore.swift` (add ignored-path tracking; `loadChildren` at ~line 597 is the load path; `gitStatusByPath` at line 344 is the pattern to mirror)
- Modify: `Sources/FileExplorerCellView.swift` (alpha for ignored rows; style lookup begins at line 84)
- Modify: `cmuxTests/FileExplorerStoreTests.swift` (add tests)

**Interfaces:**
- Consumes: existing `FileExplorerStore`, `FileExplorerNode` (`id == path`).
- Produces:

```swift
// On FileExplorerStore:
@Published private(set) var ignoredPaths: Set<String>   // absolute paths
func isIgnored(_ path: String) -> Bool
// On FileExplorerCellView.configure(...): renders icon+label at 0.4 alpha when ignored.
```

- [ ] **Step 1: Write the failing test** (append to `cmuxTests/FileExplorerStoreTests.swift`):

```swift
@Test func marksGitignoredChildrenAsIgnored() async throws {
    let dir = NSTemporaryDirectory() + "cmux-ignore-" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: dir + "/.venv", withIntermediateDirectories: true)
    try "x\n".write(toFile: dir + "/kept.txt", atomically: true, encoding: .utf8)
    try ".venv/\ncalibration.json\n".write(toFile: dir + "/.gitignore", atomically: true, encoding: .utf8)
    try "{}\n".write(toFile: dir + "/calibration.json", atomically: true, encoding: .utf8)
    func git(_ args: [String]) throws {
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.currentDirectoryURL = URL(fileURLWithPath: dir); p.arguments = args
        try p.run(); p.waitUntilExit()
    }
    try git(["init"])
    defer { try? FileManager.default.removeItem(atPath: dir) }

    let store = FileExplorerStore()
    store.showHiddenFiles = true
    await store.setRootForTesting(dir)          // if no such helper exists, use the store's
                                                // existing root-assignment used by other tests
                                                // in this file — match their setup exactly.
    try await Task.sleep(nanoseconds: 500_000_000)
    #expect(store.isIgnored(dir + "/.venv"))
    #expect(store.isIgnored(dir + "/calibration.json"))
    #expect(!store.isIgnored(dir + "/kept.txt"))
}
```

(Before writing, read the top of `FileExplorerStoreTests.swift` and reuse its existing root-setup helper verbatim instead of `setRootForTesting` if it differs.)

- [ ] **Step 2: Verify it fails** (build-for-testing errors on `isIgnored`).

- [ ] **Step 3: Implement in `FileExplorerStore`**

Add next to `gitStatusByPath` (line 344):

```swift
@Published private(set) var ignoredPaths: Set<String> = []
func isIgnored(_ path: String) -> Bool { ignoredPaths.contains(path) }
```

At the end of `loadChildren(for:at:silent:)` (after child nodes are built and assigned), collect the just-loaded child paths and kick a batched check:

```swift
refreshIgnoredStatus(forChildPaths: entries.map(\.path))
```

New members (mirror `refreshGitStatus()`'s structure at line 427 — async work off-main, publish on main):

```swift
private func refreshIgnoredStatus(forChildPaths paths: [String]) {
    guard !paths.isEmpty, !rootPath.isEmpty else { return }
    let root = rootPath
    Task.detached(priority: .utility) { [weak self] in
        let ignored = Self.checkIgnored(paths: paths, repoRoot: root)
        guard !ignored.isEmpty else { return }
        await MainActor.run { self?.ignoredPaths.formUnion(ignored) }
    }
}

/// Feeds paths to `git check-ignore --stdin -z`; returns the subset git reports ignored.
private nonisolated static func checkIgnored(paths: [String], repoRoot: String) -> Set<String> {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.currentDirectoryURL = URL(fileURLWithPath: repoRoot)
    process.arguments = ["check-ignore", "--stdin", "-z"]
    let stdin = Pipe(), stdout = Pipe()
    process.standardInput = stdin
    process.standardOutput = stdout
    process.standardError = Pipe()
    guard (try? process.run()) != nil else { return [] }
    let payload = paths.joined(separator: "\0") + "\0"
    stdin.fileHandleForWriting.write(payload.data(using: .utf8) ?? Data())
    try? stdin.fileHandleForWriting.close()
    let data = stdout.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    // exit 0 = some ignored, 1 = none, others = error
    guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return [] }
    return Set(text.split(separator: "\0").map(String.init))
}
```

Also clear `ignoredPaths = []` wherever `gitStatusByPath` is reset on root change (search for `gitStatusByPath = [:]`, line ~429).

- [ ] **Step 4: Dim in `FileExplorerCellView`**

In `configure(...)` after the icon/label are set (post line 123), add:

```swift
let ignoredAlpha: CGFloat = store?.isIgnored(node.path) == true ? 0.4 : 1.0
iconView.alphaValue = ignoredAlpha
labelField.alphaValue = ignoredAlpha
```

(Match the actual property names in the cell — read the file first; if the cell has no store reference, pass `isIgnored: Bool` through the row-configure call chain from `FileExplorerNSOutlineView`'s data source, which does have the store.)

- [ ] **Step 5: Run only the FileExplorerStoreTests class.** Expected: new test passes, existing ones untouched.

- [ ] **Step 6: Commit** (`"Files tab: dim gitignored entries via batched check-ignore"` + trailer).

---

### Task 4: Files tab restyle (`codika` style, filter-in-tree, header buttons)

**Files:**
- Modify: `Sources/FileExplorerStore.swift:10-227` (add `case codika = 6`, make it default)
- Modify: `Sources/FileExplorerCellView.swift`, `Sources/FileExplorerRowView.swift` (chevron/hover/selection)
- Modify: `Sources/FileExplorerView.swift` (filter field row + reveal/collapse-all buttons)
- Modify: `Sources/FileExplorerSearchController.swift` (expose match function)

**Interfaces:**
- Consumes: `FileExplorerStyle`, `FileExplorerSearchController`'s fuzzy matcher, `store.ignoredPaths` (Task 3).
- Produces:
  - `FileExplorerStyle.codika` with: `rowHeight` base 34, `nameFont` 13 regular, `iconSize` 16, `indentation` 16, `selectionRadius` 6, `selectionInset` 6, `hoverColor` `.labelColor.withAlphaComponent(0.05)`, `folderIconTint` `.secondaryLabelColor`, `usesBorderSelection == false`, `gitColor` same values as `.vscodeIcons`.
  - `FileExplorerStore.filterText: String` (`@Published`); when non-empty the outline shows only matching files/dirs with ancestors auto-expanded.
  - `func collapseAllNodes()` and `func revealCurrentFile()` on the view's controller layer.

- [ ] **Step 1: Add the style case.** In every `switch self` inside `FileExplorerStyle` add a `.codika` arm with the metrics above (copy the `.vscodeIcons` arm then adjust `rowHeight: 34`, `nameFont: GlobalFontMagnification.systemFont(ofSize: 13, weight: .regular)`, `iconToTextSpacing: 8`, `selectionInset: 6`, `selectionRadius: 6`, `folderIconTint: .secondaryLabelColor`). Change `static var current` default (both branches at lines 220-226) from `.vscodeIcons` to `.codika`, and add `case codika = 6` with `label: "Codika"`.

- [ ] **Step 2: Chevrons only on directories + hover.** In `FileExplorerRowView` (it already reads `FileExplorerStyle.current` at line 6): confirm hover drawing uses `style.hoverColor`; in the outline-view delegate (`Sources/FileExplorerNSOutlineView.swift`) verify leaf rows hide the disclosure triangle (`outlineView(_:shouldShowOutlineCellForItem:)` returning `item.isDirectory`); add if missing.

- [ ] **Step 3: Filter field.** In `Sources/FileExplorerView.swift`, above the tree (where `FileExplorerHeaderView` / search field mounts), add a row: rounded-rect `NSSearchField`-style field with placeholder `String(localized: "filesPanel.filter.placeholder", defaultValue: "Filter…")` + two 20pt icon buttons using `HeaderChromeIconStyle`: `arrow.up.forward.square` → reveal current file, `chevron.up.2`/`rectangle.compress.vertical` → collapse all. Bind the field to `store.filterText`.

- [ ] **Step 4: Filter behavior in the store.** Add to `FileExplorerStore`:

```swift
@Published var filterText: String = ""
/// True when `name` fuzzily matches `filterText` (case-insensitive subsequence).
static func nameMatchesFilter(_ name: String, filter: String) -> Bool {
    guard !filter.isEmpty else { return true }
    var remainder = filter.lowercased()[...]
    for ch in name.lowercased() {
        if let first = remainder.first, first == ch { remainder = remainder.dropFirst() }
        if remainder.isEmpty { return true }
    }
    return remainder.isEmpty
}
```

In the outline data source, when `filterText` is non-empty, filter each node's children to those where `nameMatchesFilter(child.name, …)` OR the child is a directory containing any match (compute per-reload, cache in a `[String: Bool]` keyed by path, invalidated when `filterText` or `contentRevision` changes — never inside `body`/data-source callbacks; recompute in a `didSet` on `filterText` that calls the store's existing reload/refresh notification). Auto-expand directories that contain matches (call the existing expand path used by `FileExplorerSearchController` when jumping to results). Unit-test `nameMatchesFilter` with 4 cases (exact, subsequence "bp"→"bus.py", non-match, empty filter) appended to `FileExplorerStoreTests`.

- [ ] **Step 5: Collapse-all + reveal.** Collapse-all: `outlineView.collapseItem(nil, collapseChildren: true)` via the container view (`FileExplorerContainerView` — reachable from `FileExplorerView`). Reveal: reuse the existing "reveal file" machinery in `FileExplorerKeyboardShortcuts.swift`/container (search for `reveal`), targeting the focused terminal's current file if the existing API provides one, else the workspace's selected file-preview panel path; wire whichever exists — read those files first and call the existing entry point rather than inventing one.

- [ ] **Step 6: Localize new strings** — add `filesPanel.filter.placeholder` ("Filter…" / 「フィルタ…」), `filesPanel.collapseAll.tooltip` ("Collapse All" / 「すべて折りたたむ」), `filesPanel.reveal.tooltip` ("Reveal Current File" / 「現在のファイルを表示」) to `Resources/Localizable.xcstrings`.

- [ ] **Step 7: Compile check (app scheme) + run FileExplorerStoreTests only. Commit** (`"Files tab: codika style, in-tree filter, collapse/reveal header"` + trailer).

---

### Task 5: `FilesGitPanelView` shell (pill header + path line)

**Files:**
- Create: `Sources/FilesGitPanelView.swift`
- Modify: `Sources/RightSidebarPanelView.swift` (content switch), `Sources/ContentView.swift` (mount site — search `RightSidebarPanelView(`)
- Modify: `cmux.xcodeproj/project.pbxproj` (wire new file)

**Interfaces:**
- Consumes: `FileExplorerPanelView(presentation: .files, …)` (existing), `GitPanelView` (Task 6 — until then use `Text("")` placeholder replaced in Task 6), `GitWorkingTreeModel` (Task 2), `RightSidebarChromeMetrics`, `sidebarActiveForegroundNSColor` helpers from `Sources/Sidebar/SidebarAppearanceSupport.swift`.
- Produces:

```swift
enum FilesGitTab: String, Codable { case files, git }

struct FilesGitPanelView: View {
    @ObservedObject var explorerState: FileExplorerState   // existing owner of width/visibility
    @AppStorage("rightSidebar.filesGitTab") var tabRaw: String = FilesGitTab.files.rawValue
    // body: header pill + path line + tab content
}
```

- [ ] **Step 1: Build the view.**

`Sources/FilesGitPanelView.swift`:

```swift
import SwiftUI

enum FilesGitTab: String, Codable {
    case files
    case git
}

/// The right sidebar: a Files | Git pill header, the ~-abbreviated root path,
/// and the active tab's content.
struct FilesGitPanelView: View {
    @ObservedObject var explorerState: FileExplorerState
    @ObservedObject var gitModel: GitWorkingTreeModel
    let rootPath: String
    let filesContent: AnyView          // FileExplorerPanelView supplied by the mount site
    let gitContent: AnyView            // GitPanelView supplied by the mount site (Task 6)

    @AppStorage("rightSidebar.filesGitTab") private var tabRaw: String = FilesGitTab.files.rawValue

    private var tab: FilesGitTab { FilesGitTab(rawValue: tabRaw) ?? .files }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.vertical, 8)
            pathLine
                .padding(.bottom, 6)
            Divider().opacity(0.35)
            switch tab {
            case .files: filesContent
            case .git: gitContent
            }
        }
    }

    private var header: some View {
        HStack(spacing: 2) {
            segment(.files,
                    label: String(localized: "filesGitPanel.tab.files", defaultValue: "Files"),
                    symbol: "doc.on.doc")
            segment(.git,
                    label: String(localized: "filesGitPanel.tab.git", defaultValue: "Git"),
                    symbol: "arrow.triangle.branch")
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        .frame(maxWidth: .infinity)
        .titlebarInteractiveControl()
    }

    private func segment(_ value: FilesGitTab, label: String, symbol: String) -> some View {
        Button {
            tabRaw = value.rawValue
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(tab == value ? Color.primary.opacity(0.12) : .clear)
            )
            .foregroundStyle(tab == value ? .primary : .secondary)
        }
        .buttonStyle(.plain)
    }

    private var pathLine: some View {
        Text(Self.abbreviatedPath(rootPath))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
    }

    static func abbreviatedPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}
```

- [ ] **Step 2: Mount it.** In `RightSidebarPanelView` (`Sources/RightSidebarPanelView.swift`), replace the mode bar + `contentForMode` with `FilesGitPanelView`, passing `AnyView(FileExplorerPanelView(presentation: .files, …existing args…))` as `filesContent` and `AnyView(EmptyView())` for `gitContent` (Task 6 swaps it), plus a `GitWorkingTreeModel` created per workspace root: hold it in the same owner object that today owns `FileExplorerStore` (`RightSidebarToolPanel` for pane hosting; the ContentView-level state object for docked hosting — search `fileExplorerStore` ownership near `ContentView.swift:10561`) and update `gitModel.repoPath` wherever `applyWorkspaceRoot` is called today. Do NOT create the model in `body`.

- [ ] **Step 3: Path line data.** `rootPath` comes from the same source that feeds the explorer root (`FileExplorerWorkspaceRoot` application — search `applyWorkspaceRoot(` call sites).

- [ ] **Step 4: Localize** `filesGitPanel.tab.files` ("Files"/「ファイル」), `filesGitPanel.tab.git` ("Git"/「Git」).

- [ ] **Step 5: Unit test the pure helper** — append to any existing ContentView-adjacent test file or create `cmuxTests/FilesGitPanelTests.swift` (wire it):

```swift
import Testing
@testable import cmux

struct FilesGitPanelTests {
    @Test func abbreviatesHomePaths() {
        let home = NSHomeDirectory()
        #expect(FilesGitPanelView.abbreviatedPath(home) == "~")
        #expect(FilesGitPanelView.abbreviatedPath(home + "/x/y") == "~/x/y")
        #expect(FilesGitPanelView.abbreviatedPath("/tmp/z") == "/tmp/z")
    }
}
```

- [ ] **Step 6: App compile check + run FilesGitPanelTests only. Commit** (`"Right sidebar: FilesGitPanelView shell with Files|Git pill header"` + trailer).

---

### Task 6: Git tab UI (`GitPanelView`)

**Files:**
- Create: `Sources/Git/GitPanelView.swift`
- Modify: `Sources/RightSidebarPanelView.swift` (swap `gitContent` placeholder)
- Modify: `cmux.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: `GitWorkingTreeModel` (Task 2 signatures), `GitStatusEntry`, `GitEntryStatus`; file-open: call the same open path the file explorer uses for single-click preview (search `FileExplorerDoubleClickActionSettings` / the container's open-file closure) to open the diff/preview for a path; Changes affordance posts `openGitChangesPanel` closure (wired in Task 8 — until then the button is hidden behind `if openChanges != nil`).
- Produces:

```swift
struct GitPanelView: View {
    @ObservedObject var model: GitWorkingTreeModel
    let openFile: (String) -> Void          // absolute path
    let openChanges: (() -> Void)?          // nil until Task 8
}
```

- [ ] **Step 1: Implement the view.** Structure (all strings via `String(localized:)`; snapshot-boundary rule: rows receive plain `GitStatusEntry` values + closures, never the model):

```swift
import SwiftUI

struct GitPanelView: View {
    @ObservedObject var model: GitWorkingTreeModel
    let openFile: (String) -> Void
    let openChanges: (() -> Void)?

    @State private var commitMessage: String = ""
    @State private var confirmDiscardAll = false

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if let error = model.lastErrorLine {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12).padding(.vertical, 4)
            }
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: []) {
                    section(
                        title: String(localized: "gitPanel.section.staged", defaultValue: "STAGED"),
                        entries: model.status.staged,
                        trailing: sectionAction(
                            String(localized: "gitPanel.action.unstageAll", defaultValue: "Unstage All")
                        ) { Task { for e in model.status.staged { await model.unstageFile(e.path) } } },
                        perRow: { entry in
                            rowActions(entry, primarySymbol: "minus",
                                       primary: { Task { await model.unstageFile(entry.path) } })
                        }
                    )
                    section(
                        title: String(localized: "gitPanel.section.modified", defaultValue: "MODIFIED"),
                        entries: model.status.modified,
                        trailing: HStack(spacing: 10) {
                            sectionAction(String(localized: "gitPanel.action.discardAll", defaultValue: "Discard All")) {
                                confirmDiscardAll = true
                            }
                            sectionAction(String(localized: "gitPanel.action.stageAll", defaultValue: "Stage All")) {
                                Task { await model.stageAll() }
                            }
                        },
                        perRow: { entry in
                            rowActions(entry, primarySymbol: "plus",
                                       primary: { Task { await model.stageFile(entry.path) } })
                        }
                    )
                    section(
                        title: String(localized: "gitPanel.section.untracked", defaultValue: "UNTRACKED"),
                        entries: model.status.untracked,
                        trailing: sectionAction(
                            String(localized: "gitPanel.action.stageAll", defaultValue: "Stage All")
                        ) { Task { await model.stageAll() } },
                        perRow: { entry in
                            rowActions(entry, primarySymbol: "plus",
                                       primary: { Task { await model.stageFile(entry.path) } })
                        }
                    )
                }
            }
            commitBox
        }
        .confirmationDialog(
            String(localized: "gitPanel.discardAll.confirm", defaultValue: "Discard all changes? This cannot be undone."),
            isPresented: $confirmDiscardAll
        ) {
            Button(String(localized: "gitPanel.discardAll.confirmButton", defaultValue: "Discard All"), role: .destructive) {
                Task { await model.discardAll() }
            }
        }
        .task { await model.refresh() }
    }

    // MARK: toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 11))
            Text(model.status.branch ?? String(localized: "gitPanel.detached", defaultValue: "detached"))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            if model.status.ahead > 0 {
                Text("↑\(model.status.ahead)").font(.system(size: 11)).foregroundStyle(.green)
            }
            if model.status.behind > 0 {
                Text("↓\(model.status.behind)").font(.system(size: 11)).foregroundStyle(.orange)
            }
            Spacer()
            if let openChanges {
                Button(action: openChanges) { Image(systemName: "plusminus") }
                    .buttonStyle(.plain)
                    .help(String(localized: "gitPanel.openChanges.tooltip", defaultValue: "Open Changes"))
            }
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.plain)
                .help(String(localized: "gitPanel.refresh.tooltip", defaultValue: "Refresh"))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }

    // MARK: sections / rows (value snapshots only below here)

    @ViewBuilder
    private func section(
        title: String, entries: [GitStatusEntry],
        trailing: some View, perRow: @escaping (GitStatusEntry) -> AnyView
    ) -> some View {
        if !entries.isEmpty {
            HStack {
                Text("\(title) (\(entries.count))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                trailing
            }
            .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 4)
            ForEach(entries) { entry in
                GitFileRow(entry: entry, open: openFile, actions: perRow(entry))
            }
        }
    }

    private func sectionAction(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func rowActions(
        _ entry: GitStatusEntry, primarySymbol: String, primary: @escaping () -> Void
    ) -> AnyView {
        AnyView(HStack(spacing: 8) {
            Button(action: primary) { Image(systemName: primarySymbol).font(.system(size: 10)) }
                .buttonStyle(.plain)
            Button { Task { await model.discardFile(entry) } } label: {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 10))
            }
            .buttonStyle(.plain)
        })
    }

    // MARK: commit box

    private var commitBox: some View {
        VStack(spacing: 8) {
            TextField(
                String(localized: "gitPanel.commitMessage.placeholder", defaultValue: "Commit message…"),
                text: $commitMessage, axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .lineLimit(2...4)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            HStack(spacing: 8) {
                Button {
                    let message = commitMessage
                    Task { if await model.commit(message: message) { commitMessage = "" } }
                } label: {
                    Text(String(localized: "gitPanel.commit", defaultValue: "Commit"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.status.staged.isEmpty ||
                          commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Button {
                    Task { await model.push() }
                } label: {
                    Text(model.hasUpstream
                         ? String(localized: "gitPanel.push", defaultValue: "Push (\(model.publishCount))")
                         : String(localized: "gitPanel.publishBranch", defaultValue: "Publish Branch (\(model.publishCount))"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(model.publishCount == 0 && model.hasUpstream)
            }
            .controlSize(.small)
        }
        .padding(12)
    }
}

/// Snapshot-boundary row: value entry + closures only.
private struct GitFileRow: View {
    let entry: GitStatusEntry
    let open: (String) -> Void
    let actions: AnyView

    @State private var hovering = false

    private var letterColor: Color {
        switch entry.status {
        case .modified: return .orange
        case .added: return .green
        case .deleted: return .red
        case .renamed: return .blue
        case .untracked: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(String(entry.status.rawValue))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(letterColor)
                .frame(width: 12)
            Text((entry.path as NSString).lastPathComponent)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if hovering { actions }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
        .onHover { hovering = $0 }
        .onTapGesture { open(entry.path) }
    }
}
```

Note: `openFile` receives the **repo-relative** path from the entry; the mount site converts to absolute (`rootPath + "/" + path`) before invoking the explorer's open-file closure.

- [ ] **Step 2: Swap the placeholder** in `RightSidebarPanelView`: `gitContent: AnyView(GitPanelView(model: gitModel, openFile: { … }, openChanges: nil))` where the openFile closure resolves absolute path and calls the same handler the file tree uses for single-click open.

- [ ] **Step 3: Localize** all keys used above (en + ja): `gitPanel.section.staged/modified/untracked`, `gitPanel.action.stageAll/unstageAll/discardAll`, `gitPanel.commit`, `gitPanel.push`, `gitPanel.publishBranch`, `gitPanel.commitMessage.placeholder`, `gitPanel.refresh.tooltip`, `gitPanel.openChanges.tooltip`, `gitPanel.discardAll.confirm`, `gitPanel.discardAll.confirmButton`, `gitPanel.detached`, `gitPanel.error.detachedPush` (from Task 2). Japanese: ステージ済み / 変更 / 未追跡 / すべてステージ / すべてアンステージ / すべて破棄 / コミット / プッシュ (%d) / ブランチを公開 (%d) / コミットメッセージ… / 更新 / 変更を開く / すべての変更を破棄しますか？この操作は取り消せません。 / すべて破棄 / デタッチ状態 / プッシュできません: デタッチ状態です。

- [ ] **Step 4: App compile check. Commit** (`"Git tab: status sections, per-file actions, commit box"` + trailer).

---

### Task 7: Delete the old right-sidebar modes

**Files:**
- Modify: `Sources/RightSidebarPanelView.swift` (delete `RightSidebarMode` enum at line 15, mode bar, `contentForMode`), `Sources/RightSidebarMode+Availability.swift` (delete file), `Sources/RightSidebarToolPanel.swift` (drop `mode`, keep files-only panel), `Sources/KeyboardShortcutSettings.swift:93-97` + label arms 219-223 (remove `switchRightSidebarToFind/Sessions/Feed/Dock`; keep `switchRightSidebarToFiles`, add `switchRightSidebarToGit`), `Sources/ContentView+RightSidebarCommandPalette.swift` (palette entries), `Sources/FileExplorerView.swift` (remove `.find` presentation), settings routing (`Sources/CmuxSettingsJSONPathSupport.swift`, `web/data/cmux-shortcuts.ts`, `web/data/cmux.schema.json` — grep `rightSidebar` and the dead action names)
- Delete: `Sources/FileExplorerSearchResultsTableView.swift`, `Sources/FileExplorerSearchResultCellView.swift` (+ pbxproj entries), Feed/Dock right-sidebar hosting references (`FeedPanelView`/`DockPanelView` mounts in RightSidebarPanelView only — the panel source files stay if other surfaces use them; grep callers first, delete the files too if the right sidebar was the only mount)
- Modify: `cmuxTests/` — delete/trim tests referencing removed modes (`HiddenRightSidebarContentMountingTests`, `FileExplorerRootSyncPolicyTests` — update to files/git enum)

**Interfaces:**
- Consumes: `FilesGitTab` (Task 5).
- Produces: `KeyboardShortcutSettings.Action.switchRightSidebarToGit` (label `String(localized: "shortcut.switchRightSidebarToGit.label", defaultValue: "Show Sidebar Git")`; no default keybinding), routed to set `FilesGitTab.git` + open the sidebar (mirror the existing `switchRightSidebarToFiles` routing — grep its call sites in `AppDelegate.swift`/`MainWindowFocusController`).

- [ ] **Step 1: Grep the blast radius** — `rg -n 'RightSidebarMode|switchRightSidebarTo(Find|Sessions|Feed|Dock)|\.find\b' Sources cmuxTests web/data` and list every hit before editing.
- [ ] **Step 2: Remove enum + UI**; replace `RightSidebarMode` storage in `FileExplorerState` (grep `mode` persistence there) with `FilesGitTab` where needed.
- [ ] **Step 3: Shortcuts**: delete the four dead actions everywhere they appear (settings UI list, `web/data/cmux-shortcuts.ts`, docs); add `switchRightSidebarToGit` following the Shortcut policy (Settings-visible, cmux.json path, docs row).
- [ ] **Step 4: Delete search-results table files + pbxproj entries.** `.find` mode folds away: `FileExplorerPanelView` keeps only `.files` presentation (delete the `presentation` parameter if `.files` is the only case left — grep constructors).
- [ ] **Step 5: Regression test** — in `cmuxTests/FileExplorerRootSyncPolicyTests.swift` (or new `RightSidebarModeRemovalTests.swift`, wired), assert the shortcut catalog no longer contains the dead actions:

```swift
@Test func deadRightSidebarShortcutsAreGone() {
    let ids = KeyboardShortcutSettings.Action.allCases.map(\.rawValue)
    #expect(!ids.contains("switchRightSidebarToFind"))
    #expect(!ids.contains("switchRightSidebarToSessions"))
    #expect(!ids.contains("switchRightSidebarToFeed"))
    #expect(!ids.contains("switchRightSidebarToDock"))
    #expect(ids.contains("switchRightSidebarToGit"))
}
```

- [ ] **Step 6: Localize** the new shortcut label (en+ja: "Show Sidebar Git" / 「サイドバーの Git を表示」); stale keys for removed strings may remain in the xcstrings (harmless).
- [ ] **Step 7: App compile + build-for-testing compile + run the regression class. Commit** (`"Right sidebar: strictly Files|Git — remove find/vault/feed/dock modes"` + trailer).

---

### Task 8: `GitChangesPanel` (main-area diff review)

**Files:**
- Create: `Sources/Panels/GitChangesPanel.swift` (Panel conformer + SwiftUI host)
- Create: `Resources/git-changes/changes.html`
- Modify: `Sources/Panels/Panel.swift:6-15` (add `case gitChanges`), the panel factory/restore switch (grep `case .markdown` in `Sources/Workspace.swift` + `SessionPersistence.swift` to find every exhaustive switch), `Sources/Git/GitPanelView.swift` (pass `openChanges`), `RightSidebarPanelView` mount (wire the closure to `workspace.openGitChangesPanel()`)
- Modify: `cmux.xcodeproj/project.pbxproj` (source + resource; `changes.html` goes in the Resources copy phase like `Resources/monaco/monaco.html` — copy that entry pattern)

**Interfaces:**
- Consumes: `GitWorkingTreeModel` (stage/unstage/discard + status), Monaco assets at `Resources/monaco/` (loader pattern from `Resources/monaco/monaco.html`: `require.config({ paths: { vs: … } })` then `require(["vs/editor/editor.main"], …)`), `MonacoWebController` patterns for WKWebView setup (read `Sources/Monaco/MonacoWebController.swift` and mirror its script-message + local-file loading approach).
- Produces:

```swift
@MainActor
final class GitChangesPanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = .gitChanges
    var displayTitle: String   // "Changes"
    init(workspace: Workspace, model: GitWorkingTreeModel)
    func reload() async        // recomputes diffs, pushes JSON to the web view
}
// On Workspace:
func openGitChangesPanel()     // focuses existing panel or creates one
```

JS bridge messages (webkit.messageHandlers.cmuxGitChanges.postMessage):
`{type: "stage"|"unstage"|"revert"|"openFile", path: string}`
Swift→JS: `window.cmuxRenderChanges(payloadJSON)` where payload is
`{files: [{path, status, staged, original, modified, language}]}`.

- [ ] **Step 1: Diff payload.** In `GitChangesPanel.reload()`, for each entry in staged+modified+untracked: `original` = `git show HEAD:<path>` output ("" for added/untracked), `modified` = current file contents ("" for deleted), `language` from `MonacoLanguageMap` (existing — grep `MonacoLanguageMap.language`), `staged` = membership in `status.staged`. Run git reads with the same `runGit` pattern as Task 2 (add an internal `static func runGit` overload or make Task 2's `runGit` `internal static` and reuse — do the latter: change its access level and call `GitWorkingTreeModel.runGit(["show", "HEAD:\(path)"], in: repoPath)`).
- [ ] **Step 2: `changes.html`.** Single page, dark-aware, loads Monaco exactly like `Resources/monaco/monaco.html` does (copy its `require.config` + error-reporting boilerplate verbatim, including the `paths: { vs }` fix), then:

```html
<div id="cards"></div>
<script>
  // Called from Swift with the payload described above.
  window.cmuxRenderChanges = function (payloadJSON) {
    const payload = JSON.parse(payloadJSON);
    const cards = document.getElementById("cards");
    cards.textContent = "";
    for (const file of payload.files) {
      const card = document.createElement("section");
      card.className = "card";
      const header = document.createElement("header");
      const title = document.createElement("span");
      title.textContent = file.path + (file.status === "U" ? "  ·  New" : "");
      header.appendChild(title);
      header.appendChild(button(file.staged ? "Unstage" : "Stage", () =>
        post({ type: file.staged ? "unstage" : "stage", path: file.path })));
      header.appendChild(button("Revert", () => post({ type: "revert", path: file.path })));
      header.appendChild(button("Open", () => post({ type: "openFile", path: file.path })));
      card.appendChild(header);
      const host = document.createElement("div");
      host.className = "diff";
      card.appendChild(host);
      cards.appendChild(card);
      const editor = monaco.editor.createDiffEditor(host, {
        readOnly: true, renderSideBySide: false, automaticLayout: true,
        scrollBeyondLastLine: false, minimap: { enabled: false },
        scrollbar: { vertical: "hidden", handleMouseWheel: false },
      });
      editor.setModel({
        original: monaco.editor.createModel(file.original, file.language),
        modified: monaco.editor.createModel(file.modified, file.language),
      });
      // Auto-height: size the host to the modified editor's content.
      const grow = () => { host.style.height =
        Math.min(2000, Math.max(80, editor.getModifiedEditor().getContentHeight() + 20)) + "px"; };
      editor.getModifiedEditor().onDidContentSizeChange(grow);
      grow();
    }
  };
  function post(msg) { window.webkit.messageHandlers.cmuxGitChanges.postMessage(msg); }
  function button(label, onClick) {
    const b = document.createElement("button");
    b.textContent = label; b.addEventListener("click", onClick); return b;
  }
</script>
```

plus a `<style>` block: cards with 8px radius, 1px `rgba(127,127,127,.25)` border, 12px gap, header 12px secondary text, buttons plain text 11px. (Button labels are English-in-web-view; add the same strings to the payload later only if we localize the web view — v1 keeps JS labels sourced from Swift: include `strings: {stage, unstage, revert, open, newBadge}` in the payload, localized Swift-side with keys `gitChanges.stage/unstage/revert/open/new` en+ja, and use those instead of literals — do it this way, not hardcoded.)
- [ ] **Step 3: Panel + host.** `GitChangesPanel` follows `RightSidebarToolPanel`'s conformer shape (id/panelType/displayTitle/focus). The hosting view embeds a `WKWebView` configured like `MonacoWebController` (same `WKWebViewConfiguration` handler registration; message handler name `cmuxGitChanges`); left column = the web view; right rail = SwiftUI checklist bound to value snapshots of the three sections with a checkbox per file (checked = staged → toggling calls stage/unstage and `reload()`), grouped by top-level directory, `+N` per file omitted in v1 if numstat isn't already loaded — include counts by running `git diff --numstat HEAD` once per reload and matching paths.
- [ ] **Step 4: Wiring.** Add `case gitChanges` to `PanelType`; fix every exhaustive switch the compiler flags; `Workspace.openGitChangesPanel()` mirrors the existing markdown-panel creation call (grep `MarkdownPanel(` in `Sources/Workspace.swift` and copy the surface-insertion call around it); Git tab toolbar + file-row click route here when the Changes panel is open.
- [ ] **Step 5: Localize** `gitChanges.title` ("Changes"/「変更」) + the payload strings from Step 2.
- [ ] **Step 6: App compile check; manual smoke via tagged build (open Changes, stage/unstage from a card, revert with confirm — revert message routes through the same `discardFile`). Commit** (`"Changes panel: stacked Monaco diff cards + staging checklist"` + trailer).

---

### Task 9: Final wiring, localization audit, build handoff

**Files:**
- Modify: `Resources/Localizable.xcstrings` (verify every key from Tasks 4-8 has en+ja), `web/data/cmux-shortcuts.ts` + shortcut docs (new `switchRightSidebarToGit` row), `web/data/cmux.schema.json` if any setting key changed
- Verify: `cmux.xcodeproj/project.pbxproj`

- [ ] **Step 1: Localization audit.** `rg -n 'String\(localized: "(filesPanel|filesGitPanel|gitPanel|gitChanges|shortcut.switchRightSidebarToGit)' Sources` → for each key, confirm an en and ja entry exists in `Resources/Localizable.xcstrings` (parse with `plutil -p` or python json). Fix gaps.
- [ ] **Step 2: pbxproj lint**: `./scripts/lint-pbxproj-test-wiring.sh` and `python3 scripts/check-workspace-package-groups.py --check` and `python3 scripts/check-package-resolved-policy.py` — all green.
- [ ] **Step 3: Targeted tests**: run only the classes added by this plan (`GitPorcelainStatusTests`, `GitWorkingTreeModelTests`, `FileExplorerStoreTests`, `FilesGitPanelTests`, the Task 7 regression class). All pass.
- [ ] **Step 4: Tagged build** for Mike: `./scripts/reload.sh --tag files-git-panel` (with `CMUX_SKIP_ZIG_BUILD=1` if the zig helper fails), then report the `App path:` as a cmd-clickable `file://` link per CLAUDE.md.
- [ ] **Step 5: Commit any stragglers**; final message states what localization audit was performed.
