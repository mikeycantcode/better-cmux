import AppKit
import SwiftUI
import WebKit

/// SwiftUI host for the markdown live-preview editor (`markdown-live.html`),
/// driven by the panel-owned ``MonacoWebController`` so the web view survives
/// SwiftUI wrapper churn exactly like the Monaco code editor.
struct MarkdownLiveEditorView: NSViewRepresentable {
    let controller: MonacoWebController
    /// The panel's current markdown; edits flow back through the controller's
    /// `onChange`, on-disk changes flow in through ``MonacoWebController/syncText(_:language:theme:)``.
    let text: String
    let isDark: Bool

    func makeNSView(context: Context) -> WKWebView {
        let webView = controller.makeWebView()
        applyAppearance(to: webView)
        controller.syncText(text, language: "markdown", theme: theme)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        applyAppearance(to: nsView)
        controller.syncText(text, language: "markdown", theme: theme)
        controller.setTheme(theme)
    }

    private var theme: String { isDark ? "cmux-dark" : "cmux-light" }

    private func applyAppearance(to webView: WKWebView) {
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        if webView.appearance !== appearance {
            webView.appearance = appearance
        }
    }
}
