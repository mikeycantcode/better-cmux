import AppKit
import CmuxEditPreview
import CMUXAgentLaunch
import Combine
import Foundation
import SwiftUI

/// A non-terminal panel that reviews one pending Claude file edit as a read-only Monaco diff.
///
/// Created above the agent's pane when a file-edit permission is pending. Its Accept / Reject /
/// Always-allow buttons resolve the permission via the existing `feed.permission.reply` path
/// (the coordinator sets ``onDecision``), after which the coordinator closes the panel.
@MainActor
final class EditReviewPanel: ObservableObject, Panel {
    let id = UUID()
    let workspaceId: UUID
    /// The permission request this panel reviews; used to resolve the decision.
    let requestId: String
    /// The computed diff to display.
    let diff: EditDiff
    /// Owns the Monaco web view across SwiftUI churn (same pattern as `FilePreviewPanel`).
    let monacoController = MonacoWebController()
    /// Invoked when the user picks a decision; the coordinator routes it to the permission reply.
    var onDecision: ((WorkstreamPermissionMode) -> Void)?

    // Reuse the closest existing kind: there is no `.editReview` case, and the panel
    // is distinguished from `FilePreviewPanel` by instance at the dispatch site.
    let panelType: PanelType = .filePreview
    var displayTitle: String { (diff.filePath as NSString).lastPathComponent }
    var displayIcon: String? { "plus.forwardslash.minus" }
    var isDirty: Bool { false }

    private var isClosed = false

    init(workspaceId: UUID, requestId: String, diff: EditDiff) {
        self.workspaceId = workspaceId
        self.requestId = requestId
        self.diff = diff
    }

    func close() {
        guard !isClosed else { return }
        isClosed = true
        monacoController.dismantle()
    }

    func focus() {
        monacoController.focus()
    }

    func unfocus() {
        // No-op. AppKit resigns the web view when another panel becomes first responder.
    }

    func triggerFlash(reason: WorkspaceAttentionFlashReason) {
        // No-op: this is a transient review panel that opens above the agent and closes on the
        // accept/reject decision, so it has no attention-flash affordance to drive.
        _ = reason
    }

    deinit {
        // Backstop teardown for detach/transfer paths where `close()` is never called.
        // The controller is owned by this panel; dismantle it on the main actor so the
        // bridge handler and web view are torn down deterministically.
        let controller = monacoController
        Task { @MainActor in
            controller.dismantle()
        }
    }
}
