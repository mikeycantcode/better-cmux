import CmuxWorkspaces
import Foundation
import SwiftUI

/// Immutable per-space value for the herdr sidebar's upper region.
///
/// `id` is the workspace id; rows never see a `Workspace` reference
/// (snapshot-boundary rule).
struct HerdrSidebarSpaceItem: Identifiable, Equatable {
    let id: UUID
    let title: String
    /// `nil` means the workspace has no agents → dim dot.
    let rollup: AgentSidebarStatus?
    let isSelected: Bool
    /// Drives the Pin/Unpin context-menu label. It must live on the item (and
    /// therefore inside the compared value) because `HerdrSpacesRowContainer`'s
    /// `==` skips the body — a menu built from state that is not compared here
    /// would keep showing a stale label after pinning or unpinning.
    let isPinned: Bool
}

/// Layout container for the herdr left sidebar.
///
/// Holds **no** store references: every value arrives as a snapshot and every
/// action leaves through a closure. The `ForEach` snapshot boundary starts here.
struct HerdrSidebarView: View {
    let spaces: [HerdrSidebarSpaceItem]
    /// Already sorted worst-first / newest-first by `AgentsSidebarModel`.
    let agents: [AgentRowSnapshot]
    let selectedPanelId: UUID?
    let onSelectSpace: (UUID) -> Void
    let onActivateAgent: (UUID, UUID) -> Void
    /// Receives the full item so menu content can be derived from compared state.
    let onSpaceContextMenu: (HerdrSidebarSpaceItem) -> AnyView

    var body: some View {
        VStack(spacing: 0) {
            spacesRegion
                .layoutPriority(1)
            Divider()
                .opacity(0.4)
            agentsRegion
                .frame(
                    minHeight: Self.agentsMinHeight(rowCount: agents.count),
                    maxHeight: .infinity
                )
        }
    }

    // MARK: - Spaces

