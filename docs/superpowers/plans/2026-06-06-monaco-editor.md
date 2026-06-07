# Monaco Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace micro/vim + the NSTextView text editor with a bundled Monaco WKWebView editor, retrofitted into `FilePreviewPanel`'s text mode, with auto-save and a `Code editor` setting.

**Architecture:** Vendor Monaco's `min/vs` into `Resources/monaco/`, serve it to a `WKWebView` via a custom URL-scheme handler, host that web view with an `NSViewRepresentable` (mirroring `Sources/Panels/MarkdownWebRenderer.swift`), and swap `FilePreviewPanel`'s text-mode view from `FilePreviewTextEditor` (NSTextView) to the new `MonacoEditorView`. A JS↔Swift bridge drives load/auto-save/theme. A new `app.codeEditor` setting (`monaco` default | `terminal`) routes the sidebar double-click and bottom-bar indicator.

**Tech Stack:** Swift 6 / SwiftUI / AppKit / WebKit (`WKWebView`, `WKURLSchemeHandler`, `WKScriptMessageHandler`), Monaco Editor (`monaco-editor` npm `min/vs` AMD build), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-06-06-monaco-editor-design.md`

**Reference files (read before starting the relevant task):**
- `Sources/Panels/MarkdownWebRenderer.swift` — the web-host pattern to mirror (Coordinator is `WKNavigationDelegate`/`WKUIDelegate`/`WKScriptMessageHandler`/`WKURLSchemeHandler`; `loadHTMLString` + baseURL; web-content-process recovery; `applyAppearance`).
- `Sources/Panels/MarkdownViewerAssets.swift` — bundle asset lookup pattern (`Bundle.url(forResource:withExtension:subdirectory:)`, `.deflate` decompression).
- `Sources/Panels/BrowserPanel.swift:2558-2701` — `CmuxDiffViewerURLSchemeHandler`, the `WKURLSchemeHandler` file-streaming pattern.
- `Sources/Panels/FilePreviewPanel.swift` — text mode (`FilePreviewMode`), `FilePreviewTextLoader` (~900-947), `FilePreviewTextSaver` (~949-969), `isDirty` (~1139), watcher reload.
- `Sources/Panels/FilePreviewPanelView.swift` + `Sources/Panels/FilePreviewTextEditor.swift` — current text-mode view + `SavingTextView` Cmd+S handling.
- `Sources/StatusBar/EditorLauncher.swift`, `EditorPreferenceSettings.swift` — terminal editor resolution + bottom-bar display name.
- `Sources/ContentView.swift` — `openSidebarFileInEditor` (~2211), `openFilePreviewFromSidebar` (~2639), `refreshBottomBarEditorName` (~2203).
- `Packages/CmuxSettings/Sources/CmuxSettings/Keys/AppCatalogSection.swift` (~70-74 `terminalEditor`), `Packages/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/AppSection.swift` (~284-296 terminalEditor row).
- `cmux.xcodeproj/project.pbxproj` — `markdown-viewer` resource entry (PBXResourcesBuildPhase) + an existing `Sources/StatusBar/*` file for the source-wiring shape.

**pbxproj policy (every task that adds a file):** add the four entries (PBXFileReference, PBXBuildFile, group child, and Sources/Resources build-phase membership). App-target source files link into **both** `cmux` and `cmux-unit`. Use valid 24-char UPPERCASE-HEX object IDs. After editing, run `python3 scripts/normalize-pbxproj.py cmux.xcodeproj/project.pbxproj` and `./scripts/check-pbxproj.sh`. Test files in `cmuxTests/` need `./scripts/lint-pbxproj-test-wiring.sh` to pass.

**Build verification (controller-run, between phases):** implementers DO NOT build. The controller runs, with a unique tag:
```
CMUX_SKIP_ZIG_BUILD=1 xcodebuild -project cmux.xcodeproj -scheme cmux-unit -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-monaco build-for-testing
```
(`CMUX_SKIP_ZIG_BUILD=1` because the prebuilt GhosttyKit.xcframework is present; the local zig is 0.16.0 but the build pins 0.15.2.) Never run bare `xcodebuild`/`open` on an untagged app. Tests run on CI/VM, never locally.

**Localization:** every user-facing string gets en + ja in `Resources/Localizable.xcstrings` via `String(localized:defaultValue:)`. A localization audit is part of the final task.

---

## Phase 0 — Vendor Monaco + asset pipeline

### Task 1: Vendor Monaco distribution + HTML shell

**Files:**
- Create: `Resources/monaco/vs/**` (vendored), `Resources/monaco/VERSION`, `Resources/monaco/monaco.html`
- Create: `scripts/vendor-monaco.sh`

- [ ] **Step 1: Write `scripts/vendor-monaco.sh`** — reproducible vendoring (pin the version):

```bash
#!/usr/bin/env bash
set -euo pipefail
# Vendors monaco-editor's min/vs build into Resources/monaco/vs.
# Re-run to bump the version (edit MONACO_VERSION).
MONACO_VERSION="0.55.1"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Resources/monaco"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
npm pack "monaco-editor@${MONACO_VERSION}" >/dev/null
tar -xzf "monaco-editor-${MONACO_VERSION}.tgz"
rm -rf "$DEST/vs"
mkdir -p "$DEST"
cp -R "package/min/vs" "$DEST/vs"
echo "$MONACO_VERSION" > "$DEST/VERSION"
echo "Vendored monaco-editor ${MONACO_VERSION} -> $DEST/vs"
```

- [ ] **Step 2: Run it**

Run: `chmod +x scripts/vendor-monaco.sh && ./scripts/vendor-monaco.sh`
Expected: `Resources/monaco/vs/loader.js`, `Resources/monaco/vs/editor/editor.main.js` (+ `.css`, `base/`, `basic-languages/`, `language/`) exist; `Resources/monaco/VERSION` contains `0.55.1`.
Verify: `ls Resources/monaco/vs/loader.js Resources/monaco/vs/editor/editor.main.js Resources/monaco/VERSION`

- [ ] **Step 3: Write `Resources/monaco/monaco.html`** — the shell. Loads the AMD loader from the custom scheme, neutralizes web workers (v1 syntax-only — avoids cross-scheme worker failures), creates a read-only-capable editor, and wires the bridge:

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8" />
  <style>
    html, body, #container { height: 100%; margin: 0; padding: 0; overflow: hidden; }
    body { background: transparent; }
  </style>
  <link rel="stylesheet" href="cmux-monaco://app/vs/editor/editor.main.css" />
</head>
<body>
  <div id="container"></div>
  <script>
    // Syntax-only: route every Monaco worker to an inert no-op worker so the
    // editor never tries to fetch a real worker over the custom scheme (which
    // WebKit blocks). Tokenization for highlighting runs on the main thread.
    var NOOP_WORKER = URL.createObjectURL(new Blob(["self.onmessage=function(){};"], {type:"text/javascript"}));
    self.MonacoEnvironment = { getWorkerUrl: function(){ return NOOP_WORKER; } };

    function post(msg){ try { window.webkit.messageHandlers.cmuxMonacoBridge.postMessage(msg); } catch(e){} }
  </script>
  <script src="cmux-monaco://app/vs/loader.js"></script>
  <script>
    require.config({ baseUrl: "cmux-monaco://app/vs" });
    require(["vs/editor/editor.main"], function () {
      var editor = monaco.editor.create(document.getElementById("container"), {
        value: "",
        language: "plaintext",
        theme: "vs-dark",
        automaticLayout: true,
        minimap: { enabled: true },
        scrollBeyondLastLine: false,
        fontLigatures: true
      });

      var suppressChange = false;     // true while we apply content from Swift
      var saveTimer = null;
      var SAVE_DEBOUNCE_MS = 600;

      function scheduleSave(){
        if (saveTimer) clearTimeout(saveTimer);
        saveTimer = setTimeout(function(){
          saveTimer = null;
          post({ type: "change", content: editor.getValue() });
        }, SAVE_DEBOUNCE_MS);
      }

      editor.onDidChangeModelContent(function(){
        if (suppressChange) return;
        scheduleSave();
      });
      editor.onDidFocusEditorWidget(function(){ post({ type: "focus" }); });
      editor.onDidBlurEditorWidget(function(){ post({ type: "blur" }); });

      // Cmd+S -> immediate save (even in auto-save mode).
      editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, function(){
        if (saveTimer) { clearTimeout(saveTimer); saveTimer = null; }
        post({ type: "requestSave", content: editor.getValue() });
      });

      // Swift -> JS API.
      window.cmuxMonaco = {
        setContent: function(text, language, theme){
          suppressChange = true;
          var model = editor.getModel();
          if (model) {
            model.setValue(text);
            if (language) monaco.editor.setModelLanguage(model, language);
          } else {
            editor.setValue(text);
          }
          if (theme) monaco.editor.setTheme(theme);
          suppressChange = false;
        },
        applyExternalChange: function(text){
          suppressChange = true;
          var pos = editor.getPosition();
          editor.getModel().setValue(text);
          if (pos) editor.setPosition(pos);
          suppressChange = false;
        },
        setTheme: function(theme){ monaco.editor.setTheme(theme); },
        focus: function(){ editor.focus(); },
        flushSave: function(){
          if (saveTimer) { clearTimeout(saveTimer); saveTimer = null; }
          post({ type: "requestSave", content: editor.getValue() });
        }
      };

      post({ type: "ready" });
    });
  </script>
</body>
</html>
```

- [ ] **Step 4: Commit**

```bash
git add scripts/vendor-monaco.sh Resources/monaco
git commit -m "Monaco: vendor min/vs distribution + HTML shell"
```

> Note: no unit test here (asset vendoring). The load is verified end-to-end in Task 6.

---

### Task 2: Monaco asset lookup + URL scheme handler

**Files:**
- Create: `Sources/Monaco/MonacoAssets.swift`
- Create: `Sources/Monaco/MonacoAssetURLSchemeHandler.swift`
- Test: `cmuxTests/MonacoAssetURLSchemeHandlerTests.swift`

- [ ] **Step 1: Write the failing test** (pure seams: MIME mapping + traversal rejection)

```swift
import Testing
@testable import cmux  // adjust import guard to match sibling tests

@Suite struct MonacoAssetURLSchemeHandlerTests {
    @Test func mimeTypeForKnownExtensions() {
        #expect(MonacoAssetMime.mimeType(forPathExtension: "js") == "text/javascript")
        #expect(MonacoAssetMime.mimeType(forPathExtension: "css") == "text/css")
        #expect(MonacoAssetMime.mimeType(forPathExtension: "html") == "text/html")
        #expect(MonacoAssetMime.mimeType(forPathExtension: "ttf") == "font/ttf")
        #expect(MonacoAssetMime.mimeType(forPathExtension: "svg") == "image/svg+xml")
        #expect(MonacoAssetMime.mimeType(forPathExtension: "xyz") == "application/octet-stream")
    }

    @Test func rejectsPathTraversal() {
        let root = URL(fileURLWithPath: "/bundle/monaco", isDirectory: true)
        #expect(MonacoAssetPath.resolve(relativePath: "vs/loader.js", under: root)?.path == "/bundle/monaco/vs/loader.js")
        #expect(MonacoAssetPath.resolve(relativePath: "../secret", under: root) == nil)
        #expect(MonacoAssetPath.resolve(relativePath: "vs/../../etc/passwd", under: root) == nil)
    }
}
```

- [ ] **Step 2: Run test, verify it fails** (types undefined). Expected: compile failure.

- [ ] **Step 3: Implement `MonacoAssets.swift`**

```swift
import Foundation

/// Locates the bundled Monaco distribution (`Resources/monaco`) inside the app bundle.
enum MonacoAssets {
    /// The on-disk URL of the vendored Monaco root (`.../monaco`), or nil if missing.
    static func rootURL(bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "monaco", withExtension: nil)
    }
}

/// MIME types for the asset scheme handler.
enum MonacoAssetMime {
    static func mimeType(forPathExtension ext: String) -> String {
        switch ext.lowercased() {
        case "js", "mjs": return "text/javascript"
        case "css": return "text/css"
        case "html": return "text/html"
        case "json": return "application/json"
        case "ttf": return "font/ttf"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "map": return "application/json"
        default: return "application/octet-stream"
        }
    }
}

/// Resolves a request path under a root, rejecting traversal escapes.
enum MonacoAssetPath {
    static func resolve(relativePath: String, under root: URL) -> URL? {
        let trimmed = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
        let candidate = root.appendingPathComponent(trimmed).standardizedFileURL
        let rootStd = root.standardizedFileURL
        let rootPrefix = rootStd.path.hasSuffix("/") ? rootStd.path : rootStd.path + "/"
        guard candidate.path == rootStd.path || candidate.path.hasPrefix(rootPrefix) else { return nil }
        return candidate
    }
}
```

- [ ] **Step 4: Implement `MonacoAssetURLSchemeHandler.swift`** (mirror `CmuxDiffViewerURLSchemeHandler` streaming)

```swift
import Foundation
import WebKit

/// Serves the bundled Monaco distribution over `cmux-monaco://app/<path>`.
@MainActor
final class MonacoAssetURLSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "cmux-monaco"

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let root = MonacoAssets.rootURL() else {
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL))
            return
        }
        // cmux-monaco://app/vs/loader.js  ->  relative path "vs/loader.js"
        let relative = url.path
        guard let fileURL = MonacoAssetPath.resolve(relativePath: relative, under: root),
              let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist))
            return
        }
        let mime = MonacoAssetMime.mimeType(forPathExtension: fileURL.pathExtension)
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": mime, "Content-Length": String(data.count)]
        )!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
```

- [ ] **Step 5: Wire pbxproj** for the two `Sources/Monaco/*.swift` (both `cmux` + `cmux-unit`) and the test file (`cmuxTests`). Normalize + check.

- [ ] **Step 6: Run test, verify it passes** (CI/controller build). Expected: PASS.

- [ ] **Step 7: Commit** `git add -A && git commit -m "Monaco: bundled asset lookup + URL scheme handler"`

---

### Task 3: Bundle `Resources/monaco` into the app

**Files:** Modify `cmux.xcodeproj/project.pbxproj`

- [ ] **Step 1:** Add `Resources/monaco` as a folder reference in the `cmux` target's `PBXResourcesBuildPhase`, mirroring the `markdown-viewer` entry (a blue folder reference so the whole tree copies to `Contents/Resources/monaco`). Use a fresh 24-hex ID for the `PBXFileReference` (`lastKnownFileType = folder;`) and the `PBXBuildFile`.

- [ ] **Step 2:** Normalize + check: `python3 scripts/normalize-pbxproj.py cmux.xcodeproj/project.pbxproj && ./scripts/check-pbxproj.sh`

- [ ] **Step 3: Commit** `git commit -am "Monaco: copy Resources/monaco into the app bundle"`

> Controller checkpoint build after Task 3.

---

## Phase 1 — Web host + bridge (read-only round trip)

### Task 4: `MonacoBridgeMessage` (JS→Swift parser)

**Files:**
- Create: `Sources/Monaco/MonacoBridgeMessage.swift`
- Test: `cmuxTests/MonacoBridgeMessageTests.swift`

- [ ] **Step 1: Failing test**

```swift
import Testing
@testable import cmux

@Suite struct MonacoBridgeMessageTests {
    @Test func parsesReady() {
        #expect(MonacoBridgeMessage(body: ["type": "ready"]) == .ready)
    }
    @Test func parsesChangeAndSave() {
        #expect(MonacoBridgeMessage(body: ["type": "change", "content": "abc"]) == .change(content: "abc"))
        #expect(MonacoBridgeMessage(body: ["type": "requestSave", "content": "x"]) == .requestSave(content: "x"))
    }
    @Test func parsesFocusBlur() {
        #expect(MonacoBridgeMessage(body: ["type": "focus"]) == .focus)
        #expect(MonacoBridgeMessage(body: ["type": "blur"]) == .blur)
    }
    @Test func rejectsUnknownAndMalformed() {
        #expect(MonacoBridgeMessage(body: ["type": "nope"]) == nil)
        #expect(MonacoBridgeMessage(body: ["type": "change"]) == nil) // missing content
        #expect(MonacoBridgeMessage(body: [:]) == nil)
    }
}
```

- [ ] **Step 2: Verify it fails** (type undefined).

- [ ] **Step 3: Implement**

```swift
import Foundation

/// A message posted from the Monaco shell JS to Swift via `cmuxMonacoBridge`.
enum MonacoBridgeMessage: Equatable, Sendable {
    case ready
    case change(content: String)
    case requestSave(content: String)
    case focus
    case blur

    /// Parses a `WKScriptMessage.body` dictionary. Returns nil for anything
    /// unrecognized or missing required fields.
    init?(body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "ready": self = .ready
        case "focus": self = .focus
        case "blur": self = .blur
        case "change":
            guard let c = dict["content"] as? String else { return nil }
            self = .change(content: c)
        case "requestSave":
            guard let c = dict["content"] as? String else { return nil }
            self = .requestSave(content: c)
        default: return nil
        }
    }
}
```

- [ ] **Step 4: pbxproj wiring** (source both targets + test). Normalize + check.
- [ ] **Step 5: Verify pass.**
- [ ] **Step 6: Commit** `Monaco: JS->Swift bridge message model`

---

### Task 5: `MonacoLanguageMap` (extension → Monaco language id)

**Files:**
- Create: `Sources/Monaco/MonacoLanguageMap.swift`
- Test: `cmuxTests/MonacoLanguageMapTests.swift`

- [ ] **Step 1: Failing test**

```swift
import Testing
@testable import cmux

@Suite struct MonacoLanguageMapTests {
    @Test func mapsCommonExtensions() {
        #expect(MonacoLanguageMap.languageId(forPath: "/a/b/Foo.swift") == "swift")
        #expect(MonacoLanguageMap.languageId(forPath: "x.ts") == "typescript")
        #expect(MonacoLanguageMap.languageId(forPath: "x.tsx") == "typescript")
        #expect(MonacoLanguageMap.languageId(forPath: "x.py") == "python")
        #expect(MonacoLanguageMap.languageId(forPath: "x.json") == "json")
        #expect(MonacoLanguageMap.languageId(forPath: "Makefile") == "makefile")
        #expect(MonacoLanguageMap.languageId(forPath: "Dockerfile") == "dockerfile")
    }
    @Test func defaultsToPlaintext() {
        #expect(MonacoLanguageMap.languageId(forPath: "x.unknownext") == "plaintext")
        #expect(MonacoLanguageMap.languageId(forPath: "noext") == "plaintext")
    }
}
```

- [ ] **Step 2: Verify it fails.**
- [ ] **Step 3: Implement** — an extension→id table plus a few filename specials (`Makefile`, `Dockerfile`, `.gitignore`→`plaintext`). Cover the ~40 most common languages; default `plaintext`. (Single enum with a static `[String:String]` and a `languageId(forPath:)` that checks the leaf filename then the lowercased extension.)
- [ ] **Step 4: pbxproj wiring + normalize + check.**
- [ ] **Step 5: Verify pass.**
- [ ] **Step 6: Commit** `Monaco: extension -> language id map`

---

### Task 6: `MonacoEditorView` + `MonacoWebController` (load + theme + focus)

**Files:**
- Create: `Sources/Monaco/MonacoWebController.swift`
- Create: `Sources/Monaco/MonacoEditorView.swift`

**Read first:** `Sources/Panels/MarkdownWebRenderer.swift` (mirror its structure precisely).

- [ ] **Step 1: Implement `MonacoWebController`** — `@MainActor final class`. Holds the `WKWebView`, conforms to `WKNavigationDelegate` + `WKScriptMessageHandler`. Responsibilities:
  - `makeWebView()`: build `WKWebViewConfiguration`, `config.setURLSchemeHandler(MonacoAssetURLSchemeHandler(), forURLScheme: "cmux-monaco")`, `config.userContentController.add(self, name: "cmuxMonacoBridge")`, create the web view, set transparent background + appearance (copy `applyAppearance`/`applyBackground` from `MarkdownWebRenderer`), `#if DEBUG isInspectable = true`, `loadHTMLString` is **not** used — instead load `URLRequest(url: URL(string: "cmux-monaco://app/monaco.html")!)` so the AMD loader's relative requests resolve against the scheme. (The `monaco.html` itself is served by the scheme handler.)
  - State: `private var isReady = false`, `pendingLoad: (text: String, language: String, theme: String)?`.
  - `load(text:language:theme:)`: store as pending; if `isReady`, call `cmuxMonaco.setContent(...)` via `evaluateJavaScript` with JSON-encoded args (use the `JSONSerialization.data(withJSONObject: [text])` → `[0]` trick from `MarkdownWebRenderer.renderMarkdownScript` to escape safely).
  - `setTheme(_:)`, `focus()` → `evaluateJavaScript`.
  - `flushSave() async` → `evaluateJavaScript("window.cmuxMonaco && window.cmuxMonaco.flushSave();")` then await a short confirmation (or just fire-and-forget + return; the resulting `requestSave` message will be handled synchronously on main before close).
  - `WKScriptMessageHandler`: parse via `MonacoBridgeMessage(body:)`; on `.ready` set `isReady`, replay `pendingLoad`; forward `.change`/`.requestSave`/`.focus`/`.blur` to injected closures (`onChange: (String)->Void`, `onRequestSave: (String)->Void`, `onFocus/onBlur`).
  - Web-content-process recovery: copy the `webViewWebContentProcessDidTerminate` reload pattern (reload the request, replay `pendingLoad` on `didFinish`/`ready`).
  - `dismantle()`: `removeScriptMessageHandler(forName: "cmuxMonacoBridge")`, nil delegates, stopLoading.

```swift
import AppKit
import WebKit

@MainActor
final class MonacoWebController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private(set) var webView: WKWebView?
    private var isReady = false
    private var pendingLoad: (text: String, language: String, theme: String)?

    var onChange: ((String) -> Void)?
    var onRequestSave: ((String) -> Void)?
    var onFocus: (() -> Void)?
    var onBlur: (() -> Void)?

    func makeWebView() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(MonacoAssetURLSchemeHandler(), forURLScheme: MonacoAssetURLSchemeHandler.scheme)
        config.userContentController.add(self, name: "cmuxMonacoBridge")
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.setValue(false, forKey: "drawsBackground")
#if DEBUG
        if #available(macOS 13.3, *) { wv.isInspectable = true }
#endif
        webView = wv
        wv.load(URLRequest(url: URL(string: "\(MonacoAssetURLSchemeHandler.scheme)://app/monaco.html")!))
        return wv
    }

    func load(text: String, language: String, theme: String) {
        pendingLoad = (text, language, theme)
        guard isReady else { return }
        applyPendingLoad()
    }

    private func applyPendingLoad() {
        guard let webView, let p = pendingLoad else { return }
        let args = jsonArgs(p.text, p.language, p.theme)
        webView.evaluateJavaScript("window.cmuxMonaco && window.cmuxMonaco.setContent(\(args)[0], \(args)[1], \(args)[2]);", completionHandler: nil)
    }

    func applyExternalChange(_ text: String) {
        guard let webView, isReady else { return }
        let args = jsonArgs(text)
        webView.evaluateJavaScript("window.cmuxMonaco && window.cmuxMonaco.applyExternalChange(\(args)[0]);", completionHandler: nil)
    }

    func setTheme(_ theme: String) {
        guard let webView, isReady else { return }
        let args = jsonArgs(theme)
        webView.evaluateJavaScript("window.cmuxMonaco && window.cmuxMonaco.setTheme(\(args)[0]);", completionHandler: nil)
    }

    func focus() { webView?.evaluateJavaScript("window.cmuxMonaco && window.cmuxMonaco.focus();", completionHandler: nil) }

    func flushSave() { webView?.evaluateJavaScript("window.cmuxMonaco && window.cmuxMonaco.flushSave();", completionHandler: nil) }

    /// JSON-encode args into a JS array literal so arbitrary text is escaped safely.
    private func jsonArgs(_ values: String...) -> String {
        (try? JSONSerialization.data(withJSONObject: values))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "cmuxMonacoBridge", let msg = MonacoBridgeMessage(body: message.body) else { return }
        switch msg {
        case .ready: isReady = true; applyPendingLoad()
        case .change(let c): onChange?(c)
        case .requestSave(let c): onRequestSave?(c)
        case .focus: onFocus?()
        case .blur: onBlur?()
        }
    }

    func dismantle() {
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "cmuxMonacoBridge")
        webView?.navigationDelegate = nil
        webView = nil
        isReady = false
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { /* ready arrives via bridge */ }
}
```

- [ ] **Step 2: Implement `MonacoEditorView`** — `NSViewRepresentable` mirroring `MarkdownWebRenderer.makeNSView/updateNSView/dismantleNSView`, owning a `MonacoWebController` (passed in, panel-owned, so the web view survives SwiftUI wrapper churn). Props: `controller: MonacoWebController`, `text: String`, `language: String`, `isDark: Bool`, `onRequestPanelFocus: () -> Void`. `makeNSView` returns `controller.makeWebView()`, sets appearance; `updateNSView` calls `controller.load(text:language:theme:)` (theme from `isDark`) and `controller.setTheme`. `dismantleNSView` does nothing (controller is panel-owned; teardown happens on panel close).

- [ ] **Step 3: pbxproj wiring** (both targets). Normalize + check.

- [ ] **Step 4: Controller checkpoint build** (`cmux-unit` build-for-testing). Expected: BUILD SUCCEEDED.

- [ ] **Step 5: Commit** `Monaco: NSViewRepresentable web host + controller`

> No unit test for the web host itself (requires a live WebView). Behavior is exercised via the FilePreviewPanel retrofit (Task 14) + manual reload. The pure seams (bridge, language map, scheme path/mime) are already covered.

---

## Phase 2 — Auto-save

### Task 7: `MonacoAtomicTextSaver` (atomic, encoding-preserving)

**Files:**
- Create: `Sources/Monaco/MonacoAtomicTextSaver.swift`
- Test: `cmuxTests/MonacoAtomicTextSaverTests.swift`

- [ ] **Step 1: Failing test** (write+read round trip in a temp dir; encoding preserved; returns the written content's hash for self-write suppression)

```swift
import Testing
import Foundation
@testable import cmux

