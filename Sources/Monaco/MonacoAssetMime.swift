import Foundation

/// MIME types for assets served by ``MonacoAssetURLSchemeHandler``.
enum MonacoAssetMime {
    /// Returns the MIME type for a file extension, defaulting to
    /// `application/octet-stream` for anything unrecognized.
    static func mimeType(forPathExtension ext: String) -> String {
        switch ext.lowercased() {
        case "js", "mjs": return "text/javascript"
        case "css": return "text/css"
        case "html": return "text/html"
        case "json": return "application/json"
        case "ttf": return "font/ttf"
        case "woff": return "font/woff"
        case "woff2": return "font/woff2"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "map": return "application/json"
        default: return "application/octet-stream"
        }
    }
}
