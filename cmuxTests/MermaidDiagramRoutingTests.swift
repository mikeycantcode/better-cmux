import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite
struct MermaidDiagramRoutingTests {
    private func writeTempFile(ext: String, contents: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-diagram-\(UUID().uuidString).\(ext)")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    @Test
    func diagramFileOpensInDiagramMode() throws {
        let path = try writeTempFile(ext: "mmd", contents: "flowchart LR\n  a --> b")
        let panel = MarkdownPanel(workspaceId: UUID(), filePath: path)
        #expect(panel.isDiagramFile)
        #expect(panel.displayMode == .diagram)
    }

    @Test
    func diagramContentIsFenceWrapped() throws {
        let path = try writeTempFile(ext: "mmd", contents: "flowchart LR\n  a --> b")
        let panel = MarkdownPanel(workspaceId: UUID(), filePath: path)
        #expect(panel.content == "```mermaid\nflowchart LR\n  a --> b\n```")
    }

    @Test
    func markdownFileIsUnaffected() throws {
        let path = try writeTempFile(ext: "md", contents: "# Title")
        let panel = MarkdownPanel(workspaceId: UUID(), filePath: path)
        #expect(!panel.isDiagramFile)
        #expect(panel.displayMode == .preview)
        #expect(panel.content == "# Title")
    }

    @Test
    func fileOpenRoutesDiagramFilesToADiagramMarkdownPanel() throws {
        // Drives the real socket path so this covers `cmux open arch.mmd`
        // end-to-end, not just the panel's own constructor.
        let path = try writeTempFile(ext: "mmd", contents: "flowchart LR\n  a --> b")
        defer { TerminalController.shared.setActiveTabManager(nil) }

        let manager = TabManager()
        let workspace = manager.addWorkspace(select: true, eagerLoadTerminal: false)
        let pane = try #require(workspace.bonsplitController.allPaneIds.first)
        TerminalController.shared.setActiveTabManager(manager)

        let result = TerminalController.shared.v2FileOpen(params: [
            "paths": [path],
            "workspace_id": workspace.id.uuidString,
            "pane_id": pane.id.uuidString,
            "focus": false
        ])

        guard case .ok(let rawPayload) = result,
              let payload = rawPayload as? [String: Any],
              let openedIdString = payload["surface_id"] as? String,
              let openedId = UUID(uuidString: openedIdString) else {
            Issue.record("Expected file.open to succeed for a .mmd file, got \(result)")
            return
        }

        let panel = try #require(workspace.markdownPanel(for: openedId))
        #expect(panel.isDiagramFile)
        #expect(panel.displayMode == .diagram)
        #expect(workspace.filePreviewPanel(for: openedId) == nil)
        #expect(payload["panel_type"] as? String == PanelType.markdown.rawValue)
        #expect(payload["display_mode"] as? String == MarkdownPanelDisplayMode.diagram.rawValue)
    }

    @Test
    func textModeOnADiagramFileExposesRawUnwrappedSource() throws {
        let path = try writeTempFile(ext: "mmd", contents: "flowchart LR\n  a --> b")
        let panel = MarkdownPanel(workspaceId: UUID(), filePath: path)
        panel.setDisplayMode(.text)
        // The editor must show the real file, not the synthesized fence.
        #expect(panel.textContent == "flowchart LR\n  a --> b")
    }
}
