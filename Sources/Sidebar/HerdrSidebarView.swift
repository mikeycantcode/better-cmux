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
    let onSpaceContextMenu: (UUID) -> AnyView

    var body: some View {
        VStack(spacing: 0) {
            spacesRegion
                .layoutPriority(1)
            Divider()
                .opacity(0.4)
            agentsRegion
                .frame(maxHeight: .infinity)
        }
    }

    // MARK: - Spaces

    private var spacesRegion: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                String(localized: "herdr.section.spaces", defaultValue: "spaces")
            )
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(spaces) { item in
                        SpacesRowView(
                            title: item.title,
                            rollup: item.rollup,
                            isSelected: item.isSelected,
                            onSelect: { onSelectSpace(item.id) }
                        )
                        .equatable()
                        .contextMenu { onSpaceContextMenu(item.id) }
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

    /// Intrinsic height of the spaces list: `n` rows plus inter-row spacing.
    static func spacesContentHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        let spacing: CGFloat = 2
        return CGFloat(rowCount) * HerdrSidebarStyle.rowHeight
            + CGFloat(rowCount - 1) * spacing
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
                design: .monospaced
            )
            .padding(.horizontal, HerdrSidebarStyle.horizontalPadding)
            .padding(.vertical, 8)

            ScrollView {
                LazyVStack(spacing: 2) {
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
                design: .monospaced
            )
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, HerdrSidebarStyle.horizontalPadding)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                isSelected: index == 0
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
