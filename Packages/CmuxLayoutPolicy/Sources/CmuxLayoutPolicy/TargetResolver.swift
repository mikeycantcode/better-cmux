import Foundation

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
        // An existing pane id resolves to itself.
        if Self.containsPane(ref, in: snapshot.tree) {
            return ref
        }

        switch ref.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "focused":
            return snapshot.focusedPaneId.flatMap { Self.containsPane($0, in: snapshot.tree) ? $0 : nil }
        case "left", "right", "up", "down":
            guard let anchorPaneId else { return nil }
            let orientation: LayoutNode.Orientation = (ref.lowercased() == "left" || ref.lowercased() == "right")
                ? .horizontal : .vertical
            let preferNext = (ref.lowercased() == "right" || ref.lowercased() == "down")
            return Self.directionalNeighbor(of: anchorPaneId, orientation: orientation,
                                            preferNext: preferNext, in: snapshot.tree)
        default:
            return nil
        }
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
        let surfaces = Self.allSurfaces(snapshot.tree)

        // An existing surface id resolves to itself.
        if surfaces.contains(where: { $0.id == ref }) {
            return ref
        }

        let needle = ref.lowercased()
        guard !needle.isEmpty else { return nil }

        let matches = surfaces.filter { surface in
            if let title = surface.title, title.lowercased().contains(needle) { return true }
            if let filePath = surface.filePath {
                let fileName = filePath.split(separator: "/").last.map(String.init) ?? filePath
                if fileName.lowercased().contains(needle) { return true }
            }
            return false
        }

        // A unique match resolves; zero or multiple (ambiguous) matches yield nil.
        guard matches.count == 1 else { return nil }
        return matches[0].id
    }

    /// Whether `node`'s subtree contains a leaf pane with the given id.
    private static func containsPane(_ paneId: String, in node: LayoutNode) -> Bool {
        switch node {
        case let .pane(pane):
            return pane.paneId == paneId
        case let .split(_, _, children):
            return children.contains { containsPane(paneId, in: $0) }
        }
    }

    /// Collects every surface across all leaf panes, in left-to-right tree order.
    private static func allSurfaces(_ node: LayoutNode) -> [LayoutNode.Surface] {
        switch node {
        case let .pane(pane):
            return pane.surfaces
        case let .split(_, _, children):
            return children.flatMap(allSurfaces)
        }
    }

    /// Returns the id of the pane adjacent to `paneId` along `orientation`, if any.
    ///
    /// Walks the tree for the nearest enclosing split with the requested orientation that contains
    /// `paneId` in one of its child subtrees, then returns the first leaf pane of the sibling on the
    /// requested side (`preferNext` selects the next/lower sibling, otherwise the previous/upper).
    private static func directionalNeighbor(of paneId: String, orientation: LayoutNode.Orientation,
                                            preferNext: Bool, in node: LayoutNode) -> String? {
        switch node {
        case .pane:
            return nil
        case let .split(splitOrientation, _, children):
            // Descend first so a nearer enclosing split wins over an outer one.
            for child in children {
                if let found = directionalNeighbor(of: paneId, orientation: orientation,
                                                   preferNext: preferNext, in: child) {
                    return found
                }
            }
            if splitOrientation == orientation,
               let index = children.firstIndex(where: { containsPane(paneId, in: $0) }) {
                let siblingIndex = preferNext ? index + 1 : index - 1
                if siblingIndex >= 0, siblingIndex < children.count {
                    return firstPaneId(in: children[siblingIndex])
                }
            }
            return nil
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
