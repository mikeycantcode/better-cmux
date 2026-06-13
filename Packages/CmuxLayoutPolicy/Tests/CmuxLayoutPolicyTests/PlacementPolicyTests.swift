import Testing
@testable import CmuxLayoutPolicy

@Suite struct PlacementPolicyTests {
    let policy = PlacementPolicy()

    // Helpers to build snapshots.
    func surface(_ id: String, type: String = "terminal", file: String? = nil) -> LayoutNode.Surface {
        .init(id: id, type: type, title: nil, filePath: file, url: nil)
    }
    func pane(_ id: String, _ surfaces: [LayoutNode.Surface], focused: Bool = false) -> LayoutNode {
        .pane(.init(paneId: id, focused: focused, selectedSurfaceId: surfaces.first?.id, surfaces: surfaces))
    }
    func snap(_ tree: LayoutNode, anchorSurface: String, anchorPane: String) -> LayoutSnapshot {
        .init(workspaceId: "w", focusedPaneId: anchorPane,
              anchor: .init(surfaceId: anchorSurface, paneId: anchorPane), tree: tree)
    }

    @Test func singlePaneSplitsRight() {
        let s = snap(pane("P1", [surface("A")], focused: true), anchorSurface: "A", anchorPane: "P1")
        #expect(policy.decide(filePath: "/x.txt", in: s, anchorSurfaceId: "A", overrides: .init())
                == .splitRight(fromSurfaceId: "A"))
    }

    @Test func alreadyHorizontalSplitOpensTabInNeighbor() {
        let tree = LayoutNode.split(orientation: .horizontal, dividerPosition: 0.5, children: [
            pane("P1", [surface("A")], focused: true),
            pane("P2", [surface("B", type: "browser")]),
        ])
        let s = snap(tree, anchorSurface: "A", anchorPane: "P1")
        #expect(policy.decide(filePath: "/x.txt", in: s, anchorSurfaceId: "A", overrides: .init())
                == .newTab(inPaneId: "P2"))
    }

    @Test func verticalSplitStillSplitsRight() {
        // A vertical (stacked) split is NOT a horizontal neighbor → still prefer a beside split.
        let tree = LayoutNode.split(orientation: .vertical, dividerPosition: 0.5, children: [
            pane("P1", [surface("A")], focused: true),
            pane("P2", [surface("B")]),
        ])
        let s = snap(tree, anchorSurface: "A", anchorPane: "P1")
        #expect(policy.decide(filePath: "/x.txt", in: s, anchorSurfaceId: "A", overrides: .init())
                == .splitRight(fromSurfaceId: "A"))
    }

    @Test func reusesAlreadyOpenFile() {
        let tree = LayoutNode.split(orientation: .horizontal, dividerPosition: 0.5, children: [
            pane("P1", [surface("A")], focused: true),
            pane("P2", [surface("F", type: "filePreview", file: "/x.txt")]),
        ])
        let s = snap(tree, anchorSurface: "A", anchorPane: "P1")
        #expect(policy.decide(filePath: "/x.txt", in: s, anchorSurfaceId: "A", overrides: .init())
                == .reuse(surfaceId: "F"))
    }

    @Test func forceHereOpensInAnchorPane() {
        let s = snap(pane("P1", [surface("A")], focused: true), anchorSurface: "A", anchorPane: "P1")
        #expect(policy.decide(filePath: "/x.txt", in: s, anchorSurfaceId: "A",
                              overrides: .init(forceHere: true)) == .here(paneId: "P1"))
    }
}
