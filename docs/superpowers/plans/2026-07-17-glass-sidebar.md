# Liquid Glass Floating Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the left sidebar a floating, rounded liquid-glass panel over a full-width terminal, with ⌘[/⌘] hide/show shortcuts, a reload button in the file tree header, and a footer that reads cleanly on glass.

**Architecture:** Reuse the existing overlay layout branch (`useWithinWindow` in `ContentView.contentAndSidebarLayout`) and the existing `NSGlassEffectView`/`NSVisualEffectView` backdrop plumbing (`WindowBackdropLayer` → `SidebarVisualEffectBackground`). Add a floating variant: inset + rounded sidebar panel, terminal extended to full window width beneath it, an explicit floating-panel frame fed to `WindowTerminalHostView` for pointer routing (the current code infers the sidebar edge from terminal-view geometry, which breaks once the terminal is full-width). New `hideSidebar`/`showSidebar` shortcut actions ride the existing shortcut pipeline.

**Tech Stack:** Swift / SwiftUI / AppKit, Xcode project `cmux.xcodeproj`, Swift Testing in `cmuxTests`.

## Global Constraints

- Build only via `./scripts/reload.sh --tag glass-sidebar` (never bare `xcodebuild` + untagged app). Compile-check via `xcodebuild ... -derivedDataPath /tmp/cmux-glass-sidebar build` is allowed.
- `WindowTerminalHostView.performHitTest` keyboard path (`allowsPortalPointerHitTesting == false` branch) must gain ZERO new work.
- Every user-facing string: `String(localized:defaultValue:)` + entries in `Resources/Localizable.xcstrings` for en AND ja.
- New shortcuts must touch all layers: both `ShortcutAction` enums (a drift test enforces sync), defaults, `handleCustomShortcut`, `Localizable.xcstrings`, `web/data/cmux-shortcuts.ts`, `web/data/cmux.schema.json`.
- Regression tests: two-commit red/green where feasible; test files MUST be wired into `cmux.xcodeproj/project.pbxproj` (verify "Executed N tests" with N > 0).
- Shared behavior policy: hide/show/toggle sidebar all go through one action path (`SidebarState` / `AppDelegate.toggleSidebarInActiveMainWindow` family); no per-entrypoint copies.

---

### Task 1: SidebarState hide/show API (TDD)

**Files:**
- Modify: `Sources/Sidebar/SidebarState.swift`
- Create: `cmuxTests/SidebarStateTests.swift` (wire into pbxproj — copy the four entries pattern from `TabManagerUnitTests.swift`)

**Interfaces:**
- Produces: `SidebarState.hide()`, `SidebarState.show()` (idempotent setters alongside existing `toggle()`).

- [ ] **Step 1: Write failing test**

```swift
import Testing
@testable import cmux

@MainActor
struct SidebarStateTests {
    @Test func hideAndShowAreIdempotent() {
        let state = SidebarState()
        state.isVisible = true
        state.hide()
        #expect(state.isVisible == false)
        state.hide()
        #expect(state.isVisible == false)
        state.show()
        #expect(state.isVisible == true)
        state.show()
        #expect(state.isVisible == true)
    }
}
```

(If `SidebarState()` requires init args, mirror its real initializer from `Sources/Sidebar/SidebarState.swift:6-15`.)

- [ ] **Step 2: Run, verify FAIL** — `xcodebuild test -project cmux.xcodeproj -scheme cmux -destination 'platform=macOS' -only-testing:cmuxTests/SidebarStateTests -derivedDataPath /tmp/cmux-glass-sidebar`. Expected: compile error `value of type 'SidebarState' has no member 'hide'`. Confirm the runner reports the test target actually compiled this file (pbxproj wiring), not "Executed 0 tests".
- [ ] **Step 3: Implement**

```swift
    func hide() { if isVisible { isVisible = false } }
    func show() { if !isVisible { isVisible = true } }
```

