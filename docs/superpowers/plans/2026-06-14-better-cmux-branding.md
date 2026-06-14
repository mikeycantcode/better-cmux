# better cmux branding (red icon + welcome pane) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recolor the app icon's gradient to bright-red→crimson and replace the auto-opened launch terminal with a branded "better cmux" welcome pane (credits + "+ New Terminal"), gated by a default-on setting; add the credit to the About panel.

**Architecture:** Icon = an offline Python recolor that remaps the chevron's blue→purple pixels to a red gradient in place (hue-masked, position-based) across the SVG + all icon PNGs — no `ictool` dependency. Welcome pane = a new non-terminal `WelcomePanel` (same pattern as `EditReviewPanel`) created as the initial surface on a fresh launch via a threaded flag + a pure `initialSurfaceKind(...)` decision; its "+ New Terminal" button creates a terminal in the pane and closes the welcome surface. Setting `app.welcomePaneOnLaunch` mirrors `automation.manualEditDiff`.

**Tech Stack:** Swift 6 / SwiftUI / AppKit, bonsplit panels, Python 3 + Pillow (offline asset step), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-06-14-better-cmux-branding-design.md`. **Branch:** `better-cmux-branding`.

---

## Verified seams (real, from exploration)

- **Icon:** chevron source art `AppIcon.icon/Assets/cmux-icon-chevron 2.png` and `design/cmux-icon-chevron.png` (identical, transparent, blue→purple gradient). Vector gradient in `web/public/cmux-icon.svg` (`<linearGradient id="cmux-chevron">` stops `#12c7f5`/`#2d8cff`/`#6c5cff`, horizontal axis). Final PNGs in `Assets.xcassets/AppIcon.appiconset/` (light `16/32/128/256/512` ×1/×2 + `_dark` variants) and `Assets.xcassets/AppIcon-Debug.appiconset/` (light only + orange "DEV" banner). `ictool`/`actool` CLI is unreliable here → recolor PNGs directly. Pillow is NOT installed.
- **Launch:** `Workspace.init(...)` (Sources/Workspace.swift ~11015) creates the initial `TerminalPanel` in an `else` block (~11087–11115) via `TerminalPanel(...)` → `panels[...] = ` → `bonsplitController.createTab(title:icon:"terminal.fill",kind:SurfaceKind.terminal,...)` → `surfaceIdToPanelId[tabId] = `. `TabManager.makeWorkspaceForCreation(...)` (~2519) constructs the Workspace; `addWorkspace(...)` (~2605, has `autoWelcomeIfNeeded`) calls it; `TabManager.init(...)` (~1295) passes `autoWelcomeIfNeeded`; `AppDelegate.createMainWindow(...)` (~7967) sets `autoWelcomeIfNeeded: initialTerminalInput == nil` and, for restore, passes a `sessionWindowSnapshot` then calls `restoreSessionSnapshot` (restored workspaces are built bare, no initial terminal). First-run `cmux welcome` runs via `AppDelegate.sendWelcomeCommandWhenReady` gated by `WelcomeSettings.shownKey`.
- **Panels:** `protocol Panel` (Sources/Panels/Panel.swift ~265) with default focus-intent impls; `EditReviewPanel`/`EditReviewPanelView` are the reference non-terminal panel; `PanelContentView.swift` `.filePreview` case dispatches `if let x = panel as? EditReviewPanel { … } else if let f = panel as? FilePreviewPanel { … }`, passing `appearance: PanelAppearance`. `Workspace.newTerminalSurface(inPane:focus:…) -> TerminalPanel?` (~14523), `Workspace.paneId(forPanelId:) -> PaneID?` (~15580), `Workspace.closePanel(_:force:) -> Bool` (~15577).
- **Setting mirror:** `automation.manualEditDiff` exists across `AutomationCatalogSection.swift`, `ManualEditDiffSettings` (cmuxApp.swift ~5120), `AutomationSection.swift` card, `CommandPaletteSettingsToggle.swift`, `KeyboardShortcutSettingsFileStore.swift` (`parseAutomationSection`), `cmux.schema.json`, `all-keys.md`. **No `general.*` namespace** — use `app.*` (`AppCatalogSection.swift` / `AppSection.swift` / `parseAppSection` / schema `app` object / all-keys `## app`).
- **About:** `AboutPanelView` (cmuxApp.swift ~2802): a button `HStack` (~2856) with `docsURL`/`githubURL` (`https://github.com/manaflow-ai/cmux`) link buttons via `openURL(url)`.

---

## Task 1: Recolor the icon gradient to red (offline asset step)

