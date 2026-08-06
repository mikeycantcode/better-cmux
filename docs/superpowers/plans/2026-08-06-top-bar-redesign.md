# Top Bar Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the titlebar's five-button left cluster into two edge clusters (left: sidebar toggle + focus back/forward; right: new-workspace + notifications + a new right-sidebar toggle), and center the workspace title in the band with a quieter style.

**Architecture:** The existing AppKit `NSTitlebarAccessoryViewController` mechanism (`TitlebarControlsAccessoryViewController` in `Sources/Update/UpdateTitlebarAccessory.swift`) gains a `cluster` parameter; the controller installs one accessory at `.left` and a second at `.right`. The layout-metrics/hint-slot machinery, which today assumes one fixed five-button row, is parameterized by cluster. `ContentView.customTitlebar` centers the folder icon + title as a band-wide overlay; the fullscreen SwiftUI mirror renders both clusters.

**Tech Stack:** Swift, SwiftUI + AppKit, Swift Testing (`cmux-unit` scheme).

## Global Constraints

- Standard presentation mode only; minimal mode behavior must be byte-identical (accessories stay hidden in minimal mode and fullscreen via `applyAccessoryVisibility`).
- Button clusters (spec §1): left accessory = toggle-left-sidebar, focus back, focus forward. Right accessory = new-workspace (`plus`), notifications (badge + popover unchanged), toggle-right-sidebar (`sidebar.right` icon, outermost button).
- Right toggle action: `AppDelegate.shared?.toggleRightSidebarInActiveMainWindow(preferredWindow:)` (`Sources/AppDelegate.swift:6374`). No new shortcuts — the action `.toggleRightSidebar` (raw `"toggleFileExplorer"`, default ⌥⌘B) already exists in `KeyboardShortcutSettings`.
- Title (spec §2): folder drag-icon + `titlebarText`, window-centered via overlay (not centered in leftover space), 13pt **medium**, secondary color (keep `fakeTitlebarTextColor` but at reduced emphasis); band stays a drag surface; trailing `rightSidebarWidth` padding on the band's interactive surface remains (issue #5099).
- Button styling unchanged (`TitlebarControlsStyleConfig` / `HeaderChromeControlMetrics`).
- All new user-facing strings localized en+ja in `Resources/Localizable.xcstrings`; localization audit before finishing.
- New test files must be wired into `cmux.xcodeproj/project.pbxproj` with **fresh unique IDs** (never reuse/adjacent-increment existing IDs — this repo has hit silent ID-collision breakage twice). Run `python3 scripts/normalize-pbxproj.py` and `./scripts/check-pbxproj.sh` after editing.
- Build check: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-topbar build`. Tests run with scheme `cmux-unit` (the `cmux` scheme runs 0 tests). Light test ceremony: run only the new targeted tests.

---

### Task 1: Cluster model + parameterized layout metrics

**Files:**
- Modify: `Sources/Update/UpdateTitlebarAccessory.swift` (slots at :458-480, metrics at :482-560, rightmost-extent at :427-448)
- Create: `cmuxTests/TitlebarControlsClusterTests.swift` (wire into pbxproj, cmuxTests target)

**Interfaces:**
- Consumes: existing `TitlebarShortcutHintActionSlot`, `TitlebarControlsLayoutMetrics`, `TitlebarControlsStyleConfig`.
- Produces (later tasks rely on these exact names):

```swift
enum TitlebarControlsCluster: String {
    case leading
    case trailing

    var slots: [TitlebarShortcutHintActionSlot] {
        switch self {
        case .leading: return [.toggleSidebar, .focusHistoryBack, .focusHistoryForward]
        case .trailing: return [.newTab, .showNotifications, .toggleRightSidebar]
        }
    }
}
```

- [ ] **Step 1: Add the `toggleRightSidebar` slot case**

In `TitlebarShortcutHintActionSlot` (`:458`), add case `toggleRightSidebar` (last) mapping to `KeyboardShortcutSettings.Action.toggleRightSidebar` in the `action` switch. The enum stays `Int, CaseIterable`; nothing may keep using `rawValue` as a layout index after this task (see Step 3).

- [ ] **Step 2: Add `TitlebarControlsCluster`**

Add the enum exactly as in Interfaces, near the slot enum.

- [ ] **Step 3: Parameterize the metrics by cluster**

In `TitlebarControlsLayoutMetrics` and the free function `titlebarHintLayoutRightmostExtent`:

```swift
static func buttonRowWidth(cluster: TitlebarControlsCluster, config: TitlebarControlsStyleConfig) -> CGFloat
// buttonCount = CGFloat(cluster.slots.count)

static func buttonCenterX(for slot: TitlebarShortcutHintActionSlot,
                          cluster: TitlebarControlsCluster,
                          config: TitlebarControlsStyleConfig) -> CGFloat
