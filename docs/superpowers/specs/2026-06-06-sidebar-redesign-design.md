# Sidebar redesign — thin rows + bottom file explorer

**Date:** 2026-06-06
**Status:** Approved design (pre-implementation)
**Author:** brainstormed with Claude

## Problem

The left sidebar (the workspace/session list) is visually heavy. Each session
renders as a multi-line block (~70px tall): a 12.5pt title plus stacked lines for
status text, branch/directory, ports, pull-request links, progress bars, and log
entries. Only a handful of sessions fit on screen, and the density makes the list
hard to skim. The user also wants a VSCode-style file explorer for the active
session, which the app does not surface in the left sidebar today.

## Goals

1. **Thin rows.** Collapse each session row to a single ~22px line: a colored
   status dot, the title, and a dimmed path. Roughly 3× the on-screen density.
2. **Bottom file explorer.** A VSCode-style file tree in the lower half of the
   left sidebar that follows the active session's working directory. Clicking a
   file inserts its path into the active terminal.

These two parts are independent and ship in sequence (Part A first).

## Non-goals (deliberately deferred)

- Inline expand-on-active rows (the chosen row style is plain one-line; richer
  detail lives in a hover tooltip, not an expanded row).
- Git-repo-root mode for the explorer (we use the raw `currentDirectory`; the
  `gitRepoRoot(for:)` helper already exists in `FileExplorerStore` if we want it
  later).
- Richer file-click actions (insert-path-into-terminal only for now; Open /
  Reveal / Copy Path remain in the right-click menu).

## Background: what already exists (grounded in code)

- **`TabItemView`** (`Sources/ContentView.swift`, ~line 15084) renders each
  session row. It is a typing-latency-sensitive view: it conforms to `Equatable`
  (a 20-property `==` at ~15090–15110) and is used with `.equatable()` so SwiftUI
  skips body re-evaluation during typing. The row's data comes from a value
  snapshot (`workspaceSnapshot`, recomputed only when a `presentationKey`
  changes) that is **excluded** from `==`. This is the snapshot-boundary
  optimization CLAUDE.md warns about.
- **Status vocabulary:** `AgentHibernationLifecycleState`
  (`Sources/AgentHibernation/AgentHibernationLifecycleState.swift`) has four
  cases: `unknown`, `running`, `idle`, `needsInput`. The row currently shows
  status via `SidebarStatusEntry` objects (`Sources/Workspace.swift` ~45–86),
  each carrying an `icon`, a `color` (hex), and a `priority`.
- **File explorer:** `FileExplorerPanelView`
  (`Sources/FileExplorerView.swift`) is an `NSViewRepresentable` wrapping an
  AppKit `NSOutlineView`. It is **per-instance** (not a singleton); `FileExplorerStore`
  and `FileExplorerState` are likewise per-instance and can safely coexist in
  multiple places at once. It already runs in the right sidebar.
- **Root syncing:** `SelectedWorkspaceDirectoryObserver`
  (`Sources/ContentView.swift` ~980–1049) observes `tabManager.$selectedTabId`
  and the selected workspace's `$currentDirectory`, and drives
  `syncFileExplorerDirectory()` (~2613–2679), which calls
  `fileExplorerStore.applyWorkspaceRoot(...)`. This is the live "follow the active
  session" plumbing — already built for the right sidebar.
- **Terminal insertion:** `FileExplorerTerminalPathInsertion.insert(paths:relativeToRootPath:intoTerminalFor:)`
  (`Sources/FileExplorerTerminalPathInsertion.swift`) sends a path to the focused
  terminal panel.
- **Persistence pattern:** `FileExplorerState` persists `width` /
  `dividerPosition` via `UserDefaults` in `@Published` `didSet` blocks
  (`fileExplorer.*` keys). Sidebar width uses `SessionPersistencePolicy`
  (`Sources/SessionPersistence.swift`); default sidebar width 220, range 120–260.

## Architecture note (existing legacy subsystem)

The surrounding code (`TabManager`, `Workspace`, `FileExplorerStore`,
`FileExplorerState`) is `ObservableObject` + `@Published` + Combine — the
pre-existing app-target architecture, not the `@Observable`/`AsyncStream` model
CLAUDE.md mandates for new packages. This feature **extends that existing
subsystem in place** rather than introducing a new one, so it reuses the existing
`ObservableObject`/Combine types (`FileExplorerStore`, `FileExplorerState`, the
directory observer) for consistency and to avoid a parallel state path. Any
genuinely new persisted UI state (the explorer panel's collapsed flag / height
ratio) follows the existing `FileExplorerState` persistence pattern. Introducing
a fresh standalone `@Observable` type here would force an impedance layer against
the Combine-based stores it must interoperate with; that trade-off is called out
for the eng-review/plan stage.

