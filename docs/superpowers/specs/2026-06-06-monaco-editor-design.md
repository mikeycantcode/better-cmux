# Monaco editor — design

**Date:** 2026-06-06
**Status:** Approved design (pre-implementation)
**Branch:** `monaco-editor`

## Problem

cmux's "open a file to edit" experience is split across two weak paths: the
left-sidebar double-click launches a terminal editor (`micro`, falling back to
`vim`) in a new terminal tab, and the file-preview path opens a basic
NSTextView editor (`FilePreviewPanel` text mode). The user wants a single,
VSCode-grade in-app code editor — Monaco — to replace the terminal editor and
become the text editor everywhere.

## Decisions (locked via Q&A)

1. **Scope — Monaco is THE editor.** Every text-file open path in cmux
   (sidebar double-click, drag-drop onto a pane, right-sidebar, `openFileSurfaces`)
   opens the file in Monaco. The existing NSTextView text editor is retired for
   text. PDF / image / media / QuickLook keep the existing `FilePreviewPanel`
   non-text modes.
2. **Keep micro/vim — yes, behind a setting.** A new `app.codeEditor` preference
   (`monaco` default, `terminal` optional). When `terminal`, the sidebar open
   falls back to the existing micro→vim/custom terminal launch built in the
   bottom-status-bar feature, reusing the existing `terminalEditor` field.
3. **Saving — auto-save.** Edits debounce after typing stops, then write to disk
   atomically. No persistent dirty indicator; flush on tab blur/close.
4. **Smarts — syntax + find/replace only.** Monaco's built-in syntax highlighting
   (~100 languages), find/replace, minimap, bracket matching, multi-cursor, theme
   matching. **No** language-server IntelliSense in v1.

## Feasibility finding (drives architecture)

A 6-way subsystem map (surface/pane model, WKWebView infra, file-open paths,
editor settings, bundled-asset pipeline, file write/watch) established that
cmux already has every piece Monaco needs:

- **An in-app text editor already exists and is fully wired.**
  `FilePreviewPanel` (`Sources/Panels/FilePreviewPanel.swift`) has a `text` mode
  (one of `text|pdf|image|media|quickLook`, `FilePreviewMode`) backed by
  `FilePreviewTextEditor` (NSTextView). It already does: async load with encoding
  detection (`FilePreviewTextLoader`, utf8→utf16→isoLatin1, 16 MB cap, ~line
  900–947), write-back on Cmd+S (`FilePreviewTextSaver.save()`, ~line 949–969,
  currently **non-atomic** `data.write(options:[])`), dirty tracking
  (`isDirty`, ~line 1139), `FileWatcher`-driven external-change reload that
  preserves dirty edits, dedup by resolved path, session snapshot/restore, and
  both sidebar callbacks route to it via `openFileSurfaces`
  (`Sources/Panels/FilePreviewWorkspaceOpenSupport.swift:6-66`).
- **Bundled web assets are a solved pattern.** `Resources/markdown-viewer/`
  ships HTML/CSS/JS into the app bundle (pbxproj `PBXResourcesBuildPhase`),
  loaded at runtime via `MarkdownViewerAssets`
  (`Bundle.url(forResource:withExtension:subdirectory:)`, optional `.deflate`
  decompression) and served to a `WKWebView` either via `loadHTMLString` with
  placeholder substitution (`shell.html`) or a custom `WKURLSchemeHandler`
  (`cmux-local-image`, `cmux-remote-image`, and `CmuxDiffViewerURLSchemeHandler`
  in `BrowserPanel.swift:2558-2701`). A build-phase script
  (`scripts/compress-markdown-viewer-assets.sh`) compresses assets.
- **A simple web-host precedent exists.** `MarkdownWebRenderer`
  (`Sources/Panels/MarkdownWebRenderer.swift`) is an `NSViewRepresentable` +
  `WKWebView` with a `cmuxLib` `WKScriptMessageHandler` and two URL scheme
  handlers — *without* the heavy `BrowserWindowPortal` system the browser uses.
  Monaco follows this lighter pattern.
- **Surface-key routing precedent exists** for letting a web surface keep its own
  shortcuts while cmux-global shortcuts still win
  (`AppDelegate.handleBrowserSurfaceKeyEquivalent` / `handleBrowserFocusModeKeyEvent`,
  `CmuxWebView.performKeyEquivalent` ~line 621).

**Therefore: do not build a new surface type.** Swap `FilePreviewPanel`'s text
mode *view* (NSTextView → Monaco WKWebView) and reuse all surrounding
infrastructure. This is the smallest, lowest-risk change that satisfies Scope A
(Monaco everywhere) because every text-open path already funnels through
`FilePreviewPanel`.

