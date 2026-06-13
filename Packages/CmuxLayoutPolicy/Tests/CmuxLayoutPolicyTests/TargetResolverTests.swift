import Testing
@testable import CmuxLayoutPolicy

@Suite struct TargetResolverTests {
    let resolver = TargetResolver()

    // Helpers to build snapshots.
    func surface(_ id: String, type: String = "terminal", title: String? = nil, file: String? = nil) -> LayoutNode.Surface {
        .init(id: id, type: type, title: title, filePath: file, url: nil)
    }
    func pane(_ id: String, _ surfaces: [LayoutNode.Surface], focused: Bool = false) -> LayoutNode {
        .pane(.init(paneId: id, focused: focused, selectedSurfaceId: surfaces.first?.id, surfaces: surfaces))
    }
    func snap(_ tree: LayoutNode, focusedPane: String?) -> LayoutSnapshot {
        .init(workspaceId: "w", focusedPaneId: focusedPane,
              anchor: .init(surfaceId: nil, paneId: focusedPane), tree: tree)
    }

    // A side-by-side (horizontal) split: P1 on the left, P2 on the right.
    func sideBySide() -> LayoutSnapshot {
        let tree = LayoutNode.split(orientation: .horizontal, dividerPosition: 0.5, children: [
            pane("P1", [surface("A")], focused: true),
            pane("P2", [surface("B", type: "browser")]),
        ])
        return snap(tree, focusedPane: "P1")
    }

    @Test func directionRightResolvesToNeighborPane() {
        let s = sideBySide()
        #expect(resolver.resolvePane("right", anchorPaneId: "P1", in: s) == "P2")
    }

    @Test func focusedResolvesToFocusedPane() {
        let s = sideBySide()
        #expect(resolver.resolvePane("focused", anchorPaneId: "P2", in: s) == "P1")
    }

    @Test func exactPaneIdPassesThrough() {
        let s = sideBySide()
        #expect(resolver.resolvePane("P2", anchorPaneId: "P1", in: s) == "P2")
    }

    @Test func uniqueFilenameSubstringResolvesSurface() {
        let tree = LayoutNode.split(orientation: .horizontal, dividerPosition: 0.5, children: [
            pane("P1", [surface("A")], focused: true),
            pane("P2", [surface("V", type: "filePreview", file: "/tmp/recordings/eval.mp4")]),
        ])
        let s = snap(tree, focusedPane: "P1")
        #expect(resolver.resolveSurface("eval.mp4", in: s) == "V")
    }

    @Test func ambiguousSubstringReturnsNil() {
        let tree = LayoutNode.split(orientation: .horizontal, dividerPosition: 0.5, children: [
            pane("P1", [surface("A", type: "filePreview", file: "/a/eval.mp4")], focused: true),
            pane("P2", [surface("B", type: "filePreview", file: "/b/eval.mp4")]),
        ])
        let s = snap(tree, focusedPane: "P1")
        #expect(resolver.resolveSurface("eval", in: s) == nil)
    }

    @Test func nonMatchReturnsNil() {
        let s = sideBySide()
        #expect(resolver.resolveSurface("does-not-exist", in: s) == nil)
    }

    @Test func exactSurfaceIdPassesThrough() {
        let s = sideBySide()
        #expect(resolver.resolveSurface("B", in: s) == "B")
    }
}
