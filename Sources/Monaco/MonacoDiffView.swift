import AppKit
import SwiftUI
import WebKit

/// SwiftUI host for a read-only Monaco diff, driven by a panel-owned ``MonacoWebController``.
///
/// Mirrors ``MonacoEditorView`` but renders an original-vs-modified diff via
/// ``MonacoWebController/loadDiff(original:modified:language:theme:)``.
struct MonacoDiffView: NSViewRepresentable {
    /// The panel-owned controller that owns the web view and bridge.
    let controller: MonacoWebController
    /// The file's current text (left/original pane).
    let original: String
    /// The proposed text (right/modified pane).
    let modified: String
    /// The Monaco language id (see ``MonacoLanguageMap``).
    let language: String
    /// Whether the cmux appearance is dark (selects the `cmux-dark` theme).
    let isDark: Bool

    func makeNSView(context: Context) -> WKWebView {
        let webView = controller.makeWebView()
        applyAppearance(to: webView)
        controller.loadDiff(original: original, modified: modified, language: language, theme: theme)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        applyAppearance(to: nsView)
        // The diff content is immutable once set (the panel is review-only: Accept/Reject are the
        // only actions), so updates only re-apply the theme — not the diff models.
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
