import CoreGraphics
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct TitlebarControlsClusterTests {
    @Test func clusterSlotMembership() {
        #expect(TitlebarControlsCluster.leading.slots == [.toggleSidebar, .focusHistoryBack, .focusHistoryForward])
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
        let expected: CGFloat = 3 * config.buttonSize + 2 * config.spacing
        #expect(TitlebarControlsLayoutMetrics.buttonRowWidth(cluster: .leading, config: config) == expected)
        #expect(TitlebarControlsLayoutMetrics.buttonRowWidth(cluster: .trailing, config: config) == expected)
    }
}
