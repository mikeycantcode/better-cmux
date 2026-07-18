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
    func textModeOnADiagramFileExposesRawUnwrappedSource() throws {
        let path = try writeTempFile(ext: "mmd", contents: "flowchart LR\n  a --> b")
        let panel = MarkdownPanel(workspaceId: UUID(), filePath: path)
        panel.setDisplayMode(.text)
        // The editor must show the real file, not the synthesized fence.
        #expect(panel.textContent == "flowchart LR\n  a --> b")
    }
}
