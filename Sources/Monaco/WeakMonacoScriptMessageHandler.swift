import AppKit
import WebKit

/// A weak `WKScriptMessageHandler` trampoline that forwards bridge messages to a
/// ``MonacoWebController`` without retaining it.
///
/// `WKUserContentController.add(_:name:)` strongly retains its handler. Registering
/// a ``MonacoWebController`` directly would form a retain cycle (controller →
/// web view → configuration → user content controller → controller) that only
/// `dismantle()` breaks; on detach/transfer paths where the panel's `close()`
/// never runs, the cycle leaks the `WKWebView` and its content process. Routing
/// through this weak trampoline keeps the user content controller from holding the
/// controller alive, so the controller deallocates with its owning panel.
///
/// Mirrors `WeakMarkdownScriptMessageHandler`.
@MainActor
final class WeakMonacoScriptMessageHandler: NSObject, WKScriptMessageHandler {
    /// The controller messages are forwarded to, held weakly to avoid a cycle.
    weak var target: WKScriptMessageHandler?

    /// Creates a trampoline forwarding to `target`.
    /// - Parameter target: The handler to forward bridge messages to.
    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
