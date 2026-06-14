# Manual-mode Monaco diff: review Claude's file edits in an editor pane (SP3)

**Status:** Approved (2026-06-13)
**Branch:** `manual-edit-diff`
**Scope:** When a coding agent in a cmux terminal is in manual edit-approval mode and proposes a
file edit, pop a Monaco two-pane diff stacked above the agent and let the developer accept/reject
it there. Review-only (no editing the proposed code). Claude Code first.

## Summary

When `claude` runs in manual approval mode and wants to edit a file, cmux already gates that edit:
the injected `PermissionRequest` hook blocks the edit and surfaces a Feed row showing the raw
`tool_input` JSON with Deny / Allow Once / Always / Bypass buttons. This feature replaces that
raw-JSON review for **file-edit tools** with a real **Monaco two-pane diff** that opens as a split
**directly above the agent's pane**; the developer accepts or rejects in that pane, and the pane
closes on decision. The accept/reject reuses the existing permission decision path verbatim — this
spec adds a richer review surface, **not** a new control path.

This is the "Claude-Code-in-VSCode" diff UX, native to cmux. It is **not** the VSCode IDE
integration protocol (WebSocket MCP server + `~/.claude/ide` lock file): that path's `openDiff`
contract is undocumented and version-fragile, and cmux already owns the decision point through its
own hook plumbing.

## Goals

- In manual approval mode, a proposed `Edit`/`Write`/`MultiEdit` shows a Monaco diff (original vs
  proposed) instead of raw JSON.
- The diff opens as a fixed, predictable split **above the agent's pane**, and **closes when the
  edit is accepted or rejected** (or on timeout).
- Accept applies the agent's proposed edit verbatim; Reject skips it. Both flow through the
  **existing** `feed.permission.reply` decision path.
- Gated by a setting (default on), discoverable + editable like other automation toggles.

## Non-goals (this spec)

- **Editing the proposed code before accepting.** Review-only: the diff is read-only. Accept =
  allow verbatim, Reject = deny. Editing-before-accept would require the IDE-protocol write-back
  contract this spec deliberately avoids.
- **The WebSocket/MCP IDE protocol** (`~/.claude/ide/*.lock`, `openDiff`). Out of scope; possible
  later upgrade.
- **Non-edit tool permissions.** Bash, WebFetch, etc. keep today's Feed JSON review UI.
- **`NotebookEdit` rich diff.** Falls back to today's JSON row in v1.
- **Codex / OpenCode / other agents.** Claude Code first (its hook wiring already exists); other
  agents are a fast follow, same as the agent-layout-control spec.
- cmux never edits the user's `CLAUDE.md` / `AGENTS.md`.

## Existing pipeline this builds on (unchanged)

The blocking decision/correlation/timeout machinery already exists and is reused as-is:

```
claude (manual mode) wants Edit foo.swift
  → PermissionRequest hook → `cmux hooks feed --source claude`
  → feed.push { event, wait_timeout_seconds: 120 }   (blocks the hook thread ≤120s)
  → FeedCoordinator.ingestBlocking inserts a permission item (keyed by request_id)
  → PermissionActionArea renders the pending decision in the Feed
  → user clicks → feed.permission.reply { request_id, mode }
  → FeedCoordinator.deliverReply signals the waiter semaphore
  → hook wakes, emits Claude's decision JSON:
       { "hookSpecificOutput": { "hookEventName": "PermissionRequest",
         "decision": { "behavior": "allow"|"deny", ... } } }
  → claude applies or skips the edit
```

Key facts the design relies on:

- The hook payload already carries `tool_name` and `tool_input` (with `file_path`, `old_string`,
  `new_string`, `content`, `edits`), `session_id`, and `cwd`.
- The hook process is spawned with the agent surface's environment, so `CMUX_SURFACE_ID` and
  `CMUX_WORKSPACE_ID` are available to anchor the diff to the calling agent's pane.
- `feed.permission.reply` modes map cleanly: **Accept → `once`**, **Reject → `deny`**,
  **Always allow edits → `always`**.

## Components

### 1. `CmuxEditPreview` — new pure leaf package (the testable core)

The only piece with real branching, so it gets the heaviest tests and lives where a test target can
reach it without launching the app.

