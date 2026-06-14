import Foundation

/// The decoded `workspace.snapshot` response: the workspace layout tree plus the calling
/// agent's anchor. Mirrors the JSON the app emits; the CLI decodes it to drive placement.
public struct LayoutSnapshot: Codable, Sendable, Equatable {
    public let workspaceId: String
    public let focusedPaneId: String?
    public let anchor: Anchor
    public let tree: LayoutNode

    public struct Anchor: Codable, Sendable, Equatable {
        public let surfaceId: String?
        public let paneId: String?
        public init(surfaceId: String?, paneId: String?) {
            self.surfaceId = surfaceId; self.paneId = paneId
        }
    }

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
        case focusedPaneId = "focused_pane_id"
        case anchor, tree
    }

    public init(workspaceId: String, focusedPaneId: String?, anchor: Anchor, tree: LayoutNode) {
        self.workspaceId = workspaceId; self.focusedPaneId = focusedPaneId
        self.anchor = anchor; self.tree = tree
    }
}

/// A node in the split tree: either a split (with oriented children) or a leaf pane.
public indirect enum LayoutNode: Codable, Sendable, Equatable {
    case split(orientation: Orientation, dividerPosition: Double, children: [LayoutNode])
    case pane(Pane)

    /// Split arrangement. `horizontal` = side-by-side panes (a vertical divider); this is the
    /// "beside" orientation the placement policy prefers.
    public enum Orientation: String, Codable, Sendable { case horizontal, vertical }

    /// A leaf pane holding a list of surfaces (tabs).
    public struct Pane: Codable, Sendable, Equatable {
        public let paneId: String
        public let focused: Bool
        public let selectedSurfaceId: String?
        public let surfaces: [Surface]
        enum CodingKeys: String, CodingKey {
            case paneId = "pane_id"
            case focused
            case selectedSurfaceId = "selected_surface_id"
            case surfaces
        }
        public init(paneId: String, focused: Bool, selectedSurfaceId: String?, surfaces: [Surface]) {
            self.paneId = paneId; self.focused = focused
            self.selectedSurfaceId = selectedSurfaceId; self.surfaces = surfaces
        }
    }

    /// One tab/surface and what it shows.
    public struct Surface: Codable, Sendable, Equatable {
        public let id: String
        public let type: String          // terminal | browser | filePreview | markdown | …
        public let title: String?
        public let filePath: String?
        public let url: String?
        enum CodingKeys: String, CodingKey {
            case id, type, title
            case filePath = "file_path"
            case url
        }
        public init(id: String, type: String, title: String?, filePath: String?, url: String?) {
            self.id = id; self.type = type; self.title = title
            self.filePath = filePath; self.url = url
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, orientation, dividerPosition = "divider_position", children }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "split":
            self = .split(
                orientation: try c.decode(Orientation.self, forKey: .orientation),
                dividerPosition: try c.decodeIfPresent(Double.self, forKey: .dividerPosition) ?? 0.5,
                children: try c.decode([LayoutNode].self, forKey: .children))
        default:
            self = .pane(try Pane(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .split(orientation, divider, children):
            try c.encode("split", forKey: .kind)
            try c.encode(orientation, forKey: .orientation)
            try c.encode(divider, forKey: .dividerPosition)
            try c.encode(children, forKey: .children)
        case let .pane(pane):
            try c.encode("pane", forKey: .kind)
            try pane.encode(to: encoder)
        }
    }
}
