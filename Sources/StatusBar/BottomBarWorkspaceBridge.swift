import SwiftUI

/// Builds the ``BottomBarSnapshot`` for the active workspace and renders
/// ``CmuxBottomBar``. Observes the workspace (git branch) and the staged-diff
/// store so the bar updates when either changes.
struct BottomBarWorkspaceBridge: View {
    @ObservedObject var workspace: Workspace
    @ObservedObject var stagedDiffStore: BottomBarStagedDiffStore
    let appVersion: String
    let editorDisplayName: String
    let contextProvider: any ContextUsageProviding
    var backgroundColor: Color? = nil

    var body: some View {
        let agentActive: Bool = {
            guard let kind = workspace.focusedTerminalPanel?.agentHibernationState?.agent.kind else { return false }
            return kind == .claude || kind == .codex
        }()
        let snapshot = BottomBarSnapshot(
            appVersion: appVersion,
            branch: workspace.gitBranch?.branch,
            isDirty: workspace.gitBranch?.isDirty ?? false,
            staged: stagedDiffStore.stats,
            editorDisplayName: editorDisplayName,
            agentActive: agentActive,
            contextUsage: contextProvider.usage(
                workingDirectory: workspace.currentDirectory,
                agentActive: agentActive
            )
        )
        CmuxBottomBar(snapshot: snapshot, backgroundColor: backgroundColor)
    }
}
