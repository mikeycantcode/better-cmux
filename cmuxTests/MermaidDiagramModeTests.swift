import AppKit
import Testing
import WebKit

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite
final class MermaidDiagramModeTests {
    @Test
    func diagramModeSuppressesDocumentPaddingAndShowsDotGrid() async throws {
        let harness = try await DiagramShellHarness.make()
        defer { harness.tearDown() }

        try await harness.render("```mermaid\nflowchart LR\n  a --> b\n```")

        let before = try await harness.evalString("getComputedStyle(document.body).padding")
        #expect(before != "0px")

        _ = try await harness.eval("window.__cmuxSetDiagramMode(true)")

        let attr = try await harness.evalString("document.documentElement.getAttribute('data-cmux-diagram')")
        #expect(attr == "1")

        let padding = try await harness.evalString("getComputedStyle(document.body).padding")
        #expect(padding == "0px")

        let overflow = try await harness.evalString("getComputedStyle(document.body).overflow")
        #expect(overflow == "hidden")

        // The dot grid is a repeating radial-gradient on the canvas layer.
        let bgImage = try await harness.evalString(
            "getComputedStyle(document.getElementById('cmux-diagram-canvas')).backgroundImage"
        )
        #expect(bgImage.contains("radial-gradient"))
    }

    @Test
    func disablingDiagramModeRestoresDocumentFlow() async throws {
        let harness = try await DiagramShellHarness.make()
        defer { harness.tearDown() }

        try await harness.render("```mermaid\nflowchart LR\n  a --> b\n```")
        _ = try await harness.eval("window.__cmuxSetDiagramMode(true)")
        _ = try await harness.eval("window.__cmuxSetDiagramMode(false)")

        let attr = try await harness.evalString("document.documentElement.getAttribute('data-cmux-diagram') || ''")
        #expect(attr == "")
        let padding = try await harness.evalString("getComputedStyle(document.body).padding")
        #expect(padding != "0px")
    }

    @Test
    func wheelWithoutModifierPansAndPinchZooms() async throws {
        let harness = try await DiagramShellHarness.make()
        defer { harness.tearDown() }

        try await harness.render("```mermaid\nflowchart LR\n  a --> b\n```")
        _ = try await harness.eval("window.__cmuxSetDiagramMode(true)")
        _ = try await harness.eval("window.__cmuxDiagramSetCamera(0, 0, 1)")

        // Plain wheel scroll pans; it must not scroll the document.
        _ = try await harness.eval("""
        document.getElementById('content').dispatchEvent(new WheelEvent('wheel', {
          deltaX: 30, deltaY: 40, bubbles: true, cancelable: true
        }));
        """)
        let panned = try await harness.evalString("JSON.stringify(window.__cmuxDiagramCamera())")
        #expect(panned.contains("\"x\":-30"))
        #expect(panned.contains("\"y\":-40"))

        // ctrl+wheel is the trackpad pinch gesture WebKit synthesizes.
        _ = try await harness.eval("window.__cmuxDiagramSetCamera(0, 0, 1)")
        _ = try await harness.eval("""
        document.getElementById('content').dispatchEvent(new WheelEvent('wheel', {
          deltaY: -10, ctrlKey: true, clientX: 0, clientY: 0, bubbles: true, cancelable: true
        }));
        """)
        let zoomed = try await harness.eval("window.__cmuxDiagramCamera().scale") as? Double
        #expect((zoomed ?? 0) > 1.0)
    }

    @Test
    func cameraScaleIsClamped() async throws {
        let harness = try await DiagramShellHarness.make()
        defer { harness.tearDown() }
        try await harness.render("```mermaid\nflowchart LR\n  a --> b\n```")
        _ = try await harness.eval("window.__cmuxSetDiagramMode(true)")

        _ = try await harness.eval("window.__cmuxDiagramSetCamera(0, 0, 500)")
        let high = try await harness.eval("window.__cmuxDiagramCamera().scale") as? Double
        #expect((high ?? 0) <= 8.0)

        _ = try await harness.eval("window.__cmuxDiagramSetCamera(0, 0, 0.0001)")
        let low = try await harness.eval("window.__cmuxDiagramCamera().scale") as? Double
        #expect((low ?? 0) >= 0.1)
    }

