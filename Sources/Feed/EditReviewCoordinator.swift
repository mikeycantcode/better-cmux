import AppKit
import Bonsplit
import CmuxEditPreview
import CMUXAgentLaunch
import Foundation

/// Opens a read-only edit-review diff above the agent for a pending file-edit permission, and
/// closes it when the permission resolves or times out.
///
/// Owns only a `requestId → (workspace, panelId)` registry — it stores the panel's id (a `UUID`),
/// never the panel object, so resolving/closing the panel deallocates it. The anchor resolver and
/// pane locator are injected so the type stays free of hard singleton wiring and is testable.
@MainActor
final class EditReviewCoordinator {
    /// Resolves a workstream id to its (workspaceId, surfaceId) anchor strings.
    private let resolveAnchor: (_ workstreamId: String) -> (workspaceId: String, surfaceId: String)?
    /// Finds the `Workspace` and the agent surface's `PaneID` for an anchor.
    private let resolvePane: (_ workspaceId: String, _ surfaceId: String) -> (Workspace, PaneID)?
    private var open: [String: (workspace: Workspace, panelId: UUID)] = [:]
    private let computer = EditPreviewComputer()

    init(
        resolveAnchor: @escaping (_ workstreamId: String) -> (workspaceId: String, surfaceId: String)?,
        resolvePane: @escaping (_ workspaceId: String, _ surfaceId: String) -> (Workspace, PaneID)?
    ) {
        self.resolveAnchor = resolveAnchor
        self.resolvePane = resolvePane
    }

    /// Opens a diff pane if this is an applicable file edit and the setting is on.
    ///
    /// `originalText` is read off-main by the caller. `reply` resolves the permission; it must
    /// capture only the request id and a singleton/weak target — NEVER the panel.
    func handlePending(requestId: String, workstreamId: String, toolName: String,
                       toolInputJSON: String, originalText: String?,
                       reply: @escaping (String, WorkstreamPermissionMode) -> Void) {
        guard ManualEditDiffSettings.isEnabled(),
              open[requestId] == nil,
              let edit = ProposedEdit.from(toolName: toolName, toolInputJSON: toolInputJSON),
              let diff = computer.compute(edit, originalText: originalText),
              let anchor = resolveAnchor(workstreamId),
              let (workspace, paneId) = resolvePane(anchor.workspaceId, anchor.surfaceId)
        else { return }

        guard let panel = workspace.splitPaneWithEditReview(
            targetPane: paneId, orientation: .vertical, insertFirst: true,
            requestId: requestId, diff: diff
        ) else { return }
        // Capture ONLY requestId + reply (a singleton-backed closure). Do NOT capture `panel`.
        panel.onDecision = { mode in reply(requestId, mode) }
        open[requestId] = (workspace, panel.id)
    }

    /// Closes the diff pane for a resolved/timed-out request, if open.
    func handleResolved(requestId: String) {
        guard let entry = open.removeValue(forKey: requestId) else { return }
        _ = entry.workspace.closePanel(entry.panelId, force: true)
    }
}