@Suite struct MonacoAtomicTextSaverTests {
    @Test func writesAtomicallyAndReportsHash() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("monaco-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        let saver = MonacoAtomicTextSaver()
        let result = try await saver.save(content: "héllo\n", to: file.path, encoding: .utf8)
        let read = try String(contentsOf: file, encoding: .utf8)
        #expect(read == "héllo\n")
        #expect(result.contentHash == MonacoAtomicTextSaver.hash(of: "héllo\n", encoding: .utf8))
    }
    @Test func preservesNonUTF8Encoding() async throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("monaco-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        let saver = MonacoAtomicTextSaver()
        _ = try await saver.save(content: "café", to: file.path, encoding: .isoLatin1)
        let raw = try Data(contentsOf: file)
        #expect(raw == "café".data(using: .isoLatin1))
    }
}
```

- [ ] **Step 2: Verify it fails.**
- [ ] **Step 3: Implement** — an `actor MonacoAtomicTextSaver` with `func save(content:to:encoding:) async throws -> SaveResult` that encodes with the given `String.Encoding`, writes via `Data.write(to:options:[.atomic])`, and returns `SaveResult(contentHash:)`. Provide `static func hash(of:encoding:) -> Int` (stable hash of the encoded bytes, e.g. a simple FNV over `Data`) used by the panel to suppress self-write watcher reloads. Throw a typed error if the encoding fails.
- [ ] **Step 4: pbxproj wiring + normalize + check.**
- [ ] **Step 5: Verify pass.**
- [ ] **Step 6: Commit** `Monaco: atomic, encoding-preserving text saver`

---

## Phase 3 — Settings

### Task 8: `CodeEditorPreferenceSettings`

**Files:**
- Create: `Sources/Monaco/CodeEditorPreferenceSettings.swift`
- Test: `cmuxTests/CodeEditorPreferenceSettingsTests.swift`

- [ ] **Step 1: Failing test**

```swift
import Testing
import Foundation
@testable import cmux

