# Sidebar Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse each left-sidebar session row to a single line (status dot + title + dimmed path) and add a VSCode-style file explorer in the lower half of the sidebar that follows the active session's directory.

**Architecture:** Two independent parts on one branch (`sidebar-redesign`). **Part A** (thin rows) gates `TabItemView`'s body on a new `compactRowMode` flag carried in the already-`Equatable`-compared settings snapshot; the dot color and compact path are precomputed into the value snapshot so the typing-latency/`Equatable` optimization is preserved. **Part B** (file explorer) reuses the existing per-instance `FileExplorerPanelView`/`FileExplorerStore`/`FileExplorerState` stack and the existing `SelectedWorkspaceDirectoryObserver`, mounting a second explorer instance in a vertical split below the session list. Part A is independently shippable before Part B is started.

**Tech Stack:** Swift 6, SwiftUI + AppKit (`NSViewRepresentable`/`NSOutlineView`), Swift Testing (`import Testing`), `UserDefaults`-backed settings, `Resources/Localizable.xcstrings` (en + ja).

---

## Conventions used throughout this plan

- **Build the app (manual verify):** `./scripts/reload.sh --tag sidebar-redesign` (never bare `xcodebuild`/`open`). The `App path:` line gives the cmd-clickable build.
- **Compile the test target:** `xcodebuild -scheme cmux-unit -derivedDataPath /tmp/cmux-sidebar-redesign build-for-testing` (CLAUDE.md: never *run* tests locally — execution happens on CI; this only confirms the test target compiles).
- **New `Sources/**` files and new `cmuxTests/**` files must be wired into `cmux.xcodeproj/project.pbxproj`** — this is not a synchronized-folder project. After creating any new `.swift` file, add its pbxproj entries (template in Task A0), then run `python3 scripts/normalize-pbxproj.py cmux.xcodeproj/project.pbxproj` and `./scripts/check-pbxproj.sh`. For test files also run `./scripts/lint-pbxproj-test-wiring.sh`.
- **Test quality (CLAUDE.md):** unit tests only cover pure logic seams and assert returned values — never source text, plist, or pbxproj contents. View wiring is verified by build + manual reload, not by fake tests.
- **Localization (CLAUDE.md):** every new user-facing string uses `String(localized:defaultValue:)` AND has en + ja entries in `Resources/Localizable.xcstrings`. `defaultValue` does not count as localization.
- **Commits:** one commit per task. Commit message footer:
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  ```

---

## Task A0: Reference — pbxproj wiring template

This task adds no code; it's the template every "create a new file" step below refers to. To wire a new file `Sources/Sidebar/Foo.swift` into the **cmux app target** (so it compiles into the app, which `cmux-unit` imports), and `cmuxTests/FooTests.swift` into the **cmuxTests target**, add four entries each, mirroring an existing wired sibling.

- [ ] **Reference: app-target file wiring.** Use an existing wired `Sources/Sidebar/*.swift` (e.g. `SidebarPathFormatter.swift`) as the model. Find its entries:

```bash
rg -n "SidebarPathFormatter.swift" cmux.xcodeproj/project.pbxproj
```

You will see exactly two lines: a `PBXBuildFile` and a `PBXFileReference`, plus membership in a `PBXGroup` (the `Sidebar` group children) and a `PBXSourcesBuildPhase` (the `cmux` target Sources). Add the same four entries for the new file with a fresh unique 24-hex object id. Then normalize + check:

```bash
python3 scripts/normalize-pbxproj.py cmux.xcodeproj/project.pbxproj
./scripts/check-pbxproj.sh
```

- [ ] **Reference: test-target file wiring.** Mirror an existing wired test (`NotificationSoundSettingsTests.swift`):

```bash
rg -n "NotificationSoundSettingsTests.swift" cmux.xcodeproj/project.pbxproj
```

Add a `PBXBuildFile`, `PBXFileReference`, `cmuxTests` `PBXGroup` membership, and `cmuxTests` `PBXSourcesBuildPhase` entry for the new test file, then:

```bash
python3 scripts/normalize-pbxproj.py cmux.xcodeproj/project.pbxproj
./scripts/lint-pbxproj-test-wiring.sh
./scripts/check-pbxproj.sh
```

> Prefer adding files via Xcode (drag into the correct group/target) when available — it writes these entries for you. The manual path above is the fallback.

---

# PART A — Thin one-line session rows

Independently shippable. After Task A7, rows render as a single line by default with a Settings toggle to restore the detailed row.

## Task A1: `SidebarCompactRowModeSettings` (settings seam) + test

**Files:**
- Create: `Sources/Sidebar/SidebarCompactRowModeSettings.swift`
- Create test: `cmuxTests/SidebarCompactRowModeSettingsTests.swift`
- Modify: `cmux.xcodeproj/project.pbxproj` (wire both files — see Task A0)

This mirrors the existing `SidebarWorkspaceDetailSettings` enum (TabManager.swift:206) and the `SidebarPathFormatter` namespace-enum pattern in `Sources/Sidebar/`.

- [ ] **Step 1: Write the failing test**

`cmuxTests/SidebarCompactRowModeSettingsTests.swift`:

```swift
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct SidebarCompactRowModeSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "SidebarCompactRowModeSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func defaultsToCompactWhenUnset() {
        let defaults = makeDefaults()
        #expect(SidebarCompactRowModeSettings.isEnabled(defaults: defaults) == true)
    }

    @Test func respectsExplicitDisable() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: SidebarCompactRowModeSettings.key)
        #expect(SidebarCompactRowModeSettings.isEnabled(defaults: defaults) == false)
    }

    @Test func respectsExplicitEnable() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: SidebarCompactRowModeSettings.key)
        #expect(SidebarCompactRowModeSettings.isEnabled(defaults: defaults) == true)
    }
}
```

- [ ] **Step 2: Verify it fails to compile/CI-fails.** Run `xcodebuild -scheme cmux-unit -derivedDataPath /tmp/cmux-sidebar-redesign build-for-testing`. Expected: FAIL — `cannot find 'SidebarCompactRowModeSettings'`.

- [ ] **Step 3: Write minimal implementation**

`Sources/Sidebar/SidebarCompactRowModeSettings.swift`:

```swift
import Foundation

/// Reads the "compact sidebar rows" preference (one-line workspace rows).
///
/// Mirrors ``SidebarWorkspaceDetailSettings`` — a stateless reader over an
/// injected `UserDefaults` so it is testable without touching
/// `UserDefaults.standard`. Defaults to `true`: compact rows are the default
/// presentation; users opt back into the detailed multi-line row.
enum SidebarCompactRowModeSettings {
    /// The `UserDefaults` key backing the compact-row preference.
    static let key = "sidebarCompactRowMode"
    /// The value used when the key has never been written.
    static let defaultValue = true

    /// Whether compact one-line rows are enabled.
    /// - Parameter defaults: the store to read (injected for tests).
    /// - Returns: `true` when compact rows should render.
    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }
}
```

- [ ] **Step 4: Wire both new files into pbxproj** (Task A0 template), then `python3 scripts/normalize-pbxproj.py cmux.xcodeproj/project.pbxproj && ./scripts/lint-pbxproj-test-wiring.sh && ./scripts/check-pbxproj.sh`.

- [ ] **Step 5: Verify compile.** Run `xcodebuild -scheme cmux-unit -derivedDataPath /tmp/cmux-sidebar-redesign build-for-testing`. Expected: build succeeds (tests run green on CI).

- [ ] **Step 6: Commit**

```bash
git add Sources/Sidebar/SidebarCompactRowModeSettings.swift cmuxTests/SidebarCompactRowModeSettingsTests.swift cmux.xcodeproj/project.pbxproj
git commit -m "Add SidebarCompactRowModeSettings (default-on compact rows preference)"
```

## Task A2: Thread `compactRowMode` into `SidebarTabItemSettingsSnapshot`

**Files:**
- Modify: `Sources/ContentView.swift` (struct at 9955; init reads at ~10001)

`SidebarTabItemSettingsSnapshot` derives `Equatable` automatically, so adding a stored property automatically extends `TabItemView.==` (which already compares `settings`). No `==` edits needed.

- [ ] **Step 1: Add the stored property.** In `struct SidebarTabItemSettingsSnapshot` (ContentView.swift:9956), immediately after `let wrapsWorkspaceTitles: Bool`, add:

```swift
    let compactRowMode: Bool
```

- [ ] **Step 2: Initialize it.** In the same struct's `init`, immediately after the line `hidesAllDetails = SidebarWorkspaceDetailSettings.hidesAllDetails(defaults: defaults)`, add:

```swift
        compactRowMode = SidebarCompactRowModeSettings.isEnabled(defaults: defaults)
```

- [ ] **Step 3: Verify compile.** `./scripts/reload.sh --tag sidebar-redesign`. Expected: builds (no behavior change yet — `compactRowMode` is unused).

- [ ] **Step 4: Commit**

```bash
git add Sources/ContentView.swift
git commit -m "Carry compactRowMode in SidebarTabItemSettingsSnapshot"
```

## Task A3: `CompactRowStatusResolver` (status → dot color hex) + test

**Files:**
- Create: `Sources/Sidebar/CompactRowStatusResolver.swift`
- Create test: `cmuxTests/CompactRowStatusResolverTests.swift`
- Modify: `cmux.xcodeproj/project.pbxproj` (wire both)

The dot reflects the highest-priority status pill's color (the same color the current status row uses). `sidebarStatusEntriesInDisplayOrder()` already returns entries sorted highest-priority-first, so the resolver picks the first entry that carries a usable color.

- [ ] **Step 1: Write the failing test**

`cmuxTests/CompactRowStatusResolverTests.swift`:

```swift
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct CompactRowStatusResolverTests {
    private func entry(key: String, color: String?, priority: Int) -> SidebarStatusEntry {
        SidebarStatusEntry(key: key, value: key, color: color, priority: priority)
    }

    @Test func returnsNilForNoEntries() {
        #expect(CompactRowStatusResolver.dotColorHex(for: []) == nil)
    }

    @Test func picksFirstEntryWithUsableColor() {
        let entries = [
            entry(key: "running", color: "34C759", priority: 10),
            entry(key: "ports", color: "FF0000", priority: 5),
        ]
        #expect(CompactRowStatusResolver.dotColorHex(for: entries) == "34C759")
    }

    @Test func skipsLeadingEntriesWithoutColor() {
        let entries = [
            entry(key: "idle", color: nil, priority: 10),
            entry(key: "needsInput", color: "FF9500", priority: 8),
        ]
        #expect(CompactRowStatusResolver.dotColorHex(for: entries) == "FF9500")
    }

    @Test func treatsEmptyColorStringAsNoColor() {
        let entries = [entry(key: "idle", color: "", priority: 10)]
        #expect(CompactRowStatusResolver.dotColorHex(for: entries) == nil)
    }
}
```

- [ ] **Step 2: Verify it fails.** `xcodebuild -scheme cmux-unit -derivedDataPath /tmp/cmux-sidebar-redesign build-for-testing`. Expected: FAIL — `cannot find 'CompactRowStatusResolver'`.

- [ ] **Step 3: Write minimal implementation**

`Sources/Sidebar/CompactRowStatusResolver.swift`:

```swift
import Foundation

/// Resolves the color of a compact-row status dot from a workspace's status
/// entries.
///
/// The compact row shows a single colored dot reflecting the session's
/// lifecycle (running / idle / needs-input / unknown). Rather than inventing a
/// palette, it reuses the color carried by the highest-priority
/// ``SidebarStatusEntry`` — the same color the detailed status row renders — so
/// the dot stays visually consistent with the rest of the UI.
enum CompactRowStatusResolver {
    /// The hex color string for the dot, or `nil` when no status entry carries a
    /// usable color (caller should fall back to a neutral/secondary color).
    ///
    /// - Parameter entries: status entries already sorted highest-priority-first
    ///   (as produced by `Workspace.sidebarStatusEntriesInDisplayOrder()`).
    /// - Returns: the first non-empty `color` hex among `entries`, or `nil`.
    static func dotColorHex(for entries: [SidebarStatusEntry]) -> String? {
        for entry in entries {
            if let color = entry.color, !color.trimmingCharacters(in: .whitespaces).isEmpty {
                return color
            }
        }
        return nil
    }
}
```

- [ ] **Step 4: Wire both files into pbxproj** (Task A0), then normalize + lint + check.

- [ ] **Step 5: Verify compile.** `xcodebuild -scheme cmux-unit -derivedDataPath /tmp/cmux-sidebar-redesign build-for-testing`. Expected: success.

- [ ] **Step 6: Commit**

```bash
git add Sources/Sidebar/CompactRowStatusResolver.swift cmuxTests/CompactRowStatusResolverTests.swift cmux.xcodeproj/project.pbxproj
git commit -m "Add CompactRowStatusResolver for one-line status dot color"
```

## Task A4: Add compact fields to the workspace snapshot

**Files:**
- Modify: `Sources/ContentView.swift` (Snapshot struct at 15053; `makeWorkspaceSnapshot()` at 16462)

Snapshot fields are **not** in `TabItemView.==`, so adding them does not affect the typing-latency optimization. Both are computed unconditionally so compact mode has data even when the user hid status pills / branch-directory.

- [ ] **Step 1: Add fields to the Snapshot struct.** In `struct Snapshot: Equatable` (ContentView.swift:15053), immediately after `let listeningPorts: [Int]`, add:

```swift
        let statusDotColorHex: String?
        let compactRowPathText: String
```

- [ ] **Step 2: Compute and set them in `makeWorkspaceSnapshot()`.** In `makeWorkspaceSnapshot()` (ContentView.swift:16462), immediately before the `return SidebarWorkspaceSnapshotBuilder.Snapshot(` line (16502), add:

```swift
        let statusDotColorHex = CompactRowStatusResolver.dotColorHex(
            for: tab.sidebarStatusEntriesInDisplayOrder()
        )
        let compactRowPathText: String = {
            guard let primary = tab.sidebarDirectoriesInDisplayOrder().first else { return "" }
            return SidebarPathFormatter.shortenedPath(primary)
        }()
```

Then, inside the `SidebarWorkspaceSnapshotBuilder.Snapshot(...)` initializer, immediately after `listeningPorts: detailVisibility.showsPorts ? tab.listeningPorts : []`, add a trailing comma to that line and append:

```swift
            statusDotColorHex: statusDotColorHex,
            compactRowPathText: compactRowPathText
```

- [ ] **Step 3: Verify compile.** `./scripts/reload.sh --tag sidebar-redesign`. Expected: builds; rows still render the existing (non-compact) body — the new fields are unused so far.

- [ ] **Step 4: Commit**

```bash
git add Sources/ContentView.swift
git commit -m "Precompute status dot color and compact path into workspace snapshot"
```

## Task A5: Render the compact one-line body in `TabItemView`

**Files:**
- Modify: `Sources/ContentView.swift` (`var body` at 15449; helpers at 15249–15305)

- [ ] **Step 1: Add the compact body + dot color helper.** In `TabItemView`, immediately before `var body: some View` (ContentView.swift:15449), add:

```swift
    private var compactStatusDotColor: Color {
        if let hex = workspaceSnapshot.statusDotColorHex, let nsColor = NSColor(hex: hex) {
            return Color(nsColor: nsColor)
        }
        return activeSecondaryColor(0.4)
    }

    @ViewBuilder
    private var compactRowContent: some View {
        let workspaceSnapshot = self.workspaceSnapshot
        let closeWorkspaceTooltip = String(localized: "sidebar.closeWorkspace.tooltip", defaultValue: "Close Workspace")
        let protectedWorkspaceTooltip = String(
            localized: "sidebar.pinnedWorkspaceProtected.tooltip",
            defaultValue: "Pinned workspace. Closing requires confirmation."
        )
        let closeButtonTooltip = workspaceSnapshot.isPinned
            ? protectedWorkspaceTooltip
            : KeyboardShortcutSettings.Action.closeWorkspace.tooltip(closeWorkspaceTooltip)
        let scaledCloseButtonHitSize = max(16, 16 * fontScale)
        let scaledCloseButtonWidth = max(
            SidebarTrailingAccessoryWidthPolicy.closeButtonWidth,
            scaledCloseButtonHitSize
        )

        HStack(alignment: .center, spacing: 6) {
            Circle()
                .fill(compactStatusDotColor)
                .frame(width: scaledFontSize(8), height: scaledFontSize(8))

            if workspaceSnapshot.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: scaledFontSize(8), weight: .semibold))
                    .foregroundColor(activeSecondaryColor(0.8))
            }

            Text(workspaceSnapshot.title)
                .font(.system(size: scaledFontSize(12.5), weight: titleFontWeight))
                .foregroundColor(activePrimaryTextColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Spacer(minLength: 6)

            if !workspaceSnapshot.compactRowPathText.isEmpty {
                Text(workspaceSnapshot.compactRowPathText)
                    .font(.system(size: scaledFontSize(9), design: .monospaced))
                    .foregroundColor(activeSecondaryColor(0.5))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .layoutPriority(0)
            }

            if unreadCount > 0 {
                ZStack {
                    Circle().fill(activeUnreadBadgeFillColor)
                    Text("\(unreadCount)")
                        .font(.system(size: scaledFontSize(9), weight: .semibold))
                        .foregroundColor(activeUnreadBadgeTextColor)
                }
                .frame(width: 16 * fontScale, height: 16 * fontScale)
            }

            if canCloseWorkspace {
                Button(action: {
                    #if DEBUG
                    cmuxDebugLog("sidebar.close workspace=\(tab.id.uuidString.prefix(5)) method=button")
                    #endif
                    tabManager.closeWorkspaceWithConfirmation(tab)
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: scaledFontSize(9), weight: .medium))
                        .foregroundColor(activeSecondaryColor(0.7))
                        .frame(width: scaledCloseButtonWidth, height: scaledCloseButtonHitSize, alignment: .center)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .safeHelp(closeButtonTooltip)
                .opacity(showCloseButton ? 1 : 0)
            }
        }
    }
```

- [ ] **Step 2: Gate the body on the flag.** In `var body: some View` (ContentView.swift:15479), replace the opening line of the content container:

```swift
        VStack(alignment: .leading, spacing: 4) {
```

with:

```swift
        Group {
        if settings.compactRowMode {
            compactRowContent
        } else {
        VStack(alignment: .leading, spacing: 4) {
```

Then find the matching close of that `VStack` (the `}` on ContentView.swift:15769, immediately before `.animation(.easeInOut(duration: 0.2), value: workspaceSnapshot.latestLog)`) and replace that single `}` with:

```swift
        }
        }
        }
```

(The first `}` closes the original `VStack`; the second closes the `else`; the third closes the outer `Group`. All the row's modifiers — padding/background/`rowHeightProbe`/`safeHelp`/contextMenu — continue to apply to the `Group` for both modes.)

- [ ] **Step 3: Enrich the hover tooltip with the moved-off-row detail.** At the row-level `.safeHelp(workspaceSnapshot.title)` (ContentView.swift:15888), replace it with a tooltip that includes the relocated detail when compact:

```swift
        .safeHelp(settings.compactRowMode ? compactRowTooltipText : workspaceSnapshot.title)
```

and add this helper next to `compactRowContent`:

```swift
    private var compactRowTooltipText: String {
        let snapshot = workspaceSnapshot
        var lines: [String] = [snapshot.title]
        if !snapshot.compactRowPathText.isEmpty { lines.append(snapshot.compactRowPathText) }
        if let branch = snapshot.compactGitBranchSummaryText, !branch.isEmpty { lines.append(branch) }
        for entry in snapshot.metadataEntries { lines.append("\(entry.value)") }
        if !snapshot.listeningPorts.isEmpty {
            lines.append(snapshot.listeningPorts.map { ":\($0)" }.joined(separator: " "))
        }
        for pr in snapshot.pullRequestRows { lines.append(pr.label) }
        return lines.joined(separator: "\n")
    }
```

- [ ] **Step 4: Build and manually verify.** `./scripts/reload.sh --tag sidebar-redesign`. Open the printed `App path:` build. Expected: each session row is a single ~22px line — status dot + title + dimmed right-aligned path; hover shows full detail; pin/unread/close behave as before; typing in a terminal has no added latency (rows don't re-render on keystrokes). Provide the build link:

```
=======================================================
[cmux DEV sidebar-redesign.app](file://<url-encoded App path from reload.sh>)
=======================================================
```

- [ ] **Step 5: Commit**

```bash
git add Sources/ContentView.swift
git commit -m "Render compact one-line workspace rows (status dot + title + path)"
```

## Task A6: Settings toggle + search entry + localized label

**Files:**
- Modify: `Sources/CommandPalette/CommandPaletteSettingsToggle.swift` (descriptor list near 465–488)
- Modify: `Sources/SettingsNavigation.swift` (entries near 364)
- Modify: `Resources/Localizable.xcstrings`

- [ ] **Step 1: Add the toggle descriptor.** In `CommandPaletteSettingsToggle.swift`, immediately after the `hideAllSidebarDetails` descriptor block (ends at the `),` on line 473), add:

```swift
            CommandPaletteSettingToggleDescriptor(
                commandId: commandIdPrefix + "compactSidebarRows",
                settingsKey: "sidebar.compactRowMode",
                title: {
                    String(localized: "settings.app.compactRowMode", defaultValue: "Compact Sidebar Rows")
                },
                sectionTitle: sidebar,
                keywords: ["sidebar.compactRowMode", "sidebar", "compact", "rows", "dense", "narrow", "thin", "one line"],
                defaultValue: SidebarCompactRowModeSettings.defaultValue,
                defaultsKey: SidebarCompactRowModeSettings.key
            ),
```

- [ ] **Step 2: Add the Settings search index entry.** In `SettingsNavigation.swift`, immediately after the `hide-sidebar-details` `setting(...)` line (364), add:

```swift
        setting(.sidebarAppearance, "compact-sidebar-rows", String(localized: "settings.app.compactRowMode", defaultValue: "Compact Sidebar Rows"), "sidebar compact rows dense narrow thin one line"),
```

- [ ] **Step 3: Add the localized string (en + ja).** In `Resources/Localizable.xcstrings`, add a `"settings.app.compactRowMode"` entry alongside the other `settings.app.*` keys, matching the existing format:

```json
    "settings.app.compactRowMode" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : {
          "stringUnit" : { "state" : "translated", "value" : "Compact Sidebar Rows" }
        },
        "ja" : {
          "stringUnit" : { "state" : "translated", "value" : "サイドバーの行をコンパクト表示" }
        }
      }
    },
```

- [ ] **Step 4: Build and verify the toggle.** `./scripts/reload.sh --tag sidebar-redesign`. In the built app, open the command palette / Settings, search "compact", toggle off → rows return to detailed layout; toggle on → rows go compact. Confirm it persists across relaunch.

- [ ] **Step 5: Commit**

```bash
git add Sources/CommandPalette/CommandPaletteSettingsToggle.swift Sources/SettingsNavigation.swift Resources/Localizable.xcstrings
git commit -m "Add Compact Sidebar Rows settings toggle (en+ja)"
```

## Task A7: `cmux.json` config mapping + docs

**Files:**
- Modify: `Sources/KeyboardShortcutSettingsFileStore.swift` (`parseSidebarSection` near 703)
- Modify: configuration docs (located in Step 2)

- [ ] **Step 1: Map the JSON key.** In `parseSidebarSection(...)` (KeyboardShortcutSettingsFileStore.swift), immediately after the `showCustomMetadata` mapping block (the last `if let value = jsonBool(section["showCustomMetadata"]) { ... }`), add:

```swift
        if let value = jsonBool(section["compactRowMode"]) {
            snapshot.managedUserDefaults[SidebarCompactRowModeSettings.key] = .bool(value)
        }
```

- [ ] **Step 2: Update the docs.** Locate the docs page that lists the sidebar config keys:

```bash
rg -l "hideAllDetails|wrapWorkspaceTitles" docs web | head
```

In that file, add a `compactRowMode` row mirroring the `hideAllDetails` row (boolean, default `true`, "Render each workspace row as a single compact line"). If the doc is localized (e.g. has `web/messages/en.json` + `web/messages/ja.json` counterparts), add the key to **both** locale catalogs.

- [ ] **Step 3: Verify compile.** `./scripts/reload.sh --tag sidebar-redesign`. Expected: builds.

- [ ] **Step 4: Localization audit (Part A).** Confirm the only new user-facing string is `settings.app.compactRowMode`, and that it has en + ja in `Localizable.xcstrings`:

```bash
rg -n "settings.app.compactRowMode" Resources/Localizable.xcstrings
rg -n "compactRowMode|Compact Sidebar Rows" Sources/
```

Expected: the xcstrings entry has both `en` and `ja`; no bare English string literals in the changed Swift.

- [ ] **Step 5: Commit**

```bash
git add Sources/KeyboardShortcutSettingsFileStore.swift docs web 2>/dev/null; git commit -m "Honor sidebar.compactRowMode in cmux.json + document it"
```

> **Part A is complete and shippable here.** Compact rows are the default, reversible via Settings or `cmux.json`.

---

# PART B — Bottom file explorer

Mounts a second file explorer in a vertical split below the session list, following the active session's directory, with a slim collapsible header and a draggable divider. Reuses the existing `FileExplorer*` stack and `SelectedWorkspaceDirectoryObserver`.

## Task B1: Namespaced persistence for `FileExplorerState` + test

**Files:**
- Modify: `Sources/FileExplorerState.swift` (init + didSets at 6–47)
- Create test: `cmuxTests/FileExplorerStatePersistenceTests.swift`
- Modify: `cmux.xcodeproj/project.pbxproj` (wire the test)

The left panel needs its **own** `FileExplorerState` whose persisted keys don't collide with the right sidebar's hardcoded `fileExplorer.*` keys. Add an injected key prefix (default preserves current behavior).

- [ ] **Step 1: Write the failing test**

`cmuxTests/FileExplorerStatePersistenceTests.swift`:

```swift
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite struct FileExplorerStatePersistenceTests {
    @Test func defaultPrefixIsBackwardCompatible() {
        let state = FileExplorerState()
        #expect(state.persistenceKeyPrefix == "fileExplorer")
    }

    @Test func customPrefixIsUsedForWidthKey() {
        let state = FileExplorerState(persistenceKeyPrefix: "sidebar.fileExplorer")
        state.width = 173
        #expect(UserDefaults.standard.double(forKey: "sidebar.fileExplorer.width") == 173)
        UserDefaults.standard.removeObject(forKey: "sidebar.fileExplorer.width")
    }
}
```

- [ ] **Step 2: Verify it fails.** `xcodebuild -scheme cmux-unit -derivedDataPath /tmp/cmux-sidebar-redesign build-for-testing`. Expected: FAIL — no `persistenceKeyPrefix`, and `init(persistenceKeyPrefix:)` doesn't exist.

- [ ] **Step 3: Implement the prefix.** In `FileExplorerState.swift`, replace the hardcoded key strings and `init()` with a prefixed form. Add a stored prefix and derive keys from it:

```swift
final class FileExplorerState: ObservableObject {
    /// Prefix for this instance's UserDefaults keys. The right sidebar uses the
    /// default ("fileExplorer"); the left-sidebar explorer passes a distinct
    /// prefix so the two instances never clobber each other's persisted state.
    let persistenceKeyPrefix: String
    private let modeKey: String

    private func key(_ suffix: String) -> String { "\(persistenceKeyPrefix).\(suffix)" }

    @Published var isVisible: Bool {
        didSet { UserDefaults.standard.set(isVisible, forKey: key("isVisible")) }
    }
    @Published var width: CGFloat {
        didSet { UserDefaults.standard.set(Double(width), forKey: key("width")) }
    }

    /// Proportion of sidebar height allocated to the tab list (0.0-1.0).
    /// The file explorer gets the remaining space below.
    @Published var dividerPosition: CGFloat {
        didSet { UserDefaults.standard.set(Double(dividerPosition), forKey: key("dividerPosition")) }
    }

    /// Whether hidden files (dotfiles) are shown in the tree.
    @Published var showHiddenFiles: Bool {
        didSet { UserDefaults.standard.set(showHiddenFiles, forKey: key("showHidden")) }
    }

    @Published private var storedMode: RightSidebarMode

    /// Active mode for the right sidebar (file tree, search, sessions, or enabled beta modes).
    var mode: RightSidebarMode {
        get { storedMode }
        set { setMode(newValue) }
    }

    init(persistenceKeyPrefix: String = "fileExplorer") {
        self.persistenceKeyPrefix = persistenceKeyPrefix
        self.modeKey = "\(persistenceKeyPrefix).mode"
        let defaults = UserDefaults.standard
        self.isVisible = defaults.bool(forKey: "\(persistenceKeyPrefix).isVisible")
        let storedWidth = defaults.double(forKey: "\(persistenceKeyPrefix).width")
        self.width = storedWidth > 0 ? CGFloat(storedWidth) : 220
        let storedPosition = defaults.double(forKey: "\(persistenceKeyPrefix).dividerPosition")
        self.dividerPosition = storedPosition > 0 ? CGFloat(storedPosition) : 0.6
        let storedShowHidden = defaults.object(forKey: "\(persistenceKeyPrefix).showHidden")
        self.showHiddenFiles = storedShowHidden == nil ? true : defaults.bool(forKey: "\(persistenceKeyPrefix).showHidden")
        let resolvedMode = RightSidebarMode(rawValue: defaults.string(forKey: "\(persistenceKeyPrefix).mode") ?? "") ?? .files
        self.storedMode = Self.availableMode(resolvedMode, defaults: defaults)
        defaults.set(self.storedMode.rawValue, forKey: self.modeKey)
    }
```

Then update any remaining reference to the old `private static let modeKey` (search the file for `Self.modeKey` and replace with `self.modeKey` / `modeKey`).

```bash
rg -n "Self.modeKey|modeKey" Sources/FileExplorerState.swift
```

- [ ] **Step 4: Wire the test file into pbxproj** (Task A0), then normalize + lint + check.

- [ ] **Step 5: Verify compile + app build.** `xcodebuild -scheme cmux-unit -derivedDataPath /tmp/cmux-sidebar-redesign build-for-testing` then `./scripts/reload.sh --tag sidebar-redesign`. Expected: both succeed; right sidebar explorer behaves exactly as before (default prefix unchanged).

- [ ] **Step 6: Commit**

```bash
git add Sources/FileExplorerState.swift cmuxTests/FileExplorerStatePersistenceTests.swift cmux.xcodeproj/project.pbxproj
git commit -m "Allow per-instance UserDefaults key prefix on FileExplorerState"
```

## Task B2: `SidebarExplorerSplit` clamp helper + test

**Files:**
- Create: `Sources/Sidebar/SidebarExplorerSplit.swift`
- Create test: `cmuxTests/SidebarExplorerSplitTests.swift`
- Modify: `cmux.xcodeproj/project.pbxproj` (wire both)

- [ ] **Step 1: Write the failing test**

`cmuxTests/SidebarExplorerSplitTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct SidebarExplorerSplitTests {
    @Test func keepsFractionWithinBoundsForTallSidebar() {
        let f = SidebarExplorerSplit.clampedSessionFraction(0.6, availableHeight: 800)
        #expect(f == 0.6)
    }

    @Test func clampsAboveMaxToLeaveRoomForExplorer() {
        // 800pt tall, min explorer 80pt -> max session fraction 0.9
        let f = SidebarExplorerSplit.clampedSessionFraction(0.99, availableHeight: 800)
        #expect(f <= 0.9 + 0.0001)
        #expect(f >= 0.9 - 0.0001)
    }

    @Test func clampsBelowMinToKeepSessionListVisible() {
        // 800pt tall, min session 96pt -> min session fraction 0.12
        let f = SidebarExplorerSplit.clampedSessionFraction(0.01, availableHeight: 800)
        #expect(f >= 96.0 / 800.0 - 0.0001)
    }

    @Test func fallsBackForNonPositiveHeight() {
        #expect(SidebarExplorerSplit.clampedSessionFraction(0.6, availableHeight: 0) == 0.6)
    }

    @Test func fallsBackForNonFiniteFraction() {
        let f = SidebarExplorerSplit.clampedSessionFraction(.nan, availableHeight: 800)
        #expect(f.isFinite)
    }
}
```

- [ ] **Step 2: Verify it fails.** `xcodebuild -scheme cmux-unit -derivedDataPath /tmp/cmux-sidebar-redesign build-for-testing`. Expected: FAIL — `cannot find 'SidebarExplorerSplit'`.

- [ ] **Step 3: Write minimal implementation**

`Sources/Sidebar/SidebarExplorerSplit.swift`:

```swift
import CoreGraphics

/// Geometry for the left-sidebar vertical split between the session list (top)
/// and the file explorer (bottom).
///
/// The stored split is a *session fraction* in `0.0...1.0` (the share of the
/// available height given to the session list). This clamps it so neither the
/// session list nor the explorer collapses below a usable minimum.
enum SidebarExplorerSplit {
    /// Minimum height for the session list (about two rows).
    static let minSessionListHeight: CGFloat = 96
    /// Minimum height for the file explorer when expanded.
    static let minExplorerHeight: CGFloat = 80
    /// Fallback fraction when geometry is unavailable or invalid.
    static let fallbackFraction: CGFloat = 0.6

    /// Clamps a session fraction to keep both panes usable.
    /// - Parameters:
    ///   - fraction: desired share of height for the session list.
    ///   - availableHeight: total height to split (excludes the footer/divider).
    /// - Returns: a finite fraction in `[minFrac, maxFrac]`, or
    ///   ``fallbackFraction`` when `availableHeight` is non-positive/invalid.
    static func clampedSessionFraction(_ fraction: CGFloat, availableHeight: CGFloat) -> CGFloat {
        guard availableHeight.isFinite, availableHeight > 0 else { return fallbackFraction }
        let safeFraction = fraction.isFinite ? fraction : fallbackFraction
        let minFrac = min(0.9, minSessionListHeight / availableHeight)
        let maxFrac = max(0.1, 1 - (minExplorerHeight / availableHeight))
        guard minFrac <= maxFrac else { return 0.5 }
        return min(max(safeFraction, minFrac), maxFrac)
    }
}
```

- [ ] **Step 4: Wire both files into pbxproj** (Task A0), then normalize + lint + check.

- [ ] **Step 5: Verify compile.** `xcodebuild -scheme cmux-unit -derivedDataPath /tmp/cmux-sidebar-redesign build-for-testing`. Expected: success.

- [ ] **Step 6: Commit**

```bash
git add Sources/Sidebar/SidebarExplorerSplit.swift cmuxTests/SidebarExplorerSplitTests.swift cmux.xcodeproj/project.pbxproj
git commit -m "Add SidebarExplorerSplit clamp for the left-sidebar vertical split"
```

## Task B3: Optional header suppression in `FileExplorerContainerView`/`FileExplorerPanelView`

**Files:**
- Modify: `Sources/FileExplorerView.swift` (panel struct 99–106; container init 748–766; header constraints ~930)

The embedded left panel uses its own slim section header, so the explorer's built-in path-input header is suppressed.

- [ ] **Step 1: Add `showsHeader` to `FileExplorerPanelView`.** In the struct (FileExplorerView.swift:99), after `var placement: FileExplorerPanelPlacement = .rightSidebar`, add:

```swift
    var showsHeader: Bool = true
```

- [ ] **Step 2: Thread it into the container.** In `FileExplorerPanelView.makeNSView` (search `FileExplorerContainerView(`), pass `showsHeader: showsHeader` to the container init. Update `FileExplorerContainerView.init` (FileExplorerView.swift:748) to accept it:

```swift
    init(
        coordinator: FileExplorerPanelView.Coordinator,
        presentation: FileExplorerPanelPresentation,
        showsHeader: Bool = true,
        searchController: (any FileSearchControlling)? = nil
    ) {
```

and store it before `super.init`: add a stored `private let showsHeader: Bool` property to `FileExplorerContainerView`, set `self.showsHeader = showsHeader` in the init.

- [ ] **Step 3: Hide the header when disabled.** After the header is added and laid out (the header constraints near line 930), add:

```swift
        headerView.isHidden = !showsHeader
```

and make the search bar / scroll view top anchor fall back to the container top when the header is hidden. Replace the `searchBarView.topAnchor.constraint(equalTo: headerView.bottomAnchor)` activation with a conditional:

```swift
            searchBarView.topAnchor.constraint(equalTo: showsHeader ? headerView.bottomAnchor : topAnchor),
```

(Leave the header's own top/leading/trailing constraints active — a hidden, zero-effect header is fine; only the *following* view's top anchor must not depend on a hidden header occupying space. If the header still reserves height when hidden, also add a `headerView.heightAnchor.constraint(equalToConstant: 0)` gated on `!showsHeader`.)

- [ ] **Step 4: Verify compile + right sidebar unchanged.** `./scripts/reload.sh --tag sidebar-redesign`. Expected: right sidebar explorer still shows its header (default `showsHeader: true`).

- [ ] **Step 5: Commit**

```bash
git add Sources/FileExplorerView.swift
git commit -m "Support header suppression in embedded FileExplorerPanelView"
```

## Task B4: Second explorer store/state + dual directory sync

**Files:**
- Modify: `Sources/ContentView.swift` (properties at 1086; `syncFileExplorerDirectory()` at 2613)

- [ ] **Step 1: Add the left-sidebar store + state.** In ContentView's property block (after `@StateObject private var sessionIndexStore = SessionIndexStore()` at 1087), add:

```swift
    @StateObject private var leftFileExplorerStore = FileExplorerStore()
    @StateObject private var leftFileExplorerState = FileExplorerState(persistenceKeyPrefix: "sidebar.fileExplorer")
```

- [ ] **Step 2: Drive the left store from the same sync.** In `syncFileExplorerDirectory()` (ContentView.swift:2613), at the very top of the method body, add:

```swift
        leftFileExplorerStore.showHiddenFiles = true
        defer { syncLeftFileExplorerDirectory() }
```

Then add a sibling method directly after `syncFileExplorerDirectory()`:

```swift
    /// Mirrors the active workspace directory onto the left-sidebar explorer
    /// store, reusing the same selection/cwd signal as the right sidebar.
    private func syncLeftFileExplorerDirectory() {
        guard let selectedId = tabManager.selectedTabId,
              let tab = tabManager.tabs.first(where: { $0.id == selectedId }) else {
            leftFileExplorerStore.applyWorkspaceRoot(.none)
            return
        }
        if tab.isRemoteWorkspace {
            guard let config = tab.remoteConfiguration, config.transport == .ssh else {
                leftFileExplorerStore.applyWorkspaceRoot(.none)
                return
            }
            let unavailableDetail = tab.remoteConnectionDetail ?? tab.remoteDaemonStatus.detail
            leftFileExplorerStore.applyWorkspaceRoot(
                .remoteSSH(
                    workspaceId: tab.id,
                    connection: SSHFileExplorerConnection(
                        destination: config.destination,
                        port: config.port,
                        identityFile: config.identityFile,
                        sshOptions: config.sshOptions
                    ),
                    displayTarget: config.displayTarget,
                    rootPath: tab.currentDirectory,
                    isAvailable: tab.remoteConnectionState == .connected,
                    unavailableDetail: unavailableDetail
                )
            )
            return
        }
        let dir = tab.currentDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dir.isEmpty else {
            leftFileExplorerStore.applyWorkspaceRoot(.none)
            return
        }
        leftFileExplorerStore.applyWorkspaceRoot(.local(path: dir))
    }
```

> The existing `onChange(of: selectedWorkspaceDirectoryObserver.directoryChangeGeneration)` (ContentView.swift:2879) already calls `syncFileExplorerDirectory()`, so the `defer` keeps both stores in lockstep without a second observer.

- [ ] **Step 3: Pass `leftFileExplorerState` into `VerticalTabsSidebar`.** Find where `VerticalTabsSidebar(...)` is constructed (search `VerticalTabsSidebar(`) and add the two new dependencies to its initializer call: `leftFileExplorerStore: leftFileExplorerStore, leftFileExplorerState: leftFileExplorerState`. Add matching stored properties to `VerticalTabsSidebar` (declare near its existing `fileExplorerState` reference):

```swift
    @ObservedObject var leftFileExplorerStore: FileExplorerStore
    @ObservedObject var leftFileExplorerState: FileExplorerState
```

- [ ] **Step 4: Verify compile.** `./scripts/reload.sh --tag sidebar-redesign`. Expected: builds; no visible change yet (panel not mounted until B6).

- [ ] **Step 5: Commit**

```bash
git add Sources/ContentView.swift
git commit -m "Drive a second left-sidebar explorer store from the active session"
```

## Task B5: `SidebarFileExplorerPanel` view (slim header + embedded tree)

**Files:**
- Create: `Sources/Sidebar/SidebarFileExplorerPanel.swift`
- Modify: `cmux.xcodeproj/project.pbxproj` (wire it)

A SwiftUI view: a slim collapsible section header (folder name + chevron) over the embedded `FileExplorerPanelView`. Collapse is stored as `!state.isVisible` on the left state (already persisted). Double-clicking a file inserts its path into the active terminal.

- [ ] **Step 1: Create the view**

`Sources/Sidebar/SidebarFileExplorerPanel.swift`:

```swift
import SwiftUI

/// The file-explorer panel hosted in the bottom of the left sidebar.
///
/// Shows a slim section header (the active folder's name + a collapse chevron)
/// above an embedded ``FileExplorerPanelView`` whose root follows the active
/// session. The header's chevron toggles `state.isVisible`; collapsed shows the
/// header only. Double-clicking a file inserts its path into the active
/// session's terminal.
struct SidebarFileExplorerPanel: View {
    @ObservedObject var store: FileExplorerStore
    @ObservedObject var state: FileExplorerState

    private var folderName: String {
        let trimmed = store.rootPath.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return String(localized: "sidebar.fileExplorer.title", defaultValue: "Explorer")
        }
        return (trimmed as NSString).lastPathComponent
    }

    var body: some View {
        VStack(spacing: 0) {
            Button {
                state.isVisible.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: state.isVisible ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text(folderName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                state.isVisible
                    ? String(localized: "sidebar.fileExplorer.collapse", defaultValue: "Collapse file explorer")
                    : String(localized: "sidebar.fileExplorer.expand", defaultValue: "Expand file explorer")
            )

            if state.isVisible {
                if store.rootPath.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(String(localized: "sidebar.fileExplorer.emptyState", defaultValue: "No folder open"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    FileExplorerPanelView(
                        store: store,
                        state: state,
                        onOpenFilePreview: { path in
                            FileExplorerTerminalPathInsertion.insert(
                                paths: [path],
                                relativeToRootPath: store.rootPath,
                                intoTerminalFor: nil
                            )
                        },
                        presentation: .files,
                        placement: .pane,
                        showsHeader: false
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
```

- [ ] **Step 2: Wire the file into pbxproj** (Task A0), then normalize + check.

- [ ] **Step 3: Verify compile.** `./scripts/reload.sh --tag sidebar-redesign`. Expected: builds (view not yet mounted).

- [ ] **Step 4: Commit**

```bash
git add Sources/Sidebar/SidebarFileExplorerPanel.swift cmux.xcodeproj/project.pbxproj
git commit -m "Add SidebarFileExplorerPanel (slim header + embedded tree)"
```

## Task B6: Mount the panel as a vertical split in `VerticalTabsSidebar`

**Files:**
- Modify: `Sources/ContentView.swift` (`VerticalTabsSidebar.body` ZStack at 10985)

- [ ] **Step 1: Replace the body's content container.** In `VerticalTabsSidebar.body`, replace the `ZStack(alignment: .bottomLeading) { ... }` block (ContentView.swift:10985–10993, ending at the `}` before `.accessibilityIdentifier("Sidebar")`) with:

```swift
        Group {
            if CmuxExtensionSidebarSelection.descriptor(for: effectiveExtensionSidebarProviderId).id == CmuxSidebarProviderDescriptor.defaultWorkspacesID {
                VStack(spacing: 0) {
                    GeometryReader { proxy in
                        let available = proxy.size.height
                        let sessionFraction = SidebarExplorerSplit.clampedSessionFraction(
                            leftFileExplorerState.isVisible ? leftFileExplorerState.dividerPosition : 1.0,
                            availableHeight: available
                        )
                        let sessionHeight = leftFileExplorerState.isVisible ? available * sessionFraction : available
                        VStack(spacing: 0) {
                            workspaceScrollArea(renderContext: renderContext)
                                .frame(height: max(0, sessionHeight))
                            if leftFileExplorerState.isVisible {
                                explorerSplitDivider
                                SidebarFileExplorerPanel(
                                    store: leftFileExplorerStore,
                                    state: leftFileExplorerState
                                )
                                .frame(maxHeight: .infinity)
                            } else {
                                SidebarFileExplorerPanel(
                                    store: leftFileExplorerStore,
                                    state: leftFileExplorerState
                                )
                            }
                        }
                    }
                    SidebarFooter(updateViewModel: updateViewModel, fileExplorerState: fileExplorerState, onSendFeedback: onSendFeedback)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 0) {
                    extensionSidebarScrollArea(renderContext: renderContext)
                    SidebarFooter(updateViewModel: updateViewModel, fileExplorerState: fileExplorerState, onSendFeedback: onSendFeedback)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
```

> The footer moves from a `.bottomLeading` overlay into normal flow at the bottom of each branch. The session list + explorer split the remaining height above it. When the explorer is collapsed, the session list takes all the height above the slim header (which the panel still renders).

- [ ] **Step 2: Verify build + manual check (no divider drag yet).** `./scripts/reload.sh --tag sidebar-redesign`. Expected: session list on top, a slim "Explorer / <folder>" header + file tree below it, footer pinned at the bottom. Selecting a different session swaps the tree's folder. Double-clicking a file inserts its path into the active terminal. The chevron collapses/expands the tree. Provide the build link as in Task A5 Step 4.

- [ ] **Step 3: Commit**

```bash
git add Sources/ContentView.swift
git commit -m "Mount file explorer as a vertical split below the session list"
```

## Task B7: Draggable split divider

**Files:**
- Modify: `Sources/ContentView.swift` (new `@State` near 1090; new `explorerSplitDivider` view; cursor constant near 1584)

- [ ] **Step 1: Add drag state + a vertical resize cursor.** In ContentView's `@State` block (near line 1090), add:

```swift
    @State private var explorerSplitDragStartFraction: CGFloat?
    @State private var isExplorerSplitDragging = false
```

and next to `fixedSidebarResizeCursor` (ContentView.swift:1584), add:

```swift
    private static let fixedExplorerSplitCursor = NSCursor(
        image: NSCursor.resizeUpDown.image,
        hotSpot: NSCursor.resizeUpDown.hotSpot
    )
```

- [ ] **Step 2: Add the divider view.** Add this computed property to `VerticalTabsSidebar` (next to `workspaceScrollArea`):

```swift
    private var explorerSplitDivider: some View {
        GeometryReader { proxy in
            // Local availableHeight is the height of the *containing* split
            // VStack; we read the parent height via the drag's translation only,
            // so use the panel proxy for clamping reference.
            Rectangle()
                .fill(Color.clear)
                .frame(height: 8)
                .contentShape(Rectangle())
                .overlay(
                    Rectangle()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 1)
                )
                .onHover { hovering in
                    if hovering { Self.fixedExplorerSplitCursor.set() } else { NSCursor.arrow.set() }
                }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named("sidebarSplit"))
                        .onChanged { value in
                            if !isExplorerSplitDragging {
                                isExplorerSplitDragging = true
                                explorerSplitDragStartFraction = leftFileExplorerState.dividerPosition
                                Self.fixedExplorerSplitCursor.set()
                            }
                            let available = max(1, splitAvailableHeight)
                            let start = explorerSplitDragStartFraction ?? leftFileExplorerState.dividerPosition
                            let next = SidebarExplorerSplit.clampedSessionFraction(
                                start + (value.translation.height / available),
                                availableHeight: available
                            )
                            withTransaction(Transaction(animation: nil)) {
                                leftFileExplorerState.dividerPosition = next
                            }
                        }
                        .onEnded { _ in
                            isExplorerSplitDragging = false
                            explorerSplitDragStartFraction = nil
                            NSCursor.arrow.set()
                        }
                )
        }
        .frame(height: 8)
    }
```

- [ ] **Step 3: Provide the available height to the divider.** Add a `@State private var splitAvailableHeight: CGFloat = 0` to `VerticalTabsSidebar` and set it from the split `GeometryReader` in B6 by adding, right after `let available = proxy.size.height`:

```swift
                        let _ = { if splitAvailableHeight != available { Task { @MainActor in splitAvailableHeight = available } } }()
```

> This records the split height for the drag math without mutating state inside the view-body projection that feeds rows (it targets a leaf `@State`, not a row store). If you prefer to avoid the `Task`, attach a `.background(GeometryReader { ... })` to the split `VStack` that writes `splitAvailableHeight` via a `PreferenceKey` instead.

Also wrap the split `VStack` (from B6) with `.coordinateSpace(name: "sidebarSplit")` so the drag translation matches the divider's space.

- [ ] **Step 4: Build + manual check.** `./scripts/reload.sh --tag sidebar-redesign`. Expected: dragging the thin divider resizes the session list vs. explorer; the cursor shows resize-up-down on hover; the split persists across relaunch (stored in `sidebar.fileExplorer.dividerPosition`); neither pane collapses below its minimum.

- [ ] **Step 5: Commit**

```bash
git add Sources/ContentView.swift
git commit -m "Add draggable divider for the left-sidebar explorer split"
```

## Task B8: Localization, docs, and final audit

**Files:**
- Modify: `Resources/Localizable.xcstrings`
- Modify: docs (located in step)

- [ ] **Step 1: Add the new sidebar strings (en + ja).** Add these keys to `Resources/Localizable.xcstrings`, matching the existing `sidebar.*` format (the `fileExplorer.empty` "No folder open" key already exists for the container; these are the panel's own strings):

```json
    "sidebar.fileExplorer.title" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Explorer" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "エクスプローラー" } }
      }
    },
    "sidebar.fileExplorer.emptyState" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "No folder open" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "フォルダが開いていません" } }
      }
    },
    "sidebar.fileExplorer.collapse" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Collapse file explorer" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "ファイルエクスプローラーを折りたたむ" } }
      }
    },
    "sidebar.fileExplorer.expand" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Expand file explorer" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "ファイルエクスプローラーを展開" } }
      }
    },
```

- [ ] **Step 2: Document the feature.** Find the sidebar docs (`rg -l "right sidebar|file explorer|Sidebar" docs web | head`) and add a short note that the left sidebar now hosts a file explorer following the active session, with a collapsible/resizable split. If localized docs exist, update `web/messages/en.json` and `web/messages/ja.json`.

- [ ] **Step 3: Localization audit (Part B).** Verify every new user-facing string has en + ja and no bare English literals were introduced:

```bash
rg -n "sidebar.fileExplorer\.(title|emptyState|collapse|expand)" Resources/Localizable.xcstrings
rg -n "Text\(\"|Label\(\"|\.help\(\"" Sources/Sidebar/SidebarFileExplorerPanel.swift
```

Expected: each key shows both `en` and `ja`; the second command returns nothing (all strings go through `String(localized:)`).

- [ ] **Step 4: Build + final manual verification.** `./scripts/reload.sh --tag sidebar-redesign`. Walk the full flow: compact rows on by default; toggle restores detail; explorer follows session selection and live `cd`; double-click inserts path into terminal; collapse/expand + resize persist; ja locale shows translated strings (switch system language or verify the xcstrings entries). Provide the build link.

- [ ] **Step 5: Commit**

```bash
git add Resources/Localizable.xcstrings docs web 2>/dev/null; git commit -m "Localize and document the left-sidebar file explorer (en+ja)"
```

---

## Self-review (completed during planning)

- **Spec coverage:** thin one-line rows (A2,A4,A5) with status dot reusing existing colors (A3) and detail-in-tooltip (A5); compact-by-default + reversible toggle (A1,A6) honored in `cmux.json` (A7); bottom file explorer following active session (B4) via reused stack (B3,B5,B6); click→terminal insertion (B5); collapsible + resizable split (B6,B7) with persistence (B1); perf-safe `Equatable`/snapshot boundary (A2 notes, A4 places fields off `==`); localization en+ja (A6,B8). All spec sections map to tasks.
- **Placeholder scan:** no TBD/TODO; every code step shows real code; doc/locale file paths are located via `rg` with concrete instructions (the repo's exact docs path isn't hard-coded because it's discovered at run time, not omitted).
- **Type consistency:** `SidebarCompactRowModeSettings.key/.defaultValue/.isEnabled`, `CompactRowStatusResolver.dotColorHex(for:)`, `SidebarExplorerSplit.clampedSessionFraction(_:availableHeight:)`, snapshot fields `statusDotColorHex`/`compactRowPathText`, `FileExplorerState(persistenceKeyPrefix:)`, `SidebarFileExplorerPanel(store:state:)`, and `FileExplorerPanelView(... showsHeader:)` are used identically across the tasks that define and consume them.

## Known risks / verify carefully

- **Footer reflow (B6):** moving `SidebarFooter` from overlay into flow changes z-order; verify the empty-area drop target and update pill still look right.
- **`splitAvailableHeight` write (B7 Step 3):** keep the height write off the row-feeding projection; prefer the `PreferenceKey` variant if any LazyVStack re-render churn appears.
- **Header suppression (B3):** if a hidden header still reserves height, add the gated `heightAnchor == 0` constraint.
- **pbxproj:** every new `Sources/**` and `cmuxTests/**` file must be wired or it silently won't compile/run; `./scripts/check-pbxproj.sh` + `./scripts/lint-pbxproj-test-wiring.sh` gate this.
