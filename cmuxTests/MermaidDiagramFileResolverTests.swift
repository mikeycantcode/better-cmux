import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite
struct MermaidDiagramFileResolverTests {
    @Test
    func recognizesDiagramExtensions() {
        #expect(MermaidDiagramFileResolver.isDiagramPathLike("arch.mmd"))
        #expect(MermaidDiagramFileResolver.isDiagramPathLike("/tmp/a/arch.mermaid"))
        #expect(MermaidDiagramFileResolver.isDiagramPathLike("docs/FLOW.MMD"))
    }

    @Test
    func rejectsNonDiagramPaths() {
        #expect(!MermaidDiagramFileResolver.isDiagramPathLike("notes.md"))
        #expect(!MermaidDiagramFileResolver.isDiagramPathLike("main.swift"))
        #expect(!MermaidDiagramFileResolver.isDiagramPathLike(""))
        #expect(!MermaidDiagramFileResolver.isDiagramPathLike("https://example.com/a.mmd"))
    }

    @Test
    func wrapsSourceInMermaidFence() {
        let wrapped = MermaidDiagramFileResolver.wrapAsMermaidFence("flowchart LR\n  a --> b")
        #expect(wrapped == "```mermaid\nflowchart LR\n  a --> b\n```")
    }

    @Test
    func wrappingTrimsTrailingNewlinesSoTheFenceStaysValid() {
        let wrapped = MermaidDiagramFileResolver.wrapAsMermaidFence("graph TD\n  a --> b\n\n\n")
        #expect(wrapped == "```mermaid\ngraph TD\n  a --> b\n```")
    }

    @Test
    func wrappingEmptySourceProducesAnEmptyFence() {
        #expect(MermaidDiagramFileResolver.wrapAsMermaidFence("   \n ") == "```mermaid\n\n```")
    }
}
