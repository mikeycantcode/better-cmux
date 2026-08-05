import Foundation
import Darwin
import CmuxNotifications
import CmuxSidebar

extension Workspace {
    struct DetachedAgentRuntimeState {
        let panelId: UUID
        let statusEntries: [String: SidebarStatusEntry]
        let agentPIDs: [String: pid_t]
        let agentPIDKeys: Set<String>
    }

    struct DetachedSurfaceTransfer {
        let sourceWorkspaceId: UUID
        let panelId: UUID
        let panel: any Panel
        let title: String
        let icon: String?
        let iconImageData: Data?
        let kind: String?
        let isLoading: Bool
        let isPinned: Bool
        let directory: String?
        let ttyName: String?
        let cachedTitle: String?
        let customTitle: String?
        let customTitleSource: Workspace.CustomTitleSource?
        let manuallyUnread: Bool
        let restoredUnreadIndicator: RestoredPanelUnreadIndicator?
        let restorableAgent: SessionRestorableAgentSnapshot?
        let restorableAgentResumeState: RestoredAgentResumeState?
        let resumeBinding: SurfaceResumeBindingSnapshot?
        let agentRuntime: DetachedAgentRuntimeState?
    }
}
