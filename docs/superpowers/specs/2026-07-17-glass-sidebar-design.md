# Liquid Glass Floating Sidebar — Design

**Date:** 2026-07-17
**Status:** Approved by Mike (brainstorming session)

## Goal

Turn the left sidebar into a floating, rounded "liquid glass" panel that blurs live
terminal content beneath it (reference: frosted-glass sidebar over colorful content),
add ⌘[ / ⌘] shortcuts to hide/show it, add a reload button to the file tree header,
and make the sidebar footer read cleanly on glass. No broader sidebar restyling
(rows, top toolbar icons, footer redesign are explicitly out of scope).

## 1. Floating glass sidebar with terminal underlap

- The terminal host surface extends to the full window width, running underneath
  the sidebar region.
- The sidebar renders as a floating panel: ~12pt corner radius, inset ~8pt from the
  window's left/top/bottom edges, drawn over the terminal.
- Backdrop: a new "floating glass" option in the existing material system —
  `WindowBackdropLayer` → `SidebarVisualEffectBackground`
  (`Packages/macOS/CmuxAppKitSupportUI/.../SidebarVisualEffectBackground.swift`).
  Uses `NSGlassEffectView` on macOS 26+ (true Liquid Glass over live content);
  falls back to `NSVisualEffectView` with `.withinWindow` blending on older macOS.
- Hit-testing contract (typing-latency-sensitive): all new routing in
  `WindowTerminalHostView.hitTest()` (`TerminalWindowPortal.swift`) stays inside
  the existing `isPointerEvent` guard. Pointer events within the visible panel's
  frame route to the sidebar; they must never reach the terminal beneath. The
  keyboard path gains zero new work.

## 2. Show/hide shortcuts: ⌘[ (hide) and ⌘] (show)

- Because the terminal is already full-width underneath, hide/show is purely a
  panel fade/slide — no terminal relayout.
- Shortcuts follow the full shortcut policy: registered in
  `KeyboardShortcutSettings`, visible/editable in Settings, supported in
  `~/.config/cmux/cmux.json`, documented in the keyboard-shortcut and
  configuration docs.
- If an existing sidebar-toggle action exists, ⌘[/⌘] bind to that shared action
  path (shared behavior policy) rather than duplicating logic. If ⌘[/⌘] are
  already taken (e.g., workspace back/forward navigation), surface the conflict
  to Mike before rebinding — do not silently steal them.

## 3. File tree header cleanup + reload button

- `SidebarFileExplorerPanel` (`Sources/Sidebar/SidebarFileExplorerPanel.swift`)
  header row: chevron + folder name on the left; a reload button
  (`arrow.clockwise`, hover-visible) trailing.
- Reload wires to the existing `FileExplorerStore.reload()` plus
  `refreshGitStatus()` (`Sources/FileExplorerStore.swift`).
- Localized tooltip via `String(localized:)` with entries in
  `Resources/Localizable.xcstrings` for all supported locales (en, ja).
- Hover style matches `SidebarFooterIconButtonStyleBody` (8pt rounded rect,
  primary-opacity fill).

## 4. Glass footer

- `SidebarFooter` (help button, extensions button, update pill, version label)
  stays inside the glass panel. Minimal restyle: hairline top separator, no
  opaque fills, update pill keeps its accent color. No structural redesign.

## 5. Out of scope

- Session/workspace row restyling, top toolbar icon restyle, footer redesign.
- iOS app, Ghostty submodule changes.

## Testing & verification

- Build via `./scripts/reload.sh --tag glass-sidebar`.
- Typing latency: confirm no additions outside the pointer-event guard in
  `hitTest()`; no new observed objects in `TabItemView`-adjacent paths.
- Pointer routing: clicks/hover on the glass panel never reach the terminal;
  clicks on exposed terminal edges still work; divider drag still works.
- Shortcut round-trip: default bindings, Settings edit, cmux.json override,
  docs updated.
- Regression tests follow the two-commit red/green policy where behavior-level
  coverage is feasible (shortcut action wiring, sidebar visibility state).
- Localization audit for every new user-facing string.
