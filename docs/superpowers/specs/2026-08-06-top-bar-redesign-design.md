# Top bar redesign — design

Date: 2026-08-06 · Branch: `big-cleanup` · Status: approved by Mike

## Goal

Restyle the standard-mode titlebar band into the minimal Codika look: a
sidebar toggle at each end of the window, the five existing controls
regrouped into two edge clusters, and a quiet, truly-centered workspace
title. Minimal presentation mode is untouched.

Non-goals: minimal mode, herdr-style left sidebar, new shortcuts, tab bar
changes, notification popover changes.

## Approach (chosen: A)

Keep the existing AppKit `NSTitlebarAccessoryViewController` mechanism
(`TitlebarControlsAccessoryViewController` in
`Sources/Update/UpdateTitlebarAccessory.swift`) and add a second accessory
at `layoutAttribute = .right`. Rejected: all-SwiftUI band using
`.titlebarInteractiveControl()` hit regions — re-solves drag/double-click/
fullscreen behaviors the accessory already handles, for no visible gain.

## 1. Button clusters

Split the current five-button left cluster (`TitlebarControlsView`) into:

- **Left accessory** (existing, `.left`, right of traffic lights):
  toggle-left-sidebar, focus back, focus forward.
- **Right accessory** (new, `.right`, flush with the window's right edge):
  new-workspace (`plus`), notifications (badge + `NSPopover` unchanged),
  toggle-right-sidebar (`sidebar.right` icon) wired to the existing
  `AppDelegate.toggleRightSidebarInActiveMainWindow`. The right-sidebar
  toggle is the outermost button, mirroring the left toggle.

Button styling is unchanged (`HeaderChromeControlMetrics`: 20pt buttons,
12pt icons). The shortcut-hint pill overlay stays with the left accessory's
toggle button; the right toggle gets the same hint treatment for ⌥⌘B under
the existing `ShortcutHintTitlebarPolicy`.

Visibility rules carry over: both accessories hide in minimal mode and in
fullscreen (`applyAccessoryVisibility`).

## 2. Centered title

In `customTitlebar` (`Sources/ContentView.swift`): the folder drag-icon +
`titlebarText` move from left-aligned to window-centered (overlay-centered
on the band, not centered in leftover space, so it doesn't shift when
sidebars open). Style drops from 13pt bold to 13pt medium, secondary color.
The band remains a drag surface everywhere that isn't a button; the folder
icon keeps its drag-out behavior.

The band's trailing padding equal to `rightSidebarWidth` remains (the right
sidebar header must stay hittable); the new right accessory sits above the
sidebar at the true window edge — when the sidebar is open the toggle
floats over its top strip, Xcode-style.

## 3. Fullscreen

`fullscreenControls` (the SwiftUI mirror of the accessory shown only in
fullscreen) splits the same way: left trio at the existing leading
placement, right trio via a new trailing placement. Same buttons, same
actions.

## 4. State

The right toggle reflects `fileExplorerState.isVisible` the same way the
left toggle mirrors sidebar visibility (via the window-associated controls
availability path). No new persistence, settings, or shortcuts — ⌘B and
⌥⌘B already exist.

## 5. Testing / verification

- Unit: pure regrouping logic if any is extracted; otherwise none — this is
  chrome layout.
- Build via tagged `reload.sh`; hands-on verification of: both toggles
  work, title stays centered while either sidebar opens/closes, drag/
  double-click-zoom still work on the band, notifications popover anchors
  correctly from its new position, fullscreen shows both clusters.
- New user-facing strings (right-toggle tooltip/accessibility label)
  localized en+ja; localization audit before finishing.
