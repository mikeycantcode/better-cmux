# VS Code-Fidelity Files + Git Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-skin the right sidebar's Files tab as a pixel-faithful VS Code explorer (metrics, chevrons, Material file icons, git decorations, section header) and rebuild the Git tab as the VS Code SCM changes view (sections + count pills + hover actions, no commit box), unifying the two duplicate git-status pipelines into one.

**Architecture:** Everything is a re-skin over existing bones. Files: `NSOutlineView` stack (`FileExplorerView/CellView/RowView/Store/Style`) gains a `.vscode` style (new default), a custom chevron, decoration badges, and a section header; icons expand the existing loose-SVG loader (`FileExplorerVSCodeIcons` + `Resources/FileTypeIcons/`). Git status becomes one shared service consumed by both the explorer and `GitWorkingTreeModel`. Git tab: `GitPanelView` is rebuilt VS Code SCM-style over the unchanged `GitWorkingTreeModel` actions.

**Tech Stack:** Swift/AppKit (`NSOutlineView`), SwiftUI (Git tab), Material Icon Theme SVGs (MIT), XCTest via `cmux-unit`.

## Global Constraints

- No design spec exists for this feature (Mike: "no spec, it's just a reskin") — this plan is the requirements document. Mike's ratified choices: Material-style bundled icons; keep the cmux Files|Git tab switcher; Git tab = Changes tree + hover actions + staged section, NO commit box; full explorer git decorations (tinted names + letter badges + folder dots).
- VS Code dark reference values (use verbatim): row height 22pt; indent 8pt per depth level (icon column separate); chevron `chevron.right`/`chevron.down` 16pt medium, secondary color, only on folders; file icon 16×16; label 13pt regular; git decoration colors — modified `#E2C08D`, untracked `#73C991`, added `#81B88B`, deleted `#C74E39`, conflict `#E4676B`, ignored 40% alpha of label; status letter badge 12pt semibold, same color as the tinted name, trailing-aligned; SCM count pill: 11pt medium white on `#4D4D4D`, capsule.
- The explorer remains AppKit; the SwiftUI snapshot-boundary rule applies to the Git tab and any SwiftUI shells: value snapshots + closures below `ForEach`, no store references, no state mutation in `body` paths (CLAUDE.md).
- `FilesGitPanelView` must keep `explorerState`/`gitModel` as plain `let` (NOT `@ObservedObject`) — a git refresh must not invalidate the shell (existing comment contract, GitPanelView.swift:161 region).
- `GitWorkingTreeModel`'s public action API (`stageFile/unstageFile/discardFile`, batches, `stageAll`, `discardAll`, `push`) and `GitPorcelainStatus` parsing stay behaviorally unchanged; `commit(message:)` stays in the model (other callers may exist) but the new Git tab UI must NOT render a commit box.
- One git-status pipeline after Task 2: the explorer must no longer run its own `git status` subprocess when a shared service covers its root. No FS-watcher double-fire (one `git status` per change burst).
- All new user-facing strings via `String(localized:defaultValue:)`, keys in `Resources/Localizable.xcstrings`, en + ja minimum, matching the 19-locale set of sibling `herdr.*` keys where those carry 19 (mirror that exact locale list). Localization audit is Task 5's gate.
- New test files: wire into `cmux.xcodeproj/project.pbxproj` with FRESH unique 24-char uppercase-hex IDs (4 entries; template `TitlebarControlsClusterTests.swift`); then `python3 scripts/normalize-pbxproj.py && ./scripts/check-pbxproj.sh && ./scripts/lint-pbxproj-test-wiring.sh`.
- Tests: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild -project cmux.xcodeproj -scheme cmux-unit -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-vscode-tests test -only-testing:cmuxTests/<Class>`. Never the `cmux` scheme for tests.
- App build check: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-vscode build`. Tagged app: `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag vscode-sidebar`.
- Typing-latency pitfalls (CLAUDE.md) apply: nothing added to `hitTest`, `forceRefresh`, `TabItemView`.
- Commits end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.

---

### Task 1: Full Material icon set + mapping expansion

**Files:**
- Modify: `Resources/FileTypeIcons/` (add SVGs + `LICENSE` file), `Sources/FileExplorerVSCodeIcons.swift` (mapping tables)
- Test: `cmuxTests/FileExplorerVSCodeIconsTests.swift` (new; pbxproj-wired)

