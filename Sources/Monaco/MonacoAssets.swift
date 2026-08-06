import Foundation

/// Locates the bundled Monaco distribution (`Resources/monaco`) inside the app bundle.
enum MonacoAssets {
    /// The on-disk URL of the vendored Monaco root (`.../monaco`), or `nil` if missing.
    static func rootURL(bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "monaco", withExtension: nil)
    }

    /// URL path prefix (under the `cmux-monaco://app` origin) that serves the
    /// Changes-panel shell from `Resources/git-changes`.
    ///
    /// The shell lives outside the Monaco distribution but must load Monaco's
    /// AMD loader and editor assets with relative-to-origin URLs. Serving it from
    /// the *same* custom-scheme origin avoids a cross-scheme subresource fetch,
    /// which WebKit restricts.
    static let gitChangesPathPrefix = "/git-changes/"

    /// The on-disk URL of the bundled `git-changes` resource folder, or `nil`.
    static func gitChangesRootURL(bundle: Bundle = .main) -> URL? {
        bundle.url(forResource: "git-changes", withExtension: nil)
    }
}
