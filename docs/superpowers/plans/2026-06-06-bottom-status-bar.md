# Bottom Status Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a VSCode-style bottom status bar in the content region (never over the left sidebar) showing cmux version, the active terminal's git branch, staged-diff numbers, and the resolved editor; rewire sidebar file double-click to open the file in a new tab running micro/vim (configurable); ship the rainbow context bar + agent usage as a hidden, seam-ready stub.

**Architecture:** New `Sources/StatusBar/` package-style folder (one type per file). The bar consumes immutable/observed values (it's always present, so it must not couple to high-churn stores in a way that re-renders on every keystroke). Staged-diff stats come from a new `StagedDiffProvider` (actor) reusing the existing `runGit` Process pattern, refreshed via a `FileWatcher` on the repo root. The editor preference is a string setting (empty = auto micro→vim) mirroring the existing `app.preferredEditor`. Open-in-editor uses `TabManager.addWorkspace(initialTerminalCommand:)`. The rainbow context bar renders only when a `ContextUsageProviding` returns non-nil; a `NullContextUsageProvider` returns nil today.

**Tech Stack:** Swift 6 (actors/async, `@Observable`/`ObservableObject`), SwiftUI, Swift Testing, `Process`/`FileWatcher`, `UserDefaults` + `CmuxSettings`/`CmuxSettingsUI` packages, `Resources/Localizable.xcstrings` (en+ja).

---

## Conventions (same as the prior feature)
- **Compile/test target:** `xcodebuild -project cmux.xcodeproj -scheme cmux-unit -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-bottom-bar CMUX_SKIP_ZIG_BUILD=1 build-for-testing` (the controller runs builds at checkpoints; implementers do NOT run Xcode builds). Check the log for `** TEST BUILD SUCCEEDED **` (don't pipe through `tail` — it masks the exit code).
- **App build (visual verify, controller only):** `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag bottom-bar`.
- **New `Sources/StatusBar/**` files and new `cmuxTests/**` files MUST be wired into `cmux.xcodeproj/project.pbxproj`** (app target / cmuxTests target respectively), then `python3 scripts/normalize-pbxproj.py cmux.xcodeproj/project.pbxproj && ./scripts/lint-pbxproj-test-wiring.sh && ./scripts/check-pbxproj.sh`. Editing EXISTING files in `Packages/CmuxSettings*/` needs no new wiring.
- **Test quality:** unit-test pure logic (numstat parsing, editor resolution, command building) asserting returned values; view/provider/wiring verified by build + manual reload. Never assert source text.
- **Locate code by searching quoted anchors**, not line numbers (they drift).
- **Localization:** every new user-facing string uses `String(localized:defaultValue:)` AND has en + ja in `Resources/Localizable.xcstrings`.
- Commit footer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`.
- pbxproj wiring template: mirror an existing wired sibling, e.g. `rg -n "SidebarExplorerSplit.swift" cmux.xcodeproj/project.pbxproj` (app-target file) and `rg -n "SidebarExplorerSplitTests.swift" cmux.xcodeproj/project.pbxproj` (test file); use fresh unique 24-hex ids.

---

## Task 1: `StagedDiffStats` + numstat parser (pure) + tests

**Files:**
- Create: `Sources/StatusBar/StagedDiffStats.swift`
- Create test: `cmuxTests/StagedDiffStatsTests.swift`
- Modify: `cmux.xcodeproj/project.pbxproj` (wire both)

- [ ] **Step 1: Write the failing test** — `cmuxTests/StagedDiffStatsTests.swift`:

```swift
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct StagedDiffStatsTests {
    @Test func emptyOutputIsZero() {
        let s = StagedDiffStats.parseNumstat("")
        #expect(s.files == 0)
        #expect(s.additions == 0)
        #expect(s.deletions == 0)
    }

    @Test func sumsAddsAndDelsAndCountsFiles() {
        let out = "12\t3\tSources/A.swift\n0\t7\tSources/B.swift\n"
        let s = StagedDiffStats.parseNumstat(out)
        #expect(s.files == 2)
        #expect(s.additions == 12)
        #expect(s.deletions == 10)
    }

    @Test func binaryFilesCountButContributeNoLines() {
        let out = "-\t-\tassets/logo.png\n5\t1\tREADME.md\n"
        let s = StagedDiffStats.parseNumstat(out)
        #expect(s.files == 2)
        #expect(s.additions == 5)
        #expect(s.deletions == 1)
    }

    @Test func isEmptyWhenNothingStaged() {
        #expect(StagedDiffStats.parseNumstat("").isEmpty)
        #expect(!StagedDiffStats.parseNumstat("1\t0\tx").isEmpty)
    }
}
```

- [ ] **Step 2: Verify it fails to compile.** `xcodebuild ... cmux-unit ... build-for-testing` → FAIL (`cannot find 'StagedDiffStats'`).

- [ ] **Step 3: Implement** — `Sources/StatusBar/StagedDiffStats.swift`:

```swift
import Foundation

/// Counts of staged (index) changes for a git repository.
///
/// Produced by ``StagedDiffProvider`` from `git diff --cached --numstat` and
/// shown in the bottom status bar as `⊕<files> +<additions> −<deletions>`.
struct StagedDiffStats: Equatable, Sendable {
    /// Number of files with staged changes.
    let files: Int
    /// Total added lines across staged files (binary files contribute 0).
    let additions: Int
    /// Total deleted lines across staged files (binary files contribute 0).
    let deletions: Int

    /// A stats value representing no staged changes.
    static let empty = StagedDiffStats(files: 0, additions: 0, deletions: 0)

    /// Whether there are no staged changes.
    var isEmpty: Bool { files == 0 && additions == 0 && deletions == 0 }

    /// Parses `git diff --cached --numstat` output.
    ///
    /// Each line is `<additions>\t<deletions>\t<path>`, where a binary file uses
    /// `-` for both counts. Blank/short lines are ignored.
    /// - Parameter output: raw stdout from `git diff --cached --numstat`.
    /// - Returns: summed additions/deletions and a per-line file count.
    static func parseNumstat(_ output: String) -> StagedDiffStats {
        var files = 0
        var additions = 0
        var deletions = 0
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = rawLine.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            files += 1
            if let add = Int(parts[0]) { additions += add }
            if let del = Int(parts[1]) { deletions += del }
        }
        return StagedDiffStats(files: files, additions: additions, deletions: deletions)
    }
}
```

- [ ] **Step 4: Wire both files into pbxproj** (template above) → normalize + lint + check.
- [ ] **Step 5: Verify compile.** `xcodebuild ... cmux-unit ... build-for-testing` → success.
- [ ] **Step 6: Commit**

```bash
git add Sources/StatusBar/StagedDiffStats.swift cmuxTests/StagedDiffStatsTests.swift cmux.xcodeproj/project.pbxproj
git commit -m "Add StagedDiffStats + numstat parser for the bottom bar"
```

## Task 2: `StagedDiffProvider` (actor)

**Files:**
- Create: `Sources/StatusBar/StagedDiffProvider.swift`
- Modify: `cmux.xcodeproj/project.pbxproj` (wire it — app target only)

Reuses the `runGit` Process pattern from `FileExplorerStore` (verbatim shape) inside an actor; pure parsing delegated to `StagedDiffStats.parseNumstat`.

- [ ] **Step 1: Implement** — `Sources/StatusBar/StagedDiffProvider.swift`:

```swift
import Foundation

/// Computes staged-diff stats for a directory's git repository, off the main
/// actor.
///
/// Mirrors ``FileExplorerStore``'s `runGit` Process pattern. Pure parsing lives
/// in ``StagedDiffStats/parseNumstat(_:)`` so it is unit-tested without a git
/// process.
actor StagedDiffProvider {
    /// Returns staged stats for the git repo containing `directory`, or `nil`
    /// when the directory is not in a git repo.
    /// - Parameter directory: any path inside the working tree.
    func stagedStats(in directory: String) -> StagedDiffStats? {
        let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let repoRoot = Self.runGit(in: trimmed, arguments: ["rev-parse", "--show-toplevel"])?
            .trimmingCharacters(in: .whitespacesAndNewlines), !repoRoot.isEmpty else {
            return nil
        }
        guard let numstat = Self.runGit(in: repoRoot, arguments: ["diff", "--cached", "--numstat"]) else {
            return nil
        }
        return StagedDiffStats.parseNumstat(numstat)
    }

    /// Runs `git` with `arguments` in `directory`, capturing stdout.
    private static func runGit(in directory: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = ProcessPipeReader.readDataToEndOfFileOrEmpty(from: pipe.fileHandleForReading)
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
```

(Confirm `ProcessPipeReader.readDataToEndOfFileOrEmpty(from:)` exists — it is the same helper `FileExplorerStore.runGit` uses; `rg -n "ProcessPipeReader" Sources/ | head`.)

- [ ] **Step 2: Wire into pbxproj** (app target) → normalize + check.
- [ ] **Step 3: Verify compile** (controller checkpoint).
- [ ] **Step 4: Commit**

```bash
git add Sources/StatusBar/StagedDiffProvider.swift cmux.xcodeproj/project.pbxproj
git commit -m "Add StagedDiffProvider actor (git diff --cached --numstat)"
```

## Task 3: `EditorPreferenceSettings` + `EditorLauncher` (pure resolver + command builder) + tests

**Files:**
- Create: `Sources/StatusBar/EditorPreferenceSettings.swift`
- Create: `Sources/StatusBar/EditorLauncher.swift`
- Create test: `cmuxTests/EditorLauncherTests.swift`
- Modify: `cmux.xcodeproj/project.pbxproj` (wire all three)

Editor preference is a single string (empty = auto micro→vim, non-empty = that command), distinct from the pre-existing `app.preferredEditor` (a GUI/preview fallback). UserDefaults key `terminalEditor`, json path `app.terminalEditor`.

- [ ] **Step 1: Write the failing test** — `cmuxTests/EditorLauncherTests.swift`:

```swift
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct EditorLauncherTests {
    @Test func autoPrefersMicroWhenAvailable() {
        let cmd = EditorLauncher.resolveEditorCommand(stored: nil, isAvailable: { $0 == "micro" })
        #expect(cmd == "micro")
    }

    @Test func autoFallsBackToVimWhenNoMicro() {
        let cmd = EditorLauncher.resolveEditorCommand(stored: "", isAvailable: { _ in false })
        #expect(cmd == "vim")
    }

    @Test func customCommandOverridesAuto() {
        let cmd = EditorLauncher.resolveEditorCommand(stored: "nvim", isAvailable: { _ in true })
        #expect(cmd == "nvim")
    }

    @Test func openCommandQuotesPath() {
        let cmd = EditorLauncher.openInEditorCommand(editor: "micro", path: "/Users/me/a b.txt")
        #expect(cmd == "micro '/Users/me/a b.txt'")
    }

    @Test func openCommandEscapesSingleQuotes() {
        let cmd = EditorLauncher.openInEditorCommand(editor: "vim", path: "/tmp/it's.txt")
        #expect(cmd == "vim '/tmp/it'\\''s.txt'")
    }

    @Test func editorDisplayNameIsLeafOfCommand() {
        #expect(EditorLauncher.editorDisplayName(forCommand: "/opt/homebrew/bin/micro --flag") == "micro")
        #expect(EditorLauncher.editorDisplayName(forCommand: "vim") == "vim")
    }
}
```

- [ ] **Step 2: Verify it fails.** `build-for-testing` → FAIL (`cannot find 'EditorLauncher'`).

- [ ] **Step 3: Implement** — `Sources/StatusBar/EditorPreferenceSettings.swift`:

```swift
import Foundation

/// Reads the terminal-editor preference used by the sidebar "open file" action
/// and the bottom-bar editor indicator.
///
/// Stored as a single command string under ``key``. An empty/unset value means
/// "auto": prefer `micro` if it is on `PATH`, else `vim`. A non-empty value is
/// used verbatim as the editor command. This is intentionally separate from
/// `app.preferredEditor` (the GUI/preview fallback editor).
enum EditorPreferenceSettings {
    /// The `UserDefaults` key backing the terminal-editor command.
    static let key = "terminalEditor"

    /// The stored editor command, or `nil` when unset/empty (→ auto).
    /// - Parameter defaults: the store to read (injected for tests).
    static func storedCommand(defaults: UserDefaults = .standard) -> String? {
        guard let raw = defaults.string(forKey: key) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
```

`Sources/StatusBar/EditorLauncher.swift`:

```swift
import Foundation

/// Resolves and launches the configured terminal editor.
///
/// The resolution and command-building functions are pure (an `isAvailable`
/// probe is injected) so they are unit-tested without touching `PATH`. The
/// `availableOnPath(_:)` helper performs the real `which` probe in production.
enum EditorLauncher {
    /// Resolves the editor command to run.
    /// - Parameters:
    ///   - stored: the configured command (nil/empty → auto micro→vim).
    ///   - isAvailable: probe returning whether a binary is on `PATH`.
    /// - Returns: `stored` when non-empty, else `"micro"` if available else `"vim"`.
    static func resolveEditorCommand(stored: String?, isAvailable: (String) -> Bool) -> String {
        if let stored, !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return isAvailable("micro") ? "micro" : "vim"
    }

    /// Builds a shell command that opens `path` in `editor`, single-quoting the
    /// path (with single-quote escaping) so spaces/specials are safe.
    static func openInEditorCommand(editor: String, path: String) -> String {
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "\(editor) '\(escaped)'"
    }

    /// The short name shown in the bottom bar (leaf of the command's first token).
    static func editorDisplayName(forCommand command: String) -> String {
        let firstToken = command.split(separator: " ").first.map(String.init) ?? command
        return (firstToken as NSString).lastPathComponent
    }

    /// Whether `name` is on `PATH` (`which <name>`), cached per process run.
    /// Used as the default `isAvailable` probe in production.
    static func availableOnPath(_ name: String) -> Bool {
        if let cached = pathCache[name] { return cached }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let ok: Bool
        do {
            try process.run()
            process.waitUntilExit()
            ok = process.terminationStatus == 0
        } catch {
            ok = false
        }
        pathCache[name] = ok
        return ok
    }

    // Process-lifetime cache of `which` results. Main-actor-confined access via
    // the call sites (bar render + open action), which are @MainActor.
    @MainActor private static var pathCache: [String: Bool] = [:]
}
```

> Note: `pathCache` is `@MainActor`-isolated; `availableOnPath` is therefore called from `@MainActor` contexts (the bar render + the open action). If the actor isolation causes friction at a call site, mark the call site `@MainActor` (both call sites already are). The pure functions (`resolveEditorCommand`, `openInEditorCommand`, `editorDisplayName`) are nonisolated and the focus of tests.

- [ ] **Step 4: Wire all three files into pbxproj** → normalize + lint + check.
- [ ] **Step 5: Verify compile.**
- [ ] **Step 6: Commit**

```bash
git add Sources/StatusBar/EditorPreferenceSettings.swift Sources/StatusBar/EditorLauncher.swift cmuxTests/EditorLauncherTests.swift cmux.xcodeproj/project.pbxproj
git commit -m "Add EditorPreferenceSettings + EditorLauncher (auto micro->vim, custom override)"
```

## Task 4: Deferred context-usage seam + value types + rainbow bar view

**Files:**
- Create: `Sources/StatusBar/ContextUsageProviding.swift`
- Create: `Sources/StatusBar/BottomBarSnapshot.swift`
- Create: `Sources/StatusBar/RainbowContextBar.swift`
- Modify: `cmux.xcodeproj/project.pbxproj` (wire all three)

- [ ] **Step 1: Implement** — `Sources/StatusBar/ContextUsageProviding.swift`:

```swift
import Foundation

/// Context-window usage for the active agent, used by the bottom bar's rainbow
/// context bar and usage text.
struct ContextUsage: Equatable, Sendable {
    /// Fraction of the context window in use, clamped to `0...1`.
    let contextFraction: Double
    /// Optional usage/limit text (e.g. session/rate-limit summary), or `nil`.
    let limitText: String?
}

/// Supplies ``ContextUsage`` for a workspace's active agent.
///
/// cmux has no native agent context/usage data today, so the production binding
/// uses ``NullContextUsageProvider`` (always `nil` → the rainbow bar is hidden).
/// A future provider (transcript parsing or an external `ccusage`-style command)
/// can replace it at the composition root without touching the bar view.
protocol ContextUsageProviding {
    /// Returns usage for the workspace with the given working directory and
    /// active agent, or `nil` when unavailable.
    func usage(workingDirectory: String?, agentActive: Bool) -> ContextUsage?
}

/// The default provider: always returns `nil` (feature deferred).
struct NullContextUsageProvider: ContextUsageProviding {
    func usage(workingDirectory: String?, agentActive: Bool) -> ContextUsage? { nil }
}
```

`Sources/StatusBar/BottomBarSnapshot.swift`:

```swift
import Foundation

/// Immutable inputs the bottom bar renders. Built by the owning view from the
/// active workspace + providers so the always-present bar doesn't couple to
/// high-churn observable state in its body.
struct BottomBarSnapshot: Equatable {
    let appVersion: String
    let branch: String?
    let isDirty: Bool
    let staged: StagedDiffStats
    let editorDisplayName: String
    let agentActive: Bool
    let contextUsage: ContextUsage?

    static let placeholder = BottomBarSnapshot(
        appVersion: "",
        branch: nil,
        isDirty: false,
        staged: .empty,
        editorDisplayName: "",
        agentActive: false,
        contextUsage: nil
    )
}
```

`Sources/StatusBar/RainbowContextBar.swift`:

```swift
import SwiftUI

/// A thin rainbow gradient bar whose filled width reflects context-window usage.
///
/// Rendered only when ``ContextUsage`` is available; deferred today (the
/// production provider returns `nil`, so the bottom bar omits this view).
struct RainbowContextBar: View {
    /// Fraction filled, clamped to `0...1`.
    let fraction: Double

    private static let gradient = LinearGradient(
        colors: [.red, .orange, .yellow, .green, .blue, .purple],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Self.gradient)
                    .frame(width: max(0, proxy.size.width * clamped))
            }
        }
        .frame(width: 80, height: 4)
    }
}
```

- [ ] **Step 2: Wire all three files into pbxproj** → normalize + check.
- [ ] **Step 3: Verify compile.**
- [ ] **Step 4: Commit**

```bash
git add Sources/StatusBar/ContextUsageProviding.swift Sources/StatusBar/BottomBarSnapshot.swift Sources/StatusBar/RainbowContextBar.swift cmux.xcodeproj/project.pbxproj
git commit -m "Add deferred context-usage seam, BottomBarSnapshot, RainbowContextBar"
```

## Task 5: `CmuxBottomBar` view

**Files:**
- Create: `Sources/StatusBar/CmuxBottomBar.swift`
- Modify: `cmux.xcodeproj/project.pbxproj` (wire it)

A pure view over `BottomBarSnapshot`: branch + staged (left), spacer, editor + version (right), and the rainbow bar only when `contextUsage != nil`.

- [ ] **Step 1: Implement** — `Sources/StatusBar/CmuxBottomBar.swift`:

```swift
import SwiftUI

/// The VSCode-style bottom status bar, rendered from an immutable
/// ``BottomBarSnapshot``. Lives in the content region (right of the left
/// sidebar). The rainbow context bar + usage text render only when the snapshot
/// carries ``ContextUsage`` (deferred today).
struct CmuxBottomBar: View {
    let snapshot: BottomBarSnapshot

    static let height: CGFloat = 24

    var body: some View {
        HStack(spacing: 12) {
            if let branch = snapshot.branch, !branch.isEmpty {
                Label {
                    Text(branch + (snapshot.isDirty ? "*" : ""))
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "arrow.triangle.branch")
                }
                .labelStyle(.titleAndIcon)
            }

            if !snapshot.staged.isEmpty {
                HStack(spacing: 6) {
                    Text("\u{2295}\(snapshot.staged.files)")
                    Text("+\(snapshot.staged.additions)").foregroundColor(.green)
                    Text("\u{2212}\(snapshot.staged.deletions)").foregroundColor(.red)
                }
                .accessibilityLabel(
                    String(
                        localized: "bottomBar.staged.accessibility",
                        defaultValue: "\(snapshot.staged.files) staged files, \(snapshot.staged.additions) additions, \(snapshot.staged.deletions) deletions"
                    )
                )
            }

            Spacer(minLength: 8)

            if let usage = snapshot.contextUsage {
                RainbowContextBar(fraction: usage.contextFraction)
                if let limitText = usage.limitText, !limitText.isEmpty {
                    Text(limitText).lineLimit(1)
                }
            }

            if !snapshot.editorDisplayName.isEmpty {
                Label {
                    Text(snapshot.editorDisplayName)
                } icon: {
                    Image(systemName: "pencil")
                }
                .labelStyle(.titleAndIcon)
            }

            if !snapshot.appVersion.isEmpty {
                Text("v\(snapshot.appVersion)")
                    .foregroundColor(.secondary)
            }
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1)
        }
    }
}
```

- [ ] **Step 2: Wire into pbxproj** → normalize + check.
- [ ] **Step 3: Verify compile.**
- [ ] **Step 4: Commit**

```bash
git add Sources/StatusBar/CmuxBottomBar.swift cmux.xcodeproj/project.pbxproj
git commit -m "Add CmuxBottomBar view (branch, staged diff, editor, version; deferred rainbow)"
```

## Task 6: Staged-diff store + mount the bar in the content region

**Files:**
- Create: `Sources/StatusBar/BottomBarStagedDiffStore.swift`
- Modify: `cmux.xcodeproj/project.pbxproj`
- Modify: `Sources/ContentView.swift`

- [ ] **Step 1: Implement the store** — `Sources/StatusBar/BottomBarStagedDiffStore.swift`:

```swift
import Foundation