## Goals

1. Text files open in a Monaco editor inside a cmux tab, with syntax
   highlighting, find/replace, minimap, multi-cursor, and theme matching cmux's
   appearance.
2. Auto-save edits to disk (atomic), preserving encoding, without a reload loop.
3. A `Code editor` setting choosing Monaco (default) vs the terminal editor.
4. Reuse the existing surface/tab/session/sidebar/file-watch infrastructure;
   add only the web-host, asset pipeline, bridge, and setting.

## Non-goals (v1)

- Language-server IntelliSense / autocomplete / go-to-definition (large,
  multi-phase; would ship syntax-only first regardless).
- Remote / SSH file editing (stays on the existing path; the current double-click
  already guards `LocalFileExplorerProvider`).
- Replacing the rendered Markdown viewer (`MarkdownPanel`) — `.md` keeps it.
- Monaco web-inspector / DevTools.
- Multi-file project model, tabs-within-editor, or a file tree inside Monaco
  (cmux's own sidebar + tabs provide that).

## Architecture

New folder `Sources/Monaco/` (one type per file), wired into the cmux app target
+ (for testable seams) the cmux-unit test target. New `Resources/monaco/` for
the vendored distribution.

### 1. Web host — `MonacoEditorView` + `MonacoWebController`
- `MonacoEditorView`: `NSViewRepresentable` hosting a `WKWebView`, modeled on
  `MarkdownWebRenderer` (simple host; **not** `BrowserWindowPortal`). Owns the
  web view lifecycle, removes script message handlers in `dismantleNSView`
  (leak-safe, mirroring `MarkdownWebRenderer`).
- `MonacoWebController` (`@MainActor`): configures `WKWebViewConfiguration` with
  the asset scheme handler + a `WKScriptMessageHandler` named `cmuxMonacoBridge`;
  loads `cmux-monaco://app/monaco.html`; exposes `load(text:language:theme:)`,
  `applyExternalChange(text:)`, `setTheme(_:)`, `focus()`, and
  `flushSave() async` (force-flush any pending debounced save before close).

### 2. JS ↔ Swift bridge — `MonacoBridgeMessage`
- A pure, `Sendable`, `Codable` value type + parser modeling messages from JS:
  `.ready`, `.change(content:)`, `.requestSave(content:)`, `.focus`, `.blur`.
  Parsing is a pure function over the `WKScriptMessage` body dict → **unit
  tested** without a web view.
- Swift→JS calls go through `evaluateJavaScript` to a global `cmuxMonaco` object
  defined in the shell: `cmuxMonaco.setContent`, `applyExternalChange`,
  `setTheme`, `focus`, `flushSave`.
- JS→Swift: `window.webkit.messageHandlers.cmuxMonacoBridge.postMessage({...})`.

### 3. Asset pipeline — `MonacoAssets` + `MonacoAssetURLSchemeHandler`
- Vendor the pinned `monaco-editor` `min/vs` build into `Resources/monaco/vs/`,
  plus a hand-written `Resources/monaco/monaco.html` shell and a
  `Resources/monaco/VERSION` recording the pinned version. Commit the
  distribution (matching the `markdown-viewer` precedent of committed libs).
- `MonacoAssets`: bundle lookup via
  `Bundle.url(forResource:withExtension:subdirectory:)` rooted at `monaco`,
  modeled on `MarkdownViewerAssets`. v1 serves files **uncompressed** (Monaco is
  already minified); deflate compression is a later optimization.
- `MonacoAssetURLSchemeHandler` (conforms `WKURLSchemeHandler`): serves
  `cmux-monaco://app/<path>` from the bundle with correct MIME types, modeled on
  `CmuxDiffViewerURLSchemeHandler` (`webView(_:start:)` → `didReceive(response)`
  / `didReceiveData` / `didFinish`; `webView(_:stop:)`). Path-normalize and
  reject traversal outside the bundle root.
- `monaco.html` shell: loads `vs/loader.js`, configures the AMD `require`
  baseUrl to `cmux-monaco://app/vs`, creates the editor on `ready`, wires
  change/save/focus/blur events to `cmuxMonacoBridge`, and exposes the global
  `cmuxMonaco` API for Swift→JS calls. Auto-save debounce (~600 ms) lives in JS;
  Cmd+S issues an immediate `requestSave`.

### 4. FilePreviewPanel retrofit (the integration)
- In `FilePreviewPanel` text mode, render `MonacoEditorView` instead of
  `FilePreviewTextEditor` (NSTextView), **except** when the file exceeds a
  large-file threshold (~2 MB) — then keep NSTextView (Monaco lags on multi-MB
  files). The NSTextView path stays as a fallback only.
- Loading: keep `FilePreviewTextLoader` (encoding detection, 16 MB cap). Pass the
  loaded text + detected encoding + a Monaco language id into the controller.
- Saving (auto-save):
  - JS posts debounced `change(content)`; the panel writes via a new
    **atomic** saver (temp file + rename, `data.write(options:[.atomic])`,
    matching `SessionPersistence`), preserving the loaded encoding.
  - **Self-write suppression:** record a hash of the last-written content; when
    the `FileWatcher` fires, skip reload if the on-disk content hash equals the
    last write (avoids the write→watch→reload loop).
  - **Flush on blur/close:** controller `flushSave()` is awaited before the panel
    closes / loses focus so no debounced edit is lost.
  - Dirty state: auto-save means the tab does not show a persistent dirty dot;
    `isDirty` stays false except for the brief in-flight window (closing never
    prompts).
- External change with no pending edits → `applyExternalChange(text)` reloads the
  buffer; mid-edit external change → buffer wins (last-write-wins).

### 5. Language + theme
- `MonacoLanguageMap`: a pure extension→Monaco-language-id map (e.g. `.swift` →
  `swift`, `.ts` → `typescript`, default `plaintext`), **unit tested**. The shell
  may also fall back to Monaco's built-in extension matching; the Swift map keeps
  it deterministic and testable.
- Theme: read cmux's effective appearance (light/dark from `AppearanceSettings`);
  pass `vs` / `vs-dark`; update live via `setTheme` on appearance change.

### 6. Keyboard routing
- When the Monaco web view is first responder, an **allowlist** of in-editor
  shortcuts (Cmd+F, Cmd+S, Cmd+/, Cmd+D, Cmd+], Cmd+[, Cmd+Shift+K, etc.) reaches
  the web view; cmux-global shortcuts (new tab/close, pane/window switching) win.
  Implemented by reusing the browser surface-key routing pattern
  (`handleBrowserSurfaceKeyEquivalent`). Cmd+S maps to an immediate save.

### 7. Settings — `app.codeEditor`
- New enum-valued preference: `monaco` (default) | `terminal`.
- Surfaced through every required layer (shared-behavior policy):
  - `Packages/CmuxSettings` `AppCatalogSection` — a `DefaultsKey<String>`
    (`id: "app.codeEditor"`, `userDefaultsKey: "codeEditor"`, default `"monaco"`).
  - `Packages/CmuxSettingsUI` `AppSection` — a picker (Monaco / Terminal editor),
    placed next to the existing `terminalEditor` row; the `terminalEditor` field
    stays (used when `terminal`).
  - `Sources/KeyboardShortcutSettingsFileStore.swift` `parseAppSection` — parse
    `codeEditor` from `cmux.json`, validate against the enum, store in managed
    UserDefaults.
  - `Sources/CmuxSettingsJSONPathSupport.swift` — add `app.codeEditor`.
  - `web/data/cmux.schema.json` — `codeEditor` string enum + description.
  - `Resources/Localizable.xcstrings` — en + ja for label/subtitle/options.
- A small `CodeEditorPreferenceSettings` helper (string enum + `resolved(defaults:)`)
  reads the setting, **unit tested**.

### 8. Open-path rewiring (`Sources/ContentView.swift`)
- Sidebar double-click currently → `openSidebarFileInEditor` (micro/vim terminal).
  Change to branch on `app.codeEditor`:
  - `monaco` → `openFilePreviewFromSidebar` / `openFileSurfaces` (now yields
    Monaco for text).
  - `terminal` → existing `openSidebarFileInEditor` (micro→vim/custom).
- Bottom-bar editor indicator (`refreshBottomBarEditorName`): show `"Monaco"`
  when `codeEditor == monaco`, else the resolved terminal editor name.

## Deliberate defaults (open to change in review)

1. `.md` files keep the rendered `MarkdownPanel` (already renders + edits +
   saves). Monaco handles all other text. Flipping `.md` → Monaco is a one-line
   change in `openFileSurfaces` routing.
2. Large files (~>2 MB) keep the NSTextView editor as a fallback.

## Performance & constraints

- Web view created lazily when a text file opens; assets served from bundle (no
  network, no local HTTP server — scheme handler only).
- Auto-save debounced in JS; disk writes off-main and atomic; self-write reload
  suppression via content hash.
- New types follow Swift 6 concurrency (`@MainActor` controller, `actor`/async
  saver, `AsyncStream`/`@Observable` where new state is needed; no
  locks/Combine/`DispatchQueue.main.async` in new code). Existing
  `FilePreviewPanel` (an `ObservableObject`) is modified minimally, not rewritten.
- Pure seams (`MonacoBridgeMessage` parse, `MonacoLanguageMap`,
  `CodeEditorPreferenceSettings.resolved`, atomic-save encoding round-trip,
  bottom-bar editor-name resolution) are unit tested without a web view or app
  launch, per the testability + test-quality policies (behavior, not source
  text or plist assertions).
- New `Sources/Monaco/**` files + `Resources/monaco/**` wired into pbxproj
  (app target; test seams reachable from `cmux-unit`); run
  `scripts/normalize-pbxproj.py` + `scripts/check-pbxproj.sh`.

## Known-tricky areas (flagged, with a plan)

- **Keyboard routing:** editor-shortcut allowlist + browser surface-key pattern.
- **Web-view render state on split/reattach:** follow `MarkdownWebRenderer`
  (works without the portal); revisit only if blanking appears.
- **Auto-save ↔ file-watcher loop:** content-hash self-write suppression.
- **Encoding fidelity:** preserve the loaded encoding on save (don't force utf8).
- **Bundle size:** Monaco `min/vs` is several MB; v1 vendors it uncompressed,
  with deflate compression available later via the existing compress script.

## Files touched

**New:**
- `Resources/monaco/vs/**` (vendored pinned `monaco-editor` `min/vs`),
  `Resources/monaco/monaco.html`, `Resources/monaco/VERSION`.
- `Sources/Monaco/MonacoEditorView.swift`
- `Sources/Monaco/MonacoWebController.swift`
- `Sources/Monaco/MonacoAssets.swift`
- `Sources/Monaco/MonacoAssetURLSchemeHandler.swift`
- `Sources/Monaco/MonacoBridgeMessage.swift`
- `Sources/Monaco/MonacoLanguageMap.swift`
- `Sources/Monaco/MonacoAtomicTextSaver.swift`
- `Sources/Monaco/CodeEditorPreferenceSettings.swift`
- Tests: `cmuxTests/MonacoBridgeMessageTests.swift`,
  `cmuxTests/MonacoLanguageMapTests.swift`,
  `cmuxTests/CodeEditorPreferenceSettingsTests.swift`,
  `cmuxTests/MonacoAtomicTextSaverTests.swift`.

**Modified:**
- `Sources/Panels/FilePreviewPanel.swift` + `FilePreviewPanelView.swift`
  (text mode → Monaco; NSTextView large-file fallback; atomic save; self-write
  suppression).
- `Sources/ContentView.swift` (sidebar double-click gate on `app.codeEditor`;
  bottom-bar editor name).
- `Packages/CmuxSettings/.../AppCatalogSection.swift`,
  `Packages/CmuxSettingsUI/.../AppSection.swift`,
  `Sources/KeyboardShortcutSettingsFileStore.swift`,
  `Sources/CmuxSettingsJSONPathSupport.swift`,
  `web/data/cmux.schema.json`,
  `Resources/Localizable.xcstrings` (en + ja).
- `cmux.xcodeproj/project.pbxproj` (new sources + resources, both targets).

## Sequencing

1. Vendor Monaco assets + `monaco.html` shell + asset scheme handler; render a
   static Monaco in a throwaway harness / the panel to prove asset loading.
2. `MonacoEditorView` + `MonacoWebController` + `MonacoBridgeMessage`; load file
   text into Monaco (read-only round-trip).
3. Auto-save: debounced change → atomic saver → self-write suppression → flush on
   close. Encoding fidelity.
4. Language map + theme matching + keyboard routing allowlist.
5. `FilePreviewPanel` retrofit (text mode → Monaco; large-file fallback).
6. `app.codeEditor` setting end-to-end (catalog, UI, cmux.json, schema, paths,
   localization) + sidebar double-click rewire + bottom-bar indicator.
7. Tests for all pure seams; localization audit.

## Open questions for the plan stage

- Exact pinned `monaco-editor` version and the minimal `min/vs` subset to vendor
  (full vs trimmed languages) to balance features vs bundle size.
- Precise large-file threshold and how to detect it pre-load (file size stat).
- Whether the auto-save debounce/interval should be configurable (default: not in
  v1; hardcode ~600 ms).
- Exact in-editor keyboard allowlist and any conflicts with existing cmux global
  shortcuts.
