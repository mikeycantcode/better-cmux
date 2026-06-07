import Foundation
import WebKit

/// Serves the bundled Monaco distribution over `cmux-monaco://app/<path>`.
///
/// The handler streams files from the app bundle's `monaco` resource directory,
/// rejecting any request that would escape that directory. It is registered on a
/// ``MonacoWebController``'s `WKWebViewConfiguration` so the AMD loader, editor
/// assets, and the `monaco.html` shell all load from a single trusted origin.
///
/// File reads happen off the main thread on a background queue (the editor assets
/// are multi-MB — `editor.api` alone is ~3.6MB — so reading them synchronously on
/// `@MainActor` would stall the UI on every editor open). Callbacks are skipped
/// once WebKit calls `webView(_:stop:)`, so a torn-down task never touches a dead
/// `WKURLSchemeTask`.
final class MonacoAssetURLSchemeHandler: NSObject, WKURLSchemeHandler {
    /// The custom URL scheme this handler answers.
    static let scheme = "cmux-monaco"

    /// Tracks a single in-flight scheme task's stopped state so off-main callbacks
    /// can bail after `stop`. `@unchecked Sendable`: every field is mutated only
    /// while holding `condition`'s lock, which serializes access across the
    /// background read queue and the main-thread `stop` callback.
    private final class SchemeTaskState: @unchecked Sendable {
        let condition = NSCondition()
        var isStopped = false
        var callbacksInFlight = 0
    }

    // Guards `activeSchemeTasks`. Lock carve-out: a short synchronous critical
    // section over a tiny dictionary, touched from synchronous WKURLSchemeHandler
    // callbacks (main thread) and the background read queue; promoting to an actor
    // would force `await` hops through those non-async callbacks for no benefit.
    private let lock = NSLock()
    private var activeSchemeTasks: [ObjectIdentifier: SchemeTaskState] = [:]
    private let readQueue = DispatchQueue(
        label: "com.manaflow.cmux.monaco-asset-read",
        qos: .userInitiated
    )

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let root = MonacoAssets.rootURL() else {
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL))
            return
        }
        // cmux-monaco://app/vs/loader.js  ->  relative path "/vs/loader.js"
        let relative = url.path
        guard let fileURL = MonacoAssetPath.resolve(relativePath: relative, under: root) else {
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist))
            return
        }

        let taskID = ObjectIdentifier(urlSchemeTask as AnyObject)
        let state = SchemeTaskState()
        lock.lock()
        activeSchemeTasks[taskID] = state
        lock.unlock()

        readQueue.async { [weak self] in
            guard let self else { return }
            guard let data = try? Data(contentsOf: fileURL) else {
                _ = self.performSchemeTaskCallback(taskID) {
                    urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist))
                }
                self.finishSchemeTask(taskID)
                return
            }

            let mime = MonacoAssetMime.mimeType(forPathExtension: fileURL.pathExtension)
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": mime, "Content-Length": String(data.count)]
            )!

            guard self.performSchemeTaskCallback(taskID, { urlSchemeTask.didReceive(response) }) else { return }
            guard self.performSchemeTaskCallback(taskID, { urlSchemeTask.didReceive(data) }) else { return }
            guard self.performSchemeTaskCallback(taskID, { urlSchemeTask.didFinish() }) else { return }
            self.finishSchemeTask(taskID)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        stopSchemeTask(ObjectIdentifier(urlSchemeTask as AnyObject))
    }

    /// Runs `callback` only if the task is still active, blocking a concurrent
    /// `stop` from returning until the callback completes. Returns `false` (and
    /// skips `callback`) once the task is stopped.
    private func performSchemeTaskCallback(_ taskID: ObjectIdentifier, _ callback: () -> Void) -> Bool {
        lock.lock()
        let state = activeSchemeTasks[taskID]
        lock.unlock()
        guard let state else { return false }

        state.condition.lock()
        guard !state.isStopped else {
            state.condition.unlock()
            return false
        }
        state.callbacksInFlight += 1
        state.condition.unlock()

        callback()

        state.condition.lock()
        state.callbacksInFlight -= 1
        if state.callbacksInFlight == 0 {
            state.condition.broadcast()
        }
        let active = !state.isStopped
        state.condition.unlock()
        return active
    }

    private func finishSchemeTask(_ taskID: ObjectIdentifier) {
        stopSchemeTask(taskID)
    }

    private func stopSchemeTask(_ taskID: ObjectIdentifier) {
        lock.lock()
        let state = activeSchemeTasks.removeValue(forKey: taskID)
        lock.unlock()
        guard let state else { return }

        state.condition.lock()
        state.isStopped = true
        while state.callbacksInFlight > 0 {
            state.condition.wait()
        }
        state.condition.unlock()
    }
}