**Files:**
- Create: `scripts/recolor_icon_red.py`
- Modify: `web/public/cmux-icon.svg`
- Modify (regenerated, binary): `AppIcon.icon/Assets/cmux-icon-chevron 2.png`, `design/cmux-icon-chevron.png`, all PNGs in `Assets.xcassets/AppIcon.appiconset/` and `Assets.xcassets/AppIcon-Debug.appiconset/`, `web/app/icon.png`, `web/app/apple-icon.png`, `web/public/logo.png`.

- [ ] **Step 1: Recolor the vector SVG gradient stops**

In `web/public/cmux-icon.svg`, change the three `<stop>` colors:
```
#12c7f5  →  #ff5a5a
#2d8cff  →  #ff2d2d
#6c5cff  →  #c81e3a
```
(Exact edit: replace `stop-color="#12c7f5"` → `stop-color="#ff5a5a"`, `stop-color="#2d8cff"` → `stop-color="#ff2d2d"`, `stop-color="#6c5cff"` → `stop-color="#c81e3a"`.)

- [ ] **Step 2: Ensure Pillow is available**

Run: `python3 -c "import PIL" 2>/dev/null && echo present || python3 -m pip install --user Pillow`
Expected: `present`, or a successful Pillow install. (Offline asset tooling only — not part of the app build.)

- [ ] **Step 3: Write the recolor script**