- **Input:** `tool_name: String`, `tool_input` (decoded fields), and `originalText: String?` (the
  file's current on-disk text, or `nil` if the file does not exist).
- **Output:** `EditDiff { originalText: String, modifiedText: String, languageId: String,
  isNewFile: Bool, applicable: Bool }`.
- **Rules:**
  - `Write` → `modifiedText = tool_input.content`. If `originalText == nil` → `originalText = ""`,
    `isNewFile = true`. Else overwrite (`originalText` = disk).
  - `Edit` → `modifiedText` = `originalText` with the first occurrence of `old_string` replaced by
    `new_string` (honor `replace_all` when present). If `old_string` is not found in `originalText`
    → `applicable = false` (caller falls back to the JSON row).
  - `MultiEdit` → apply each entry in `edits` sequentially to `originalText`; if any entry's
    `old_string` is not found → `applicable = false`.
  - `languageId` derived from the file extension via the existing `MonacoLanguageMap` mapping (lift
    or mirror the small mapping the Monaco panel already uses).
- **No AppKit / socket / filesystem deps** — `originalText` is injected, so the type is a pure
  transformation and is unit-tested with Swift Testing.
- Follows the package rules: documented public API, one major type per file, constructor injection,
  no singletons, no free functions.

### 2. Monaco diff rendering (extend the existing Monaco integration)

cmux already has a production Monaco integration (`MonacoWebController` → `Resources/monaco/
monaco.html`, served over the `cmux-monaco://` scheme). Monaco 0.55.1 ships `createDiffEditor`.

- **`monaco.html`:** add a `setDiff(original, modified, language, theme)` method to the
  `window.cmuxMonaco` API that disposes any existing editor, builds read-only original + modified
  models, and creates a side-by-side `monaco.editor.createDiffEditor` (read-only, `automaticLayout`).
- **Monaco controller:** add `loadDiff(original:modified:language:theme:)` mirroring the existing
  `load(text:language:theme:)`, including the not-ready `pendingLoad` queueing.
- No new asset pipeline, scheme handler, or bridge — all reused.

### 3. `EditReviewPanel` — the review surface

A dedicated panel that hosts the Monaco diff plus an accept/reject toolbar and binds to one pending
permission's `request_id`.

- **Contents:** the Monaco diff (from the `EditDiff`), a header (file path, "new file" badge when
  `isNewFile`), and a toolbar: **Accept** (primary), **Reject**, and **Always allow edits**
  (secondary). A header also shows the agent/session it belongs to.
- **Placement (diff-specific, fixed):** opens as a **new split stacked directly above the agent's
  pane** (top/bottom split, diff on top), anchored via `CMUX_SURFACE_ID`. This is **not** the SP1
  `PlacementPolicy`; it is a fixed, predictable placement used only for edit-review diffs. Opening
  the split shrinks the agent terminal while the diff is up; closing restores it.
- **Decision wiring:** the toolbar buttons call the **existing** `feed.permission.reply` with the
  panel's `request_id` (Accept→`once`, Reject→`deny`, Always→`always`). No new socket method, no new
  decision contract.
- **Lifecycle:**
  - Opens when a file-edit permission arrives **and** the setting is on **and** the edit is
    `applicable`.
  - **Closes when the edit is accepted or rejected** — whether the decision came from this panel
    **or** from the Feed row — and on the 120s timeout (briefly shows "timed out").
  - Ephemeral: no reuse logic; each pending edit opens a fresh panel keyed by `request_id`.

### 4. Feed integration (one source of truth)

- The Feed permission item still appears (it is the system of record and the fallback when the diff
  panel is closed). For file-edit tools its row shows a compact summary and the same buttons.
- Per the shared-behavior policy, resolving in **either** the diff panel or the Feed row resolves
  the one underlying permission (same `request_id` → same `feed.permission.reply`), and both
  surfaces reconcile (the diff panel closes, the Feed row shows the resolved badge).

### 5. Setting + discovery

- New key **`automation.manualEditDiff`** (`Bool`, default **on**), mirroring the existing
  `automation.agentCapabilityBrief`:
  - CmuxSettings catalog key in the automation section.
  - CmuxSettingsUI automation row + curated entry.
  - Command-palette toggle.
  - Round-tripped to `~/.config/cmux/cmux.json`; documented in `web/data/cmux.schema.json` and
    `skills/cmux-settings/references/all-keys.md`.
  - `Resources/Localizable.xcstrings` strings (title/subtitleOn/subtitleOff/note) in en + ja.
- When off, file-edit permissions fall back to today's Feed JSON UI; nothing else changes.

## Data flow

```
claude (manual) → Edit foo.swift
  PermissionRequest hook → feed.push (blocks ≤120s)               [unchanged]
  FeedCoordinator inserts permission item (request_id)            [unchanged]
  NEW: file-edit tool + automation.manualEditDiff on + applicable?
       read originalText off-main (disk @ file_path, nil if absent)
       EditDiff = CmuxEditPreview.compute(tool_name, tool_input, originalText)
       if applicable: open EditReviewPanel split ABOVE agent (CMUX_SURFACE_ID),
                      render Monaco diff via loadDiff(...)
       else: leave today's Feed JSON row (no panel)
  user clicks Accept/Reject (diff panel or Feed row)
  feed.permission.reply { request_id, mode }                      [unchanged]
  EditReviewPanel closes; Feed row shows resolved badge
  hook wakes → emits allow/deny → claude proceeds                 [unchanged]
```

## Threading / policy

- Reading `originalText` from disk is read-only and happens **off-main** before building the
  `EditDiff` (no focus side effects), consistent with the socket threading policy.
- Opening/closing the split and rendering Monaco are UI mutations on the main actor.
- Opening the diff split must **not** steal focus per the focus policy beyond the intended
  presentation of the review pane above the agent; the decision itself is user-driven.

## Edge cases (settled)

- **Trigger conditions:** only manual approval mode (the permission only fires then) and only
  `Edit` / `Write` / `MultiEdit`. `NotebookEdit`, non-edit tools, and non-`applicable` edits keep
  the Feed JSON row; no panel opens.
- **Sequential by nature:** claude awaits each permission, so a session shows at most one edit diff
  at a time. Multiple agents → multiple panels, each anchored to its own surface by `request_id`.
- **Timeout:** at 120s the hook returns and the panel closes (shows "timed out"); behavior matches
  today's Feed timeout handling.
- **New file:** `Write` to a non-existent path diffs against empty original with a "new file" badge.
- **Non-applicable edit** (`old_string` not found): fall back to the Feed JSON row rather than
  showing a misleading diff.

## Testing

- **`CmuxEditPreview`** — Swift Testing unit tests, two-commit red/green:
  - `Edit` substitution (single + `replace_all`).
  - `Write` new file (`isNewFile`, empty original) vs overwrite existing.
  - `MultiEdit` sequential application.
  - `languageId` from extension.
  - `old_string` not found → `applicable == false`.
- **Decision mapping** — a behavioral test that a file-edit permission still resolves through
  `feed.permission.reply`, and that Accept maps to `once` / Reject to `deny` / Always to `always`.
  The decision path is unchanged, so this asserts the mapping, not a new wire.
- **No source-text / plist / signature tests** (per the test-quality policy). The setting is
  verified through runtime behavior (file-edit permission shows a diff when on, JSON row when off),
  not by reading catalog/schema source.

## Localization

- New user-facing strings: the `automation.manualEditDiff` Settings toggle title/subtitle/note, the
  command-palette entry, the diff panel header/badges ("new file", "timed out"), and the Accept /
  Reject / Always-allow button labels. Add en + ja to `Resources/Localizable.xcstrings`, plus the
  CmuxSettings catalog key, `cmux.schema.json`, and `all-keys.md` for the setting. Run the
  localization audit over every touched user-facing surface before handoff.

## Open risks / verify at build time

- **`createDiffEditor` in the vendored Monaco 0.55.1 shell:** confirm it renders correctly under
  the `cmux-monaco://` scheme and current `paths:{vs}` loader config; the single editor already
  works, so the diff editor should too, but verify the read-only side-by-side layout + theme.
- **Surface anchoring from the hook:** confirm `CMUX_SURFACE_ID` (and workspace id) reliably reach
  the app for the pending permission so the split opens above the **correct** agent pane; if a
  surface id is missing, fall back to the focused pane (and still show the diff).
- **Split-above primitive:** confirm `pane.create` (direction up) + opening the diff content yields
  a clean top/bottom split and that closing it restores the agent terminal's size.
- **Feed ↔ panel reconciliation:** ensure resolving from the Feed row closes the panel and vice
  versa without double-replying to the same `request_id`.
