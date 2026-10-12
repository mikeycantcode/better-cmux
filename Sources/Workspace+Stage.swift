import AppKit
import Bonsplit
import Foundation
import SwiftUI

/// Where a new stage pane splits from its anchor.
nonisolated struct StageSplitPlacement: Equatable, Sendable {
    let orientation: SplitOrientation
    /// `true` puts the stage before the anchor (above it for `.vertical`).
    let insertFirst: Bool

    /// Wide windows put the stage on the right; tall windows put it on top.
    static func forWindowSize(_ size: CGSize?) -> StageSplitPlacement {
        guard let size, size.height > size.width else {
            return StageSplitPlacement(orientation: .horizontal, insertFirst: false)
        }
        return StageSplitPlacement(orientation: .vertical, insertFirst: true)
    }
}

/// The "stage": the rounded glass pane where `cmux open` content and new
/// terminals appear. Every pane created by a split is a stage pane; the card
/// treatment only applies while the workspace has more than one pane.
extension Workspace {
    func isStagePane(_ paneId: PaneID) -> Bool {
        stagePaneIds.contains(paneId.id) && bonsplitController.allPaneIds.count > 1
    }

    /// The most recently created live stage pane, if any.
    var liveStagePaneId: PaneID? {
        let livePanes = bonsplitController.allPaneIds
        guard livePanes.count > 1 else { return nil }
        for id in stagePaneIds.reversed() {
            if let pane = livePanes.first(where: { $0.id == id }) { return pane }
        }
        return nil
    }

    var stageSplitPlacement: StageSplitPlacement {
        StageSplitPlacement.forWindowSize(hostWindowSize)
    }

    private var hostWindowSize: CGSize? {
        guard let tabManager = owningTabManager,
              let app = AppDelegate.shared,
              let windowId = app.windowId(for: tabManager),
              let window = app.mainWindow(for: windowId) else {
            return NSApp.keyWindow?.frame.size
        }
        return window.frame.size
    }

    /// Opens files in the stage: as tabs in the live stage pane, or in a new
    /// stage pane split from `anchorPaneId` (right, or above in tall windows).
    @discardableResult
    func openFilesInStage(
        filePaths: [String],
        anchorPaneId: PaneID?,
        focus: Bool
    ) -> [any Panel] {
        guard let firstPath = filePaths.first else { return [] }
        if let stage = liveStagePaneId {
            return openFileSurfaces(
                inPane: stage,
                filePaths: filePaths,
                focus: focus,
                reuseExisting: filePaths.count == 1
            )
        }

        let previouslyFocusedPanelId = focusedPanelId
        guard let anchor = anchorPaneId ?? bonsplitController.focusedPaneId ?? bonsplitController.allPaneIds.first else {
            return []
        }
        let placement = stageSplitPlacement
        guard let firstPanel = splitPaneWithFileSurface(
            targetPane: anchor,
            orientation: placement.orientation,
            insertFirst: placement.insertFirst,
            filePath: firstPath
        ) else { return [] }

        var opened: [any Panel] = [firstPanel]
        if filePaths.count > 1, let stage = paneId(forPanelId: firstPanel.id) {
            opened += openFileSurfaces(
                inPane: stage,
                filePaths: Array(filePaths.dropFirst()),
                focus: focus
            )
        }
        if !focus, let previouslyFocusedPanelId, panels[previouslyFocusedPanelId] != nil {
            focusPanel(previouslyFocusedPanelId)
        }
        return opened
    }
}

extension Workspace {
    /// Pushes the stage card chrome into Bonsplit: every live stage pane is
    /// decorated while the workspace has more than one pane.
    func syncStagePaneDecorations() {
        if bonsplitController.paneDecorationView == nil {
            bonsplitController.paneDecorationView = { _, layer in
                AnyView(StageCardChrome(layer: layer))
            }
        }
        let livePanes = bonsplitController.allPaneIds
        var decorations: [PaneID: PaneDecoration] = [:]
        if livePanes.count > 1 {
            for pane in livePanes where stagePaneIds.contains(pane.id) {
                decorations[pane] = StagePaneCardMetrics.decoration
            }
        }
        bonsplitController.paneDecorations = decorations
        refreshStageRegion()
    }
}

/// Where the live stage pane sits in window coordinates (top-left origin), for
/// the translucent-backdrop gradient behind it. A dedicated object, not a
/// `Workspace` `@Published`: it changes on every divider drag, and only the
/// root backdrop mask should re-render for that.
@MainActor
final class StageRegionModel: ObservableObject {
    enum Placement: Equatable { case trailing, top }

    struct Region: Equatable {
        var frame: CGRect
        var placement: Placement
    }

    @Published private(set) var region: Region?

    func update(_ next: Region?) {
        switch (region, next) {
        case (nil, nil):
            return
        case let (current?, next?)
            where current.placement == next.placement
                && abs(current.frame.minX - next.frame.minX) < 0.5
                && abs(current.frame.minY - next.frame.minY) < 0.5
                && abs(current.frame.width - next.frame.width) < 0.5
                && abs(current.frame.height - next.frame.height) < 0.5:
            return
        default:
            region = next
        }
    }
}

extension Workspace {
    /// Recomputes ``stageRegionModel`` from Bonsplit's layout. Pane frames are
    /// in Bonsplit's global (window) coordinate space.
    func refreshStageRegion(snapshot: LayoutSnapshot? = nil) {
        guard let stage = liveStagePaneId else {
            stageRegionModel.update(nil)
            return
        }
        let layout = snapshot ?? bonsplitController.layoutSnapshot()
        guard let pane = layout.panes.first(where: { $0.paneId == stage.id.uuidString }) else {
            stageRegionModel.update(nil)
            return
        }
        let frame = CGRect(x: pane.frame.x, y: pane.frame.y, width: pane.frame.width, height: pane.frame.height)
        let container = layout.containerFrame
        let touchesTrailingEdge = frame.maxX >= container.x + container.width - 1
        let startsAfterLeadingEdge = frame.minX > container.x + 1
        let placement: StageRegionModel.Placement = touchesTrailingEdge && startsAfterLeadingEdge ? .trailing : .top
        stageRegionModel.update(.init(frame: frame, placement: placement))
    }
}
