/// Decides where `cmux open <file>` should place a file, given the current layout snapshot.
///
/// Beside-split by default; if the anchor pane is already in a horizontal (side-by-side) split,
/// open a new tab in the neighbor pane instead of adding a third column. See ``decide(filePath:in:anchorSurfaceId:overrides:)``.
public struct PlacementPolicy: Sendable {
    public init() {}

    /// Returns the placement for opening `filePath`.
    ///
    /// The decision order is:
    /// 1. `overrides.forceHere` (the `--here` / `--tab` flag) opens a tab in the anchor's own pane.
    /// 2. If reuse is allowed and a `filePreview` surface anywhere already shows `filePath`, focus it.
    /// 3. If the anchor pane has a horizontal (side-by-side) neighbor pane, open a tab there rather
    ///    than adding a third column.
    /// 4. Otherwise open a new pane to the right of the anchor.
    ///
    /// - Parameters:
    ///   - filePath: Absolute path of the file to open (for reuse detection).
    ///   - snapshot: The decoded workspace layout.
    ///   - anchorSurfaceId: The calling agent's surface id (`CMUX_SURFACE_ID`).
    ///   - overrides: CLI flag overrides.
    /// - Returns: the ``Placement`` the CLI should execute.
    public func decide(filePath: String, in snapshot: LayoutSnapshot,
                       anchorSurfaceId: String, overrides: PlacementOverrides) -> Placement {
        let panes = Self.allPanes(snapshot.tree)
        let anchorPaneId = snapshot.anchor.paneId
            ?? panes.first(where: { $0.surfaces.contains { $0.id == anchorSurfaceId } })?.paneId

        if overrides.forceHere, let anchorPaneId { return .here(paneId: anchorPaneId) }

        if overrides.allowReuse {
            for p in panes {
                if let s = p.surfaces.first(where: { $0.type == "filePreview" && $0.filePath == filePath }) {
                    return .reuse(surfaceId: s.id)
                }
            }
        }

        if let anchorPaneId, let neighbor = Self.horizontalNeighbor(of: anchorPaneId, in: snapshot.tree) {
            return .newTab(inPaneId: neighbor)
        }
        return .splitRight(fromSurfaceId: anchorSurfaceId)
    }

    /// Collects every leaf pane in `node`, in left-to-right tree order.
    private static func allPanes(_ node: LayoutNode) -> [LayoutNode.Pane] {
        switch node {
        case let .pane(pane):
            return [pane]
        case let .split(_, _, children):
            return children.flatMap(allPanes)
        }
    }

    /// Returns the id of the pane horizontally adjacent to `paneId`, if any.
    ///
    /// Walks the tree looking for the nearest enclosing `.horizontal` split that contains `paneId`
    /// in one of its child subtrees. Among the sibling subtrees, the nearest right neighbor is
    /// preferred; if there is none to the right, the nearest left neighbor is used. The chosen
    /// neighbor subtree's first (left-most) pane id is returned.
    private static func horizontalNeighbor(of paneId: String, in node: LayoutNode) -> String? {
        switch node {
        case .pane:
            return nil
        case let .split(orientation, _, children):
            // Prefer a nearer enclosing horizontal split deeper in the tree: descend first.
            for child in children {
                if let found = horizontalNeighbor(of: paneId, in: child) {
                    return found
                }
            }
            if orientation == .horizontal {
                if let index = children.firstIndex(where: { subtree(contains: paneId, in: $0) }) {
                    // Prefer the nearest sibling to the right, else the nearest to the left.
                    if index + 1 < children.count {
                        return firstPaneId(in: children[index + 1])
                    }
                    if index - 1 >= 0 {
                        return firstPaneId(in: children[index - 1])
                    }
                }
            }
            return nil
        }
    }

    /// Whether `node`'s subtree contains a leaf pane with the given id.
    private static func subtree(contains paneId: String, in node: LayoutNode) -> Bool {
        switch node {
        case let .pane(pane):
            return pane.paneId == paneId
        case let .split(_, _, children):
            return children.contains { subtree(contains: paneId, in: $0) }
        }
    }

    /// The left-most leaf pane id in `node`'s subtree, if any.
    private static func firstPaneId(in node: LayoutNode) -> String? {
        switch node {
        case let .pane(pane):
            return pane.paneId
        case let .split(_, _, children):
            for child in children {
                if let id = firstPaneId(in: child) { return id }
            }
            return nil
        }
    }
}
