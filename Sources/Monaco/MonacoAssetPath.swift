import Foundation

/// Resolves a request path under a trusted root, rejecting traversal escapes.
enum MonacoAssetPath {
    /// Resolves `relativePath` against `root`, returning `nil` if the resolved
    /// path would escape the root directory (e.g. via `..` segments).
    static func resolve(relativePath: String, under root: URL) -> URL? {
        let trimmed = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
        let candidate = root.appendingPathComponent(trimmed).standardizedFileURL
        let rootStd = root.standardizedFileURL
        let rootPrefix = rootStd.path.hasSuffix("/") ? rootStd.path : rootStd.path + "/"
        guard candidate.path == rootStd.path || candidate.path.hasPrefix(rootPrefix) else { return nil }
        return candidate
    }
}
