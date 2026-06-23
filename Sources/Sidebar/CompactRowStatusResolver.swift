import Foundation
import CmuxSidebar

/// Resolves the color of a compact-row status dot from a workspace's status
/// entries.
///
/// The compact row shows a single colored dot reflecting the session's
/// lifecycle (running / idle / needs-input / unknown). Rather than inventing a
/// palette, it reuses the color carried by the highest-priority
/// ``SidebarStatusEntry`` — the same color the detailed status row renders — so
/// the dot stays visually consistent with the rest of the UI.
enum CompactRowStatusResolver {
    /// The hex color string for the dot, or `nil` when no status entry carries a
    /// usable color (caller should fall back to a neutral/secondary color).
    ///
    /// - Parameter entries: status entries already sorted highest-priority-first
    ///   (as produced by `Workspace.sidebarStatusEntriesInDisplayOrder()`).
    /// - Returns: the first non-empty `color` hex among `entries`, or `nil`.
    static func dotColorHex(for entries: [SidebarStatusEntry]) -> String? {
        for entry in entries {
            if let color = entry.color, !color.trimmingCharacters(in: .whitespaces).isEmpty {
                return color
            }
        }
        return nil
    }
}
