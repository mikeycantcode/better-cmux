# Bottom status bar — design

**Date:** 2026-06-06
**Status:** Approved design (pre-implementation)
**Branch:** `bottom-status-bar`

## Problem

cmux has no VSCode-style bottom status bar. The user wants one showing the cmux
version, the active terminal's git branch, staged-diff numbers, an editor
indicator (micro if installed, else vim), a "rainbow" context-usage bar for the
active agent, and — when Claude/Codex is active — usage/session limits.
Additionally, double-clicking a file in the sidebar should open it in the
configured editor (replacing the path-into-terminal behavior), and the editor
choice should be configurable.

## Feasibility finding (drives scope)

A thorough codebase search found **no native agent context-window or usage/limit
data** in cmux (zero hits for tokens/context/usage/rate-limit/ccusage). cmux does
know the active agent (Claude/Codex, via `AgentHibernationPanelState` →
`SessionAgent`) and the path to that agent's transcript JSONL, but it never reads
transcript contents for metrics. Therefore:

- The **rainbow context bar** and **usage/session limits** are **deferred**: built
  as a hidden, seam-ready stub (a `ContextUsageProviding` provider that returns
  `nil` today) so a real data source (transcript parsing or an external
  `ccusage`-style command) can be wired later without rework.
- Everything else (version, branch, staged diff, editor indicator,
  open-in-editor, settings) is buildable now with existing infrastructure.

## Goals

1. A bottom status bar in the **content region** (right of the left sidebar — it
   never covers the left workspace sidebar), reflecting the active workspace.
2. Segments: git branch (+dirty), staged-diff numbers, editor indicator, cmux
   version; plus a hidden/deferred rainbow context bar + usage stub.
3. Double-clicking a sidebar file opens it in the configured editor in a **new
   tab**; the previous path-insertion behavior is **removed**.
4. A configurable editor preference: `auto` (micro→vim) by default, or a custom
   command.

## Non-goals (deferred / out of scope)

- Real context-window % and session/rate-limit values (no data source yet) — the
  rainbow bar + usage remain hidden behind the provider seam.
- Reading/parsing agent transcripts or shelling out to `ccusage` (a later phase).

## Background: what exists (grounded in code)

- **Content layout:** `ContentView.swift` —
  `contentAndSidebarLayout` (~2750) → `terminalContentWithRightSidebarPanel`
  (~2162) is an `HStack { terminalContent ; rightSidebarPanel }` that already
  sits to the right of the left sidebar. The left sidebar is a sibling earlier in
  the parent `HStack` (~2776) / applied as leading padding (~2764). The right
  sidebar width is `rightSidebarWidth` (~2177).
- **App version:** `Bundle.main.infoDictionary?["CFBundleShortVersionString"]`
  (used at `ContentView.swift:3335`, `cmuxApp.swift:2394`).
- **Git branch:** `workspace.gitBranch?.branch` (a `SessionGitBranchSnapshot?`),
  already shown in the sidebar.
- **Git process helper:** `FileExplorerStore`'s `runGit(in:arguments:)`
  (~1405) and the git-status parser (~1321–1430) — a reusable `Process`-based
  pattern (`git status --porcelain`, `parseStatusChars`). No staged-diff
  line/file counts exist yet.
- **Agent detection:** `TerminalPanel.agentHibernationState`
  (`Panels/TerminalPanel.swift:101`); the agent kind is
  `agentHibernationState?.agent.agent` (`SessionAgent` enum:
  claude/codex/grok/opencode/rovodev/hermesAgent).
- **Send to terminal:** `TerminalPanel.sendText(_:)` (~667), used by
  `FileExplorerTerminalPathInsertion`.
- **Sidebar double-click:** `SidebarFileExplorerPanel`'s `onOpenFilePreview`
  closure currently calls `FileExplorerTerminalPathInsertion.insert(...)` (added
  in the prior sidebar-redesign feature). The right-sidebar explorer's
  `onOpenFilePreview` routes to `openFilePreviewFromSidebar` (~2238) → a built-in
  preview surface; that right-sidebar behavior is unchanged by this feature.
- **Non-bool settings precedent:** `AppearanceSettings.AppearanceMode`
  (string/enum, parsed at `KeyboardShortcutSettingsFileStore.swift:398`) and
  `MarkdownFontSizeSettings` (numeric). Non-bool settings are surfaced via custom
  Settings UI views (not the command-palette toggle list) and parsed from
  `cmux.json` as `.string`/`.int`.

## Architecture

New package-style folder `Sources/StatusBar/` (one type per file), wired into the
cmux app target + (for the testable seams) the cmux-unit test target.

### 1. Placement & layout — `CmuxBottomBar`
- A SwiftUI view mounted at the **bottom of the content region**. Concretely, wrap
  the content side so the bar is a bottom row of `terminalContentWithRightSidebarPanel`
  (spanning content + right sidebar, i.e. everything right of the left sidebar).
- Fixed height (~24pt), own background + a top hairline divider, `lineLimit(1)`
  segments. It reads an **immutable snapshot** (`BottomBarSnapshot`) computed by
  the owning view, not live stores, to stay cheap (and to avoid coupling the
  always-present bar to high-churn observable state).
- Reflects the **active workspace** (`tabManager.selectedWorkspace`) and its
  **focused terminal panel**.

### 2. Segments (left → right)
- **Left:** branch (`workspace.gitBranch.branch` + `*` if dirty) and staged-diff
  (`⊕<files> +<adds> −<dels>`; hidden when nothing staged).
- **Right:** editor indicator (resolved editor name) and cmux version.
- **Deferred (hidden):** rainbow context bar (a thin gradient fill) + usage text,
  rendered only when `ContextUsageProviding` returns non-nil. Returns nil today.

