import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct MonacoAssetTests {
    @Test func mimeTypeForKnownExtensions() {
        #expect(MonacoAssetMime.mimeType(forPathExtension: "js") == "text/javascript")
        #expect(MonacoAssetMime.mimeType(forPathExtension: "css") == "text/css")
        #expect(MonacoAssetMime.mimeType(forPathExtension: "html") == "text/html")
        #expect(MonacoAssetMime.mimeType(forPathExtension: "ttf") == "font/ttf")
        #expect(MonacoAssetMime.mimeType(forPathExtension: "svg") == "image/svg+xml")
        #expect(MonacoAssetMime.mimeType(forPathExtension: "JS") == "text/javascript")
        #expect(MonacoAssetMime.mimeType(forPathExtension: "xyz") == "application/octet-stream")
    }

    @Test func resolvesPathsUnderRoot() {
        let root = URL(fileURLWithPath: "/bundle/monaco", isDirectory: true)
        #expect(MonacoAssetPath.resolve(relativePath: "vs/loader.js", under: root)?.path == "/bundle/monaco/vs/loader.js")
        #expect(MonacoAssetPath.resolve(relativePath: "/vs/loader.js", under: root)?.path == "/bundle/monaco/vs/loader.js")
        #expect(MonacoAssetPath.resolve(relativePath: "monaco.html", under: root)?.path == "/bundle/monaco/monaco.html")
    }

    @Test func rejectsPathTraversal() {
        let root = URL(fileURLWithPath: "/bundle/monaco", isDirectory: true)
        #expect(MonacoAssetPath.resolve(relativePath: "../secret", under: root) == nil)
        #expect(MonacoAssetPath.resolve(relativePath: "vs/../../etc/passwd", under: root) == nil)
    }
}