/// Owns the bottom bar's staged-diff state for the active workspace directory,
/// refreshing off-main via ``StagedDiffProvider`` and re-running when the repo's
/// files change (a `FileWatcher` on the directory, throttled — catches `git add`).
@MainActor
final class BottomBarStagedDiffStore: ObservableObject {
    @Published private(set) var stats: StagedDiffStats = .empty

    private let provider = StagedDiffProvider()
    private var directory: String = ""
    private var watcher: FileWatcher?
    private var watchTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    /// Points the store at `directory` (the active workspace's cwd). No-op when
    /// unchanged. Empty clears the bar's staged segment.
    func activate(directory newDirectory: String) {
        let trimmed = newDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != directory else { return }
        directory = trimmed
        stopWatching()
        guard !trimmed.isEmpty else {
            stats = .empty
            return
        }
        // Throttled FS watch so `git add` / commits refresh the staged counts.
        let w = FileWatcher(path: trimmed, throttle: .milliseconds(300))
        watcher = w
        let events = w.events
        watchTask = Task { @MainActor [weak self] in
            for await _ in events {
                self?.refresh()
            }
        }
        refresh()
    }

    /// Recomputes staged stats off-main and publishes the result.
    func refresh() {
        let dir = directory
        guard !dir.isEmpty else { stats = .empty; return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self, provider] in
            let next = await provider.stagedStats(in: dir) ?? .empty
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in self?.stats = next }
        }
    }

    private func stopWatching() {
        watchTask?.cancel(); watchTask = nil
        watcher = nil
    }
}
```

(Confirm `FileWatcher(path:throttle:)` and its `.events` `AsyncSequence` signature against `FileExplorerStore.updateDirectoryWatcher` — mirror it exactly.)

- [ ] **Step 2: Add the store to ContentView.** In `struct ContentView` near the other `@StateObject`s (e.g. after `leftFileExplorerState`), add:

```swift
    @StateObject private var bottomBarStagedDiffStore = BottomBarStagedDiffStore()
    private let bottomBarContextProvider: any ContextUsageProviding = NullContextUsageProvider()
