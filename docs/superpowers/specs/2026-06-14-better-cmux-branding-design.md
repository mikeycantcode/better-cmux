# better cmux: red icon + welcome pane

**Status:** Approved (2026-06-14)
**Branch:** `better-cmux-branding`
**Scope:** Recolor the app icon's blue→purple gradient to bright-red→crimson; replace the
auto-opened launch terminal with a branded "better cmux" welcome pane (credits + "+ New Terminal");
add the same credit to the About panel.

## Summary

Three related branding changes:

1. **Icon** — recolor the chevron gradient from blue→purple (`#12c7f5 → #2d8cff → #6c5cff`) to
   **bright red → crimson (`#ff5a5a → #ff2d2d → #c81e3a`)** across the dock icon, web, and iOS art.
2. **Welcome pane** — on a fresh launch (no session to restore, no explicit terminal input), the
   initial surface is a branded **welcome pane** instead of an auto-opened terminal: the red logo,
   "better cmux", credits to the original cmux team + this build's maintainer, and a
   **"+ New Terminal"** button. Shown **every** such launch; gated by a default-on setting.
3. **About panel** — add the same credit line + a `github.com/mikeycantcode` link.

## Decisions (confirmed)

- Launch UX: **welcome pane that replaces the auto-opened terminal** (not a separate window).
- Frequency: **every launch** when there is no saved session to restore.
- Icon palette: **bright red → crimson** `#ff5a5a → #ff2d2d → #c81e3a`.
- Original cmux credit points at `https://github.com/manaflow-ai/cmux` (the URL the About panel
  already links). This build credit: `https://github.com/mikeycantcode`.
- Draft credit copy (final wording editable in the view): *"Built on cmux by manaflow-ai — all
  credit to the original team. This build: github.com/mikeycantcode."*

## Non-goals (this spec)

- A separate splash/credits **window** (rejected in favor of the in-pane welcome).
- Onboarding flow / multi-step welcome. The pane is a single static screen.
- Changing session-restore behavior, `cmux open`, or explicit-terminal launches — those keep
  opening terminals as today.
- Reworking the icon **shape** — only the gradient color changes.

## Current state (verified)

- **Icon:** Apple Icon Composer source `AppIcon.icon/` layers a rasterized chevron
  `design/cmux-icon-chevron.png` (blue→purple gradient baked in); the true vector gradient lives in
  `web/public/cmux-icon.svg` (`linearGradient` stops, horizontal axis `x1=91 … x2=179`). Light
  appiconset PNGs are produced by `ictool` from the `.icon`; dark variants by
  `scripts/generate_dark_icon.py`; debug/nightly by `scripts/generate_nightly_icon.py`.
  `ictool` is available (Xcode); no SVG renderer / Pillow / Icon Composer.app installed.
- **Launch:** `Workspace.init` (Sources/Workspace.swift) always creates one terminal surface;
  bonsplit is configured `autoCloseEmptyPanes: true`, `allowCloseLastPane: false` (no empty-pane
  state today). First-run runs a `cmux welcome` CLI command in the terminal, gated by
  `WelcomeSettings.shownKey` (`"cmuxWelcomeShown"`); `AppDelegate.sendWelcomeCommandWhenReady`.
- **Panels:** `Sources/Panels/Panel.swift` defines `protocol Panel` + `enum PanelType`;
  `PanelContentView.swift` dispatches a panel instance → its SwiftUI view; `EditReviewPanel`
  (added recently) is the reference non-terminal `Panel`. New terminal:
  `Workspace.newTerminalSurface(inPane:…)` / `newTerminalSurfaceInFocusedPane(…)`;
  `TabManager.newSurface()`.
- **About:** `AboutWindowController` / `AboutPanelView` in `Sources/cmuxApp.swift` already show the
  icon, version, and a `github.com/manaflow-ai/cmux` link.
- **Display name:** `Resources/Info.plist` `CFBundleDisplayName`/`CFBundleName` = `bettercmux`.

## Components

### A. Icon recolor

- **`web/public/cmux-icon.svg`** — change the three gradient stops to `#ff5a5a` / `#ff2d2d` /
  `#c81e3a` (this is the vector source of truth and feeds web art).
- **Chevron recolor** — recolor the gradient pixels of the chevron art the `.icon` consumes by
  mapping each opaque pixel's position along the horizontal gradient axis to the new red gradient
  (linear interpolation between the three stops), preserving the alpha channel and any glow. A small
  Python script under `scripts/` performs this; it requires an imaging library (Pillow), installed
  into a local venv or via `pip --user` as part of the icon-regeneration step (documented in the
  script header). Position-based remap (not hue-rotation) yields exactly the chosen reds.
- **Regenerate** — run `ictool` to rebuild the light `AppIcon.appiconset` PNGs from `AppIcon.icon`,
  then `scripts/generate_dark_icon.py` for dark variants, then `scripts/generate_nightly_icon.py`
  for the debug/nightly banners (red base, banner unchanged). Regenerate web downscales
  (`web/app/icon.png`, `web/app/apple-icon.png`, `web/app/favicon.ico`, `web/public/logo.png`) and
  `ios/cmux/Assets.xcassets/CmuxLogo.imageset/cmux-logo.svg` from the new master.
- **Risk / fallback:** if `ictool` regeneration from the `.icon` proves unreliable in this
  environment, fall back to recoloring the existing `AppIcon.appiconset` PNGs directly with the same
  position-based remap (light set) + `generate_dark_icon.py` (dark set). Either way the build + a
  visual check confirm the dock icon is red.

