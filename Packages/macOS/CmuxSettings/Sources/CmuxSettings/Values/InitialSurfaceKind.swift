/// Which surface a freshly-created workspace opens with.
///
/// A fresh, input-less launch with the `app.welcomePaneOnLaunch` setting enabled opens the
/// welcome pane; every other path (session restore, an explicit initial terminal command, or the
/// setting disabled) opens a terminal.
public enum InitialSurfaceKind: Equatable, Sendable {
    /// The non-terminal welcome pane (branding + "+ New Terminal").
    case welcome
    /// A normal terminal surface.
    case terminal

    /// Decides the initial surface for a new workspace.
    ///
    /// Returns ``welcome`` only for a fresh (not session-restored), input-less launch with the
    /// `app.welcomePaneOnLaunch` setting on; otherwise ``terminal``.
    ///
    /// - Parameters:
    ///   - isFreshLaunch: `true` when the workspace is being created fresh, not restored from a
    ///     session snapshot.
    ///   - hasInitialInput: `true` when an explicit initial terminal command/input was supplied,
    ///     which always forces a terminal.
    ///   - welcomeEnabled: the resolved value of the `app.welcomePaneOnLaunch` setting.
    /// - Returns: ``welcome`` or ``terminal``.
    public static func resolve(
        isFreshLaunch: Bool,
        hasInitialInput: Bool,
        welcomeEnabled: Bool
    ) -> InitialSurfaceKind {
        guard isFreshLaunch, !hasInitialInput, welcomeEnabled else { return .terminal }
        return .welcome
    }
}
