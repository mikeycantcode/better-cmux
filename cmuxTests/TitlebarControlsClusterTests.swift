import CoreGraphics
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct TitlebarControlsClusterTests {
    @Test func clusterSlotMembership() {
        #expect(TitlebarControlsCluster.leading.slots == [.toggleSidebar, .focusHistoryBack, .focusHistoryForward, .newTab, .showNotifications])
        #expect(TitlebarControlsCluster.trailing.slots == [.newTab, .showNotifications, .toggleRightSidebar])
        let all = TitlebarControlsCluster.leading.slots + TitlebarControlsCluster.trailing.slots
        #expect(Set(all).count == TitlebarShortcutHintActionSlot.allCases.count)
    }

    @Test func toggleRightSidebarSlotMapsToAction() {
        #expect(TitlebarShortcutHintActionSlot.toggleRightSidebar.action == .toggleRightSidebar)
    }

    @Test func buttonCenterXUsesClusterIndexNotRawValue() {
        let config = TitlebarControlsStyle.classic.config
        // .newTab is rawValue 2 but index 0 in the trailing cluster.
        let x = TitlebarControlsLayoutMetrics.buttonCenterX(for: .newTab, cluster: .trailing, config: config)
        #expect(x == config.groupPadding.leading + config.buttonSize / 2.0)
    }

    @Test func buttonRowWidthCountsClusterButtons() {
        let config = TitlebarControlsStyle.classic.config
        // Annotated CGFloat so both sides of #expect are the same static type;
        // an inferred Double here fails the swift-testing comparison even when
        // the bit patterns are identical.
        let expectedLeading: CGFloat = 5 * config.buttonSize + 4 * config.spacing
        let expectedTrailing: CGFloat = 3 * config.buttonSize + 2 * config.spacing
        #expect(TitlebarControlsLayoutMetrics.buttonRowWidth(cluster: .leading, config: config) == expectedLeading)
        #expect(TitlebarControlsLayoutMetrics.buttonRowWidth(cluster: .trailing, config: config) == expectedTrailing)
    }

    /// The minimal-mode hover host renders `TitlebarShortcutHintActionSlot`s, but its
    /// click/hit proxy is the fixed 5-column `MinimalModeSidebarControlActionSlot`
    /// layout in `WindowDragHandleView.swift` / `MinimalModeSidebarControls.swift`.
    /// The two enums are distinct types, so lock the icon order to the hit-region
    /// column order by case name — if they drift, clicks land on the wrong button.
    @Test func minimalSidebarHostSlotsMatchHitRegionColumnOrder() {
        let rendered = TitlebarControlsCluster.minimalSidebarHost.slots.map { String(describing: $0) }
        let hitRegions = MinimalModeSidebarControlActionSlot.allCases.map { String(describing: $0) }
        #expect(rendered == hitRegions)
    }
}
