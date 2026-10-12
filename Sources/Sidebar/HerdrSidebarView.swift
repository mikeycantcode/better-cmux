import CmuxAppKitSupportUI
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
    let onSelectSpace: (UUID) -> Void
    /// Receives the full item so menu content can be derived from compared state.
    let onSpaceContextMenu: (HerdrSidebarSpaceItem) -> AnyView
    /// Non-nil only while a Bonsplit tab drag is collecting drop targets.
    /// When set, space rows publish their frames through
    /// `SidebarWorkspaceRowFramePreferenceKey` and this closure turns the
    /// collected anchors into the host's target-writing overlay.
    ///
    /// The gate lives here, not around the whole sidebar: the `if` that mounts
    /// the reader gives its content fresh SwiftUI identity every time the drag
    /// gate flips, so it must sit *below* the `ScrollView` (which then keeps its
    /// scroll offset mid-drag) — the same mount depth the classic workspace list
    /// uses. Row frame emission is branchless (`[:]` when disabled), so toggling
    /// never re-identifies the rows themselves.
    var spaceRowFrameAnchorReader: (([UUID: Anchor<CGRect>]) -> AnyView)?
    /// Store-owning sections below the spaces list (explorer + source control
    /// graph). Built by the host so this container stays store-free.
    var lowerContent: AnyView = AnyView(EmptyView())

    @AppStorage("sidebar.spaces.expanded") private var isSpacesExpanded = true

    /// Height the lower sections keep however long the spaces list grows.
    static let lowerContentMinHeight: CGFloat = 220

    var body: some View {
        VStack(spacing: 0) {
            spacesRegion
                .layoutPriority(1)
            Divider()
                .opacity(0.4)
            lowerContent
                .frame(minHeight: Self.lowerContentMinHeight, maxHeight: .infinity)
        }
    }

    // MARK: - Spaces

    private var spacesRegion: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(
                String(localized: "herdr.section.spaces", defaultValue: "spaces")
            )
            if isSpacesExpanded {
                ScrollView {
                    gatedSpaceRows
                }
                .scrollBounceBehavior(.basedOnSize)
                .modifier(Self.SidebarScrollChrome())
                // Grow with content, then stop: a bare flexible ScrollView with
                // `layoutPriority(1)` would claim the whole sidebar and starve the
                // lower sections. Capping at the intrinsic content height makes the
                // spaces list grow up to its content and scroll only once the
                // available height is smaller than that cap.
                .frame(maxHeight: Self.spacesContentHeight(rowCount: spaces.count))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The spaces `LazyVStack`, with the drop-target frame reader installed only
    /// while a drag is collecting. Kept as the innermost gated node so the flip
    /// never re-identifies the enclosing `ScrollView` or the sidebar around it.
    @ViewBuilder
    private var gatedSpaceRows: some View {
        if let spaceRowFrameAnchorReader {
            spaceRows
                .overlayPreferenceValue(SidebarWorkspaceRowFramePreferenceKey.self) { anchors in
                    spaceRowFrameAnchorReader(anchors)
                }
        } else {
            spaceRows
        }
    }

    private var spaceRows: some View {
        LazyVStack(spacing: Self.rowSpacing) {
            ForEach(spaces) { item in
                HerdrSpacesRowContainer(
                    item: item,
                    onSelect: onSelectSpace,
                    contextMenuContent: onSpaceContextMenu
                )
                .equatable()
                .sidebarWorkspaceFrameAnchor(
                    id: item.id,
                    isEnabled: spaceRowFrameAnchorReader != nil
                )
            }
        }
    }

    /// Single source of truth for `LazyVStack` row spacing in both regions;
    /// `spacesContentHeight` depends on it, so it must not be inlined.
    static let rowSpacing: CGFloat = 2

    /// Intrinsic height of the spaces list: `n` rows plus inter-row spacing.
    static func spacesContentHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        return CGFloat(rowCount) * HerdrSidebarStyle.rowHeight
            + CGFloat(rowCount - 1) * rowSpacing
    }

    // MARK: - Shared

    /// The sidebar scroll-chrome treatment the classic workspace list applies:
    /// clear the SwiftUI/AppKit scroll backgrounds so the translucent sidebar
    /// shows through, and use cmux's overlay scroller configuration. Store-free
    /// — it only touches the enclosing `NSScrollView`.
    private struct SidebarScrollChrome: ViewModifier {
        func body(content: Content) -> some View {
            content
                .background(Color.clear)
                .modifier(ClearScrollBackground())
                .background(
                    SidebarScrollViewResolver { scrollView in
                        scrollView?.applySidebarOverlayScrollerConfiguration()
                    }
                    .frame(width: 0, height: 0)
                )
        }
    }

    /// Same look as the Explorer and Source Control Graph section headers:
    /// chevron, uppercased 11pt semibold title, 22pt row, click to collapse.
    private func sectionHeader(_ title: String) -> some View {
        Button {
            isSpacesExpanded.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isSpacesExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 12)
                Text(title.uppercased())
                    .cmuxFont(size: 11, weight: .semibold)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    let statuses: [AgentSidebarStatus] = [.blocked, .working, .idle]
    let titles = ["cmux", "herdr", "ghostty"]

    return HerdrSidebarView(
        spaces: zip(titles, statuses).enumerated().map { index, pair in
            HerdrSidebarSpaceItem(
                id: UUID(),
                title: pair.0,
                rollup: pair.1,
                isSelected: index == 0,
                isPinned: index == 1
            )
        },
        onSelectSpace: { _ in },
        onSpaceContextMenu: { _ in AnyView(EmptyView()) }
    )
    .frame(width: 220, height: 400)
}
#endif
