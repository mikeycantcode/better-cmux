# Mermaid diagram viewer

Date: 2026-07-18
Status: approved, ready for implementation planning

## Problem

Planning and design conversations with an agent are frequently graph-shaped —
architectures, state machines, data flow, decision trees. Today that structure gets
flattened into prose and bullet lists because text is the only channel between the
agent and the user. cmux can render the graph instead.

cmux already renders mermaid, but only as a fence inside a scrolling markdown
document: page-scroll interaction, markdown chrome, no camera. That is a document
viewer that happens to contain a diagram, not a diagram viewer.

## Goal

`cmux open arch.mmd` opens a high-fidelity, minimal diagram surface. The agent writes
and rewrites the `.mmd` file; the panel re-renders live. Text-first authoring, visual
consumption.

## Non-goals

Explicitly cut from v1:

- Export (SVG/PNG, clipboard, save panel). This is a conversation surface, not a
  publishing tool.
- Any toolbar, zoom control, or persistent chrome. Resting state is the diagram on
  dots.
- Click-a-node-to-jump-to-source, drag-to-reposition. Editing is text-first.
- A native Swift mermaid renderer.
- A new `PanelType`.

## Existing infrastructure this builds on

Discovered during design; it is most of the feature.

- `Sources/Panels/MarkdownWebRenderer.swift` — `NSViewRepresentable` over a
  `WKWebView`, with a `WKScriptMessageHandler` registered as `cmuxLib`.
- `Resources/markdown-viewer/mermaid.min.js` — bundled (2.5 MB), lazy-loaded exactly
  once per WebView on first mermaid fence. Load path:
  `shell.html:1014` posts `{lib: 'mermaid'}` → `MarkdownWebRenderer.swift:645-690`
  (`handleLibRequest`) injects it → `window.__cmuxLibLoaded(name)` at `shell.html:1021`.
- `Sources/Panels/MarkdownPanel.swift:78, :423-442` — `FileWatcher` giving live reload
  on disk change, including atomic-replace handling. Update path is file-mediated:
  file write → watcher → `loadFileContent` (`:343`) → `coordinator.update(markdown:theme:)`
  (`MarkdownWebRenderer.swift:105`) → `evaluateJavaScript`.
- `Sources/Panels/FilePreviewWorkspaceOpenSupport.swift:17-55` —
  `Workspace.openFileSurfaces(...)`, the single file-type routing point.
- `Sources/FileOpenSocketSupport.swift:73-176` — `v2FileOpen` socket handler.

## Design

### 1. Routing

`FilePreviewWorkspaceOpenSupport.swift:17-55` gains a branch alongside the existing
markdown check: extensions `mmd` and `mermaid` route to the markdown panel opened in
diagram mode.

`cmux open` is the only verb. No new CLI subcommand — the agent already knows `cmux
open`, and this composes with existing smart placement (`CLI/cmux_open.swift:865`,
`PlacementPolicy`).

### 2. Diagram display mode

`MarkdownPanel.displayMode` (`MarkdownPanel.swift:39`) gains a `.diagram` case
alongside `.preview` and `.text`. `.text` remains available on a `.mmd` file as the
raw-source escape hatch.

In diagram mode `shell.html` renders a single diagram with no document flow:

- **Dot grid.** Low-contrast dots on the cmux background, fixed to *diagram* space —
  they translate and scale with the camera. This is what makes pan/zoom read as
  physical rather than as scrolling a page.
- **Theming.** cmux background color; mermaid `themeVariables` driven from the app
  palette (node fill, edge stroke, label text), dark/light following the existing
  theme plumbing in `MarkdownViewerAssets.shellHTML(isDark:)`.
- **Interaction.** Drag to pan. Pinch / scroll to zoom. Double-click to fit. No
  scrollbars, no toolbar, no visible controls.

### 3. Live reload with camera preservation

The `FileWatcher` already delivers re-render on change. The new work is capturing the
camera transform (pan offset + zoom scale) before re-render and restoring it after, so
the diagram updates beneath a stationary camera instead of snapping to fit. A diagram
being iterated on should not jump every time the agent adds an edge.

Fit-to-view applies on first render only, and on explicit double-click.

### 4. Error reporting

`shell.html` calls `mermaid.parse()` before rendering and posts the result back
through the existing `cmuxLib` message handler.

- **Panel:** invalid syntax shows an inline error card naming the mermaid message and
  offending line, rendered *over the last good diagram*, which stays visible. A typo
  mid-edit must not blank the diagram being read.
- **CLI:** `FileOpenSocketSupport.swift` holds the `file.open` response until the
  parse callback arrives, so `cmux open bad.mmd` exits non-zero and prints the error
  to stderr. Valid diagrams print nothing. A timeout falls through to success so a
  hung WebView cannot wedge the CLI.

This closes the agent's feedback loop: the agent finds out its own diagram is broken
without the user having to act as the compiler.

### 5. Agent exposure

- `Sources/WorkspaceSnapshotSocketSupport.swift:193-208` — the `snapshotActions`
  array is the designated advertisement point for agent-facing verbs.
- `skills/cmux-markdown/SKILL.md` — document the `.mmd` pattern next to the existing
  markdown one: write the file, `cmux open diagram.mmd`, then rewrite the file to
  update.

No new RPC method. The update path stays file-mediated, identical to markdown.

## Risk

Blocking `file.open` on a WebView callback is the only place this design introduces a
new mechanism into the socket layer; everything else is reuse. If it proves ugly
against `ControlCommandCoordinator`, the fallback is a separate validate verb
(`cmux mermaid check <file>`) that the agent calls before opening, with the panel's
inline error card unchanged.

## Testing

- Routing: `.mmd` and `.mermaid` open in diagram mode; `.md` behavior unchanged.
- Live reload: rewriting the file re-renders; camera offset and zoom survive the
  re-render.
- Errors: invalid syntax yields non-zero exit and stderr text from `cmux open`; the
  panel shows the error card with the prior render still visible; a valid file prints
  nothing.
- Theme: diagram colors follow dark/light switches.
- Regression: markdown panels containing mermaid fences still render as before.

## Localization

The inline error card and any new user-facing strings require entries in
`Resources/Localizable.xcstrings` for all supported locales (English, Japanese) per
the repo localization policy.
