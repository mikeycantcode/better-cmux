import Foundation

/// Locates the bundled Monaco distribution (`Resources/monaco`) inside the app bundle.
enum MonacoAssets {
    /// The on-disk URL of the vendored Monaco root (`.../monaco`), or `nil` if missing.
    static func rootURL(bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "monaco", withExtension: nil)
    }
}
