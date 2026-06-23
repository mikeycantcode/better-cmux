import Foundation
import Bonsplit

extension TerminalController {
    /// Builds the read-only `workspace.snapshot` response: the full bonsplit layout tree,
    /// per-surface descriptors, the calling agent's echoed anchor, and a self-documenting
    /// `actions` list. The emitted JSON decodes cleanly into `CmuxLayoutPolicy.LayoutSnapshot`
    /// (the CLI's placement contract); extra keys (`container_frame`, per-pane `frame`,
    /// `actions`) are ignored by that decoder but consumed by the spec/CLI.
    ///
    /// Read-only and focus-neutral: this never activates a window, selects a workspace, or
    /// changes focus. The tree/panel reads are MainActor state, so the handler runs off-main
    /// (socket worker) and hops to the main actor via `v2MainSync` for the snapshot read only.
    nonisolated func v2WorkspaceSnapshot(params: [String: Any]) -> V2CallResult {
        guard let tabManager = v2MainSync({ self.v2ResolveTabManager(params: params) }) else {
            return .err(code: "unavailable", message: "TabManager not available", data: nil)
        }

        var payload: [String: Any]?
        v2MainSync {
            guard let ws = self.v2ResolveWorkspace(params: params, tabManager: tabManager) else { return }

            let controller = ws.bonsplitController
            let tree = controller.treeSnapshot()

            // Echo the caller's anchor surface and resolve its owning pane (no focus change).
            let anchorSurfaceId = Self.snapshotAnchorSurfaceId(params: params)
            let anchorPaneId: String? = {
                guard let anchorSurfaceId,
                      let panelUUID = UUID(uuidString: anchorSurfaceId) else { return nil }
                return ws.paneId(forPanelId: panelUUID)?.id.uuidString
            }()

            let containerFrame: [String: Any]
            switch tree {
            case .pane(let p): containerFrame = Self.snapshotFrameDict(p.frame)
            case .split(let s):
                // The split tree's outermost node carries no frame; derive the union from children.
                _ = s
                containerFrame = Self.snapshotContainerFrame(of: tree)
            }

            payload = [
                "workspace_id": ws.id.uuidString,
                "container_frame": containerFrame,
                "focused_pane_id": self.v2OrNull(controller.focusedPaneId?.id.uuidString),
                "anchor": [
                    "surface_id": self.v2OrNull(anchorSurfaceId),
                    "pane_id": self.v2OrNull(anchorPaneId)
                ],
                "tree": Self.snapshotNode(tree, workspace: ws),
                "actions": Self.snapshotActions
            ]
        }

        guard let payload else {
            return .err(code: "not_found", message: "Workspace not found", data: nil)
        }
        return .ok(payload)
    }

    /// The anchor surface id the caller supplied (its own `CMUX_SURFACE_ID`), echoed back so
    /// the CLI can root its placement policy on the agent's surface. Accepts `surface_id`.
    private nonisolated static func snapshotAnchorSurfaceId(params: [String: Any]) -> String? {
        if let raw = (params["surface_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return raw
        }
        return nil
    }

    /// Maps one bonsplit `ExternalTreeNode` into the contract JSON node
    /// (`{kind:"split", orientation, divider_position, children}` or
    /// `{kind:"pane", pane_id, frame, focused, selected_surface_id, surfaces}`).
    @MainActor
    private static func snapshotNode(_ node: ExternalTreeNode, workspace ws: Workspace) -> [String: Any] {
        switch node {
        case .split(let split):
            return [
                "kind": "split",
                "orientation": split.orientation,
                "divider_position": split.dividerPosition,
                "children": [
                    snapshotNode(split.first, workspace: ws),
                    snapshotNode(split.second, workspace: ws)
                ]
            ]
        case .pane(let pane):
            let paneUUID = UUID(uuidString: pane.id)
            let focusedPaneId = ws.bonsplitController.focusedPaneId?.id.uuidString
            // Resolve surface descriptors from the owning panel; surface ids are panel ids
            // (the socket-facing surface id), not the internal bonsplit tab id.
            var surfaces: [[String: Any]] = []
            var selectedSurfaceId: String?
            for tab in pane.tabs {
                let tabID = TabID(uuid: UUID(uuidString: tab.id) ?? UUID())
                guard let panelUUID = ws.panelIdFromSurfaceId(tabID) else { continue }
                let panel = ws.panels[panelUUID]
                let surfaceIdString = panelUUID.uuidString
                if tab.id == pane.selectedTabId { selectedSurfaceId = surfaceIdString }
                surfaces.append(snapshotSurface(
                    surfaceId: surfaceIdString,
                    title: tab.title,
                    panel: panel
                ))
            }
            return [
                "kind": "pane",
                "pane_id": pane.id,
                "frame": snapshotFrameDict(pane.frame),
                "focused": (paneUUID != nil && pane.id == focusedPaneId),
                "selected_surface_id": selectedSurfaceId as Any? ?? NSNull(),
                "surfaces": surfaces
            ]
        }
    }

    /// One surface (tab) descriptor: stable type token, title, plus best-effort
    /// `file_path` (file preview / markdown) and `url` (browser). Fields that are not cheaply
    /// available are omitted rather than emitted as null.
    @MainActor
    private static func snapshotSurface(
        surfaceId: String,
        title: String,
        panel: (any Panel)?
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "id": surfaceId,
            "type": snapshotTypeToken(panel?.panelType),
            "title": title
        ]
        switch panel {
        case let filePreview as FilePreviewPanel:
            dict["file_path"] = filePreview.filePath
        case let markdown as MarkdownPanel:
            dict["file_path"] = markdown.filePath
        case let browser as BrowserPanel:
            if let url = browser.currentURL?.absoluteString { dict["url"] = url }
        default:
            break
        }
        return dict
    }

