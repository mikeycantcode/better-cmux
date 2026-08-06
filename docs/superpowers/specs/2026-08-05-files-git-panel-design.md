# Files + Git right panel — design

Date: 2026-08-05 · Branch: `big-cleanup` · Status: approved by Mike

## Goal

Replace the right sidebar's current file viewer (and its six-mode switcher) with a
single beautiful **Files | Git** panel modeled on the Codika screenshots:
a restyled file tree, a real git status/commit tab, and a main-area **Changes**
diff-review panel. This panel becomes the permanent home of files: a later pass
turns the left sidebar into the herdr-style spaces/agents experience and removes
files from the left entirely.

Non-goals for this pass: top-bar redesign, left-sidebar/herdr work, commit
history browsing, branch management UI.

## Approach (chosen: A)

Keep the fast AppKit `NSOutlineView` + `FileExplorerStore` tree and re-skin it;
build the Git tab as new SwiftUI over a new git data layer; build the Changes
view as a main-area panel hosting stacked Monaco inline-diff cards in one
WKWebView. Rejected: SwiftUI tree rewrite (regression risk for identical
pixels), web-rendered panel (wrong feel for a native tree).

## 1. Panel structure

- `FilesGitPanelView` replaces `RightSidebarPanelView` content: header with a
  centered **Files | Git** pill switcher (icon + label per segment; active
  segment gets a subtle raised background), a muted `~`-abbreviated workspace
  path line, then the active tab.
- **Strictly Files | Git.** The mode enum/mode bar and right-sidebar hosting of
  Find, Vault (sessions), Feed, Dock, and custom sidebars are deleted. Find
  folds into the tree filter field. Shortcuts/command-palette entries for dead
  modes are removed.
- Resize: unchanged — existing `.explorerDivider` drag machinery, clamping, and
  `FileExplorerState.width` persistence.

## 2. Files tab

- Tree stays `NSOutlineView` + `FileExplorerStore`. Restyle to the screenshot:
  34–36pt rows, 13px labels, chevrons only on directories, VSCode SVG icons at
  16px, directories-first sort, hover highlight, accent-tinted selection pill.
- **Gitignored dimming**: new batched `git check-ignore --stdin` pass in
  `FileExplorerStore`, cached per directory load; ignored entries render at
  ~40% opacity through the existing styling pipeline.
- Above the tree: rounded "Filter…" field that live-filters the visible tree
  (fuzzy name match, auto-expands matches; reuses the existing search
  controller's matcher, rendered in-tree — the separate results table dies),
  plus reveal-current-file and collapse-all icon buttons.

## 3. Git data layer

- New `GitWorkingTreeModel` (ObservableObject, per workspace, owned by the
  panel). Parses `git status --porcelain=v2 --branch` into branch info (name,
  ahead/behind) and sections: **Staged / Modified / Untracked**, entries
  `{path, status ∈ M A D R U}`.
- Refresh: file-watcher events (debounced) + after every action.
- Actions (async, off-main, shelling to git): stage/unstage file, discard file
  (`git checkout --` / `git clean` for untracked; discard confirms first),
  Stage All, Discard All, commit with message, push (`git push`, or
  `git push -u origin <branch>` when no upstream — the "Publish Branch" case).
- Errors render as an inline red line under the toolbar; no alert dialogs.

## 4. Git tab UI

- Toolbar under the header: branch name, ahead/behind counts, refresh,
  collapse. No decorative buttons.
- Sections as caps labels ("MODIFIED (3)") with right-aligned Stage All /
  Discard All text buttons. File rows: colored status letter (M orange,
  A green, D red, U gray) + filename; click opens the diff; hover reveals
  per-file stage/discard icons.
- Bottom-pinned commit box: multiline "Commit message…" field, Commit button
  (accent; disabled when message empty or nothing staged), green
  Push/"Publish Branch (N)" button.

## 5. Changes panel (main area)

- New panel type `GitChangesPanel`, opens as a main-area tab (like Monaco
  panels). Scope v1: uncommitted vs HEAD.
- Right rail: native SwiftUI file checklist (checkbox = staged, grouped by
  directory, per-file +N counts).
- Main column: **one** WKWebView with stacked Monaco inline-diff cards — one
  auto-height diff editor per file with a filename header and New/undo/stage
  controls — using the bundled Monaco.
- Entry points: "Changes" affordance in the Git tab toolbar; clicking a file
  row in the Git tab.

## 6. Deletions

Right-sidebar mode enum + mode bar, Feed/Dock/Vault right-sidebar hosting,
custom-sidebar right mode, `.find` presentation and its results table, dead
shortcuts/palette entries and their settings routing.

## 7. Testing

- Unit: porcelain-v2 parser; stage/unstage/discard/commit/push actions against
  a temp fixture repo; check-ignore dimming; filter matching; regression that
  removed modes are no longer reachable via shortcuts.
- All user-facing strings localized (en+ja) per repo policy; localization audit
  before finishing.
- Build verified with tagged `reload.sh`; full suite execution deferred per
  Mike's standing instruction.