```

- [ ] **Step 3: Add a bottom-bar builder** to `ContentView` (a `@ViewBuilder` that builds the snapshot from the active workspace + stores). Add this method to `ContentView`:

```swift
    @ViewBuilder
    private func bottomBarView() -> some View {
        let ws = tabManager.selectedWorkspace
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let editorCommand = EditorLauncher.resolveEditorCommand(
            stored: EditorPreferenceSettings.storedCommand(),
            isAvailable: { EditorLauncher.availableOnPath($0) }
        )
        let editorName = EditorLauncher.editorDisplayName(forCommand: editorCommand)
        let agentActive: Bool = {
            guard let kind = ws?.focusedTerminalPanel?.agentHibernationState?.agent.kind else { return false }
            return kind == .claude || kind == .codex
        }()
        let snapshot = BottomBarSnapshot(
            appVersion: version,
            branch: ws?.gitBranch?.branch,
            isDirty: ws?.gitBranch?.isDirty ?? false,
            staged: bottomBarStagedDiffStore.stats,
            editorDisplayName: editorName,
            agentActive: agentActive,
            contextUsage: bottomBarContextProvider.usage(
                workingDirectory: ws?.currentDirectory,
                agentActive: agentActive
            )
        )
        CmuxBottomBar(snapshot: snapshot)
    }
