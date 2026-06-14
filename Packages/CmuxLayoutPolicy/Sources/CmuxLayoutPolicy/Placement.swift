/// What the CLI should do to fulfill `cmux open` for a file.
public enum Placement: Sendable, Equatable {
    /// Create a new pane to the right of the anchor, then open the file there.
    case splitRight(fromSurfaceId: String)
    /// Open the file as a new tab in an existing pane.
    case newTab(inPaneId: String)
    /// The file is already open in this surface; just focus it.
    case reuse(surfaceId: String)
    /// Open as a new tab in the anchor's own pane (the `--here` / `--tab` override).
    case here(paneId: String)
}

/// Caller overrides for `cmux open`, from CLI flags.
public struct PlacementOverrides: Sendable, Equatable {
    public var forceHere: Bool          // --here / --tab
    public var forcedSplit: LayoutNode.Orientation?   // --split left/right/up/down → orientation
    public var allowReuse: Bool
    public init(forceHere: Bool = false, forcedSplit: LayoutNode.Orientation? = nil, allowReuse: Bool = true) {
        self.forceHere = forceHere; self.forcedSplit = forcedSplit; self.allowReuse = allowReuse
    }
}