`scripts/recolor_icon_red.py`:
```python
#!/usr/bin/env python3
"""Recolor the cmux chevron gradient from blue->purple to bright-red->crimson.

Operates on rasterized icon PNGs in place: it masks only the chromatic blue/cyan/
purple chevron pixels (the squircle is white, the shadow gray, the dark background
neutral, the DEV banner orange -- all left untouched) and remaps each masked pixel
to the red gradient (#ff5a5a -> #ff2d2d -> #c81e3a) by its horizontal position
within the chevron, preserving per-pixel luminance and alpha so edges/glow survive.

Requires Pillow:  python3 -m pip install --user Pillow
Run from repo root:  python3 scripts/recolor_icon_red.py
"""
import colorsys
import os

from PIL import Image

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Red gradient stops (position 0.0, 0.52, 1.0) as RGB.
STOPS = [(0.0, (0xFF, 0x5A, 0x5A)), (0.52, (0xFF, 0x2D, 0x2D)), (1.0, (0xC8, 0x1E, 0x3A))]

# Blue/cyan/purple hue band (in [0,1] turns) that the chevron occupies.
HUE_LO, HUE_HI = 170.0 / 360.0, 290.0 / 360.0
SAT_MIN = 0.25  # ignore near-gray pixels (squircle, shadow, dark bg)

TARGETS = [
    "AppIcon.icon/Assets/cmux-icon-chevron 2.png",
    "design/cmux-icon-chevron.png",
    "web/app/icon.png",
    "web/app/apple-icon.png",
    "web/public/logo.png",
]
APPICON_DIRS = [
    "Assets.xcassets/AppIcon.appiconset",
    "Assets.xcassets/AppIcon-Debug.appiconset",
]


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def gradient_color(pos):
    pos = max(0.0, min(1.0, pos))
    for i in range(len(STOPS) - 1):
        p0, c0 = STOPS[i]
        p1, c1 = STOPS[i + 1]
        if pos <= p1:
            t = 0.0 if p1 == p0 else (pos - p0) / (p1 - p0)
            return lerp(c0, c1, t)
    return STOPS[-1][1]


def chevron_bbox(px, w, h):
    """Bounding box (min_x, max_x) of masked chevron pixels, for position mapping."""
    min_x, max_x = w, -1
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            hh, _, s = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            sat = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)[1]
            if sat >= SAT_MIN and HUE_LO <= hh <= HUE_HI:
                min_x = min(min_x, x)
                max_x = max(max_x, x)
    return min_x, max_x


def recolor(path):
    full = os.path.join(REPO, path)
    if not os.path.exists(full):
        print("skip (missing):", path)
        return
    img = Image.open(full).convert("RGBA")
    w, h = img.size
    px = img.load()
    min_x, max_x = chevron_bbox(px, w, h)
    if max_x < 0:
        print("skip (no chevron pixels):", path)
        return
    span = max(1, max_x - min_x)
    changed = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            hh, light, _ = colorsys.rgb_to_hls(r / 255, g / 255, b / 255)
            sat = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)[1]
            if sat < SAT_MIN or not (HUE_LO <= hh <= HUE_HI):
                continue
            base = gradient_color((x - min_x) / span)
            # Scale the red toward the pixel's original luminance so anti-aliased
            # edges and the glow keep their shading.
            bl, _, _ = colorsys.rgb_to_hls(base[0] / 255, base[1] / 255, base[2] / 255)
            scale = (light / bl) if bl > 0 else 1.0
            scale = max(0.35, min(1.6, scale))
            nr = min(255, int(base[0] * scale))
            ng = min(255, int(base[1] * scale))
            nb = min(255, int(base[2] * scale))
            px[x, y] = (nr, ng, nb, a)
            changed += 1
    img.save(full)
    print(f"recolored {changed:>7} px  {path}")


def main():
    paths = list(TARGETS)
    for d in APPICON_DIRS:
        full_d = os.path.join(REPO, d)
        if os.path.isdir(full_d):
            for f in sorted(os.listdir(full_d)):
                if f.endswith(".png"):
                    paths.append(os.path.join(d, f))
    for p in paths:
        recolor(p)


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Run the recolor**

Run: `cd /Users/mikeycantcode/cmux-mikesversion && python3 scripts/recolor_icon_red.py`
Expected: a list of `recolored <N> px <path>` lines for the chevron sources, every `AppIcon.appiconset` PNG (light + `_dark`), the `AppIcon-Debug.appiconset` PNGs (chevron only; the orange DEV banner is outside the hue band and is left orange), and the web PNGs. No `skip (no chevron pixels)` for the appiconset entries.

- [ ] **Step 5: Build and visually verify the icon is red**

Run: `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag bcb 2>&1 | tail -4`, then open the printed app and confirm the **dock icon is red** (light + dark appearance). Spot-check `Assets.xcassets/AppIcon.appiconset/512.png` and `512_dark.png` visually (e.g. `qlmanage -p` or open in Preview) — chevron red, squircle/background unchanged.
If a variant looks wrong (e.g. residual blue at edges or an over-darkened gradient), adjust `SAT_MIN`/`HUE_HI`/the `scale` clamp in the script and re-run Step 4 — do **not** hand-edit PNGs.

- [ ] **Step 6: Commit**

```bash
git add scripts/recolor_icon_red.py web/public/cmux-icon.svg "AppIcon.icon/Assets/cmux-icon-chevron 2.png" design/cmux-icon-chevron.png Assets.xcassets/AppIcon.appiconset Assets.xcassets/AppIcon-Debug.appiconset web/app/icon.png web/app/apple-icon.png web/public/logo.png
git commit -m "Recolor app icon gradient blue->red (bright red -> crimson)"
```
(Note: `web/app/favicon.ico` and the iOS `cmux-logo.svg` embed composites that this PNG pass doesn't cover; leave them as a documented follow-up — the dock/app icon and web SVG/PNGs are the in-scope surfaces.)

---

## Task 2: `app.welcomePaneOnLaunch` setting (default on)

**Files:**
- Modify: `Packages/CmuxSettings/Sources/CmuxSettings/Keys/AppCatalogSection.swift`
- Modify: `Sources/cmuxApp.swift` (add `WelcomePaneSettings`)
- Modify: `Packages/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/AppSection.swift`
- Modify: `Sources/CommandPalette/CommandPaletteSettingsToggle.swift`
- Modify: `Sources/KeyboardShortcutSettingsFileStore.swift`
- Modify: `web/data/cmux.schema.json`, `skills/cmux-settings/references/all-keys.md`, `Resources/Localizable.xcstrings`

- [ ] **Step 1: Add the catalog key**

In `AppCatalogSection.swift`, mirroring the `automation.manualEditDiff` `DefaultsKey<Bool>` shape, add a sibling (place it near other app booleans, before `public init()`):
```swift
    public let welcomePaneOnLaunch = DefaultsKey<Bool>(
        id: "app.welcomePaneOnLaunch",
        defaultValue: true,
        userDefaultsKey: "welcomePaneOnLaunch"
    )
```

- [ ] **Step 2: Add the runtime accessor**

In `Sources/cmuxApp.swift`, right after the `ManualEditDiffSettings` enum, add (mirroring it exactly):
```swift
enum WelcomePaneSettings {
    static let welcomePaneOnLaunchKey = "welcomePaneOnLaunch"
    static let defaultWelcomePaneOnLaunch = true