    @Test
    func dotGridTransformsWithTheCamera() async throws {
        let harness = try await DiagramShellHarness.make()
        defer { harness.tearDown() }
        try await harness.render("```mermaid\nflowchart LR\n  a --> b\n```")
        _ = try await harness.eval("window.__cmuxSetDiagramMode(true)")
        _ = try await harness.eval("window.__cmuxDiagramSetCamera(100, 50, 2)")

        let canvasTransform = try await harness.evalString(
            "document.getElementById('cmux-diagram-canvas').style.transform"
        )
        let contentTransform = try await harness.evalString(
            "document.getElementById('content').style.transform"
        )
        // Both layers share the camera, so dots track the diagram exactly.
        #expect(canvasTransform.contains("scale(2)"))
        #expect(contentTransform.contains("scale(2)"))
        #expect(contentTransform.contains("translate(100px, 50px)"))
    }
}

@MainActor
private final class DiagramShellHarness {
    private let window: NSWindow
    private let webView: MarkdownWebView
    private let coordinator: MarkdownWebRenderer.Coordinator
    private let configuration: WKWebViewConfiguration
    private let mermaidHandler: DiagramMermaidStubHandler

    private init(
        window: NSWindow,
        webView: MarkdownWebView,
        coordinator: MarkdownWebRenderer.Coordinator,
        configuration: WKWebViewConfiguration,
        mermaidHandler: DiagramMermaidStubHandler
    ) {
        self.window = window
        self.webView = webView
        self.coordinator = coordinator
        self.configuration = configuration
        self.mermaidHandler = mermaidHandler
    }

    static func make() async throws -> DiagramShellHarness {
        let markdownURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-markdown-diagram-mode-\(UUID().uuidString).md")
        let frame = NSRect(x: 0, y: 0, width: 720, height: 480)
        let configuration = WKWebViewConfiguration()
        let mermaidHandler = DiagramMermaidStubHandler()
        configuration.userContentController.add(mermaidHandler, name: "cmuxLib")
        let webView = MarkdownWebView(frame: frame, configuration: configuration)
        mermaidHandler.webView = webView
        let coordinator = MarkdownWebRenderer.Coordinator()
        coordinator.webView = webView
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = webView
        window.orderFrontRegardless()

        let loadDelegate = DiagramShellLoadDelegate()
        webView.navigationDelegate = loadDelegate
        try await loadDelegate.load(MarkdownViewerAssets.shared.shellHTML(isDark: true), in: webView, baseURL: markdownURL)

        coordinator.setFontSize(MarkdownFontSizeSettings.defaultPointSize)

        return DiagramShellHarness(
            window: window,
            webView: webView,
            coordinator: coordinator,
            configuration: configuration,
            mermaidHandler: mermaidHandler
        )
    }

    func tearDown() {
        webView.navigationDelegate = nil
        coordinator.webView = nil
        configuration.userContentController.removeScriptMessageHandler(forName: "cmuxLib")
        window.close()
    }

    func render(_ markdown: String) async throws {
        let data = try JSONSerialization.data(withJSONObject: [markdown])
        let literal = try #require(String(data: data, encoding: .utf8))
        _ = try await webView.evaluateJavaScript("window.__cmuxRenderMarkdown(\(literal)[0]);")
    }

    @discardableResult
    func eval(_ script: String) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }

    func evalString(_ script: String) async throws -> String {
        let result = try await webView.evaluateJavaScript(script)
        return (result as? String) ?? ""
    }
}

private final class DiagramShellLoadDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ html: String, in webView: WKWebView, baseURL: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.loadHTMLString(html, baseURL: baseURL)
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        finish(.success(()))
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(error))
    }
}

@MainActor
private final class DiagramMermaidStubHandler: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == "cmuxLib",
              let body = message.body as? [String: Any],
              body["lib"] as? String == "mermaid" else { return }
        webView?.evaluateJavaScript(
            """
            window.mermaid = {
              initialize: function() {},
              render: function(id, src) {
                var width = 240;
                var height = 120;
                return Promise.resolve({
                  svg: '<svg data-stub-mermaid="1" width="100%" style="max-width:' + width + 'px;" viewBox="0 0 ' + width + ' ' + height + '" xmlns="http://www.w3.org/2000/svg"><rect x="0" y="0" width="' + width + '" height="' + height + '" fill="#d73a49"></rect><text x="20" y="65" font-size="18" fill="#ffffff">Mermaid label</text></svg>'
                });
              }
            };
            if (window.__cmuxLibLoaded) { window.__cmuxLibLoaded('mermaid'); }
            """,
            completionHandler: nil
        )
    }
}