**Interfaces:**
- Consumes: existing loader `FileExplorerVSCodeIcons` (lazy `Bundle.main.url(forResource:withExtension:"svg", subdirectory:"FileTypeIcons")`, `iconCache["name@size"]`), existing mapping tables (~100 extensions, 14 filenames).
- Produces: `FileExplorerVSCodeIcons.iconName(forFileName:) -> String` (extract the lookup into a pure, testable function if not already one) covering the expanded set; `folderIconName(expanded: Bool) -> String` returning `folder`/`folder-open`.

**Details:**
- Source of icons: the MIT-licensed Material Icon Theme (`PKief/vscode-material-icon-theme`). Fetch via `npm pack material-icon-theme` (or `curl` the GitHub release tarball) into the scratchpad, then copy ONLY the SVGs referenced by the expanded mapping table (~250 icons: every extension/filename in the mapping, plus `folder`, `folder-open`, and the per-name folder variants for `src`, `test`/`tests`, `node_modules`, `docs`, `.git`, `assets`, `config`, `scripts`, `public`, `build`). Do not vendor all ~1000. Copy the upstream `LICENSE` into `Resources/FileTypeIcons/LICENSE-material-icon-theme.md`.
- Expand the extension table to cover at minimum: py, pyi, ipynb, js, mjs, cjs, jsx, ts, tsx, json, jsonc, yaml, yml, toml, xml, html, css, scss, less, md, mdx, rs, go, java, kt, swift, m, mm, h, hpp, c, cc, cpp, zig, rb, php, sh, zsh, bash, fish, sql, graphql, proto, lock, svg, png, jpg, jpeg, gif, webp, ico, pdf, zip, tar, gz, mp4, mov, mp3, wav, ttf, otf, woff, woff2, env, ini, cfg, conf, log, txt, csv, tsv, plist, xcconfig, entitlements, strings, xcstrings, storyboard, xib, gradle, cmake, dockerfile-ext (see filename table), makefile-ext, tf, vue, svelte, astro, prisma, sol, dart, ex, exs, erl, hs, lua, nim, r, scala, clj, pl, vim.
- Expand the filename table: `Dockerfile`, `docker-compose.yml`, `Makefile`, `CMakeLists.txt`, `package.json`, `package-lock.json`, `pnpm-lock.yaml`, `yarn.lock`, `bun.lockb`, `tsconfig.json`, `.gitignore`, `.gitattributes`, `.editorconfig`, `.eslintrc*`, `.prettierrc*`, `README.md`, `LICENSE`, `CHANGELOG.md`, `Cargo.toml`, `Cargo.lock`, `go.mod`, `go.sum`, `Package.swift`, `Gemfile`, `requirements.txt`, `pyproject.toml`, `.env` (+ `.env.*` prefix rule).
- If an SVG named in the mapping is missing from upstream, fall back to the existing generic `document` icon name at TABLE-BUILD time (a mapping must never point at a nonexistent resource — the test enforces this).

**Steps:**
- [ ] **Step 1: Write failing tests**: (a) every value in both mapping tables resolves to an existing bundled SVG URL; (b) spot lookups (`main.py` → python, `Dockerfile` → docker, `foo.tsx` → react/tsx icon name per upstream naming, unknown ext → generic document); (c) `folderIconName(expanded:)` returns distinct existing icons.
- [ ] **Step 2: Wire test file into pbxproj (fresh IDs), run guards, run tests: FAIL.**
- [ ] **Step 3: Fetch icons, copy the referenced subset + license, expand the tables.** Verify `Resources` group picks up new files the same way the existing 76 are wired (folder reference vs individual entries — mirror exactly what exists).
- [ ] **Step 4: Run tests: PASS. App build check.**
- [ ] **Step 5: Commit** `feat: full material icon coverage for the file explorer`.

---

### Task 2: One git-status pipeline (`GitStatusMonitor`)

**Files:**
- Create: `Sources/Git/GitStatusMonitor.swift`
- Modify: `Sources/FileExplorerStore.swift` (consume monitor; delete `GitStatusProvider` parser + `GitFileStatus` usage), `Sources/Git/GitWorkingTreeModel.swift` (consume/share), `Sources/RightSidebarToolPanel.swift` (single poke path)
- Test: `cmuxTests/GitStatusMonitorTests.swift` (new; pbxproj-wired)

**Interfaces:**
- Consumes: `GitWorkingTreeModel.runGit` (`nonisolated static`), `GitPorcelainStatus.parse`, `GitEntryStatus`.
- Produces:

```swift
@MainActor final class GitStatusMonitor: ObservableObject {
    static func shared(forRepoRoot root: String) -> GitStatusMonitor  // one per repo root
    @Published private(set) var statusByPath: [String: GitEntryStatus]   // absolute path → status (worst of X/Y)
    @Published private(set) var directoryHasChanges: Set<String>          // absolute dir paths with dirty descendants
    @Published private(set) var porcelain: GitPorcelainStatus             // the full parse, for the Git tab
    func scheduleRefresh()   // 300 ms trailing debounce, cancels in-flight, generation-tokened
    func refreshNow() async
}
```

- Equality-guard every publish (assign only when changed). Stale results must be discarded via a generation token (this fixes the explorer's existing stale-overwrite race).
- `GitWorkingTreeModel` keeps its API but sources `status` from the monitor for its `repoPath` (subscribe + mirror into its own `@Published status` so `GitPanelView` and the Changes webview code paths don't change); mutations (`stage…`) call `monitor.refreshNow()` after completing instead of private refresh.
- `FileExplorerStore`: replace `refreshGitStatus()`/`GitStatusProvider`/`gitStatusByPath: [String: GitFileStatus]` with a subscription to `GitStatusMonitor.shared(forRepoRoot: resolvedRepoRoot)` mapping to the same published property renamed type: `gitStatusByPath: [String: GitEntryStatus]` + `directoryHasChanges`. Keep the `check-ignore` pipeline as-is (separate concern). If the root is not inside a git repo, the monitor publishes empty and the store shows no decorations (match current behavior).
- FS-watcher double-fire: the explorer's `FileWatcher` event calls `monitor.scheduleRefresh()` (plus its own directory `reload()`); `RightSidebarToolPanel.swift:35`'s poke of the git model becomes redundant — remove it (the model rides the monitor now). Result: one `git status` per change burst.
- Delete the now-unused `GitFileStatus` enum and v1 parser; migrate `FileExplorerStyle.gitColor(for:)` to take `GitEntryStatus`.

**Steps:**
- [ ] **Step 1: Failing tests**: parse→statusByPath mapping incl. worst-of-X/Y flattening and rename `originalPath` handling; `directoryHasChanges` rollup (nested dirs all marked, unrelated dirs not); equality guard (same porcelain twice → one publish; use a probe subscriber counting emissions); per-root instance identity (`shared(forRepoRoot:)` returns same instance for same normalized root).
- [ ] **Step 2: Wire pbxproj, guards, run: FAIL.**
- [ ] **Step 3: Implement** monitor + both consumers + poke-path cleanup.
- [ ] **Step 4: Run new tests + existing `GitPorcelain`-related and FileExplorer persistence tests (find and run the test classes touching `FileExplorerStore` and Git parsing). App build check.**
- [ ] **Step 5: Commit** `refactor: single git status pipeline shared by explorer and git tab`.

---

### Task 3: `.vscode` explorer style — metrics, chevrons, decorations

**Files:**
- Modify: `Sources/FileExplorerStore.swift` (`FileExplorerStyle`: new case, new default, cached `current`), `Sources/FileExplorerCellView.swift` (layout: chevron column, badge label, folder dot), `Sources/FileExplorerView.swift` (row height, indentation, hide stock disclosure triangles for `.vscode`), `Sources/FileExplorerRowView.swift` (selection/hover fills per VS Code)
- Test: `cmuxTests/FileExplorerVSCodeStyleTests.swift` (new; pbxproj-wired)

**Interfaces:**
- Consumes: Task 1 icons (`folderIconName(expanded:)`), Task 2 `gitStatusByPath: [String: GitEntryStatus]` + `directoryHasChanges`.
- Produces: `FileExplorerStyle.vscode` with exactly: `rowHeight 22` (× `GlobalFontMagnification`), `indentation 8`, `iconSize 16`, `nameFont` 13pt regular, `iconToTextSpacing 6`, `selectionInset 0`, `selectionRadius 0` (VS Code selection is full-width square), hover `NSColor.white.withAlphaComponent(0.07)`-equivalent via existing hover color plumbing, `gitColor(for: GitEntryStatus)` returning the Global Constraints hexes. New static `FileExplorerStyle.cachedCurrent` (invalidated by a UserDefaults observation) replacing per-row `UserDefaults` reads at `heightOfRowByItem`/`configure` — all styles benefit.
- Default migration: `FileExplorerStyle.current` defaults to `.vscode` when the defaults key is unset. A user who explicitly picked another style keeps it (key present → honored).
- Cell layout for `.vscode`: `[chevron 16pt (folders only, rotates on expand — hide the outline view's stock disclosure via `outlineView(_:shouldShowOutlineCellForItem:)` false for .vscode + custom chevron in cell, clicking it toggles expansion)] [icon 16] [6pt] [name 13pt, tinted by git status] [spacer] [trailing badge: status letter M/U/A/D 12pt semibold in the same tint — files; or 6pt filled dot circle — folders in `directoryHasChanges`]`. Ignored paths keep 0.4 alpha. Other styles render exactly as before (regression guard: switching styles in the debug/style picker must not change).
- `FileExplorerCellView.configure(with:gitStatus:isIgnored:)` signature extends to carry `directoryHasChanges` membership (or a precomputed `decoration: FileRowDecoration` value — implementer's choice, keep it a value type).

**Steps:**
- [ ] **Step 1: Failing tests**: `.vscode` metric values exact; `gitColor(for:)` hex round-trip for all `GitEntryStatus` cases (compare via hex string of the NSColor); default-migration logic (unset key → `.vscode`, explicit `"codika"` → `.codika`); `cachedCurrent` returns updated style after the defaults key changes (post the change, assert new value).
- [ ] **Step 2: Wire pbxproj, guards, run: FAIL.**
- [ ] **Step 3: Implement.** AppKit layout code is not unit-testable — keep the testable parts (metrics, colors, migration, decoration value building) pure.
- [ ] **Step 4: Run tests + app build check.**
- [ ] **Step 5: Commit** `feat: vscode explorer style with chevrons and git decorations`.

---

### Task 4: Explorer section header (root row + actions)

**Files:**
- Modify: `Sources/FileExplorerHeaderView.swift` (or the header SwiftUI/AppKit shell the right sidebar uses — locate where the filter field mounts), `Sources/FileExplorerStore.swift` (new file/folder creation), `Sources/FileExplorerView.swift` (collapse-all)
- Test: extend `cmuxTests/FileExplorerVSCodeStyleTests.swift` (creation-path logic only)

**Interfaces:**
- Consumes: `FileExplorerStore` (rootPath, reload, expandedPaths).
- Produces: header row above the tree, VS Code-style: root folder name UPPERCASED, 11pt semibold, secondary color, leading chevron (collapses/expands the whole tree view region is NOT needed — static label is fine this pass), and four trailing icon buttons that appear on sidebar hover: new-file (`doc.badge.plus`), new-folder (`folder.badge.plus`), refresh (`arrow.clockwise`), collapse-all (`rectangle.compress.vertical`). 22pt row, buttons 20pt hit / 14pt icons, secondary color.
- Actions: new-file/new-folder prompt with an `NSAlert` + accessory text field (same prompt pattern as `WorkspaceRenamePrompt.run` — reuse its shape, not its code), create via `FileManager` **relative to the selected folder** (or root when none/file selected), then `store.reload()` + reveal/select the new node. Refresh = `store.reload()`. Collapse-all = clear `expandedPaths` + `outlineView.collapseItem(nil, collapseChildren: true)` via a store-posted signal (match how reload signals reach the coordinator today).
- `FileExplorerStore.createFile(named:inDirectory:)` / `createFolder(named:inDirectory:)` return `Result<String, Error>`; errors surface via `NSAlert`. Pure name-validation helper (`rejects empty, "/", names existing in dir`) is the unit-testable piece.
- All five new strings localized (`fileExplorer.header.newFile` etc. + prompt titles/buttons).

**Steps:**
- [ ] **Step 1: Failing tests** for the validation helper (empty, slash, duplicate, valid) and creation into a temp dir (`FileManager`-real, no mocks).
- [ ] **Step 2: Run: FAIL.**
- [ ] **Step 3: Implement header + actions + localization entries.**
- [ ] **Step 4: Run tests + app build check.**
- [ ] **Step 5: Commit** `feat: vscode explorer header with create/refresh/collapse actions`.

---

### Task 5: VS Code SCM Git tab + localization audit

**Files:**
- Modify: `Sources/Git/GitPanelView.swift` (rebuild body; keep file name), `Resources/Localizable.xcstrings`
- Test: `cmuxTests/GitScmViewModelTests.swift` (new; pbxproj-wired) — for the pure section/row projection

**Interfaces:**
- Consumes: `GitWorkingTreeModel` (unchanged API), `GitPorcelainStatus` via the model's `status`, Task 1 icons (file icon per name in rows), Task 3 `gitColor` hexes (share one color source — move the status-color mapping to a small shared enum/helper if needed so explorer and SCM agree).
- Produces pure projection (testable):

```swift
struct ScmRowSnapshot: Identifiable, Equatable {
    var id: String { section.rawValue + path }
    let section: ScmSection            // .staged, .changes  (untracked merges INTO .changes, VS Code-style, marked U)
    let path: String                   // repo-relative
    let fileName: String
    let directoryText: String          // dimmed path, "" for root files
    let statusLetter: String           // M/A/D/R/U
    let statusColorHex: String
}
enum ScmSection: String { case staged, changes }
func scmRows(from status: GitPorcelainStatus) -> (staged: [ScmRowSnapshot], changes: [ScmRowSnapshot])  // sorted by fileName, case-insensitive
```

- View structure (VS Code dark fidelity): toolbar row keeps branch name + ahead/behind + refresh + open-changes (existing actions, restyled quiet). Then `SOURCE CONTROL`-style header is NOT needed (tab chrome exists) — go straight to sections: `Staged Changes` (only when non-empty) and `Changes`, each a 22pt header row: chevron (collapsible, `@State`), 11pt semibold title, count pill (11pt medium white on `#4D4D4D` capsule), hover-revealed section actions (staged: unstage-all `minus.circle`; changes: stage-all `plus.circle`, discard-all `arrow.uturn.backward.circle`).
- Rows: 22pt, `[file icon 16 (Task 1 loader — add a small SwiftUI `FileTypeIconView(fileName:size:)` wrapper if none exists)] [fileName 13pt primary] [directoryText 12pt tertiary, truncating head] [spacer] [hover actions] [status letter 12pt semibold in statusColorHex]`. Hover actions (appear on row hover, right of spacer, before the letter): changes rows = open `go.forward`? No — VS Code order: open-file (`doc`), discard (`arrow.uturn.backward`), stage (`plus`); staged rows = open-file, unstage (`minus`). 16pt icon buttons, secondary color.
- Row click = existing behavior (reveal in Changes panel via the mount-site closure, else preview). Discard keeps the existing `PendingConfirm` confirmation flow. NO commit box, NO push/publish button in this view (model keeps the API; the toolbar drops them).
- Rows are value views (`ScmRowSnapshot` + closures), `Equatable`, `.equatable()` in the `ForEach`; the `LazyVStack` structure stays. `GitPanelView` keeps observing `model` above the boundary exactly as today.
- **Localization audit (this task's second half, per CLAUDE.md):** enumerate every user-facing string added across Tasks 1–5 (`rg` the touched files for `Text(`, `accessibilityLabel`, `safeHelp`, `NSAlert` strings), verify each exists in `Localizable.xcstrings` with the full sibling locale set (mirror `herdr.*`'s 19), parse the file with python3 to compare key × locale coverage. State the audit result explicitly in the report.

**Steps:**
- [ ] **Step 1: Failing tests** for `scmRows`: staged/changes bucketing (untracked → changes with `U`), sort order, directoryText derivation (`"neetcode/problems"` for nested, `""` for root), rename shows `R` with new path, id stability across sections.
- [ ] **Step 2: Wire pbxproj, guards, run: FAIL.**
- [ ] **Step 3: Implement projection + rebuilt view + localization entries.**
- [ ] **Step 4: Run tests + app build check + tagged build (`reload.sh --tag vscode-sidebar`, build only).**
- [ ] **Step 5: Run the localization audit, record results in the report.**
- [ ] **Step 6: Commit** `feat: vscode scm changes view for the git tab`.

---

## Self-review notes

- Coverage vs Mike's ratified choices: icons (T1), tab switcher untouched (all), SCM view no-commit-box (T5), full decorations (T2 data + T3 render). Unification win (T2). Header/create actions (T4).
- Type consistency: `GitEntryStatus` is the single status enum after T2; `gitColor(for:)` migrated in T3; T5 shares the same hexes. `GitStatusMonitor` API repeated verbatim in T2/T3 consumers.
- Order matters: T1 (icons) and T2 (data) are independent; T3 needs both; T4 needs T3's style; T5 needs T1 + T2 (+ color helper from T3). Execution order 1 → 2 → 3 → 4 → 5 with 1‖2 parallelizable only if writers are separated — they touch disjoint files EXCEPT `FileExplorerStore.swift` (T2) — T1 does not touch it. T1 and T2 may run concurrently with explicit-path staging.