    static func isEnabled(defaults: UserDefaults = .standard) -> Bool {
        if defaults.object(forKey: welcomePaneOnLaunchKey) == nil {
            return defaultWelcomePaneOnLaunch
        }
        return defaults.bool(forKey: welcomePaneOnLaunchKey)
    }
}
```

- [ ] **Step 3: Add the Settings UI card**

In `AppSection.swift`, find an existing `DefaultsValueModel<Bool>` toggle card in that file and mirror it: add a `@State private var welcomePaneOnLaunchModel: DefaultsValueModel<Bool>`, initialize it in `init` (`_welcomePaneOnLaunchModel = State(initialValue: DefaultsValueModel(store: defaultsStore, key: catalog.app.welcomePaneOnLaunch))`), reference `welcomePaneOnLaunchCard` in `body`, and add:
```swift
    @ViewBuilder
    private var welcomePaneOnLaunchCard: some View {
        SettingsCard {
            SettingsCardRow(
                configurationReview: .json("app.welcomePaneOnLaunch"),
                String(localized: "settings.app.welcomePaneOnLaunch", defaultValue: "Welcome Pane on Launch"),
                subtitle: welcomePaneOnLaunchModel.current
                    ? String(localized: "settings.app.welcomePaneOnLaunch.subtitleOn", defaultValue: "New windows open to a welcome pane with a New Terminal button.")
                    : String(localized: "settings.app.welcomePaneOnLaunch.subtitleOff", defaultValue: "New windows open a terminal immediately.")
            ) {
                Toggle("", isOn: Binding(get: { welcomePaneOnLaunchModel.current }, set: { welcomePaneOnLaunchModel.set($0) }))
                    .labelsHidden()
                    .controlSize(.small)
                    .accessibilityIdentifier("SettingsWelcomePaneOnLaunchToggle")
            }
            SettingsCardDivider()
            SettingsCardNote(String(localized: "settings.app.welcomePaneOnLaunch.note", defaultValue: "When enabled, opening a fresh window (no restored session) shows the better cmux welcome pane instead of an immediate terminal. Restored sessions are unaffected."))
        }
    }
```
Match the actual `SettingsCard`/`SettingsCardRow` signatures used by the sibling card in `AppSection.swift` (copy the sibling card verbatim, change only keys/text/identifier/model). If `AppSection`'s init takes `catalog`/`defaultsStore` differently, follow its existing pattern.

- [ ] **Step 4: Command-palette toggle**

In `CommandPaletteSettingsToggle.swift`, mirror the `manualEditDiff` descriptor but in the app section (use the same `sectionTitle` value the other `app.*` toggles in that file use; if none exist, use the app/general section title constant present in the file):
```swift
            CommandPaletteSettingToggleDescriptor(
                commandId: commandIdPrefix + "welcomePaneOnLaunch",
                settingsKey: "app.welcomePaneOnLaunch",
                title: {
                    String(localized: "settings.app.welcomePaneOnLaunch", defaultValue: "Welcome Pane on Launch")
                },
                sectionTitle: app,
                keywords: ["app.welcomePaneOnLaunch", "welcome", "launch", "startup", "new", "terminal", "pane"],
                defaultValue: WelcomePaneSettings.defaultWelcomePaneOnLaunch,
                defaultsKey: WelcomePaneSettings.welcomePaneOnLaunchKey
            ),
```
(If the file has no `app` section-title local, read how other non-automation toggles set `sectionTitle` and match it.)

- [ ] **Step 5: cmux.json config parsing**

In `Sources/KeyboardShortcutSettingsFileStore.swift`, find the function that parses the `app` config section (e.g. `parseAppSection`; if app keys are parsed elsewhere, follow that). Add, mirroring the `manualEditDiff` parse line:
```swift
        if let value = jsonBool(section["welcomePaneOnLaunch"]) {
            snapshot.managedUserDefaults[WelcomePaneSettings.welcomePaneOnLaunchKey] = .bool(value)
        }
```
(Use the same `section`/`jsonBool`/`snapshot.managedUserDefaults` names the surrounding parser uses.)

- [ ] **Step 6: Schema + docs**

In `web/data/cmux.schema.json`, in the `app` properties object (alphabetical), add:
```json
        "welcomePaneOnLaunch": {
          "type": "boolean",
          "default": true,
          "description": "Show the better cmux welcome pane on a fresh launch instead of an immediate terminal."
        },