---

## Part A — one-line session rows

### Visual

A single `HStack`:

```
● systems-design-v…                    ~/learning
◆ Decrypt base64 e…                       ~/code1
○ Build link-in-bio…             …/mylinkdump/tam
```

- **Status dot** — leading, ~8pt × `fontScale`. Color reflects the session's
  lifecycle status. We **reuse the color the current status row already uses**
  (derived from the workspace's primary `SidebarStatusEntry` / lifecycle state),
  so the palette stays consistent with the rest of the current UI and we invent
  no new colors. Fallback: neutral/secondary gray when no status is present.
  `needsInput` is the case that should visually stand out.
- **Title** — 12.5pt semibold (unchanged size), `lineLimit(1)`, tail truncation.
  Forced single-line regardless of the `wrapsWorkspaceTitles` setting.
- **Path** — right-aligned, dimmed (~9pt monospaced, secondary color ~0.5),
  **head**-truncated so the informative tail shows (`…/mylinkdump/tam`). Given a
  minimum width budget so the title is not crushed. Reuses the existing
  `compactDirectoryCandidates` / `SidebarPathFormatter` machinery.
- **Kept on-row:** pin icon, unread badge, hover-only close button (all already
  small).
- **Moved to hover tooltip** (`.safeHelp` on the row): branch, directory list,
  ports, pull-request titles, progress, latest log. Nothing is lost — relocated
  off the row. The snapshot still computes this data, so it is available for the
  tooltip at no extra cost.

If the leading glyph currently shown (the asterisk in the screenshots) encodes
agent type rather than being decorative, keep it as a small secondary glyph
between the dot and the title; otherwise the status dot replaces it.

### Default + reversibility

Compact rows become the **default**. A localized Settings toggle
("Compact sidebar rows") restores the detailed multi-line row, and is honored in
`~/.config/cmux/cmux.json` like other sidebar settings. Precedent exists
(`sidebarHideAllDetails`, key `sidebarHideAllDetails`).

### Implementation shape

- Add one boolean to the settings snapshot (`SidebarTabItemSettingsSnapshot`),
  e.g. `compactRowMode`. Because that snapshot is already compared in
  `TabItemView.==` (structurally), the flag rides along automatically — **no other
  change to the 20-property `==`**, and toggling correctly triggers a redraw.
- Gate the body: `if settings.compactRowMode { compactBody } else { currentBody }`
  via two `@ViewBuilder` computed properties. The current body is preserved
  verbatim for the non-compact path.
- `compactBody` is the single `HStack` above with `lineLimit(1)` everywhere.
- No new `@Observable`/store reads in the row body (snapshot-boundary preserved).
  Compact mode renders strictly *fewer* view nodes than today.

### Why this is performance-safe

`TabItemView` is on a typing hot path. The change is purely a conditional render
branch keyed on a flag inside the already-compared settings snapshot; the
`Equatable` identity comparison and the snapshot caching (`presentationKey`) are
otherwise untouched. Animations on `latestLog` / `progress` / `metadataBlocks`
become no-ops in compact mode because those sections do not render.

---

## Part B — bottom file explorer

### Layout

Restructure the left sidebar body into:

```
VStack(spacing: 0) {
    sessionList        // flexible — the existing LazyVStack scroll area
    explorerDivider    // draggable horizontal resizer
    explorerPanel      // slim header + embedded FileExplorerPanelView
    footer             // existing SidebarFooter, pinned at very bottom
}
```

The footer (help / extensions / update pill) stays pinned at the bottom; the
explorer sits between the list and the footer. This resolves the collision that
would otherwise occur (the footer currently anchors `.bottomLeading`).

### Behavior

- **Root follows the active session.** Reuse `SelectedWorkspaceDirectoryObserver`
  to drive a **second** `FileExplorerStore` instance (independent from the right
  sidebar's). When the selected session changes, or its `currentDirectory`
  changes live (e.g. `cd` in the terminal), call
  `store.applyWorkspaceRoot(.local(path:))` on the left store. `currentDirectory`
  is a non-optional `String` (may be empty) — treat empty as "no folder".
- **Click a file → insert path into terminal.** On selection/activation, call
  `FileExplorerTerminalPathInsertion.insert(paths: [path], relativeToRootPath:
  store.rootPath, intoTerminalFor: window)`. Right-click retains Open / Reveal in
  Finder / Copy Path.
- **VSCode-style chrome:**
  - Slim **section header** showing the folder name with a **chevron** to
    collapse/expand. Collapsed → header only; the session list reclaims the
    space. Collapse animates with the existing `.easeInOut(0.18)` used elsewhere.
  - **Draggable horizontal divider** to resize the panel, using the same drag /
    cursor pattern as the right-sidebar resizer (no animation on live drag, per
    the existing `Transaction(animation: nil)` approach).
- **Empty state:** when there is no active session or its directory is empty,
  the panel shows a localized "No folder open" message.

### Embedded chrome

`FileExplorerPanelView`/its container currently always shows a built-in
path-input header that is too heavy for an embedded sidebar use. Add a
`showsHeader: false` (or equivalent) option to the container so the slim section
header is the only chrome in this placement. Mount with `placement: .pane`
(routes focus via the `onFocus` callback rather than the right-sidebar focuser).

### State + persistence

A small piece of new UI state holds the panel's **collapsed** flag and **height
ratio** (0–1 of the available sidebar height), persisted via `UserDefaults`
following the existing `FileExplorerState` `didSet` pattern (e.g. keys
`sidebar.explorerCollapsed`, `sidebar.explorerPanelHeight`, default ~0.35).
Height is clamped to the space available after the session list's minimum and the
footer.

### Snapshot-boundary compliance

The session list remains a `LazyVStack` of value-snapshot rows (unchanged and
already safe). The new explorer panel is a sibling that must **not** read
`dragState` / `tabManager` `@Observable`/`ObservableObject` refs inside the
`LazyVStack` row subtree; it consumes height/collapse state as values and the
store independently. This keeps the list virtualization intact.

---

## Files touched

All in the app target, following existing patterns.

- `Sources/ContentView.swift`
  - `TabItemView`: `compactBody` + body gate (Part A).
  - `VerticalTabsSidebar` / sidebar body: the `VStack` split, divider, explorer
    panel mount, second `FileExplorerStore`/`FileExplorerState`, and reuse of the
    directory observer (Part B).
- `Sources/FileExplorerView.swift` (+ its container view): optional
  `showsHeader` for embedded placement.
- Settings model + Settings UI: the "Compact sidebar rows" toggle.
- `Resources/Localizable.xcstrings`: new strings with **en + ja** (see below).
- Configuration docs + `cmux.json` schema/docs: document the new toggle.

## Localization

New user-facing strings, each requiring **en and ja** entries (the `sidebar.*`
namespace is 100% ja-covered today; match it). Proposed keys:

- `sidebar.fileExplorer.header` — "File Explorer" (or folder-name fallback label)
- `sidebar.fileExplorer.emptyState` — "No folder open"
- `sidebar.fileExplorer.collapse` — collapse chevron tooltip
- `sidebar.fileExplorer.expand` — expand chevron tooltip
- `settings.sidebar.compactRows` — "Compact sidebar rows" (toggle label + help)

xcstrings entry shape (real format):

```json
"sidebar.fileExplorer.emptyState": {
  "extractionState": "manual",
  "localizations": {
    "en": { "stringUnit": { "state": "translated", "value": "No folder open" } },
    "ja": { "stringUnit": { "state": "translated", "value": "フォルダが開いていません" } }
  }
}
```

There is no automatic ja→en fallback; ja values must be hand-entered or ja-locale
users see English.

## Performance & constraints checklist

- `TabItemView.==` 20-property comparison unchanged except the new flag riding in
  the already-compared settings snapshot. `.equatable()` call site untouched.
- No new `@Observable`/store reads inside the `LazyVStack` row subtree
  (snapshot-boundary rule).
- No state mutation inside view-body computations (directory sync stays in the
  observer's sink / `didSet`, not in `body`).
- Reuse the existing `FileExplorer` Combine/`ObservableObject` types in place;
  do not introduce a parallel state system.
- Divider drag uses the existing non-animated transaction + cursor pattern.
- All new user-facing strings localized en + ja.
- New toggle added to settings, surfaced in Settings UI, honored in `cmux.json`,
  and documented.

## Sequencing

1. **Part A — thin one-line rows.** Smaller, self-contained, immediately visible.
2. **Part B — bottom file explorer.** Reuses the existing explorer + observer.

## Open questions for the plan stage

- Exact source for the per-row status color/lifecycle (primary `SidebarStatusEntry`
  vs. a direct `AgentHibernationLifecycleState` on the workspace) — pick the most
  direct, perf-safe accessor.
- Whether the embedded explorer reuses a second `FileExplorerState` instance for
  collapse/height or a tiny dedicated holder.
- Minimum heights for the split (session list min vs. explorer min) and the
  default height ratio.