- [ ] **Step 4: Run, verify PASS** (same command).
- [ ] **Step 5: Commit** — `git commit -m "Add SidebarState.hide()/show() with tests"` (include pbxproj wiring in this commit).

### Task 2: Floating glass panel layout

**Files:**
- Modify: `Sources/ContentView.swift` (overlay branch ~2557-2574; `sidebarPanelContainer` ~1952-1971)
- Modify: `Packages/macOS/CmuxAppKitSupportUI/.../WindowChrome/Sidebar/WindowChromeSidebarMaterialOption.swift`
- Modify: `Packages/macOS/CmuxAppKitSupportUI/.../WindowChrome/Sidebar/SidebarBackdropSettingsSnapshot.swift` (only if defaults live here; otherwise where `sidebarMaterial`/blend defaults are declared — `cmuxApp.swift:344/2534` reads)

**Interfaces:**
- Produces: layout constants `SidebarFloatingPanelMetrics` (see below), used by Task 3's hit-testing.

- [ ] **Step 1: Add metrics** (new small file `Sources/Sidebar/SidebarFloatingPanelMetrics.swift`):

```swift
enum SidebarFloatingPanelMetrics {
    static let inset: CGFloat = 8      // leading/top/bottom gap from window edges
    static let cornerRadius: CGFloat = 12
}
```

