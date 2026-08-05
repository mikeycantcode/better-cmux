import AppKit
import SwiftUI
import WebKit

/// SwiftUI host for a Monaco editor web view, driven by a panel-owned
/// ``MonacoWebController``.
///
/// Mirrors ``MarkdownWebRenderer``'s representable: the controller owns the web
/// view across SwiftUI wrapper churn, while this view applies the current text,
/// language, and appearance on each update.
struct MonacoEditorView: NSViewRepresentable {
    /// The panel-owned controller that owns the web view and bridge.
    let controller: MonacoWebController
    /// The full text to display.
    let text: String
    /// The Monaco language id (see ``MonacoLanguageMap``).
    let language: String
    /// Whether the cmux appearance is dark (selects the `cmux-dark` theme).
    let isDark: Bool

    func makeNSView(context: Context) -> WKWebView {
        let webView = controller.makeWebView()
        applyAppearance(to: webView)
        controller.load(text: text, language: language, theme: theme)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        applyAppearance(to: nsView)
        controller.load(text: text, language: language, theme: theme)
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
