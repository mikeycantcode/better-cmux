/// Decides where `cmux open <file>` should place a file, given the current layout snapshot.
///
/// Beside-split by default; if the anchor pane is already in a horizontal (side-by-side) split,
/// open a new tab in the neighbor pane instead of adding a third column. See ``decide(filePath:in:anchorSurfaceId:overrides:)``.
public struct PlacementPolicy: Sendable {
    public init() {}

    /// Returns the placement for opening `filePath`.
    ///
    /// - Parameters:
    ///   - filePath: Absolute path of the file to open (for reuse detection).
    ///   - snapshot: The decoded workspace layout.
    ///   - anchorSurfaceId: The calling agent's surface id (`CMUX_SURFACE_ID`).
    ///   - overrides: CLI flag overrides.
    /// - Returns: the ``Placement`` the CLI should execute.
    public func decide(filePath: String, in snapshot: LayoutSnapshot,
                       anchorSurfaceId: String, overrides: PlacementOverrides) -> Placement {
        .here(paneId: "STUB")
    }
}
