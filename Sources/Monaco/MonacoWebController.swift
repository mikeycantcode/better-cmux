import AppKit
import WebKit

/// Drives a single Monaco editor `WKWebView`: loads the bundled shell, bridges
/// JS↔Swift, and exposes content/theme/focus/save operations.
///
/// The controller is owned by the panel (not the SwiftUI wrapper) so the web view
/// survives SwiftUI re-creating its `NSViewRepresentable` during split/workspace
/// churn — the same ownership model ``MarkdownWebRenderer`` uses for its session.
@MainActor
final class MonacoWebController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    /// The hosted web view, created lazily by ``makeWebView()``.
    private(set) var webView: WKWebView?

    private var isReady = false
    private var pendingLoad: (text: String, language: String, theme: String)?

    /// Called with the full buffer when Monaco reports a debounced content change.
    var onChange: ((String) -> Void)?
    /// Called with the full buffer when an explicit save is requested (Cmd+S / flush).
    var onRequestSave: ((String) -> Void)?
    /// Called when the editor widget gains focus.
    var onFocus: (() -> Void)?
    /// Called when the editor widget loses focus.
    var onBlur: (() -> Void)?

    /// Returns the hosted web view, creating and loading it on first call.
    func makeWebView() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(MonacoAssetURLSchemeHandler(), forURLScheme: MonacoAssetURLSchemeHandler.scheme)
        config.userContentController.add(self, name: "cmuxMonacoBridge")
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
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

    private func shellRequest() -> URLRequest {
        URLRequest(url: URL(string: "\(MonacoAssetURLSchemeHandler.scheme)://app/monaco.html")!)
    }

    private func load(request: URLRequest) {
        isReady = false
        webView?.load(request)
    }

    /// Loads `text` into the editor with the given Monaco language id and theme.
    /// If the editor is not ready yet, the load is queued and applied on `ready`.
    func load(text: String, language: String, theme: String) {
        pendingLoad = (text, language, theme)
        guard isReady else { return }
        applyPendingLoad()
    }

    private func applyPendingLoad() {
        guard let webView, let p = pendingLoad else { return }
        let args = jsonArgs(p.text, p.language, p.theme)
        webView.evaluateJavaScript(
            "window.cmuxMonaco && window.cmuxMonaco.setContent(\(args)[0], \(args)[1], \(args)[2]);",
            completionHandler: nil
        )
    }

    /// Replaces the editor buffer with `text` from an external on-disk change,
    /// preserving the cursor position.
    func applyExternalChange(_ text: String) {
        guard let webView, isReady else { return }
        let args = jsonArgs(text)
        webView.evaluateJavaScript(
            "window.cmuxMonaco && window.cmuxMonaco.applyExternalChange(\(args)[0]);",
            completionHandler: nil
        )
    }

    /// Sets the Monaco theme (`"vs"` / `"vs-dark"`).
    func setTheme(_ theme: String) {
        guard let webView, isReady else { return }
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
        case .change(let content): onChange?(content)
        case .requestSave(let content): onRequestSave?(content)
        case .focus: onFocus?()
        case .blur: onBlur?()
        }
    }

    /// Tears down the web view and bridge. Call from the owning panel's `close()`.
    func dismantle() {
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "cmuxMonacoBridge")
        webView?.navigationDelegate = nil
        webView = nil
        isReady = false
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // The editor signals readiness via the `ready` bridge message, not here:
        // navigation finishing only means the HTML/JS started loading.
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let current = self.webView, current === webView else { return }
        // Recover by reloading the shell; pendingLoad replays on `ready`.
        load(request: shellRequest())
    }
}