@Suite struct CodeEditorPreferenceSettingsTests {
    private func defaults() -> UserDefaults {
        let d = UserDefaults(suiteName: "monaco-test-\(UUID().uuidString)")!
        return d
    }
    @Test func defaultsToMonaco() {
        #expect(CodeEditorPreferenceSettings.resolved(defaults: defaults()) == .monaco)
    }
    @Test func readsTerminal() {
        let d = defaults(); d.set("terminal", forKey: CodeEditorPreferenceSettings.key)
        #expect(CodeEditorPreferenceSettings.resolved(defaults: d) == .terminal)
    }
    @Test func unknownFallsBackToMonaco() {
        let d = defaults(); d.set("emacs-in-a-bottle", forKey: CodeEditorPreferenceSettings.key)
        #expect(CodeEditorPreferenceSettings.resolved(defaults: d) == .monaco)
    }
}
```

- [ ] **Step 2: Verify it fails.**
- [ ] **Step 3: Implement**

```swift
import Foundation

/// Which editor opens when a file is opened from the sidebar/preview path.
enum CodeEditorChoice: String, Sendable { case monaco, terminal }

enum CodeEditorPreferenceSettings {
    static let key = "codeEditor"
    static func resolved(defaults: UserDefaults = .standard) -> CodeEditorChoice {
        guard let raw = defaults.string(forKey: key), let choice = CodeEditorChoice(rawValue: raw) else { return .monaco }
        return choice
    }
}
```

- [ ] **Step 4: pbxproj wiring + normalize + check.**
- [ ] **Step 5: Verify pass.**
- [ ] **Step 6: Commit** `Monaco: code editor preference (monaco | terminal)`

---

### Task 9: Settings catalog + UI + cmux.json + schema + paths

**Files:**
- Modify: `Packages/CmuxSettings/Sources/CmuxSettings/Keys/AppCatalogSection.swift`
- Modify: `Packages/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/AppSection.swift`
- Modify: `Sources/KeyboardShortcutSettingsFileStore.swift`
- Modify: `Sources/CmuxSettingsJSONPathSupport.swift`
- Modify: `web/data/cmux.schema.json`
- Test: `cmuxTests/CodeEditorJSONParseTests.swift` (parse `cmux.json` `app.codeEditor` → managed defaults)

- [ ] **Step 1:** Add catalog key in `AppCatalogSection` (mirror `terminalEditor` at ~70-74):
```swift
public let codeEditor = DefaultsKey<String>(id: "app.codeEditor", defaultValue: "monaco", userDefaultsKey: "codeEditor")
```
- [ ] **Step 2:** Add a `SettingsCardRow` Picker in `AppSection` next to the terminalEditor row: options Monaco / Terminal editor, bound to a `DefaultsValueModel<String>` on `catalog.app.codeEditor`, `configurationReview: .json("app.codeEditor")`. Keep the existing terminalEditor TextField (used when `terminal`). Localize the label/subtitle/option titles.
- [ ] **Step 3:** Add a failing parse test, then add `codeEditor` handling in `KeyboardShortcutSettingsFileStore.parseAppSection` (validate against `monaco`/`terminal`, store under `CodeEditorPreferenceSettings.key`). Two-commit red/green per regression policy.
- [ ] **Step 4:** Add `"app.codeEditor"` to `CmuxSettingsJSONPathSupport.supportedSettingsJSONPaths`.
- [ ] **Step 5:** Add `codeEditor` to `web/data/cmux.schema.json` (string `enum: ["monaco","terminal"]`, default `"monaco"`, description).
- [ ] **Step 6:** pbxproj test wiring + normalize + check.
- [ ] **Step 7:** Commit `Monaco: code editor setting (catalog, UI, cmux.json, schema)`

---

### Task 10: Localization (en + ja)

**Files:** Modify `Resources/Localizable.xcstrings`

- [ ] **Step 1:** Add en + ja for every new user-facing string: settings picker label (`settings.app.codeEditor`), subtitle, the two option titles (`Monaco (built-in)` / `Terminal editor`), and any in-editor chrome introduced (e.g. an error/fallback toast key if added). Use `String(localized:defaultValue:)` at call sites.
- [ ] **Step 2:** Parse the file (valid JSON) and confirm each new key has both locales.
- [ ] **Step 3:** Commit `Monaco: localize code editor settings (en, ja)`

---

## Phase 4 — Integration

### Task 11: Retrofit `FilePreviewPanel` text mode → Monaco

**Files:**
- Modify: `Sources/Panels/FilePreviewPanel.swift`
- Modify: `Sources/Panels/FilePreviewPanelView.swift`

**Read first:** both files end-to-end + `FilePreviewTextEditor.swift`.

- [ ] **Step 1:** In `FilePreviewPanel`, add a panel-owned `MonacoWebController` (lazy) and a `useMonacoForText` decision: `true` when `FilePreviewMode == .text` AND the loaded byte size ≤ a `largeFileThresholdBytes` (= 2 * 1024 * 1024). Above threshold → keep NSTextView (existing path). Add `lastWrittenContentHash: Int?`.
- [ ] **Step 2:** Wire the controller closures:
  - `onChange = { [weak self] content in self?.autoSave(content) }`
  - `onRequestSave = { [weak self] content in self?.autoSave(content) }`
  - `onFocus`/`onBlur` → existing focus-intent hooks.
  - `autoSave(_:)`: compute `hash = MonacoAtomicTextSaver.hash(of: content, encoding: detectedEncoding)`; skip if equal to current on-disk hash; else `Task { let r = try await saver.save(...); self.lastWrittenContentHash = r.contentHash; self.textContent = content }` (off-main actor save; assign hash on main).
- [ ] **Step 3:** Load: when entering text mode with Monaco, after `FilePreviewTextLoader` returns, call `controller.load(text: loadedText, language: MonacoLanguageMap.languageId(forPath: filePath), theme: isDark ? "vs-dark" : "vs")` and set `lastWrittenContentHash = MonacoAtomicTextSaver.hash(of: loadedText, encoding: detectedEncoding)`.
- [ ] **Step 4:** File-watcher reload: in the existing external-change handler, compute the on-disk content hash; if it equals `lastWrittenContentHash`, **skip** (our own write). Otherwise, if no pending local edits, `controller.applyExternalChange(newText)`; if mid-edit, keep buffer (last-write-wins).
- [ ] **Step 5:** Close/blur flush: before the panel tears down (its `close()`), call `controller.flushSave()` then `controller.dismantle()`. The resulting `requestSave` is handled synchronously on main; ensure `autoSave` is invoked before dismantle.
- [ ] **Step 6:** Dirty: with auto-save, leave `isDirty == false` for Monaco-backed text (no persistent dot; closing never prompts). (NSTextView fallback keeps current explicit-save dirty behavior.)
- [ ] **Step 7:** In `FilePreviewPanelView`, render `MonacoEditorView(controller:text:language:isDark:onRequestPanelFocus:)` for the Monaco text case; keep `FilePreviewTextEditor` for the fallback/non-text cases.
- [ ] **Step 8:** Controller checkpoint build (`cmux-unit`). Expected: BUILD SUCCEEDED.
- [ ] **Step 9:** Commit `Monaco: editor as FilePreviewPanel text mode (auto-save, large-file fallback)`

> No new unit test in this task (UI/integration; covered by the pure seams + manual dogfood). If a behavioral seam is extractable (e.g. the "should use Monaco?" decision + self-write-suppression decision), add a tiny pure helper + Swift Testing test for it.

---

### Task 12: Route sidebar double-click + bottom-bar indicator via `app.codeEditor`

**Files:** Modify `Sources/ContentView.swift`

**Read first:** `openSidebarFileInEditor` (~2211), `openFilePreviewFromSidebar` (~2639), `refreshBottomBarEditorName` (~2203), and the `SidebarFileExplorerPanel` `onOpenFile` wiring.

- [ ] **Step 1:** In the sidebar double-click handler, branch on `CodeEditorPreferenceSettings.resolved()`:
  - `.monaco` → `openFilePreviewFromSidebar(path)` (text routes through `openFileSurfaces` → FilePreviewPanel → Monaco).
  - `.terminal` → existing `openSidebarFileInEditor(path:)` (micro→vim/custom).
- [ ] **Step 2:** In `refreshBottomBarEditorName`, when `.monaco` set the name to `String(localized: "bottomBar.editor.monaco", defaultValue: "Monaco")`; when `.terminal`, keep the resolved terminal editor name. Re-resolve on `app.codeEditor` change (already covered by the global `UserDefaults.didChangeNotification` subscription).
- [ ] **Step 3:** Add the `bottomBar.editor.monaco` localization (en + ja) if not added in Task 10.
- [ ] **Step 4:** Controller checkpoint build. Expected: BUILD SUCCEEDED.
- [ ] **Step 5:** Commit `Monaco: sidebar open + bottom-bar indicator honor code editor setting`

---

## Phase 5 — Final

### Task 13: Localization audit + final review

- [ ] **Step 1:** Enumerate every user-facing surface changed (settings picker + subtitle + options, bottom-bar "Monaco", any toast/error). Parse `Resources/Localizable.xcstrings`, confirm en + ja for each new key. `rg` the changed Swift files for bare English in `Text(`/`Button(`/`String(localized:` to confirm none slipped through.
- [ ] **Step 2:** Controller: full `cmux-unit` build-for-testing (compiles app + test targets). Confirm pbxproj normalized + `check-pbxproj.sh` + `lint-pbxproj-test-wiring.sh` pass.
- [ ] **Step 3:** Dispatch the final code-quality reviewer over the whole branch diff.
- [ ] **Step 4:** Use `superpowers:finishing-a-development-branch`.

---

## Self-review notes (plan author)

- **Spec coverage:** asset pipeline (T1-3), web host + bridge (T4-6), auto-save + atomic save + self-write suppression (T7, T11), language + theme (T5, T6/T11), keyboard routing (deferred into T6/T11 controller — Monaco's `addCommand` handles in-editor shortcuts; cmux global shortcuts already win via the standard responder chain since the web view is a child; revisit only if a conflict shows in dogfood), settings end-to-end (T8-10), open-path rewire + bottom bar (T12), large-file fallback (T11), `.md` stays on MarkdownPanel (no change to `openFileSurfaces` markdown branch — implicit), tests for all pure seams, localization (T10, T13). Covered.
- **Type consistency:** `MonacoWebController.load(text:language:theme:)`, `MonacoBridgeMessage` cases, `MonacoAtomicTextSaver.save/hash`, `CodeEditorPreferenceSettings.resolved/key`, `CodeEditorChoice` used consistently across tasks.
- **Known risk (worker loading):** the `monaco.html` neutralizes workers (syntax-only). If syntax highlighting needs the editor worker, switch to a Blob-proxy `getWorkerUrl` that bootstraps `importScripts("cmux-monaco://app/vs/base/worker/workerMain.js")`. Validate in T6 (load a `.ts` file, confirm highlighting + no fatal console errors).
- **Import guard:** match the existing `cmuxTests` import pattern (`#if canImport(cmux_DEV) import cmux_DEV #elseif canImport(cmux) @testable import cmux #endif`); the snippets above show `@testable import cmux` for brevity — implementers use the repo's actual guard.