```

> `bottomBarView()` reads `tabManager` (observed) and `bottomBarStagedDiffStore` (observed `@StateObject`). To observe the selected workspace's `gitBranch` changes, ContentView must already re-render when that `@Published` changes — it does not automatically for a non-observed nested object, so drive refresh via Step 5's `.onChange`/notification and the observed store; the branch is also refreshed whenever selection changes (which ContentView observes via `tabManager`). If branch staleness appears in manual testing, wrap the bar content in a tiny child `@ObservedObject var workspace: Workspace` view (mirroring the sidebar pattern) — note this as the fallback.

- [ ] **Step 4: Mount the bar in the content region.** In `contentAndSidebarLayout(appearance:)`, the content side is `terminalContentWithRightSidebarPanel(appearance:)` (standard branch) / the inner `HStack` (withinWindow branch). Wrap the content region in a `VStack` so the bar pins to the bottom of everything right of the left sidebar. Change `terminalContentWithRightSidebarPanel` (ContentView.swift) from:

```swift
    private func terminalContentWithRightSidebarPanel(appearance: WindowAppearanceSnapshot) -> some View {
        // File explorer is always in the view tree. Visibility is controlled by
        // frame width (0 when hidden), avoiding SwiftUI view insertion/removal
        // and all associated transition animations.
        return HStack(spacing: 0) {
            terminalContentWithSidebarDropOverlay(appearance: appearance)
            rightSidebarPanelWithBackdrop(appearance: appearance)
        }
    }
