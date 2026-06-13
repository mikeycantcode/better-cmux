/// Resolves human-friendly references to pane and surface identifiers against a layout snapshot.
///
/// The reorg CLI verbs (`move-tab`, `reorder-tab`, `swap-panes`) accept either raw ids or
/// ergonomic references — a direction (`left`/`right`/`up`/`down`) relative to the calling
/// agent's anchor pane, the special `focused` pane, or a case-insensitive title/file-name
/// substring for surfaces. ``TargetResolver`` turns those references into the concrete ids the
/// socket commands require, returning `nil` when a reference does not match or is ambiguous.
public struct TargetResolver: Sendable {
    /// Creates a resolver. The type is stateless; the snapshot is passed per call.
    public init() {}

    /// Resolves a pane reference to a concrete pane id.
    ///
    /// - Parameters:
    ///   - ref: One of: an existing pane id (returned as-is if it matches a pane); a direction
    ///     (`left`/`right`/`up`/`down`) interpreted relative to `anchorPaneId`; or `focused`
    ///     (the snapshot's focused pane). Directions are case-insensitive.
    ///   - anchorPaneId: The calling agent's pane, used as the origin for directional references.
    ///   - snapshot: The decoded workspace layout.
    /// - Returns: the matching pane id, or `nil` if the reference cannot be resolved.
    public func resolvePane(_ ref: String, anchorPaneId: String?, in snapshot: LayoutSnapshot) -> String? {
        nil
    }

    /// Resolves a surface reference to a concrete surface id.
    ///
    /// - Parameters:
    ///   - ref: Either an existing surface id (returned as-is if it matches a surface) or a
    ///     case-insensitive substring matched against each surface's title and file name. A
    ///     substring that matches more than one surface is ambiguous and yields `nil`.
    ///   - snapshot: The decoded workspace layout.
    /// - Returns: the matching surface id, or `nil` if there is no match or the match is ambiguous.
    public func resolveSurface(_ ref: String, in snapshot: LayoutSnapshot) -> String? {
        nil
    }
}
