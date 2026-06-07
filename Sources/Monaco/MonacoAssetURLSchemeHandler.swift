import Foundation
import WebKit

/// Serves the bundled Monaco distribution over `cmux-monaco://app/<path>`.
///
/// The handler streams files from the app bundle's `monaco` resource directory,
/// rejecting any request that would escape that directory. It is registered on a
/// ``MonacoWebController``'s `WKWebViewConfiguration` so the AMD loader, editor
/// assets, and the `monaco.html` shell all load from a single trusted origin.
@MainActor
final class MonacoAssetURLSchemeHandler: NSObject, WKURLSchemeHandler {
    /// The custom URL scheme this handler answers.
    static let scheme = "cmux-monaco"

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let root = MonacoAssets.rootURL() else {
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorBadURL))
            return
        }
        // cmux-monaco://app/vs/loader.js  ->  relative path "/vs/loader.js"
        let relative = url.path
        guard let fileURL = MonacoAssetPath.resolve(relativePath: relative, under: root),
              let data = try? Data(contentsOf: fileURL) else {
            urlSchemeTask.didFailWithError(NSError(domain: NSURLErrorDomain, code: NSURLErrorFileDoesNotExist))
            return
        }
        let mime = MonacoAssetMime.mimeType(forPathExtension: fileURL.pathExtension)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": mime, "Content-Length": String(data.count)]
        )!
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