```
In `skills/cmux-settings/references/all-keys.md`, in the `app` section (alphabetical), add:
```markdown
| `app.welcomePaneOnLaunch` | boolean | `true` | Show the better cmux welcome pane on a fresh launch instead of an immediate terminal. |
```

- [ ] **Step 7: Localization (en + ja, minimal splice)**

In `Resources/Localizable.xcstrings`, splice 4 keys next to an existing `settings.app.*` key (match the file's `"key": {` format — no space before colon — both `en` and `ja`):
- `settings.app.welcomePaneOnLaunch` → en "Welcome Pane on Launch" / ja "起動時のウェルカムペイン"
- `.subtitleOn` → en "New windows open to a welcome pane with a New Terminal button." / ja "新しいウィンドウは「新規ターミナル」ボタン付きのウェルカムペインで開きます。"
- `.subtitleOff` → en "New windows open a terminal immediately." / ja "新しいウィンドウはすぐにターミナルを開きます。"
- `.note` → en "When enabled, opening a fresh window (no restored session) shows the better cmux welcome pane instead of an immediate terminal. Restored sessions are unaffected." / ja "有効にすると、（復元セッションのない）新規ウィンドウで、すぐにターミナルを開く代わりに better cmux のウェルカムペインを表示します。復元されたセッションには影響しません。"
Verify: `python3 -c "import json; json.load(open('Resources/Localizable.xcstrings')); print('ok')"` → `ok`.

- [ ] **Step 8: Build + commit**

Run: `cd Packages/CmuxSettings && swift build` then `CMUX_SKIP_ZIG_BUILD=1 xcodebuild -project ../../cmux.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-bcb build 2>&1 | tail -6` → `** BUILD SUCCEEDED **`.
```bash
git add Packages/CmuxSettings Packages/CmuxSettingsUI Sources/cmuxApp.swift Sources/CommandPalette/CommandPaletteSettingsToggle.swift Sources/KeyboardShortcutSettingsFileStore.swift web/data/cmux.schema.json skills/cmux-settings/references/all-keys.md Resources/Localizable.xcstrings
git commit -m "Add app.welcomePaneOnLaunch setting (catalog, UI, palette, schema, docs, l10n)"
```

---

## Task 3: `WelcomePanel` + `WelcomePanelView`

**Files:**
- Create: `Sources/Panels/WelcomePanel.swift`
- Create: `Sources/Panels/WelcomePanelView.swift`
- Modify: `Sources/Panels/PanelContentView.swift`
- Modify: `cmux.xcodeproj/project.pbxproj`

- [ ] **Step 1: Create `WelcomePanel`**

`Sources/Panels/WelcomePanel.swift` (mirror `EditReviewPanel`'s Panel conformance; the focus-intent methods come from the protocol-extension defaults):
```swift
import AppKit
import Combine
import Foundation
import SwiftUI

/// A non-terminal panel shown as the initial surface on a fresh launch: the better cmux
/// branding, credits, and a "+ New Terminal" button. The owning workspace sets ``onNewTerminal``
/// to create a terminal in this pane and close the welcome surface.
@MainActor
final class WelcomePanel: ObservableObject, Panel {
    let id = UUID()
    let workspaceId: UUID
    /// Invoked by the "+ New Terminal" button; the workspace wires this to create a terminal in
    /// this panel's pane and then close this welcome surface.
    var onNewTerminal: (() -> Void)?

    // Reuse the closest existing kind; distinguished from FilePreviewPanel by instance at dispatch.
    let panelType: PanelType = .filePreview
    var displayTitle: String { String(localized: "welcome.tabTitle", defaultValue: "Welcome") }
    var displayIcon: String? { "sparkles" }
    var isDirty: Bool { false }

    init(workspaceId: UUID) {
        self.workspaceId = workspaceId
    }

    func close() {}
    func focus() {}
    func unfocus() {}
    func triggerFlash(reason: WorkspaceAttentionFlashReason) { _ = reason }
}
```

- [ ] **Step 2: Create `WelcomePanelView`**

`Sources/Panels/WelcomePanelView.swift`:
```swift
import SwiftUI

/// The better cmux welcome screen: red app-icon logo, title, credits, and a "+ New Terminal" button.
struct WelcomePanelView: View {
    @ObservedObject var panel: WelcomePanel
    let appearance: PanelAppearance

    private let originalURL = URL(string: "https://github.com/manaflow-ai/cmux")!
    private let buildURL = URL(string: "https://github.com/mikeycantcode")!

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
            Text(String(localized: "welcome.title", defaultValue: "better cmux"))
                .font(.system(size: 26, weight: .bold))
            VStack(spacing: 4) {
                Text(String(localized: "welcome.creditOriginal", defaultValue: "Built on cmux by manaflow-ai — all credit to the original team."))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(String(localized: "welcome.creditBuildPrefix", defaultValue: "This build:"))
                        .foregroundStyle(.secondary)
                    Link("github.com/mikeycantcode", destination: buildURL)
                }
                Link(String(localized: "welcome.originalLink", defaultValue: "github.com/manaflow-ai/cmux"), destination: originalURL)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .font(.callout)
            Button {
                panel.onNewTerminal?()
            } label: {
                Label(String(localized: "welcome.newTerminal", defaultValue: "New Terminal"), systemImage: "plus")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            Text(String(localized: "welcome.shortcutHint", defaultValue: "⌘T also opens a terminal"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: appearance.backgroundColor))
    }
}
```

- [ ] **Step 3: Dispatch the view in `PanelContentView`**

In `Sources/Panels/PanelContentView.swift`, in the `.filePreview` case, add a `WelcomePanel` branch **before** the `EditReviewPanel`/`FilePreviewPanel` branches:
```swift
            if let welcomePanel = panel as? WelcomePanel {
                WelcomePanelView(panel: welcomePanel, appearance: appearance)
            } else if let editReviewPanel = panel as? EditReviewPanel {
                EditReviewPanelView(panel: editReviewPanel, appearance: appearance)
            } else if let filePreviewPanel = panel as? FilePreviewPanel {
                // ...existing FilePreviewPanelView(...) call unchanged...
            }
```
(Keep the existing `FilePreviewPanelView(...)` arguments exactly as they are.)

- [ ] **Step 4: Wire both files into the pbxproj**

Add `WelcomePanel.swift` and `WelcomePanelView.swift` to the `cmux` target (mirror how `EditReviewPanel.swift`/`EditReviewPanelView.swift` are referenced: `PBXFileReference` + group entry + `PBXBuildFile` + `PBXSourcesBuildPhase`, fresh **unique** 24-hex IDs — do NOT reuse any existing ID; verify with `grep`). Then `python3 scripts/normalize-pbxproj.py cmux.xcodeproj/project.pbxproj && ./scripts/check-pbxproj.sh`.

- [ ] **Step 5: Localization for the welcome view (en + ja)**

Splice into `Resources/Localizable.xcstrings` (both locales) the keys: `welcome.tabTitle` (Welcome / ようこそ), `welcome.title` ("better cmux" both — proper noun, keep English in ja), `welcome.creditOriginal` (en above / ja "cmux（manaflow-ai 製）を基にしています。オリジナルチームに感謝します。"), `welcome.creditBuildPrefix` (This build: / このビルド:), `welcome.originalLink` (keep the URL string in both), `welcome.newTerminal` (New Terminal / 新規ターミナル), `welcome.shortcutHint` ("⌘T also opens a terminal" / "⌘T でもターミナルを開けます"). Verify JSON parses.

- [ ] **Step 6: Build + commit**

Run: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-bcb build 2>&1 | tail -6` → `** BUILD SUCCEEDED **`.
```bash
git add Sources/Panels/WelcomePanel.swift Sources/Panels/WelcomePanelView.swift Sources/Panels/PanelContentView.swift cmux.xcodeproj/project.pbxproj Resources/Localizable.xcstrings
git commit -m "Add WelcomePanel + WelcomePanelView (better cmux welcome screen)"
```

---

## Task 4: Launch seam — show the welcome pane on a fresh launch

**Files:**
- Create: `Packages/CmuxSettings/Sources/CmuxSettings/InitialSurfaceKind.swift` (pure, testable)
- Test: `Packages/CmuxSettings/Tests/CmuxSettingsTests/InitialSurfaceKindTests.swift`
- Modify: `Sources/Workspace.swift`, `Sources/TabManager.swift`, `Sources/AppDelegate.swift`

- [ ] **Step 1: Write the failing decision-function test**

`Packages/CmuxSettings/Tests/CmuxSettingsTests/InitialSurfaceKindTests.swift`:
```swift
import Testing
@testable import CmuxSettings

@Suite struct InitialSurfaceKindTests {
    @Test func freshAndEnabledIsWelcome() {
        #expect(initialSurfaceKind(isFreshLaunch: true, hasInitialInput: false, welcomeEnabled: true) == .welcome)
    }
    @Test func freshButDisabledIsTerminal() {
        #expect(initialSurfaceKind(isFreshLaunch: true, hasInitialInput: false, welcomeEnabled: false) == .terminal)
    }
    @Test func initialInputForcesTerminal() {
        #expect(initialSurfaceKind(isFreshLaunch: true, hasInitialInput: true, welcomeEnabled: true) == .terminal)
    }
    @Test func notFreshIsTerminal() {
        #expect(initialSurfaceKind(isFreshLaunch: false, hasInitialInput: false, welcomeEnabled: true) == .terminal)
    }
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd Packages/CmuxSettings && swift test --filter InitialSurfaceKindTests`
Expected: FAIL to build (`initialSurfaceKind` / `InitialSurfaceKind` undefined).

- [ ] **Step 3: Implement the decision function**

`Packages/CmuxSettings/Sources/CmuxSettings/InitialSurfaceKind.swift`:
```swift
/// Which surface a freshly-created workspace opens with.
public enum InitialSurfaceKind: Equatable, Sendable {
    /// The better cmux welcome pane.
    case welcome
    /// A terminal (the historical default).
    case terminal
}

/// Decides the initial surface for a new workspace.
///
/// - Parameters:
///   - isFreshLaunch: True when the workspace is created fresh (not restored from a session).
///   - hasInitialInput: True when an explicit initial terminal command/input was requested.
///   - welcomeEnabled: The `app.welcomePaneOnLaunch` setting.
/// - Returns: ``InitialSurfaceKind/welcome`` only for a fresh, input-less launch with the setting on.
public func initialSurfaceKind(isFreshLaunch: Bool, hasInitialInput: Bool, welcomeEnabled: Bool) -> InitialSurfaceKind {
    guard isFreshLaunch, !hasInitialInput, welcomeEnabled else { return .terminal }
    return .welcome
}
```
Note: this is a top-level `public func` — `CmuxSettings` already contains pure decision helpers; if the package's lint forbids free functions, make it `public enum InitialSurfaceDecider { public static func kind(...) }` and update the test call sites accordingly.

- [ ] **Step 4: Run to verify it passes**

Run: `cd Packages/CmuxSettings && swift test --filter InitialSurfaceKindTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Thread a welcome flag through workspace creation**

Add `createWelcomePanel: Bool = false` to `Workspace.init(...)`, `TabManager.makeWorkspaceForCreation(...)`, and `TabManager.addWorkspace(...)` and `TabManager.init(...)` (pass through). In `AppDelegate.createMainWindow(...)`, compute it where `autoWelcomeIfNeeded` is computed:
```swift
let welcomePane = initialSurfaceKind(
    isFreshLaunch: sessionWindowSnapshot == nil,
    hasInitialInput: initialTerminalInput != nil,
    welcomeEnabled: WelcomePaneSettings.isEnabled()
) == .welcome
```
and pass `createWelcomePanel: welcomePane` into `TabManager(...)`. (Restore path keeps `createWelcomePanel: false`.)

- [ ] **Step 6: Create the WelcomePanel in `Workspace.init`**

In `Workspace.init`'s initial-surface `else` block (the one creating `TerminalPanel`), branch on the flag:
```swift
} else if createWelcomePanel {
    let welcomePanel = WelcomePanel(workspaceId: id)
    panels[welcomePanel.id] = welcomePanel
    panelTitles[welcomePanel.id] = welcomePanel.displayTitle
    if let tabId = bonsplitController.createTab(
        title: welcomePanel.displayTitle,
        icon: "sparkles",
        kind: SurfaceKind.filePreview,
        isDirty: false,
        isPinned: false
    ) {
        surfaceIdToPanelId[tabId] = welcomePanel.id
        initialTabId = tabId
    }
    welcomePanel.onNewTerminal = { [weak self, weak welcomePanel] in
        guard let self, let welcomePanel,
              let pane = self.paneId(forPanelId: welcomePanel.id) else { return }
        _ = self.newTerminalSurface(inPane: pane, focus: true)
        _ = self.closePanel(welcomePanel.id, force: true)
    }
} else {
    // ...existing TerminalPanel creation, unchanged...
}
```
(Match the exact existing local names — `initialTabId`, `panelTitles`, `surfaceIdToPanelId`, `bonsplitController` — used in the sibling terminal branch.)

- [ ] **Step 7: Suppress the auto `cmux welcome` terminal command when the welcome pane shows**

In `TabManager.addWorkspace(...)`, the first-run block calls `sendWelcomeCommandWhenReady` when `autoWelcomeIfNeeded && select && !shown`. Guard it so it does **not** run when this workspace was created with `createWelcomePanel == true` (there is no terminal to receive it):
```swift
if autoWelcomeIfNeeded && select && !createWelcomePanel
   && !UserDefaults.standard.bool(forKey: WelcomeSettings.shownKey) {
    // ...existing sendWelcomeCommandWhenReady...
}
```

- [ ] **Step 8: Build + commit**

Build the app (`CMUX_SKIP_ZIG_BUILD=1 xcodebuild … -scheme cmux … build` → `** BUILD SUCCEEDED **`) and the package tests (`cd Packages/CmuxSettings && swift test --filter InitialSurfaceKindTests` → pass).
```bash
git add Packages/CmuxSettings Sources/Workspace.swift Sources/TabManager.swift Sources/AppDelegate.swift cmux.xcodeproj/project.pbxproj
git commit -m "Launch into the welcome pane on a fresh window (app.welcomePaneOnLaunch)"
```
(If `InitialSurfaceKind.swift` is a new package file, ensure the package picks it up — SPM auto-includes `Sources/CmuxSettings/*.swift`; no pbxproj change needed for the package's own sources.)

---

## Task 5: About panel credit

**Files:** Modify `Sources/cmuxApp.swift` (`AboutPanelView`).

- [ ] **Step 1: Add a "this build" link button**

In `AboutPanelView`, add a property next to `githubURL`:
```swift
    private let betterCmuxURL = URL(string: "https://github.com/mikeycantcode")
```
In the button `HStack` (after the GitHub button), add:
```swift
                if let url = betterCmuxURL {
                    Button(String(localized: "about.betterCmux", defaultValue: "better cmux")) {
                        openURL(url)
                    }
                }
```

- [ ] **Step 2: Add the credit line**

Below the app name/description `VStack` (the one with `about.appName`/`about.description`), add a caption credit:
```swift
                Text(String(localized: "about.credit", defaultValue: "better cmux — built on cmux by manaflow-ai. This build: github.com/mikeycantcode"))
                    .multilineTextAlignment(.center)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
```

- [ ] **Step 3: Localize (en + ja)**

Splice `about.betterCmux` (better cmux / better cmux) and `about.credit` (en above / ja "better cmux — cmux（manaflow-ai 製）を基にしています。このビルド: github.com/mikeycantcode") into `Resources/Localizable.xcstrings`. Verify JSON parses.

- [ ] **Step 4: Build + commit**

Build the app → `** BUILD SUCCEEDED **`.
```bash
git add Sources/cmuxApp.swift Resources/Localizable.xcstrings
git commit -m "About panel: credit original cmux + this build (github.com/mikeycantcode)"
```

---

## Task 6: Verification + dogfood

**Files:** none (verification only).

- [ ] **Step 1: Guards + l10n audit**

Run:
```bash
./scripts/check-pbxproj.sh && ./scripts/lint-pbxproj-test-wiring.sh
python3 -c "import json; json.load(open('Resources/Localizable.xcstrings')); print('xcstrings ok')"
python3 - <<'PY'
import json
d=json.load(open('Resources/Localizable.xcstrings'))['strings']
keys=['settings.app.welcomePaneOnLaunch','settings.app.welcomePaneOnLaunch.subtitleOn','settings.app.welcomePaneOnLaunch.subtitleOff','settings.app.welcomePaneOnLaunch.note','welcome.tabTitle','welcome.title','welcome.creditOriginal','welcome.creditBuildPrefix','welcome.newTerminal','welcome.shortcutHint','about.betterCmux','about.credit']
bad=[k for k in keys if not {'en','ja'} <= set(d.get(k,{}).get('localizations',{}))]
print('MISSING', bad) if bad else print('l10n ok', len(keys),'keys')
PY
```
Expected: pbxproj OK, test-wiring ok, `xcstrings ok`, `l10n ok`.

- [ ] **Step 2: Build app + test target**

```bash
CMUX_SKIP_ZIG_BUILD=1 xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-bcb build 2>&1 | tail -4
CMUX_SKIP_ZIG_BUILD=1 xcodebuild -project cmux.xcodeproj -scheme cmux-unit -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-bcb build-for-testing 2>&1 | tail -4
```
Expected: `** BUILD SUCCEEDED **` and `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 3: Dogfood (visual)**

```bash
CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag bcb
```
Open the printed app. Verify: (1) **dock icon is red**; (2) a fresh window shows the **welcome pane** (red logo, "better cmux", credits with both GitHub links, "+ New Terminal"); (3) clicking **+ New Terminal** replaces the welcome pane with a terminal in that pane; (4) Help > About cmux shows the credit + "better cmux" link; (5) toggling `app.welcomePaneOnLaunch` off in Settings → a new window opens a terminal immediately. Surface the app link per CLAUDE.md.

---

## Notes for the executor

- **Icon is an offline asset step** — Pillow is a dev dependency for `recolor_icon_red.py`, not part of the app build. The recolor is idempotent-ish but re-running on already-red PNGs is a no-op (red hue is outside the blue mask), so it's safe to re-run after tuning thresholds.
- **No `ictool` dependency** — the recolor operates on the existing rasterized PNGs directly; do not attempt to regenerate via Icon Composer.
- **`WelcomePanel` reuses `PanelType.filePreview`** and is dispatched by instance cast in `PanelContentView` (same pattern as `EditReviewPanel`); the dispatch order must check `WelcomePanel` and `EditReviewPanel` before `FilePreviewPanel`.
- **Restore safety** — the welcome pane must only appear for `sessionWindowSnapshot == nil` fresh launches; never inject it into a restored session (the `initialSurfaceKind` `isFreshLaunch` flag enforces this).
- **No retain cycle** — `welcomePanel.onNewTerminal` captures `[weak self, weak welcomePanel]`.
- Match all mirrored boilerplate (setting card, palette descriptor, config parser) to the **actual** sibling in each file; this plan shows the deltas.