    private var spacesRegion: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                String(localized: "herdr.section.spaces", defaultValue: "spaces")
            )
            ScrollView {
                LazyVStack(spacing: Self.rowSpacing) {
                    ForEach(spaces) { item in
                        HerdrSpacesRowContainer(
                            item: item,
                            onSelect: onSelectSpace,
                            contextMenuContent: onSpaceContextMenu
                        )
                        .equatable()
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            // Grow with content, then stop: a bare flexible ScrollView with
            // `layoutPriority(1)` would claim the whole sidebar and starve the
            // agents region. Capping at the intrinsic content height makes the
            // spaces list grow up to its content and scroll only once the
            // available height is smaller than that cap.
            .frame(maxHeight: Self.spacesContentHeight(rowCount: spaces.count))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Single source of truth for `LazyVStack` row spacing in both regions;
    /// `spacesContentHeight` depends on it, so it must not be inlined.
    static let rowSpacing: CGFloat = 2

    /// Approximate height of one `AgentRowView` (title line + sub line + its 4pt
    /// vertical padding). `AgentRowView` is intrinsically sized, so this is only
    /// used to compute the agents region's minimum-height floor — a slight
    /// under- or over-estimate shifts that floor, it never clips a row.
    static let agentRowHeightEstimate: CGFloat =
        HerdrSidebarStyle.rowFontSize + HerdrSidebarStyle.subFontSize + 1 + 8

    /// Intrinsic height of the spaces list: `n` rows plus inter-row spacing.
    static func spacesContentHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        return CGFloat(rowCount) * HerdrSidebarStyle.rowHeight
            + CGFloat(rowCount - 1) * rowSpacing
    }

    /// Height the agents region is guaranteed to keep whenever it has rows:
    /// its header plus roughly three agent rows. Without this floor, a long
    /// spaces list (whose content cap then exceeds the available height) lets
    /// `layoutPriority(1)` win again and collapses agents toward zero.
    static func agentsMinHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        let headerHeight = HerdrSidebarStyle.headerFontSize + 16
        let rows = CGFloat(min(rowCount, 3))
        return headerHeight + rows * Self.agentRowHeightEstimate
            + max(0, rows - 1) * rowSpacing
    }

    // MARK: - Agents

    private var agentsRegion: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text(String(localized: "herdr.section.agents", defaultValue: "agents"))
                    .foregroundStyle(Color.secondary)
                Spacer(minLength: 0)
                Text(String(localized: "herdr.section.priority", defaultValue: "priority"))
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            }
            .cmuxFont(
                size: HerdrSidebarStyle.headerFontSize,
                weight: HerdrSidebarStyle.headerFontWeight,
                design: HerdrSidebarStyle.fontDesign
            )
            .padding(.horizontal, HerdrSidebarStyle.horizontalPadding)
            .padding(.vertical, 8)

            ScrollView {
                LazyVStack(spacing: Self.rowSpacing) {
                    ForEach(agents) { snapshot in
                        AgentRowView(
                            snapshot: snapshot,
                            isSelected: snapshot.panelId == selectedPanelId,
                            onActivate: {
                                onActivateAgent(snapshot.workspaceId, snapshot.panelId)
                            }
                        )
                        .equatable()
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Shared

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .cmuxFont(
                size: HerdrSidebarStyle.headerFontSize,
                weight: HerdrSidebarStyle.headerFontWeight,
                design: HerdrSidebarStyle.fontDesign
            )
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, HerdrSidebarStyle.horizontalPadding)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Space item projection

extension HerdrSidebarView {
    /// Flattens the sidebar's render items into the herdr spaces list.
    ///
    /// Pure projection (no store reads beyond the passed-in items), so the
    /// caller can build it once per body pass and hand rows immutable values.
    /// Group headers contribute a single row for their anchor workspace — the
    /// anchor has no `.workspace` render item of its own, and the existing
    /// sidebar header displays the group's name, so that is the row's title.
    /// Plain workspaces use `workspace.title`, matching
    /// `SidebarWorkspaceSnapshotBuilder.Snapshot.title`.
    @MainActor
    static func herdrSpaceItems(
        renderItems: [SidebarWorkspaceRenderItem],
        rollups: [UUID: AgentSidebarStatus],
        selectedWorkspaceId: UUID?,
        pinnedWorkspaceIds: Set<UUID>
    ) -> [HerdrSidebarSpaceItem] {
        renderItems.map { item in
            let id: UUID
            let title: String
            switch item {
            case .groupHeader(let group, _):
                id = group.anchorWorkspaceId
                title = group.name
            case .workspace(let workspace):
                id = workspace.id
                title = workspace.title
            }
            return HerdrSidebarSpaceItem(
                id: id,
                title: title,
                rollup: rollups[id],
                isSelected: id == selectedWorkspaceId,
                isPinned: pinnedWorkspaceIds.contains(id)
            )
        }
    }
}

// MARK: - Spaces row container

/// Wraps `SpacesRowView` + its context menu behind an `Equatable` boundary.
///
/// Attaching `.contextMenu { onSpaceContextMenu(id) }` directly at the `ForEach`
/// call site invokes the `AnyView`-producing closure on every evaluation of the
/// spaces list body — building menu content for every row on every render and
/// defeating the row's own `.equatable()`. Hoisting it into this container means
/// the closure is only called from *this* view's `body`, which SwiftUI skips
/// entirely while `item` is unchanged.
private struct HerdrSpacesRowContainer: View, Equatable {
    let item: HerdrSidebarSpaceItem
    let onSelect: (UUID) -> Void
    let contextMenuContent: (HerdrSidebarSpaceItem) -> AnyView

    /// Closures are identity-less; equality is the value snapshot only —
    /// same contract as `SpacesRowView` / `AgentRowView`.
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.item == rhs.item }

    var body: some View {
        SpacesRowView(
            title: item.title,
            rollup: item.rollup,
            isSelected: item.isSelected,
            onSelect: { onSelect(item.id) }
        )
        .equatable()
        .contextMenu { contextMenuContent(item) }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("HerdrSidebarView") {
    let workspaceIds = (0..<3).map { _ in UUID() }
    let statuses: [AgentSidebarStatus] = [.blocked, .working, .idle]
    let titles = ["cmux", "herdr", "ghostty"]

    return HerdrSidebarView(
        spaces: zip(workspaceIds, zip(titles, statuses)).enumerated().map { index, pair in
            HerdrSidebarSpaceItem(
                id: pair.0,
                title: pair.1.0,
                rollup: pair.1.1,
                isSelected: index == 0,
                isPinned: index == 1
            )
        },
        agents: zip(workspaceIds, zip(titles, statuses)).map { workspaceId, pair in
            AgentRowSnapshot(
                workspaceId: workspaceId,
                panelId: UUID(),
                workspaceTitle: pair.0,
                agentName: "claude",
                workspaceAgentCount: 1,
                status: pair.1,
                statusChangedAt: Date()
            )
        },
        selectedPanelId: nil,
        onSelectSpace: { _ in },
        onActivateAgent: { _, _ in },
        onSpaceContextMenu: { _ in AnyView(EmptyView()) }
    )
    .frame(width: 220, height: 400)
}
#endif
