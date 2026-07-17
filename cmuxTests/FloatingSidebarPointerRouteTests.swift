import XCTest
import CoreGraphics

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Unit coverage for the floating glass sidebar pointer-routing decision used by
/// `WindowTerminalHostView.performHitTest` / `shouldPassThroughToSidebarResizer`.
/// The leading resize band spans `[maxX - 6, maxX + 4]` (see
/// `SidebarResizeInteraction`).
final class FloatingSidebarPointerRouteTests: XCTestCase {
    // Panel: x in [8, 208], y in [8, 592]. Trailing edge (divider) at x = 208.
    private let panelFrame = CGRect(x: 8, y: 8, width: 200, height: 584)

    func testPointInsidePanelRoutesToPanel() {
        let route = FloatingSidebarPointerRoute.route(
            point: CGPoint(x: 100, y: 300),
            panelFrame: panelFrame
        )
        XCTAssertEqual(route, .panel)
    }

    func testPointJustRightOfPanelWithinBandRoutesToResizer() {
        // maxX = 208; band extends to 208 + 4 = 212. x = 211 is outside the panel
        // but inside the resize band.
        let route = FloatingSidebarPointerRoute.route(
            point: CGPoint(x: 211, y: 300),
            panelFrame: panelFrame
        )
        XCTAssertEqual(route, .resizer)
    }

    func testPointFarRightOfPanelRoutesToNone() {
        // Well past the band (208 + 4 = 212): terminal region.
        let route = FloatingSidebarPointerRoute.route(
            point: CGPoint(x: 400, y: 300),
            panelFrame: panelFrame
        )
        XCTAssertEqual(route, .none)
    }

    func testResizeBandOverlappingPanelInteriorPrefersPanel() {
        // The inner half of the band (208 - 6 = 202 ... 208) is inside the panel.
        // Panel routing must win so the glass panel keeps receiving the event.
        let route = FloatingSidebarPointerRoute.route(
            point: CGPoint(x: 205, y: 300),
            panelFrame: panelFrame
        )
        XCTAssertEqual(route, .panel)
    }

    func testPointAboveAndRightOfPanelWithinBandXRoutesToResizer() {
        // Band is defined purely by x for the leading edge; a point at the band x
        // but above the panel's vertical extent still routes to the resizer.
        let route = FloatingSidebarPointerRoute.route(
            point: CGPoint(x: 210, y: 700),
            panelFrame: panelFrame
        )
        XCTAssertEqual(route, .resizer)
    }
}