```

to:

```swift
    private func terminalContentWithRightSidebarPanel(appearance: WindowAppearanceSnapshot) -> some View {
        // File explorer is always in the view tree. Visibility is controlled by
        // frame width (0 when hidden), avoiding SwiftUI view insertion/removal
        // and all associated transition animations.
        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                terminalContentWithSidebarDropOverlay(appearance: appearance)
                rightSidebarPanelWithBackdrop(appearance: appearance)
            }
            bottomBarView()
        }
    }
```

Then handle the **withinWindow** branch of `contentAndSidebarLayout` (which builds its own `HStack` instead of calling `terminalContentWithRightSidebarPanel`). Replace that branch's inner `HStack { terminalContentWithSidebarDropOverlay.padding(.leading,…) ; rightSidebarPanelWithBackdrop }` with a `VStack(spacing: 0) { <that HStack> ; bottomBarView() }` so the bar also appears (and clears the left sidebar) in withinWindow mode. Keep the left-sidebar `.padding(.leading,…)` on the terminal content inside the HStack exactly as before.

> Result: in both layout modes the bar spans the content + right-sidebar region (everything right of the left sidebar) and pins to the bottom. The left sidebar (a sibling / the `.padding(.leading)`) is never covered.

- [ ] **Step 5: Drive staged-diff refresh.** Add `.onChange`/notification wiring so the store tracks the active workspace's directory. Find where ContentView attaches lifecycle modifiers (it already uses `.onChange(of: selectedWorkspaceDirectoryObserver.directoryChangeGeneration)` for the file explorer). Add alongside it:

```swift
        view = AnyView(view.onChange(of: tabManager.selectedWorkspace?.currentDirectory ?? "") { newDir in
            bottomBarStagedDiffStore.activate(directory: newDir)
        })
        view = AnyView(view.onChange(of: selectedWorkspaceDirectoryObserver.directoryChangeGeneration) { _ in
            bottomBarStagedDiffStore.refresh()
        })
