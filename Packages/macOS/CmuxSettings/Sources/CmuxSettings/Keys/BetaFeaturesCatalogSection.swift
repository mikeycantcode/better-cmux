import Foundation

/// Beta-feature toggles. Each key here gates an experimental code path
/// in the running app. Betas follow the pattern
/// `<feature-domain>.beta.<flag-name>` so the cmux.json view groups them
/// sensibly.
public struct BetaFeaturesCatalogSection: SettingCatalogSection {
    /// Extensions: the experimental ExtensionKit sidebar-extension surface
    /// (puzzle button, sidebar-toggle provider menu, installed-extension
    /// host, and the extensions browser). Defaults off; while off, every
    /// extension-related entry point is hidden so the feature stays opt-in
    /// while it is in beta.
    public let extensions = DefaultsKey<Bool>(
        id: "extensions.beta.enabled",
        defaultValue: false,
        userDefaultsKey: "extensions.beta.enabled"
    )

    /// Custom sidebars: user/agent-authored sidebars (interpreted Swift or
    /// JSON) discovered from `~/.config/cmux/sidebars/` and selectable in the
    /// sidebar button's provider picker. Defaults on; while off, no custom
    /// sidebar appears in the picker and a persisted custom selection falls
    /// back to the default workspaces sidebar.
    public let customSidebars = DefaultsKey<Bool>(
        id: "customSidebars.beta.enabled",
        defaultValue: true,
        userDefaultsKey: "customSidebars.beta.enabled"
    )


    public init() {}
}