### 3. Staged diff — `StagedDiffProvider` (actor)
- `func stagedStats(forRepoAt:) async -> StagedDiffStats?` running
  `git diff --cached --numstat` (sum `+adds`/`−dels`) and a staged-file count
  (`git diff --cached --name-only | wc`-equivalent in Swift). `StagedDiffStats`
  is a `Sendable` value (`files: Int, additions: Int, deletions: Int`).
- Reuses the existing `runGit` Process pattern (moved/duplicated minimally into
  the provider). Off-main; throttled; refreshed on workspace focus / directory
  change / the existing git-status refresh cadence. Results projected into
  `BottomBarSnapshot`.
- **Testable seam:** a `parseNumstat(_ output: String) -> StagedDiffStats` pure
  function (Swift Testing unit tests on the parser; no git process in tests).

### 4. Editor preference — `EditorPreferenceSettings` + `EditorLauncher`
- `EditorPreferenceSettings` (string enum + custom command), modeled on
  `AppearanceSettings`: `static let key`, a `resolved(defaults:) -> EditorChoice`
  returning `.auto` / `.command(String)`. Honored in `cmux.json` (`app.editor` or
  an `editor` section) and a Settings UI row (picker + custom-command text field).
- `EditorLauncher`:
  - `resolveEditorCommand(preference:pathProbe:) -> String` — pure resolver: for
    `.auto`, return `"micro"` if a probe says micro is on PATH, else `"vim"`; for
    `.command(c)`, return `c`. **Testable** with an injected `pathProbe` closure
    (no real `which` call in tests).
  - `editorIsAvailable(_ name:) -> Bool` — `which <name>` via Process (cached),
    behind the injected probe in production.
  - The bottom-bar editor indicator shows the resolved command's leaf name.

### 5. Open-in-editor + double-click rewrite
- Sidebar **double-click** opens the file in a **new tab** whose terminal runs
  `<resolvedEditor> <quoted path>`. The previous `FileExplorerTerminalPathInsertion`
  path-insertion closure in `SidebarFileExplorerPanel` is **removed** (and any
  now-dead "insert path" affordance for the left panel).
- New-tab-with-command: the exact cmux API to create a tab/pane that runs an
  initial command is confirmed during the plan stage (explore found `sendText` +
  pane/tab creation; the plan pins the new-tab-with-initial-command call). The
  editor command is shell-quoted to handle spaces.

### 6. Deferred context/usage seam — `ContextUsageProviding`
- `protocol ContextUsageProviding { func usage(for workspace snapshot) -> ContextUsage? }`
  where `ContextUsage` carries `contextFraction: Double` (0–1, drives the rainbow
  gradient fill) and optional `limitText: String?`. A `NullContextUsageProvider`
  returns `nil` → the rainbow bar + usage are not rendered. Injected at the
  composition root so a real provider can replace it later.

## Settings & localization
- New `EditorPreferenceSettings` surfaced in the Settings UI (a picker:
  Auto / Custom, with a command text field), honored in `cmux.json`
  (`KeyboardShortcutSettingsFileStore` parse), and documented in
  `web/data/cmux.schema.json`.
- All new user-facing strings (editor setting label/help, any bar tooltips/empty
  states) localized **en + ja** in `Resources/Localizable.xcstrings`.
- Add `app.editor` (or `editor.command`) to the `supportedSettingsJSONPaths`
  registry (the hand-maintained list the prior feature flagged).

## Performance & constraints
- The bottom bar is always present, so it consumes an **immutable snapshot**, not
  live observable stores (avoid re-rendering the bar on every keystroke / git
  tick). Snapshot recomputed on workspace selection / git-status refresh, not in a
  view-body projection.
- Staged-diff git calls are off-main, throttled, and reuse the existing git
  refresh cadence — no new high-frequency watching.
- New code follows Swift 6 concurrency (actors / async, `@Observable` where new
  state is needed); pure seams (`parseNumstat`, `resolveEditorCommand`) are unit
  tested without processes; no locks/Combine in new types.
- New `Sources/StatusBar/**` files wired into pbxproj (app target; test seams
  reachable from cmux-unit).

## Files touched
- New: `Sources/StatusBar/CmuxBottomBar.swift` (+ small segment subviews),
  `BottomBarSnapshot.swift`, `StagedDiffProvider.swift`, `StagedDiffStats.swift`,
  `EditorPreferenceSettings.swift`, `EditorLauncher.swift`,
  `ContextUsageProviding.swift`.
- `Sources/ContentView.swift` — mount the bar in the content region; build the
  `BottomBarSnapshot`; rewire sidebar double-click to open-in-editor.
- `Sources/Sidebar/SidebarFileExplorerPanel.swift` — double-click → open-in-editor;
  remove the path-insertion closure.
- `Sources/KeyboardShortcutSettingsFileStore.swift` + Settings UI +
  `web/data/cmux.schema.json` + `Sources/CmuxSettingsJSONPathSupport.swift` —
  the editor preference.
- `Resources/Localizable.xcstrings` — en+ja for new strings.

## Sequencing
1. Static bar shell + placement (version + branch first; cheapest, immediately
   visible).
2. Staged-diff provider + segment.
3. Editor preference + resolver + indicator.
4. Double-click → open-in-editor (new tab); remove path-insertion.
5. Deferred context/usage seam (hidden rainbow bar wired to a null provider).
6. Settings UI + cmux.json + localization + docs.

## Open questions for the plan stage
- Exact cmux API to create a new tab/pane running an initial command
  (`<editor> <path>`).
- Where the Settings UI editor row best fits (which existing Settings section view).
- Final `cmux.json` key name (`app.editor` vs an `editor` section).
