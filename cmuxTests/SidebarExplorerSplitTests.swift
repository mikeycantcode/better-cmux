import CoreGraphics
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct SidebarExplorerSplitTests {
    @Test func keepsFractionWithinBoundsForTallSidebar() {
        let f = SidebarExplorerSplit.clampedSessionFraction(0.6, availableHeight: 800)
        #expect(f == 0.6)
    }

    @Test func clampsAboveMaxToLeaveRoomForExplorer() {
        // 800pt tall, min explorer 80pt -> max session fraction 0.9
        let f = SidebarExplorerSplit.clampedSessionFraction(0.99, availableHeight: 800)
        #expect(f <= 0.9 + 0.0001)
        #expect(f >= 0.9 - 0.0001)
    }

    @Test func clampsBelowMinToKeepSessionListVisible() {
        // 800pt tall, min session 96pt -> min session fraction 0.12
        let f = SidebarExplorerSplit.clampedSessionFraction(0.01, availableHeight: 800)
        #expect(f >= 96.0 / 800.0 - 0.0001)
    }

    @Test func fallsBackForNonPositiveHeight() {
        #expect(SidebarExplorerSplit.clampedSessionFraction(0.6, availableHeight: 0) == 0.6)
    }

    @Test func fallsBackForNonFiniteFraction() {
        let f = SidebarExplorerSplit.clampedSessionFraction(.nan, availableHeight: 800)
        #expect(f == SidebarExplorerSplit.fallbackFraction)
    }
}
