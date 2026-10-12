import AppKit
import WebKit

/// Drives a single Monaco editor `WKWebView`: loads the bundled shell, bridges
/// JS↔Swift, and exposes content/theme/focus/save operations.
///
/// The controller is owned by the panel (not the SwiftUI wrapper) so the web view
/// survives SwiftUI re-creating its `NSViewRepresentable` during split/workspace
/// churn — the same ownership model ``MarkdownWebRenderer`` uses for its session.
/// The `WKWebView` subclass hosting Monaco.
///
/// cmux re-parents panes by `removeFromSuperview` → `addSubview` (bonsplit
/// splits, pane drags, workspace switches). While a `WKWebView` is out of a
/// window WebKit suspends painting — and can reclaim the WebContent process —
/// which previously left the editor permanently black with no user-facing
/// reload. This drives WebKit's in-window lifecycle out on detach and back in
/// on re-entry, mirroring ``MarkdownWebView``.
@MainActor
final class MonacoWebView: WKWebView {
    /// Invoked when the view leaves its window (the detach half of a re-parent).
    var onLeaveWindow: (() -> Void)?
    /// Invoked when the view re-enters a window after being detached.
    var onReenterWindow: (() -> Void)?

    private var needsRenderingReattach = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            needsRenderingReattach = true
            callVoidSelectorIfAvailable("viewDidHide")
            callVoidSelectorIfAvailable("_exitInWindow")
            onLeaveWindow?()
        } else {
            reattachRenderingState()
            onReenterWindow?()
        }
    }

    /// Resumes WebKit's rendering after the view re-enters a window: nudges the
    /// in-window lifecycle back on and forces a layout/display pass so the live
    /// document repaints instead of staying blank.
    private func reattachRenderingState() {
        guard needsRenderingReattach else { return }
        needsRenderingReattach = false
        callVoidSelectorIfAvailable("viewDidUnhide")
        callVoidSelectorIfAvailable("_enterInWindow")
        callVoidSelectorIfAvailable("_endDeferringViewInWindowChangesSync")
        needsLayout = true
        needsDisplay = true
        setNeedsDisplay(bounds)
        layoutSubtreeIfNeeded()
        displayIfNeeded()
    }

    /// Calls a private `WKWebView` lifecycle selector when present. Guarded by
    /// `responds(to:)` so it degrades to a no-op if the selector is removed.
    private func callVoidSelectorIfAvailable(_ rawSelector: String) {
        let selector = NSSelectorFromString(rawSelector)
        guard responds(to: selector) else { return }
        typealias Fn = @convention(c) (AnyObject, Selector) -> Void
        let fn = unsafeBitCast(method(for: selector), to: Fn.self)
        fn(self, selector)
    }
}