    /// Stable, contract-facing surface type token. `filePreview` is spelled in lowerCamelCase
    /// here (not the panel's `"filepreview"` raw value) so the CLI's reuse detection — which
    /// matches `type == "filePreview"` — works against the emitted JSON.
    private nonisolated static func snapshotTypeToken(_ type: PanelType?) -> String {
        switch type {
        case .terminal: return "terminal"
        case .browser, .extensionBrowser: return "browser"
        case .markdown: return "markdown"
        case .filePreview: return "filePreview"
        case .project: return "project"
        case .rightSidebarTool: return "rightSidebarTool"
        case .customSidebar: return "customSidebar"
        case .agentSession: return "agentSession"
        case .none: return "unknown"
        }
    }

    /// Converts a bonsplit `PixelRect` into the `{x,y,width,height}` JSON the spec uses.
    private nonisolated static func snapshotFrameDict(_ rect: PixelRect) -> [String: Any] {
        ["x": rect.x, "y": rect.y, "width": rect.width, "height": rect.height]
    }

    /// Union frame covering every pane under `node`, used for the top-level `container_frame`
    /// when the root is a split (which itself carries no frame).
    private nonisolated static func snapshotContainerFrame(of node: ExternalTreeNode) -> [String: Any] {
        var minX = Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        var found = false
        func walk(_ n: ExternalTreeNode) {
            switch n {
            case .pane(let p):
                found = true
                minX = min(minX, p.frame.x)
                minY = min(minY, p.frame.y)
                maxX = max(maxX, p.frame.x + p.frame.width)
                maxY = max(maxY, p.frame.y + p.frame.height)
            case .split(let s):
                walk(s.first)
                walk(s.second)
            }
        }
        walk(node)
        guard found else { return ["x": 0, "y": 0, "width": 0, "height": 0] }
        return ["x": minX, "y": minY, "width": maxX - minX, "height": maxY - minY]
    }

    /// The static, self-documenting list of layout verbs the snapshot advertises. Mirrors the
    /// CLI subcommands so any agent reading the snapshot also learns what it can do.
    private nonisolated static var snapshotActions: [[String: Any]] {
        [
            ["verb": "open", "cli": "cmux open <file>",
             "desc": "Show a file beside you (smart placement)."],
            ["verb": "snapshot", "cli": "cmux snapshot",
             "desc": "This layout, as JSON."],
            ["verb": "move-tab", "cli": "cmux move-tab <surface> --to-pane <pane|left|right|up|down>",
             "desc": "Move a tab to another pane."],
            ["verb": "reorder-tab", "cli": "cmux reorder-tab <surface> --index N",
             "desc": "Reorder a tab within its pane."],
            ["verb": "swap-panes", "cli": "cmux swap-panes <a> <b>",
             "desc": "Swap two panes."]
        ]
    }
}
