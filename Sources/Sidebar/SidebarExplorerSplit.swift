import CoreGraphics

/// Geometry for the left-sidebar vertical split between the session list (top)
/// and the file explorer (bottom).
///
/// The stored split is a *session fraction* in `0.0...1.0` (the share of the
/// available height given to the session list). This clamps it so neither the
/// session list nor the explorer collapses below a usable minimum.
enum SidebarExplorerSplit {
    /// Minimum height for the session list (about two rows).
    static let minSessionListHeight: CGFloat = 96
    /// Minimum height for the file explorer when expanded.
    static let minExplorerHeight: CGFloat = 80
    /// Fallback fraction when geometry is unavailable or invalid.
    static let fallbackFraction: CGFloat = 0.6

    /// Clamps a session fraction to keep both panes usable.
    /// - Parameters:
    ///   - fraction: desired share of height for the session list.
    ///   - availableHeight: total height to split (excludes the footer/divider).
    /// - Returns: a finite fraction in `[minFrac, maxFrac]`, or
    ///   ``fallbackFraction`` when `availableHeight` is non-positive/invalid.
    static func clampedSessionFraction(_ fraction: CGFloat, availableHeight: CGFloat) -> CGFloat {
        guard availableHeight.isFinite, availableHeight > 0 else { return fallbackFraction }
        let safeFraction = fraction.isFinite ? fraction : fallbackFraction
        let minFrac = min(0.9, minSessionListHeight / availableHeight)
        let maxFrac = max(0.1, 1 - (minExplorerHeight / availableHeight))
        guard minFrac <= maxFrac else { return 0.5 }
        return min(max(safeFraction, minFrac), maxFrac)
    }
}