@MainActor
final class MonacoWebController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    /// The hosted web view, created lazily by ``makeWebView()``.
    private(set) var webView: WKWebView?

    /// The shell page under `cmux-monaco://app/`. Monaco by default; the
    /// markdown live-preview editor (`markdown-live.html`) speaks the same
    /// bridge, so this controller drives it unchanged.
    private let shellPath: String

    init(shellPath: String = "monaco.html") {
        self.shellPath = shellPath
        super.init()
    }

    private var isReady = false
    private var pendingLoad: (text: String, language: String, theme: String)?
    private var pendingDiff: (original: String, modified: String, language: String, theme: String)?
    // The text/language last pushed into the editor, used to make `load` idempotent.
    // SwiftUI re-runs the representable's `updateNSView` on every parent change and
    // calls `load` each time; without this guard, re-applying the same buffer would
    // run Monaco's destructive `setValue` (resetting the cursor and undo history)
    // on every keystroke's auto-save round-trip. Theme is excluded — `setTheme`
    // handles appearance changes non-destructively.
    private var lastAppliedContent: (text: String, language: String)?
    // The theme last pushed into the editor, used to make `setTheme` idempotent so
    // SwiftUI's repeated `updateNSView` does not re-run `monaco.editor.setTheme`
    // on every keystroke's round-trip.
    private var lastAppliedTheme: String?
    /// Whether the shell was ready at the moment the host view left its window,
    /// used to tell a pane-reparent artifact apart from a genuinely broken load.
    private var shellWasHealthyWhenDetached = false

    /// Called with the full buffer when Monaco reports a debounced content change.
    var onChange: ((String) -> Void)?
    /// Called with the full buffer when an explicit save is requested (Cmd+S / flush).
    var onRequestSave: ((String) -> Void)?
    /// Called on the first keystroke of an edit burst, before the debounced save,
    /// so the panel can mark a local edit in flight (last-write-wins on conflict).
    var onEditing: (() -> Void)?
    /// Called when the editor widget gains focus.
    var onFocus: (() -> Void)?
    /// Called when the editor widget loses focus.
    var onBlur: (() -> Void)?

    /// Returns the hosted web view, creating and loading it on first call.
    func makeWebView() -> WKWebView {
        if let webView {
            // SwiftUI recreates the representable (and a fresh host view) when the
            // pane hierarchy changes — e.g. a bonsplit split. Detach the retained
            // web view from its stale host first so it is re-parented cleanly,
            // mirroring `MarkdownWebRenderer.makeNSView`'s reuse path.
            if webView.superview != nil { webView.removeFromSuperview() }
            return webView
        }
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(MonacoAssetURLSchemeHandler(), forURLScheme: MonacoAssetURLSchemeHandler.scheme)
        // Register through a weak trampoline so `userContentController` does not
        // strongly retain this controller. A direct `add(self, ...)` forms a
        // retain cycle that only `dismantle()` breaks, leaking the web view and its
        // content process on detach/transfer paths where `close()` never runs.
        config.userContentController.add(
            WeakMonacoScriptMessageHandler(self),
            name: "cmuxMonacoBridge"
        )
        let wv = MonacoWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        bindWindowLifecycle(wv)
        wv.setValue(false, forKey: "drawsBackground")
        wv.allowsBackForwardNavigationGestures = false
        wv.allowsLinkPreview = false
#if DEBUG
        if #available(macOS 13.3, *) { wv.isInspectable = true }
#endif
        webView = wv
        load(request: shellRequest())
        return wv
    }

    /// Wires the host view's window-detach/re-entry hooks so a pane re-parent
    /// (bonsplit split, drag, workspace switch) cannot leave the editor blank.
    private func bindWindowLifecycle(_ wv: MonacoWebView) {
        wv.onLeaveWindow = { [weak self] in
            guard let self else { return }
            self.shellWasHealthyWhenDetached = self.isReady
        }
        wv.onReenterWindow = { [weak self] in
            guard let self else { return }
            // A still-ready document is alive but merely unpainted; the host
            // view's repaint nudge in `viewDidMoveToWindow` handles that case.
            guard !self.isReady else { return }
            // Only recover a document that was healthy before the detach, so a
            // shell that failed while attached is not retried on every re-parent.
            guard self.shellWasHealthyWhenDetached else { return }
            self.shellWasHealthyWhenDetached = false
            // Seed the replay from the last applied buffer before `load(request:)`
            // clears it, so the recovered editor repopulates on `ready`.
            if self.pendingLoad == nil, let last = self.lastAppliedContent {
                self.pendingLoad = (last.text, last.language, self.lastAppliedTheme ?? "cmux-dark")
            }
            self.load(request: self.shellRequest())
        }
    }

    private func shellRequest() -> URLRequest {
        URLRequest(url: URL(string: "\(MonacoAssetURLSchemeHandler.scheme)://app/\(shellPath)")!)
    }

    private func load(request: URLRequest) {
        isReady = false
        // The fresh document starts empty, so forget what we believe is applied;
        // the queued `pendingLoad` replays on `ready` and reseeds it.
        lastAppliedContent = nil
        lastAppliedTheme = nil
        webView?.load(request)
    }

    /// Loads `text` into the editor with the given Monaco language id and theme.
    /// If the editor is not ready yet, the load is queued and applied on `ready`.
    ///
    /// Idempotent: re-applying the text/language already in the editor is a no-op
    /// (only the theme is re-applied via ``setTheme(_:)`` separately), so SwiftUI's
    /// repeated `updateNSView` calls do not run Monaco's destructive `setValue` and
    /// reset the cursor mid-edit.
    func load(text: String, language: String, theme: String) {
        if let last = lastAppliedContent, last.text == text, last.language == language {
            return
        }
        pendingLoad = (text, language, theme)
        guard isReady else { return }
        applyPendingLoad()
    }

    private func applyPendingLoad() {
        guard let webView, let p = pendingLoad else { return }
        lastAppliedContent = (p.text, p.language)
        // `setContent` applies the theme too, so record it to keep `setTheme`
        // idempotent and avoid a redundant re-apply on the next `updateNSView`.
        lastAppliedTheme = p.theme
        let args = jsonArgs(p.text, p.language, p.theme)
        webView.evaluateJavaScript(
            "window.cmuxMonaco && window.cmuxMonaco.setContent(\(args)[0], \(args)[1], \(args)[2]);",
            completionHandler: nil
        )
    }

    /// Loads a read-only two-pane diff (original vs modified) into the editor.
    ///
    /// If the web view is not ready yet, the diff is queued and applied on `ready`.
    /// A controller used for a diff shows only the diff editor; it does not also call ``load``.
    func loadDiff(original: String, modified: String, language: String, theme: String) {
        pendingDiff = (original, modified, language, theme)
        guard isReady else { return }
        applyPendingDiff()
    }

    private func applyPendingDiff() {
        guard let webView, let d = pendingDiff else { return }
        let args = jsonArgs(d.original, d.modified, d.language, d.theme)
        webView.evaluateJavaScript(
            "window.cmuxMonaco && window.cmuxMonaco.setDiff(\(args)[0], \(args)[1], \(args)[2], \(args)[3]);",
            completionHandler: nil
        )
    }

    /// Replaces the editor buffer with `text` from an external on-disk change,
    /// preserving the cursor position.
    func applyExternalChange(_ text: String) {
        guard let webView, isReady else { return }
        lastAppliedContent = (text, lastAppliedContent?.language ?? "plaintext")
        let args = jsonArgs(text)
        webView.evaluateJavaScript(
            "window.cmuxMonaco && window.cmuxMonaco.applyExternalChange(\(args)[0]);",
            completionHandler: nil
        )
    }

    /// Keeps the editor in sync with a panel's text without clobbering edits:
    /// the first call loads normally; later calls whose text differs from what
    /// the editor holds (an on-disk change) are applied in place, preserving
    /// the cursor, instead of `setContent` resetting cursor and undo history.
    func syncText(_ text: String, language: String, theme: String) {
        guard isReady, let last = lastAppliedContent else {
            load(text: text, language: language, theme: theme)
            return
        }
        guard last.text != text else { return }
        applyExternalChange(text)
    }

    /// Sets the Monaco theme (`"cmux-light"` / `"cmux-dark"`).
    ///
    /// Idempotent: re-applying the theme already in effect is a no-op so SwiftUI's
    /// repeated `updateNSView` does not run `monaco.editor.setTheme` every keystroke.
    func setTheme(_ theme: String) {
        guard let webView, isReady else { return }
        guard lastAppliedTheme != theme else { return }
        lastAppliedTheme = theme
        let args = jsonArgs(theme)
        webView.evaluateJavaScript("window.cmuxMonaco && window.cmuxMonaco.setTheme(\(args)[0]);", completionHandler: nil)
    }

    /// Moves keyboard focus into the editor.
    func focus() {
        webView?.evaluateJavaScript("window.cmuxMonaco && window.cmuxMonaco.focus();", completionHandler: nil)
    }

    /// Forces any pending debounced save to fire immediately. The resulting
    /// `requestSave` message is delivered on the main actor before teardown.
    func flushSave() {
        webView?.evaluateJavaScript("window.cmuxMonaco && window.cmuxMonaco.flushSave();", completionHandler: nil)
    }

    /// Reads the editor's current buffer synchronously via the JS return value.
    ///
    /// Unlike ``flushSave()`` (which posts `requestSave` back over the bridge), this
    /// awaits the buffer directly, so a caller can persist the final edit and then
    /// tear down the bridge without racing an in-flight message. Returns `nil` when
    /// the editor is not yet initialized or the evaluation fails.
    func currentEditorValue() async -> String? {
        (try? await webView?.evaluateJavaScript(
            "window.cmuxMonaco ? window.cmuxMonaco.currentValue() : null"
        )) as? String
    }

    /// JSON-encodes args into a JS array literal so arbitrary text is escaped safely.
    private func jsonArgs(_ values: String...) -> String {
        (try? JSONSerialization.data(withJSONObject: values))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "cmuxMonacoBridge", let msg = MonacoBridgeMessage(body: message.body) else { return }
        switch msg {
        case .ready:
            isReady = true
            applyPendingLoad()
            applyPendingDiff()
        case .change(let content):
            // The editor now holds `content`; record it so a subsequent `load`
            // echoing the same text (e.g. from the panel persisting its buffer)
            // is a no-op and does not reset the cursor mid-edit.
            recordEditorContent(content)
            onChange?(content)
        case .requestSave(let content):
            recordEditorContent(content)
            onRequestSave?(content)
        case .editing: onEditing?()
        case .focus: onFocus?()
        case .blur: onBlur?()
        }
    }

    private func recordEditorContent(_ content: String) {
        lastAppliedContent = (content, lastAppliedContent?.language ?? "plaintext")
    }

    /// Tears down the web view and bridge. Call from the owning panel's `close()`.
    func dismantle() {
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "cmuxMonacoBridge")
        webView?.navigationDelegate = nil
        if let hosted = webView as? MonacoWebView {
            hosted.onLeaveWindow = nil
            hosted.onReenterWindow = nil
        }
        webView = nil
        isReady = false
        lastAppliedContent = nil
        lastAppliedTheme = nil
        pendingLoad = nil
        pendingDiff = nil
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // The editor signals readiness via the `ready` bridge message, not here:
        // navigation finishing only means the HTML/JS started loading.
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let current = self.webView, current === webView else { return }
        // Seed the pending load from the last content we applied BEFORE the
        // recovery reload clears `lastAppliedContent`, so the recovered editor
        // repopulates on `ready` without waiting for a SwiftUI `updateNSView`.
        if pendingLoad == nil, let last = lastAppliedContent {
            pendingLoad = (last.text, last.language, lastAppliedTheme ?? "cmux-dark")
        }
        // Recover by reloading the shell; pendingLoad replays on `ready`.
        load(request: shellRequest())
    }
}
