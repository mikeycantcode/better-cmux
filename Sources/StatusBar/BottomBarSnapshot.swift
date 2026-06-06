import Foundation

/// Immutable inputs the bottom bar renders. Built by the owning view from the
/// active workspace + providers so the always-present bar doesn't couple to
/// high-churn observable state in its body.
struct BottomBarSnapshot: Equatable {
    let appVersion: String
    let branch: String?
    let isDirty: Bool
    let staged: StagedDiffStats
    let editorDisplayName: String
    let agentActive: Bool
    let contextUsage: ContextUsage?

    static let placeholder = BottomBarSnapshot(
        appVersion: "",
        branch: nil,
        isDirty: false,
        staged: .empty,
        editorDisplayName: "",
        agentActive: false,
        contextUsage: nil
    )
}