- [ ] **Step 2: Make the overlay branch the floating layout.** In `contentAndSidebarLayout` (`ContentView.swift:2557-2574`):
  - Remove the terminal's `.padding(.leading, sidebarState.isVisible ? sidebarWidth : 0)` so the terminal reference view spans the full width (this is what makes the terminal underlap).
  - Inset the sidebar overlay: `.padding(.leading, SidebarFloatingPanelMetrics.inset).padding(.vertical, SidebarFloatingPanelMetrics.inset)`.
  - Pass `cornerRadius: SidebarFloatingPanelMetrics.cornerRadius` into the backdrop: `sidebarBackdropLayer` already clips to `materialPolicy.cornerRadius` — override the snapshot's cornerRadius for the floating layout (add a `cornerRadiusOverride` parameter defaulting to nil on `sidebarPanelContainer`, applied when building the policy/clip).
  - Animate visibility: wrap the conditional sidebar overlay in `.transition(.move(edge: .leading).combined(with: .opacity))` and flip `isVisible` inside `withAnimation(.spring(duration: 0.25))` at the toggle call sites (Task 4 centralizes this — for now, in `AppDelegate.toggleSidebarInActiveMainWindow`'s SwiftUI-facing closure `onToggleSidebar` at `ContentView.swift:1692/2091`).
- [ ] **Step 3: Default appearance = liquid glass within-window.** Make the floating branch active by default: where `useWithinWindow` is computed (`sidebarBlendMode == withinWindow && !sidebarMatchTerminalBackground`), change the default `sidebarBlendMode` setting value to `.withinWindow` and default `sidebarMaterial` to `.liquidGlass` (find the registered defaults for these keys — `SidebarBackdropSettingsSnapshot` / settings registration in `cmuxApp.swift`). Do NOT remove the settings; users can still pick other materials.
- [ ] **Step 4: Build** — `xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-glass-sidebar build`. Expected: succeeds.
- [ ] **Step 5: Visual check** — `./scripts/reload.sh --tag glass-sidebar --launch`; confirm rounded glass panel floats over terminal content, terminal renders beneath it, ⌘B still toggles.
- [ ] **Step 6: Commit.**

### Task 3: Pointer routing for the floating panel

**Files:**
- Modify: `Sources/TerminalWindowPortal.swift` (`WindowTerminalHostView`, `performHitTest` 142-222, `shouldPassThroughToSidebarResizer` 272-336)
- Modify: `Sources/ContentView.swift` (publish panel frame)

**Interfaces:**
- Consumes: `SidebarFloatingPanelMetrics` (Task 2).
- Produces: `WindowTerminalHostView.floatingSidebarFrame: CGRect?` (in host-view coordinates; nil when sidebar hidden).

- [ ] **Step 1: Add the frame property + pass-through.** In `WindowTerminalHostView`:

```swift
var floatingSidebarFrame: CGRect? // set by portal sync; nil when sidebar hidden
```

Inside `performHitTest`, **inside** the `routingContext.allowsPortalPointerHitTesting` branch (after the titlebar check, before divider checks):

```swift
if let panelFrame = floatingSidebarFrame, panelFrame.contains(point) {
    clearActiveDividerCursor(restoreArrow: true)
    return nil   // let the SwiftUI glass panel receive the event
}
```

The keyboard branch (lines 219-221) is untouched.

- [ ] **Step 2: Fix the resizer inference.** `shouldPassThroughToSidebarResizer` currently infers the divider from hosted-view `minX` (breaks at full-width terminal, `hasLeadingContent` guard 286-299). When `floatingSidebarFrame` is non-nil, compute `dividerX = panelFrame.maxX` directly and return `SidebarResizeInteraction.Edge.leading.hitRange(dividerX:).contains(point.x)`, skipping the geometry inference. When nil (sidebar hidden or non-floating layout), keep the existing code path unchanged.
- [ ] **Step 3: Publish the frame from SwiftUI.** In `ContentView`, attach a `GeometryReader`/`onGeometryChange` to the sidebar panel overlay that reports its frame in window coordinates; forward it to the portal via the existing portal plumbing (`TerminalWindowPortal` owns `hostView` — add a setter that converts window coords to hostView coords and assigns `floatingSidebarFrame`; update on visibility change too, setting nil when hidden). Frame updates happen on layout changes only — never per-event.
- [ ] **Step 4: Build + manual verification** with `reload.sh --tag glass-sidebar --launch`:
  - Click/hover/scroll over the glass panel → sidebar reacts, terminal beneath never does.
  - Drag the panel's trailing edge → resizes.
  - Click terminal to the right of the panel → focuses terminal; typing latency feels unchanged.
  - Hide sidebar (⌘B) → clicks land on the now-exposed terminal area.
- [ ] **Step 5: Commit.**

### Task 4: hideSidebar/showSidebar shortcut actions (⌘[/⌘]), move Focus Back/Forward to ⌘⌥[/⌘⌥]

**Files:**
- Modify: `Packages/macOS/CmuxSettings/Sources/CmuxSettings/Values/ShortcutAction.swift` (cases, `group` → `.workspace`, `displayName`)
- Modify: `Packages/macOS/CmuxSettings/Sources/CmuxSettings/Values/ShortcutAction+Defaults.swift`
- Modify: `Sources/KeyboardShortcutSettings.swift` (cases ~76, `label` ~199, defaults ~341, `isPublicShortcutAction` ~306)
- Modify: `Sources/AppDelegate.swift` (`handleCustomShortcut` ~13238)
- Modify: `Resources/Localizable.xcstrings` (en + ja)
- Modify: `web/data/cmux-shortcuts.ts`, `web/data/cmux.schema.json` (bindings enum ~:1269)
- Create: `cmuxTests/SidebarShortcutDefaultsTests.swift` (wire into pbxproj)

**Interfaces:**
- Consumes: `SidebarState.hide()/show()` (Task 1) via `AppDelegate.toggleSidebarInActiveMainWindow(preferredWindow:)`-style helpers.
- Produces: action ids `hideSidebar`, `showSidebar` (raw values, stable in cmux.json/schema/docs).

- [ ] **Step 1 (red commit): failing defaults test**

```swift
import Testing
@testable import cmux

struct SidebarShortcutDefaultsTests {
    @Test func hideShowSidebarDefaults() {
        let hide = KeyboardShortcutSettings.Action.hideSidebar.defaultShortcut
        let show = KeyboardShortcutSettings.Action.showSidebar.defaultShortcut
        #expect(hide == StoredShortcut(key: "[", command: true, shift: false, option: false, control: false))
        #expect(show == StoredShortcut(key: "]", command: true, shift: false, option: false, control: false))
    }
    @Test func focusHistoryMovedToOption() {
        let back = KeyboardShortcutSettings.Action.focusHistoryBack.defaultShortcut
        #expect(back == StoredShortcut(key: "[", command: true, shift: false, option: true, control: false))
    }
}
```

(Adapt accessor names to the real API at `KeyboardShortcutSettings.swift:341` — the pattern is `case .toggleSidebar: return StoredShortcut(key: "b", command: true, ...)`.) Run `-only-testing:cmuxTests/SidebarShortcutDefaultsTests`; expected FAIL (no such cases). Commit the test alone; CI goes red.

- [ ] **Step 2 (green commit): implement across all layers.**
  - Both enums: `case hideSidebar`, `case showSidebar`; labels `String(localized: "shortcut.hideSidebar.label", defaultValue: "Hide Left Sidebar")` / `"shortcut.showSidebar.label", "Show Left Sidebar"`; package `displayName` mirrors; `group` = same group as `toggleSidebar` (`.workspace`, `ShortcutAction.swift:174-180`); include in `isPublicShortcutAction`.
  - Defaults: hide = `cmd+[`, show = `cmd+]`; change `focusHistoryBack/Forward` defaults from `cmd+[`/`cmd+]` to `cmd+opt+[`/`cmd+opt+]` in BOTH defaults files (`ShortcutAction+Defaults.swift:58-59`, `KeyboardShortcutSettings.swift:390-393`). Leave `browserBack`/`browserForward` (browser-focus-scoped, `ShortcutAction+Defaults.swift:109-110`) at `cmd+[`/`cmd+]` — verify in `handleCustomShortcut` that browser-scoped matches are evaluated before the new global sidebar bindings so a focused browser pane still gets back/forward; if evaluation order doesn't already guarantee it, place the sidebar checks after the browser checks.
  - Dispatch (`AppDelegate.swift`, next to the `toggleSidebar` block at 13238-13241):

```swift
if matchConfiguredShortcut(event: event, action: .hideSidebar) {
    _ = setSidebarVisibilityInActiveMainWindow(false, preferredWindow: mainWindowForShortcutEvent(event))
    return true
}
if matchConfiguredShortcut(event: event, action: .showSidebar) {
    _ = setSidebarVisibilityInActiveMainWindow(true, preferredWindow: mainWindowForShortcutEvent(event))
    return true
}
```

  Implement `setSidebarVisibilityInActiveMainWindow(_:preferredWindow:)` by refactoring `toggleSidebarInActiveMainWindow` (AppDelegate.swift:6642) so toggle/hide/show share one path that ends in `withAnimation { sidebarState.show()/hide()/toggle() }` (shared-behavior policy; also route the command-palette and titlebar toggle through the same helper).
  - `Localizable.xcstrings`: en + ja for both new label keys (ja: 「左サイドバーを隠す」/「左サイドバーを表示」).
  - `web/data/cmux-shortcuts.ts`: two entries with `{ en, ja }` descriptions next to `toggleSidebar` (:82); update the reserved-keys note at :104-118 to say focus history now defaults to ⌘⌥[/⌘⌥].
  - `web/data/cmux.schema.json`: add `hideSidebar`, `showSidebar` to the `shortcuts.bindings` propertyNames enum.
  - Config template regenerates automatically from `publicShortcutActions` (`KeyboardShortcutSettingsFileStore+Template.swift`) — no manual edit.
- [ ] **Step 3: Run tests** (defaults test + full `cmuxTests` for the enum drift test). Expected: PASS.
- [ ] **Step 4: Manual round-trip** — reload tagged app: ⌘[ hides with animation, ⌘] shows, ⌘B still toggles, both new rows visible/editable in Settings → Keyboard Shortcuts, an override in `~/.config/cmux/cmux.json` (`"hideSidebar": "cmd+shift+h"`) is honored, ⌘[/⌘] still do back/forward inside a focused browser pane.
- [ ] **Step 5: Commit (green), push both commits so CI shows red→green.**

### Task 5: File tree header cleanup + reload button

**Files:**
- Modify: `Sources/Sidebar/SidebarFileExplorerPanel.swift` (header HStack, lines 25-47)
- Modify: `Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `FileExplorerStore.reload()` (`Sources/FileExplorerStore.swift:939`), `refreshGitStatus()` (:850 region).

- [ ] **Step 1: Restructure the header.** Keep the collapse Button (chevron + `folderName`) as the leading element, then `Spacer()`, then a trailing reload button shown on row hover (track with `@State private var isHovering = false` + `.onHover` on the header HStack):

```swift
Button {
    store.reload()
    store.refreshGitStatus()
} label: {
    Image(systemName: "arrow.clockwise")
        .font(.system(size: 11, weight: .medium))
}
.buttonStyle(.plain)
.frame(width: 22, height: 22)
.background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(reloadHovering ? 0.08 : 0)))
.opacity(isHovering ? 1 : 0)
.help(String(localized: "sidebar.fileExplorer.reload.tooltip", defaultValue: "Reload file tree"))
.accessibilityLabel(String(localized: "sidebar.fileExplorer.reload.tooltip", defaultValue: "Reload file tree"))
```

(Verify `refreshGitStatus()`'s exact name/visibility at the call site; if it's internal to reload flow, calling `reload()` alone is fine.) Give the header row consistent padding: `.padding(.horizontal, 10).frame(height: 28)` to de-cramp it, matching sidebar row metrics.
- [ ] **Step 2: Localize** — add `sidebar.fileExplorer.reload.tooltip` en + ja (「ファイルツリーを再読み込み」) to `Localizable.xcstrings`.
- [ ] **Step 3: Build + manual check** — hover shows button, click repopulates tree (add a file in another terminal, reload, see it appear), collapse toggle still works.
- [ ] **Step 4: Commit.**

### Task 6: Footer polish on glass

**Files:**
- Modify: `Sources/ContentView.swift` (`SidebarFooter` 12633-12647)

- [ ] **Step 1:** Add a hairline separator above the footer instead of any solid fill: prepend `Divider().opacity(0.35)` (or `Rectangle().fill(.separator).frame(height: 1)`) to the `VStack`; confirm no opaque `.background` fills exist in `SidebarFooter`/`SidebarVersionFooter` (exploration found none — hover fills in `SidebarFooterIconButtonStyleBody` use `Color.primary.opacity` and stay).
- [ ] **Step 2:** Build, visually confirm footer (help, update pill, version text) reads cleanly on glass; update pill keeps accent color.
- [ ] **Step 3: Commit.**

### Task 7: Final verification + localization audit

- [ ] **Step 1:** Full build `./scripts/reload.sh --tag glass-sidebar --launch`; run full `cmuxTests` suite.
- [ ] **Step 2:** Typing-latency review: `git diff main -- Sources/TerminalWindowPortal.swift` — confirm every addition is inside the `allowsPortalPointerHitTesting` branch; no additions to `TabItemView` equatable paths or `forceRefresh()`.
- [ ] **Step 3:** Localization audit (per CLAUDE.md): enumerate new strings (`shortcut.hideSidebar.label`, `shortcut.showSidebar.label`, `sidebar.fileExplorer.reload.tooltip`), parse `Localizable.xcstrings` to confirm en+ja for each; confirm `cmux-shortcuts.ts` entries carry `{ en, ja }`; `rg` the diff for new bare English literals in `Text(`/`Button(`/`.help(`.
- [ ] **Step 4:** Settings/docs check: new shortcut rows render in Settings; `cmux.schema.json` validates a cmux.json containing the new ids; keyboard-shortcuts and configuration doc pages show them.
- [ ] **Step 5:** Commit any fixes; state audit results in the handoff.