### B. Welcome pane

- **`WelcomePanel`** (`Sources/Panels/WelcomePanel.swift`) — a `@MainActor final class … : Panel`
  mirroring `EditReviewPanel`'s non-terminal conformance (focus-intent defaults from the protocol
  extension; `panelType` reuses the closest existing kind; instance-cast dispatch). Holds a
  reference to its workspace/pane so the button can create a terminal in place. No `monacoController`.
- **`WelcomePanelView`** (`Sources/Panels/WelcomePanelView.swift`) — SwiftUI: the app icon image
  (renders red after the recolor), the "better cmux" title, the credit copy with tappable links to
  `github.com/manaflow-ai/cmux` and `github.com/mikeycantcode`, and a prominent **"+ New Terminal"**
  button. The button calls a closure the panel/coordinator wires to
  `workspace.newTerminalSurface(inPane: <this pane>)` then closes the welcome surface (so the
  terminal replaces the welcome tab in the same pane). `⌘T` / the existing new-terminal action also
  work (they create a terminal in the focused pane as today; if that pane holds the welcome surface,
  the welcome surface is replaced).
- **Launch seam** — at the point the initial surface is created for a **fresh** workspace
  (`Workspace.init` / `TabManager.addWorkspace`, in the no-restore + `initialTerminalInput == nil`
  path) and `WelcomePaneSettings.isEnabled()` is true, create a `WelcomePanel` instead of a
  `TerminalPanel`. Session restoration, `initialTerminalInput`, and additional splits create
  terminals normally. The launch-surface decision is a small, unit-testable function:
  `initialSurfaceKind(isFreshLaunch:hasInitialInput:welcomeEnabled:) -> .welcome | .terminal`.
- **`cmux welcome` interplay** — when the welcome pane is enabled, skip the auto
  `sendWelcomeCommandWhenReady` first-run terminal command (there is no terminal to send to). The
  `cmux welcome` CLI command remains available manually and via the Help menu.

### C. About panel credit

- Add a "better cmux" credit line to `AboutPanelView` (Sources/cmuxApp.swift): the same copy as the
  welcome pane, plus a `github.com/mikeycantcode` link button alongside the existing
  `manaflow-ai/cmux` link. Reuse one localized string set across both surfaces.

### D. Setting

- **`general.welcomePaneOnLaunch`** (`Bool`, default **true**) — round-tripped to `cmux.json`,
  visible/editable in Settings + command palette, documented in `cmux.schema.json` and
  `all-keys.md`, localized en+ja. Mirrors the `automation.manualEditDiff` pattern (catalog key +
  Settings row + palette descriptor + a `WelcomePaneSettings` accessor enum + config parser entry).
  Placed in the most fitting existing section (General/Appearance if present, else Automation).

## Data flow

```
launch (fresh window, no restore, no initialTerminalInput)
  Workspace/TabManager initial-surface creation
    initialSurfaceKind(isFreshLaunch: true, hasInitialInput: false,
                        welcomeEnabled: WelcomePaneSettings.isEnabled())
      → .welcome  → create WelcomePanel  (instead of TerminalPanel)
      → .terminal → create TerminalPanel (restore / explicit input / setting off)
  WelcomePanelView shown in the pane
    user clicks "+ New Terminal" (or ⌘T)
      → workspace.newTerminalSurface(inPane: thisPane) ; close the welcome surface
      → terminal now occupies the pane
```

## Localization

New user-facing strings, en + ja: welcome title ("better cmux"), the credit copy, the
"+ New Terminal" button label, the About credit line, and the `general.welcomePaneOnLaunch`
Settings title/subtitle/note. "better cmux" and the GitHub URLs are proper nouns (not translated);
surrounding copy is translated. Update `Resources/Localizable.xcstrings` (minimal splice, both
locales), plus the CmuxSettings catalog, `cmux.schema.json`, and `all-keys.md` for the setting. Run
the localization audit before handoff.

## Testing

- **`initialSurfaceKind(...)`** — pure-function unit tests (Swift Testing): fresh + enabled →
  `.welcome`; fresh + disabled → `.terminal`; has initial input → `.terminal`; not fresh (restore)
  → `.terminal`.
- **`WelcomePanel`** — mirrors `EditReviewPanel`; verify it conforms to `Panel` and the
  "+ New Terminal" action creates a terminal surface and removes the welcome surface (behavioral,
  through the workspace API where reachable; no source-text tests).
- **Icon** — verified by a successful build and a visual check that the dock icon and welcome-pane
  logo render red. Per the test-quality policy, no tests that merely assert PNG/asset bytes or
  source strings.

## Open risks / verify at build time

- **`ictool` regeneration** of the `.icon` → appiconset (see fallback above). Confirm the `.icon`
  bundle's chevron asset location so the recolor targets the file `ictool` actually reads.
- **Welcome-surface replacement** — confirm closing the welcome surface and opening a terminal in
  the same pane is seamless (no flash of an empty pane; bonsplit `allowCloseLastPane: false` means
  the welcome surface must be replaced, not closed-then-created — create the terminal first, then
  close the welcome tab, or reuse the surface slot).
- **Setting section** — place `welcomePaneOnLaunch` in the correct existing Settings section;
  confirm the section exists (General vs Appearance vs Automation) during planning.
- **Icon imaging dependency** — Pillow (or equivalent) must be available to the recolor script;
  document the install in the script and keep it out of the app build (offline asset step).