```

and an initial activation in the existing `.onAppear` / first-setup path:

```swift
        bottomBarStagedDiffStore.activate(directory: tabManager.selectedWorkspace?.currentDirectory ?? "")
```

(Place the initial `activate` call where ContentView already does first-load workspace setup — e.g. the same `.onAppear` that calls `refreshWorkspaceSnapshot`/`syncFileExplorerDirectory`. If unsure, add a dedicated `.onAppear { bottomBarStagedDiffStore.activate(directory: tabManager.selectedWorkspace?.currentDirectory ?? "") }` on the bar container.)

- [ ] **Step 6: Build + manual verify (controller checkpoint).** `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag bottom-bar`. Expect: a bottom bar across the content area (not over the left sidebar) showing `⎇ <branch>[*]`, staged `⊕/+/−` when something is staged, the editor name, and `v<version>`. Selecting a different workspace updates branch/staged. `git add` in the active terminal updates the staged numbers within ~300ms. Provide the cmd-clickable app link.

- [ ] **Step 7: Commit**

```bash
git add Sources/StatusBar/BottomBarStagedDiffStore.swift Sources/ContentView.swift cmux.xcodeproj/project.pbxproj
git commit -m "Mount bottom status bar in the content region with staged-diff store"
```

## Task 7: Sidebar double-click → open in new tab via editor (remove path insertion)

**Files:**
- Modify: `Sources/Sidebar/SidebarFileExplorerPanel.swift`
- Modify: `Sources/ContentView.swift` (the `VerticalTabsSidebar` construction + a new open-in-editor closure; thread through `VerticalTabsSidebar`)

- [ ] **Step 1: Add an open-in-editor closure parameter to `SidebarFileExplorerPanel`.** Replace its current `onOpenFilePreview` closure (which calls `FileExplorerTerminalPathInsertion.insert`). Change the struct to accept an injected action and call it on double-click. In `Sources/Sidebar/SidebarFileExplorerPanel.swift`:
  - Add a stored property: `let onOpenFile: (String) -> Void`
  - Update the doc comment line "Double-clicking a file inserts its path into the active session's terminal." → "Double-clicking a file opens it in the configured editor in a new tab."
  - Replace the `FileExplorerPanelView(... onOpenFilePreview: { path in FileExplorerTerminalPathInsertion.insert(...) } ...)` closure with:

```swift
                    FileExplorerPanelView(
                        store: store,
                        state: state,
                        onOpenFilePreview: { path in
                            onOpenFile(path)
                        },
                        presentation: .files,
                        placement: .pane,
                        showsHeader: false
                    )
