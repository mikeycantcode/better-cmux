# Agent layout control: "pull up `<file>`" + tab reorg + auto-discovery

**Status:** Approved (2026-06-12)
**Branch:** `agent-layout-control`
**Scope:** SP1 (pull-up-file + agent screen-context) + SP2 (tab/pane reorg), with automatic
agent discovery. Manual-mode Monaco diff (SP3) is a separate later spec.

## Summary

Let coding agents running inside cmux terminals reorganize the workspace on the developer's
behalf — open a file beside them, see what's on screen, and move/reorder tabs and panes — when
the developer asks in plain English. The developer never types `cmux`; the agent learns the
capabilities automatically at launch and invokes the bundled `cmux` CLI itself.

Almost all primitives already exist (`file.open`, `surface.split`, `pane.*`, `surface.move`,
`surface.reorder`, `pane.swap`, `tab.action`, `pane.list`, `bonsplitController.treeSnapshot()`,
and the auto-installed `claude` wrapper). This feature adds: one consolidated read-only
introspection command, a pure placement-policy in the CLI, a few ergonomic CLI verbs, and a
capability brief auto-injected by the agent wrapper.

## Goals

- `cmux open <file>` places the file intelligently (see placement policy) relative to the
  calling agent's pane, so the developer sees it without managing layout.
- Agents can query a single rich snapshot of the current workspace layout + what each surface
  shows, to make placement/reorg decisions.
- Agents can move and reorder tabs/panes via ergonomic verbs that accept human-friendly targets.
- Agents discover all of this **automatically** — zero developer setup, no `cmux` typing by the
  human, no file edits, no MCP.

## Non-goals (this spec)

- Manual-mode Monaco edit-approval diff (SP3) — separate spec.
- MCP server/tools — cmux has no MCP infra; the wrapper-brief + CLI is the automatic path now.
  MCP is a possible later upgrade.
- Auto-wrappers for Codex / OpenCode / Pi — discovery ships for **Claude Code** first (its
  wrapper already exists at `Resources/bin/claude`); other agents are a fast follow.
- cmux never edits the user's `CLAUDE.md` / `AGENTS.md`.

## Placement policy (the "pull up" core)

Confirmed behavior:

- **"Horizontal split" = beside** — a new pane to the **right** of the agent (cmux left/right
  split, vertical divider).
- Anchor = the calling agent's surface (`CMUX_SURFACE_ID`), in its pane `P`.
- **If `P` is NOT already part of a left/right split** → open the file in a **new right split**
  beside the agent (`surface.split direction=right type=file`... see "open mechanism").
- **If `P` IS already in a left/right split** → do **not** add a 3rd column; open the file as a
  **new tab in the neighbor pane** (the horizontally-adjacent non-agent pane). With exactly two
  panes the neighbor is unambiguous; with more, pick the nearest right neighbor of `P` (else the
  nearest left).
- The file opens **focused by default** (the developer asked to *see* it); `--no-focus` keeps
  focus on the agent.
- If the same file is already open in a `filePreview` surface, **reuse/focus it** instead of
  opening a duplicate.

This decision is a **pure function** in the CLI: `decide(snapshot, anchorSurfaceId, overrides)
-> Placement`, where `Placement` is one of `.splitRight(fromSurface:)`,
`.newTab(inPane:)`, `.reuse(surface:)`, or `.here(pane:)`. It is unit-tested independently of
the app and the socket.

## Components

### 1. `workspace.snapshot` — new read-only socket command (app)

Returns the full layout tree + rich per-surface descriptors in one call. Read-only ⇒ off-main
execution policy (no focus side effects), per the socket threading/focus policy.

Shape (JSON):

```json
{
  "workspace_id": "…", "container_frame": {"x":0,"y":0,"width":…,"height":…},
  "focused_pane_id": "…",
  "anchor": { "surface_id": "<CMUX_SURFACE_ID echo>", "pane_id": "…" },
  "tree": {
    "kind": "split", "orientation": "horizontal", "divider_position": 0.5,
    "children": [
      { "kind": "pane", "pane_id": "…", "frame": {…}, "focused": true,
        "selected_surface_id": "…",
        "surfaces": [
          { "id": "…", "type": "terminal", "title": "zsh", "selected": true,
            "cwd": "/Users/…/pi", "command": "claude" },
          { "id": "…", "type": "browser", "title": "TensorBoard", "url": "http://localhost:6006/…" },
          { "id": "…", "type": "filePreview", "title": "eval.mp4", "file_path": "/…/eval.mp4" },
          { "id": "…", "type": "markdown", "title": "notes", "source": "/…/notes.md" }
        ] },
      { "kind": "pane", "pane_id": "…", … }
    ]
  },
  "actions": [
    { "verb": "open",        "cli": "cmux open <file>",                 "desc": "Show a file beside you (smart placement)." },
    { "verb": "snapshot",    "cli": "cmux snapshot",                    "desc": "This layout, as JSON." },
    { "verb": "move-tab",    "cli": "cmux move-tab <surface> --to-pane <pane|left|right|up|down>", "desc": "Move a tab to another pane." },
    { "verb": "reorder-tab", "cli": "cmux reorder-tab <surface> --index N", "desc": "Reorder a tab within its pane." },
    { "verb": "swap-panes",  "cli": "cmux swap-panes <a> <b>",          "desc": "Swap two panes." }
  ]
}
```

