import CoreGraphics

/// Layout constants for the floating liquid-glass sidebar panel.
///
/// The left sidebar renders as a rounded panel inset from the window edges,
/// floating over the full-width terminal content rather than pushing it
/// aside. These constants are shared with the panel's hit-testing (see
/// `WindowTerminalHostView`) so the underlapping terminal region is computed
/// consistently.
enum SidebarFloatingPanelMetrics {
    /// Leading/top/bottom gap from the window edges to the floating panel.
    static let inset: CGFloat = 8

    /// Corner radius applied to the floating panel's backdrop.
    static let cornerRadius: CGFloat = 12
}
