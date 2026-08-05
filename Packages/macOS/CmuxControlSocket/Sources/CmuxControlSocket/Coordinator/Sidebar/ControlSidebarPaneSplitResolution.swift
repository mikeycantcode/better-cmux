public import Foundation

/// The outcome of the v1 `new_pane` split.
public enum ControlSidebarPaneSplitResolution: Sendable, Equatable {
    /// The pane was created.
    case created(UUID)
    /// Creation failed.
    case failed
}