// index = CGFloat(cluster.slots.firstIndex(of: slot) ?? 0)  — NOT slot.rawValue

static func hintInterval(for slot: TitlebarShortcutHintActionSlot,
                         cluster: TitlebarControlsCluster,
                         width: CGFloat,
                         config: TitlebarControlsStyleConfig,
                         xOffset: CGFloat) -> ClosedRange<CGFloat>

static func contentSize(cluster: TitlebarControlsCluster,
                        config: TitlebarControlsStyleConfig,
                        titlebarShortcutHintXOffset: Double = ShortcutHintDebugSettings.defaultTitlebarHintX) -> NSSize

func titlebarHintLayoutRightmostExtent(cluster: TitlebarControlsCluster,
                                       config: TitlebarControlsStyleConfig,
                                       titlebarShortcutHintXOffset: Double = ...) -> CGFloat
// iterate cluster.slots instead of TitlebarShortcutHintActionSlot.allCases
```

Update every call site in this file to compile (the view/VC still describe the old five-button row until Tasks 2-3 — pass `.leading` there for now; Task 2 fixes the semantics). Other files' call sites: `Sources/ContentView.swift:2114` (`fullscreenControlsWidth`) — pass `.leading` for now; Task 4 revisits.

- [ ] **Step 4: Write the tests**

`cmuxTests/TitlebarControlsClusterTests.swift`, Swift Testing, using the repo's import pattern:

```swift
import Testing
#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct TitlebarControlsClusterTests {
    @Test func clusterSlotMembership() {
        #expect(TitlebarControlsCluster.leading.slots == [.toggleSidebar, .focusHistoryBack, .focusHistoryForward])
        #expect(TitlebarControlsCluster.trailing.slots == [.newTab, .showNotifications, .toggleRightSidebar])
        let all = TitlebarControlsCluster.leading.slots + TitlebarControlsCluster.trailing.slots
        #expect(Set(all).count == TitlebarShortcutHintActionSlot.allCases.count)
    }

    @Test func toggleRightSidebarSlotMapsToAction() {
        #expect(TitlebarShortcutHintActionSlot.toggleRightSidebar.action == .toggleRightSidebar)
    }

    @Test func buttonCenterXUsesClusterIndexNotRawValue() {
        let config = TitlebarControlsStyle.classic.config
        // .newTab is rawValue 2 but index 0 in the trailing cluster.
        let x = TitlebarControlsLayoutMetrics.buttonCenterX(for: .newTab, cluster: .trailing, config: config)
        #expect(x == config.groupPadding.leading + config.buttonSize / 2.0)
    }

    @Test func buttonRowWidthCountsClusterButtons() {
        let config = TitlebarControlsStyle.classic.config
        let expected = 3 * config.buttonSize + 2 * config.spacing
        #expect(TitlebarControlsLayoutMetrics.buttonRowWidth(cluster: .leading, config: config) == expected)
        #expect(TitlebarControlsLayoutMetrics.buttonRowWidth(cluster: .trailing, config: config) == expected)
    }
}
```

(If `TitlebarControlsStyle.classic.config` isn't accessible from tests, construct whatever `TitlebarControlsStyleConfig` initializer exists — read the type first.)

- [ ] **Step 5: Wire the test file into pbxproj** (4 entries, fresh unique IDs; use `cmuxTests/TabManagerUnitTests.swift` entries as a template), then `python3 scripts/normalize-pbxproj.py` and `./scripts/check-pbxproj.sh`.

- [ ] **Step 6: Build + run the new suite**

```bash
CMUX_SKIP_ZIG_BUILD=1 xcodebuild -project cmux.xcodeproj -scheme cmux-unit -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-topbar test -only-testing:cmuxTests/TitlebarControlsClusterTests
```

Expected: PASS, executed 4 tests (0 executed means broken wiring — fix before proceeding).

- [ ] **Step 7: Commit** — `git commit -m "Top bar: cluster model and cluster-parameterized titlebar layout metrics"`

### Task 2: Cluster-aware TitlebarControlsView + right-sidebar toggle button

**Files:**
- Modify: `Sources/Update/UpdateTitlebarAccessory.swift` (`TitlebarControlsView` :811-1160)
- Modify: `Resources/Localizable.xcstrings` (new keys, en+ja)

**Interfaces:**
- Consumes: `TitlebarControlsCluster` from Task 1.
- Produces: `TitlebarControlsView` gains `let cluster: TitlebarControlsCluster` and `let onToggleRightSidebar: () -> Void` (alongside the five existing closures — all instances pass all closures; only the cluster's own buttons render).

- [ ] **Step 1: Add the properties** `cluster` and `onToggleRightSidebar` to `TitlebarControlsView`.

- [ ] **Step 2: Render buttons per cluster**

Restructure `controlsGroup` (`:946`): extract each existing button into a private `@ViewBuilder` helper (`toggleSidebarButton(...)`, `notificationsButton(...)`, `newTabButton(...)`, `backButton(...)`, `forwardButton(...)` — bodies are the existing code verbatim), add:

```swift
private func toggleRightSidebarButton(config: TitlebarControlsStyleConfig, foregroundColor: Color) -> some View {
    TitlebarControlButton(
        config: config,
        foregroundColor: foregroundColor,
        accessibilityIdentifier: "titlebarControl.toggleRightSidebar",
        accessibilityLabel: String(localized: "titlebar.rightSidebar.accessibilityLabel", defaultValue: "Toggle Right Sidebar"),
        action: {
            #if DEBUG
            cmuxDebugLog("titlebar.toggleRightSidebar")
            #endif
            onToggleRightSidebar()
        }) {
        iconLabel(systemName: "sidebar.right", config: config, iconGeometryKeyPrefix: "titlebarControl_toggleRightSidebarIcon")
    }
    .safeHelp(KeyboardShortcutSettings.Action.toggleRightSidebar.tooltip(String(localized: "titlebar.rightSidebar.tooltip", defaultValue: "Show or hide the right sidebar")))
}
```

Then the row becomes:

```swift
let content = HStack(spacing: config.spacing) {
    ForEach(cluster.slots, id: \.self) { slot in
        button(for: slot, config: config, foregroundColor: foregroundColor)
    }
}
```

with a `@ViewBuilder func button(for slot:...)` switch mapping each slot to its helper. Slot order in `cluster.slots` is the on-screen left-to-right order (so `.toggleRightSidebar` is outermost on the right cluster).

- [ ] **Step 3: Cluster-scope the hint layout**

`titlebarHintIntervals` (`:1110`) iterates `cluster.slots` instead of `TitlebarShortcutHintActionSlot.allCases`; pass `cluster:` through to `hintInterval` and use the Task-1 `contentSize(cluster:...)` in `body` (`:876`). The ⌥⌘B hint for the right toggle comes free via `ShortcutHintTitlebarPolicy` (note: hint pills are gated to ⌘-only shortcuts in some paths — do not fight that; whatever the policy yields for ⌥⌘B is acceptable).

- [ ] **Step 4: Fix instantiation sites to compile** — the accessory VC init (`:1766`) and `ContentView.fullscreenControls` (`Sources/ContentView.swift:2074`): pass `cluster: .leading` and `onToggleRightSidebar: {}` for now (Tasks 3-4 finish them).

- [ ] **Step 5: Localize** the two new keys (`titlebar.rightSidebar.accessibilityLabel`, `titlebar.rightSidebar.tooltip`) in `Resources/Localizable.xcstrings` with en + ja values (ja: "右サイドバーを表示/非表示" for both, label "右サイドバーの切り替え" for the accessibility label).

- [ ] **Step 6: Build** (scheme `cmux`, tagged derivedDataPath). Expected: succeeds.

- [ ] **Step 7: Commit** — `"Top bar: cluster-aware titlebar controls view with right-sidebar toggle"`

### Task 3: Second accessory at .right

**Files:**
- Modify: `Sources/Update/UpdateTitlebarAccessory.swift` (`TitlebarControlsAccessoryViewController` init :1749-1817, size/layout :1836-1910; `UpdateTitlebarAccessoryController` :2669-2900)

**Interfaces:**
- Consumes: Task 2's `TitlebarControlsView(cluster:onToggleRightSidebar:...)`.
- Produces: `TitlebarControlsAccessoryViewController(cluster:notificationStore:settingsRuntime:)`; controller installs two accessories with identifiers `cmux.titlebarControls` (left, unchanged) and `cmux.titlebarControls.trailing` (right).

- [ ] **Step 1: Give the VC a cluster**

Add `let cluster: TitlebarControlsCluster` to `TitlebarControlsAccessoryViewController.init`, pass it to `TitlebarControlsView`, and add the right-toggle closure:

```swift
let toggleRightSidebar = { [weak containerView] in
    _ = AppDelegate.shared?.toggleRightSidebarInActiveMainWindow(preferredWindow: containerView?.window)
}
```

Every internal use of `TitlebarControlsLayoutMetrics.contentSize(...)` in this class (`:1899` and any others) passes `cluster:`.

- [ ] **Step 2: Install both accessories**

In `UpdateTitlebarAccessoryController`: add `private let trailingControlsIdentifier = NSUserInterfaceItemIdentifier("cmux.titlebarControls.trailing")`. In `attachIfNeeded` (`:2829-2838`), after the existing left install, install the trailing one the same way with `cluster: .trailing`, `layoutAttribute = .right`, identifier `trailingControlsIdentifier`. Left accessory keeps `cluster: .leading`.

- [ ] **Step 3: Visibility + removal cover both**

`applyAccessoryVisibility` (`:2852`) and `removeAccessoryIfPresent` (`:2868`) match `view.identifier == controlsIdentifier || view.identifier == trailingControlsIdentifier`. Any other loop keyed on `controlsIdentifier` in this class gets the same treatment (grep the class).

- [ ] **Step 4: Build**, then launch once via `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag topbar --launch` and visually confirm: right cluster hugs the right window edge, notifications popover opens anchored to its bell, minimal mode hides both, fullscreen hides both.

- [ ] **Step 5: Commit** — `"Top bar: trailing titlebar accessory with new-workspace, notifications, right-sidebar toggle"`

### Task 4: Centered quiet title + fullscreen trailing cluster

**Files:**
- Modify: `Sources/ContentView.swift` (`customTitlebar` :2138-2202, `fullscreenControls` :2073-2115, band overlay :2230-2248, `fullscreenControlsPlacement` :1748)

**Interfaces:**
- Consumes: Task 2's view signature; Task 1's `contentSize(cluster:...)`.
- Produces: nothing downstream.

- [ ] **Step 1: Center the title**

In `customTitlebar`, replace the leading `HStack { folder icon; Text; Spacer() }` layout: keep the ZStack/drag-handle/inset-reader, but render the folder icon + title as a **band-centered overlay**:

```swift
HStack(spacing: 8) {
    if let directory = focusedDirectory {
        DetachedFolderDragIcon(directory: directory)
            .frame(width: 16, height: 16)
    }
    Text(titlebarText)
        .cmuxFont(size: 13, weight: .medium)
        .foregroundColor(fakeTitlebarTextColor(appearance: appearance).opacity(0.72))
        .lineLimit(1)
        .allowsHitTesting(false)
}
.frame(maxWidth: .infinity, alignment: .center)   // centered in the full band width
```

The centering must be against the full band (the band already spans the window), so the title does not shift when either sidebar opens. The fullscreen width-reservation `Color.clear` block (`:2159-2167`) is no longer needed for title flow — delete it (the fullscreen controls live in the band overlay). Keep `frame(height:)`, top padding, `contentShape`, double-click monitor, and the bottom `WindowChromeBorder` exactly as-is. Drop `leadingPadding` from the title row only if it no longer lays anything out — `TitlebarLeadingInsetReader` stays.

- [ ] **Step 2: Two fullscreen clusters**

Make `fullscreenControls` a function `fullscreenControls(cluster: TitlebarControlsCluster) -> some View` passing `cluster:` and, for `.trailing`, `onToggleRightSidebar: { _ = AppDelegate.shared?.toggleRightSidebarInActiveMainWindow(preferredWindow: nil) }` (leading passes `{}`; both pass all other closures unchanged; both share `fullscreenControlsViewModel` only if the anchor logic allows — otherwise give the trailing cluster its own `TitlebarControlsViewModel` since the notifications bell now lives there; move the notifications anchor to the trailing instance). In the band overlay (`:2230`), keep the existing leading placement rendering `fullscreenControls(cluster: .leading)`, and add:

```swift
.overlay(alignment: .topTrailing) {
    if isFullScreen {
        fullscreenControls(cluster: .trailing)
            .frame(height: max(1, WindowChromeMetrics.appTitlebarHeight - 2), alignment: .center)
            .padding(.top, 2)
            .padding(.trailing, 10)
    }
}
```

`fullscreenControlsWidth` (`:2112`) now uses `contentSize(cluster: .leading, ...)` — or delete it if Step 1 removed its only consumer.

- [ ] **Step 3: Build + hands-on check** (reload tag `topbar`, launch): title centered and stable while toggling both sidebars; drag + double-click-zoom on the band still work; enter fullscreen → both clusters visible, notifications popover anchors correctly; exit fullscreen → AppKit accessories return.

- [ ] **Step 4: Commit** — `"Top bar: centered quiet title and fullscreen trailing cluster"`

### Task 5: Localization audit + final build

**Files:**
- Verify: `Resources/Localizable.xcstrings`; all files touched by Tasks 1-4.

- [ ] **Step 1: Audit** — `rg` Tasks 1-4's diffs for new bare English UI strings; parse `Localizable.xcstrings` and confirm `titlebar.rightSidebar.accessibilityLabel` and `titlebar.rightSidebar.tooltip` each have `en` and `ja` values. Fix anything missing.
- [ ] **Step 2: Full build** (scheme `cmux`) + run the Task 1 suite once. Expected: build succeeds, 4 tests pass.
- [ ] **Step 3: Commit** any fixes — `"Top bar: localization audit fixes"` (skip commit if clean).
