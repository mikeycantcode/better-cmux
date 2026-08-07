# herdr left sidebar — design

Date: 2026-08-07 · Branch: `big-cleanup` · Status: approved by Mike

## Goal

Replace the built-in left sidebar content with the minimal herdr layout:
a `spaces` section (the workspace list, restyled to a state dot + name)
above an `agents` section (one row per live agent panel, showing a
working/blocked/idle state glyph, status word, and agent name), ordered by
priority. This becomes the default sidebar look on this branch.

Non-goals: bottom "new / menu" bar, time-in-state text, last-activity
lines, hook-free status inference (process-name fallback), a new "space"
entity above workspaces, changes to extension/custom sidebar providers,
minimal presentation mode, right sidebar.

## Approach (chosen: A)

Keep `VerticalTabsSidebar` (`Sources/ContentView.swift:10192`) as the host —
it owns the extension/custom-sidebar provider switch, resize, floating-panel
chrome, and drag-and-drop — and replace only its **built-in content** with
the herdr layout. New views live in new focused files under
`Sources/Sidebar/`. The existing rich row machinery (metadata rows, git/PR
lines, explorer split, unread previews) is bypassed for the built-in
provider, not deleted.

Rejected: a brand-new sidebar component replacing `sidebarView` wholesale —
re-solves resize/persistence/provider routing for no visible gain.

## 1. Data: status projection

- New enum `AgentSidebarStatus: { blocked, working, idle, unknown }`,
  mapped from `AgentHibernationLifecycleState`
  (`needsInput` → blocked, `running` → working, `idle` → idle,
  `unknown` → unknown).
- New `AgentsSidebarModel` (ObservableObject), pattern-copied from
  `SidebarUnreadModel` (`TerminalNotificationStore.swift:2016`): listens to
  workspace lifecycle changes via a coalesced publisher (~40 ms, like
  `WorkspaceSidebarObservation`), rebuilds immutable snapshots behind an
  equality guard, and publishes:
  - `agentRows: [AgentRowSnapshot]` where
    `AgentRowSnapshot { workspaceId, panelId, workspaceTitle, agentName,
    workspaceAgentCount, status, statusChangedAt }` — one per panel that has
    at least one agent lifecycle key on its workspace
    (`Workspace.agentLifecycleStatesByPanelId`). Per-panel status merges that
    panel's keys with the existing precedence
    (running > needsInput > unknown > idle) then maps to
    `AgentSidebarStatus`.
  - `workspaceRollups: [WorkspaceID: AgentSidebarStatus]` — worst status
    across the workspace's panels (blocked > working > idle > unknown).
- `statusChangedAt` is tracked per (panelId, status) transition inside the
  model (not displayed) so ordering is stable.
- Agent display name (`claude`, `codex`, …) resolved from the panel's agent
  status keys / `SessionAgentPresentation`; falls back to `agent` when
  unresolvable.
- Sort: blocked first, then working, idle, unknown; ties by most recent
  `statusChangedAt` first.

## 2. Spaces section

- Header text `spaces` (lowercase, secondary, bold-mono feel matching the
  mock; concrete font: 13pt semibold monospaced, secondary color).
- One row per workspace, same underlying ordered list the current sidebar
  renders (groups keep their collapse behavior; group headers render in the
  same minimal style as workspace rows but keep their disclosure affordance).
- Row = state dot + workspace title. Dot color from the workspace rollup:
  blocked = red/pink, working = yellow, idle = green, none/unknown = dim
  gray. Selected workspace gets the subtle full-width highlight.
- Click selects the workspace (existing selection path). Existing context
  menu, drag-to-reorder, and rename affordances survive on the new rows.
- Removed from the sidebar: unread count badges, latest-notification text,
  git branch/PR/ports metadata rows, compact-row status dot machinery,
  media-activity chips, and the left explorer split entry points. The
  titlebar bell is the only notification surface.
- Rows follow the snapshot-boundary rule (CLAUDE.md): `Equatable` value
  rows fed by immutable snapshots + closure bundles; no store references
  below the ForEach boundary.

## 3. Agents section

- Divider, then header row: `agents` leading, `priority` trailing (static
  label this pass, same style as headers).
- One row per `AgentRowSnapshot`, two lines:
  - Line 1: state glyph + workspace title, plus `· N` when
    `workspaceAgentCount > 1`.
  - Line 2 (indented under title): status word in its state color
    (`blocked` red/pink, `working` yellow, `idle` green, `unknown` dim) +
    `·` + agent name in secondary color.
- Glyphs: blocked = filled ring (target) in red/pink; working = animated
  scatter-dots in yellow; idle = checkmark in green; unknown = hollow dot,
  dim.
- The working glyph animates (gentle dot shimmer, timer-driven). The
  animation lives entirely inside the glyph subview so parent rows do not
  re-evaluate; no per-frame state writes outside it.
- Click focuses that agent's exact panel: select the workspace, then focus
  the panel via the existing panel-focus routing.
- Row selected-state highlight matches the spaces rows.

## 4. Layout

Within the existing sidebar panel chrome: spaces section scrolls in the
upper region; agents section is pinned below it with its own scroll when
tall. No bottom action bar this pass — new-workspace stays in the titlebar.

## 5. Testing / verification

- Unit (cmux-unit scheme): lifecycle → `AgentSidebarStatus` mapping;
  workspace rollup precedence; priority sort incl. recency tiebreak;
  per-panel row synthesis and `workspaceAgentCount`; agent-name fallback.
- Hands-on: tagged `reload.sh` build; verify with a real claude session
  (hooks installed) that a row appears, animates while working, flips to
  blocked on a permission prompt, and to idle on stop; clicking rows
  focuses the right panel/workspace; extension and custom sidebars still
  render via their providers; resize and visibility toggles unaffected.
- Localization: new user-facing strings (`spaces`, `agents`, `priority`,
  status words, accessibility labels) via `String(localized:)`, en + ja,
  audit before finishing.