```

- [ ] **Step 2: Thread the closure from ContentView through `VerticalTabsSidebar`.** Add to `struct VerticalTabsSidebar` a stored property `let onOpenFileInEditor: (String) -> Void`, pass it into `SidebarFileExplorerPanel(store:state:onOpenFile:)` at its construction site, and add the argument at the single `VerticalTabsSidebar(` call site in ContentView:

```swift
                onOpenFileInEditor: { path in openSidebarFileInEditor(path: path) },
```

- [ ] **Step 3: Implement `openSidebarFileInEditor` in ContentView** (creates a new tab running the editor):

```swift
    private func openSidebarFileInEditor(path: String) {
        let editor = EditorLauncher.resolveEditorCommand(
            stored: EditorPreferenceSettings.storedCommand(),
            isAvailable: { EditorLauncher.availableOnPath($0) }
        )
        let command = EditorLauncher.openInEditorCommand(editor: editor, path: path)
        let workingDirectory = (path as NSString).deletingLastPathComponent
        _ = tabManager.addWorkspace(
            title: (path as NSString).lastPathComponent,
            workingDirectory: workingDirectory.isEmpty ? nil : workingDirectory,
            initialTerminalCommand: command,
            select: true
        )
    }
```

(`TabManager.addWorkspace(title:workingDirectory:initialTerminalCommand:select:...)` runs `initialTerminalCommand` on PTY spawn — verbatim API confirmed.)

- [ ] **Step 4: Remove now-dead path-insertion wiring.** Confirm `FileExplorerTerminalPathInsertion` is no longer referenced by the left panel (`rg -n "FileExplorerTerminalPathInsertion" Sources/Sidebar/`); the right-sidebar / other usages stay. Do NOT delete `FileExplorerTerminalPathInsertion.swift` (it may be used elsewhere — `rg -n "FileExplorerTerminalPathInsertion" Sources/` to confirm remaining users; leave it if any).

- [ ] **Step 5: Build + manual verify.** `reload.sh --tag bottom-bar`. Double-click a file in the left sidebar's explorer → a new tab opens running `<editor> '<path>'` (the file opens in micro/vim). Path is no longer inserted into the existing terminal.

- [ ] **Step 6: Commit**

```bash
git add Sources/Sidebar/SidebarFileExplorerPanel.swift Sources/ContentView.swift
git commit -m "Open sidebar file double-click in editor (new tab); remove path insertion"
```

## Task 8: Editor preference setting (catalog + Settings UI + cmux.json + registry)

**Files:**
- Modify: `Packages/CmuxSettings/Sources/CmuxSettings/Keys/AppCatalogSection.swift`
- Modify: `Packages/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/AppSection.swift`
- Modify: `Sources/KeyboardShortcutSettingsFileStore.swift`
- Modify: `Sources/CmuxSettingsJSONPathSupport.swift`
- Modify: `web/data/cmux.schema.json`

The setting is a string (empty = auto micro→vim), mirroring the existing `app.preferredEditor` `DefaultsValueModel<String>` + TextField row.

- [ ] **Step 1: Add the catalog key.** In `AppCatalogSection.swift`, next to the `preferredEditor` key (find `preferredEditor` / mirror its `DefaultsKey<String>` shape), add:

```swift
    public let terminalEditor = DefaultsKey<String>(
        id: "app.terminalEditor",
        defaultValue: "",
        userDefaultsKey: "terminalEditor"
    )
```

(Match the actual `DefaultsKey<String>` initializer of `preferredEditor`; if it differs, copy that exact shape. The `userDefaultsKey` MUST be `"terminalEditor"` to match `EditorPreferenceSettings.key`.)

- [ ] **Step 2: Add the Settings UI row.** In `AppSection.swift`, immediately after the existing `// Preferred Editor` `SettingsCardRow` block, add a `terminalEditor` row + `@State` model. First add the model near the other `@State private var ... : DefaultsValueModel<...>` declarations (mirror `preferredEditor`'s declaration):

```swift
    @State private var terminalEditor = DefaultsValueModel(catalog.app.terminalEditor)
```

(Match how `preferredEditor`'s `DefaultsValueModel` is constructed in this file.) Then the row, after the Preferred Editor row + its `SettingsCardDivider()`:

```swift
            // Terminal Editor (sidebar double-click opens here; shown in the status bar)
            SettingsCardRow(
                configurationReview: .json("app.terminalEditor"),
                String(localized: "settings.app.terminalEditor", defaultValue: "Terminal Editor"),
                subtitle: String(localized: "settings.app.terminalEditor.subtitle", defaultValue: "Editor used when opening a file from the sidebar (in a new tab) and shown in the status bar. Leave empty for auto (micro, then vim).")
            ) {
                TextField(
                    String(localized: "settings.app.terminalEditor.placeholder", defaultValue: "auto (micro, then vim)"),
                    text: Binding(get: { terminalEditor.current }, set: { terminalEditor.set($0) })
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
            }
            .settingsSearchAnchors(["setting:app:terminalEditor"])
            SettingsCardDivider()
```

- [ ] **Step 3: Parse from cmux.json.** In `Sources/KeyboardShortcutSettingsFileStore.swift`, in `parseAppSection`, after the existing `app.preferredEditor`/`app.appearance` handling, add:

```swift
        if let raw = jsonString(section["terminalEditor"]) {
            snapshot.managedUserDefaults[EditorPreferenceSettings.key] = .string(raw)
        }
```

(Use `EditorPreferenceSettings.key` if visible from this file/module; otherwise the literal `"terminalEditor"`. Place it next to the other `app.*` string mappings.)

- [ ] **Step 4: Register the JSON path.** In `Sources/CmuxSettingsJSONPathSupport.swift`, add to `supportedSettingsJSONPaths` next to `"app.preferredEditor"`:

```swift
        "app.terminalEditor",
```

- [ ] **Step 5: Document in the schema.** In `web/data/cmux.schema.json`, in the `app` section's properties (next to `preferredEditor`), add a `terminalEditor` string property: `{"type": "string", "description": "Editor used to open files from the sidebar (new tab) and shown in the status bar. Empty = auto (micro, then vim)."}`. Validate JSON parses (`python3 -c "import json; json.load(open('web/data/cmux.schema.json')); print('ok')"`).

- [ ] **Step 6: Build + verify (controller).** `reload.sh --tag bottom-bar` (and `cmux-unit build-for-testing` since package files changed). In Settings → App, the "Terminal Editor" field appears; setting it to e.g. `nvim` changes the bottom-bar indicator and the editor used on double-click. Empty → shows `micro` (or `vim` if micro absent).

- [ ] **Step 7: Commit**

```bash
git add Packages/CmuxSettings Packages/CmuxSettingsUI Sources/KeyboardShortcutSettingsFileStore.swift Sources/CmuxSettingsJSONPathSupport.swift web/data/cmux.schema.json
git commit -m "Add app.terminalEditor setting (catalog, Settings UI, cmux.json, schema)"
```

## Task 9: Localization (en+ja) + final audit

**Files:**
- Modify: `Resources/Localizable.xcstrings`

- [ ] **Step 1: Add en+ja entries** for every new key, matching the existing format (one real example: `settings.app.appearance`). Keys to add (skip any that already exist):
  - `settings.app.terminalEditor` → "Terminal Editor" / "ターミナルエディタ"
  - `settings.app.terminalEditor.subtitle` → the English subtitle above / a Japanese translation
  - `settings.app.terminalEditor.placeholder` → "auto (micro, then vim)" / "自動 (micro、なければ vim)"
  - `bottomBar.staged.accessibility` → "%lld staged files, %lld additions, %lld deletions" form / Japanese (note: this key uses interpolation; in xcstrings store the `%lld %lld %lld` substitution variant matching the `String(localized:)` interpolation, OR simplify the Swift to a non-interpolated label if the catalog interpolation is awkward — prefer a plain non-interpolated accessibility string if unsure).

> Implementation note: if the interpolated `bottomBar.staged.accessibility` catalog entry is awkward, change the Swift in Task 5 to a simpler non-interpolated `String(localized: "bottomBar.staged.accessibility", defaultValue: "Staged changes")` and localize that. The visible numbers are data and need no localization.

JSON entry shape (one example):

```json
    "settings.app.terminalEditor" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Terminal Editor" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "ターミナルエディタ" } }
      }
    },
```

Validate: `python3 -c "import json; json.load(open('Resources/Localizable.xcstrings')); print('ok')"`.

- [ ] **Step 2: Localization audit.** Confirm each new key has en + ja and matches the Swift `String(localized:)` keys; confirm no bare English literals were introduced in `Sources/StatusBar/**`:

```bash
rg -n "Text\(\"|Label\(\"\|\.accessibilityLabel\(\"" Sources/StatusBar/
rg -n "String\(localized:" Sources/StatusBar/ Packages/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/AppSection.swift | rg "terminalEditor|bottomBar"
```

- [ ] **Step 3: Build + verify.** `cmux-unit build-for-testing` + `reload.sh --tag bottom-bar`.

- [ ] **Step 4: Commit**

```bash
git add Resources/Localizable.xcstrings
git commit -m "Localize bottom-bar + terminal editor strings (en+ja)"
```

---

## Self-review (completed during planning)
- **Spec coverage:** content-region placement (T6); version + branch + staged-diff + editor segments (T1,T2,T5,T6); staged-diff via git numstat reusing runGit (T1,T2); editor auto micro→vim + custom (T3,T8); double-click opens in new tab + path-insertion removed (T7); deferred rainbow context bar + usage behind `ContextUsageProviding` null seam (T4,T5); settings + cmux.json + schema + registry (T8); localization en+ja (T9). All spec sections map to tasks.
- **Placeholder scan:** real code in every step; the two "if awkward, do X" notes (branch-staleness fallback, interpolated a11y string) are explicit decision branches with concrete fallbacks, not TODOs. Plan-stage open questions from the spec are resolved (new-tab API = `addWorkspace(initialTerminalCommand:)`; Settings row = `AppSection` mirroring `preferredEditor`; key = `app.terminalEditor`).
- **Type consistency:** `StagedDiffStats(files:additions:deletions:)`/`.parseNumstat`/`.isEmpty`/`.empty`; `StagedDiffProvider.stagedStats(in:)`; `EditorPreferenceSettings.key`/`.storedCommand`; `EditorLauncher.resolveEditorCommand(stored:isAvailable:)`/`.openInEditorCommand(editor:path:)`/`.editorDisplayName(forCommand:)`/`.availableOnPath`; `ContextUsage(contextFraction:limitText:)`; `BottomBarSnapshot(...)`; `BottomBarStagedDiffStore.activate(directory:)`/`.refresh()`/`.stats`; `CmuxBottomBar(snapshot:)`; `RainbowContextBar(fraction:)` — all used consistently across tasks.

## Known risks / verify carefully
- **Branch staleness in the bar** (Task 6 note): if `gitBranch` updates don't reflect without re-selection, add the small `@ObservedObject var workspace` child view.
- **withinWindow layout branch** (Task 6 Step 4): two layout modes — both must get the bar without covering the left sidebar; verify in both `sidebarBlendMode` settings.
- **`addWorkspace(initialTerminalCommand:)`** runs the command on spawn; verify the editor actually opens (not just types) and quoting handles spaces/quotes.
- **pbxproj:** every new `Sources/StatusBar/**` + `cmuxTests/**` file wired, else silent no-compile.
- **`FileWatcher` API shape** (Task 6 Step 1): mirror `FileExplorerStore.updateDirectoryWatcher` exactly.