- Built from `bonsplitController.treeSnapshot()` plus per-surface enrichment by panel type:
  terminal → `cwd`/`command` (from reported shell state / tty), browser → `url`,
  filePreview → `file_path`, markdown → `source`. Missing fields are omitted (not null-spammed).
- The `actions` array makes the snapshot **self-documenting**: any agent that looks at the
  screen also learns what it can do.
- Surface metadata that isn't readily available off-main (e.g. live cwd) is best-effort; absence
  is acceptable for v1.

### 2. PlacementPolicy — pure CLI logic (Swift, in the bundled CLI)

- Input: decoded `workspace.snapshot`, `anchorSurfaceId` (from `CMUX_SURFACE_ID`), and override
  flags (`--here`, `--split <dir>`, `--tab`).
- Walks the tree to find the anchor pane and whether it has a horizontal (left/right) neighbor.
- Emits a `Placement`; the CLI then issues the matching existing socket call.
- No app, AppKit, or socket dependency in the decision function ⇒ unit-testable.

### 3. CLI verbs (bundled `cmux` CLI)

- **`cmux open <file>`** — smart by default: snapshot → policy → `surface.split` (new pane,
  `type=file`) **or** `file.open --pane <neighbor>`. Overrides: `--here` (current pane tab),
  `--split <left|right|up|down>` (force orientation), `--tab` (force new tab in current pane),
  `--no-focus`. Reuses an existing preview of the same path. (Enhances the existing `cmux open`.)
- **`cmux snapshot`** — prints `workspace.snapshot` JSON (for agents + debugging).
- **`cmux move-tab <surface> --to-pane <pane|left|right|up|down>`** → `surface.move` (cross-pane).
- **`cmux reorder-tab <surface> --index N | --before/--after <surface>`** → `surface.reorder`.
- **`cmux swap-panes <a> <b>`** → `pane.swap`.
- Targets accept ids or human-friendly references resolved against the snapshot (e.g.
  `right` = the pane right of the anchor; a title/filename match for a surface). Resolution is
  part of the pure, tested logic.

### 4. Automatic discovery — agent capability brief via the wrapper

- Extend `Resources/bin/claude` (the existing auto-on-PATH Claude Code wrapper) to also inject
  `--append-system-prompt` with a **concise** cmux capability brief (a few lines: open a file →
  `cmux open`, see layout → `cmux snapshot`, rearrange → `cmux move-tab`/`reorder-tab`, plus
  "use only when the user asks to see/arrange things").
- Gated by a setting `agent.cmuxCapabilityBrief` (default **on**), round-tripped to
  `cmux.json` like other toggles, visible in Settings + command palette.
- Brief kept short to bound per-session token cost and to stay high-signal.
- Claude Code only in this spec; the wrapper pattern extends to other agents later.

## Data flow

```
developer (to agent): "pull up eval.mp4"
agent (already briefed at launch): runs  cmux open eval.mp4
  cmux CLI:
    read CMUX_WORKSPACE_ID / CMUX_SURFACE_ID
    socket workspace.snapshot ─────────────► app returns tree + descriptors + actions
    PlacementPolicy(snapshot, anchor, overrides) → Placement     (pure, tested)
    socket surface.split | file.open | (reuse → surface.focus)   (existing primitives)
```

## Threading / policy

- `workspace.snapshot` is read-only ⇒ off-main allowed; it must **not** steal focus.
- `cmux open` placement issues mutating commands (`surface.split`/`file.open`) which are
  main-actor per existing policy; `focus` follows the `--no-focus` flag and the focus policy.

## Testing

- **PlacementPolicy** (Swift unit tests, CLI test target): two-commit red/green.
  - single pane → `.splitRight`
  - already left/right split → `.newTab(inPane: neighbor)`
  - file already open → `.reuse`
  - `--here` / `--split` / `--tab` overrides
  - >2-pane neighbor disambiguation (nearest right, else left)
  - target resolution: `right`/title/filename → ids
- **`workspace.snapshot`** verified via a behavioral python/socket test against a tagged build
  (asserts tree shape + per-surface descriptors + `actions`). No source-text/plist tests.
- Wrapper brief: assert (behaviorally, against the built wrapper) that `--append-system-prompt`
  is added when the setting is on and `CMUX_SURFACE_ID` is set, and omitted when off. Avoid
  asserting on the exact brief wording.

## Localization

- New user-facing strings: the `agent.cmuxCapabilityBrief` Settings toggle title/subtitle and
  the command-palette entry. Add en + ja to the appropriate catalogs, the CmuxSettings catalog
  key, `cmux.schema.json`, and `all-keys.md`. CLI `--help` text is developer-facing English
  (matches existing CLI help; not localized).

## Open risks / decisions to verify at build time

- **Off-main surface metadata:** cwd/command for terminals may require main-actor or reported
  shell state; if not cheaply available off-main, omit those fields in v1 rather than block.
- **`surface.split` with `type=file`:** confirm `surface.split` can create a `filePreview`
  surface directly; if it only does terminal/browser/markdown, split an empty pane
  (`pane.create`) then `file.open --pane`. Resolve during implementation; the policy emits an
  abstract `Placement` so the wiring is swappable.
- **Neighbor identification in the tree:** define "horizontal neighbor" precisely against the
  `treeSnapshot` structure (sibling under a horizontal split, walking up from the anchor pane).
- **Wrapper brief token cost:** keep under ~6 lines; revisit if it bloats context.
- **CLI test target:** confirm the bundled CLI has (or can get) a Swift test target for the
  PlacementPolicy red/green; if not, host the pure policy where a test target can reach it.
