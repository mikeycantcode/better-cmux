import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Regression coverage for cmuxApp.sidebarAppearanceMigrationPlan(currentVersion:snapshot:),
/// the pure decision function backing migrateSidebarAppearanceDefaultsIfNeeded. See
/// https://github.com/manaflow-ai/cmux/ Task 2 review: pristine installs must not have the
/// ancient legacy sidebar defaults force-written over the new liquid-glass @AppStorage literals.
final class SidebarAppearanceMigrationTests: XCTestCase {
    private let legacySnapshot: [String: String] = [
        "sidebarMaterial": "sidebar",
        "sidebarBlendMode": "behindWindow",
        "sidebarState": "followWindow",
        "sidebarTintHex": "#101010",
        "sidebarTintOpacity": "0.54",
        "sidebarBlurOpacity": "0.79",
        "sidebarCornerRadius": "0.0",
    ]

    func testFreshInstallWithNoStoredKeysIsNotMigrated() {
        let plan = cmuxApp.sidebarAppearanceMigrationPlan(currentVersion: 0, snapshot: [:])
        XCTAssertTrue(plan.v1Writes.isEmpty)
        XCTAssertTrue(plan.v2Writes.isEmpty)
        XCTAssertEqual(plan.finalVersion, 2)
    }

    func testInstallWithFullLegacyDefaultSetStoredIsMigratedToLiquidGlass() {
        let plan = cmuxApp.sidebarAppearanceMigrationPlan(currentVersion: 0, snapshot: legacySnapshot)

        XCTAssertEqual(plan.v1Writes["sidebarPreset"], "nativeSidebar")
        XCTAssertEqual(plan.v1Writes["sidebarMaterial"], "sidebar")
        XCTAssertEqual(plan.v1Writes["sidebarBlendMode"], "withinWindow")

        XCTAssertEqual(plan.v2Writes["sidebarMaterial"], "liquidGlass")
        XCTAssertEqual(plan.v2Writes["sidebarBlendMode"], "withinWindow")
        XCTAssertEqual(plan.finalVersion, 2)
    }

    func testCustomizedInstallIsLeftUntouched() {
        var customized = legacySnapshot
        customized["sidebarMaterial"] = "hudWindow"

        let plan = cmuxApp.sidebarAppearanceMigrationPlan(currentVersion: 0, snapshot: customized)

        XCTAssertTrue(plan.v1Writes.isEmpty)
        XCTAssertTrue(plan.v2Writes.isEmpty)
        XCTAssertEqual(plan.finalVersion, 2)
    }

    func testAlreadyAtVersion2IsANoOp() {
        let plan = cmuxApp.sidebarAppearanceMigrationPlan(currentVersion: 2, snapshot: legacySnapshot)
        XCTAssertTrue(plan.v1Writes.isEmpty)
        XCTAssertTrue(plan.v2Writes.isEmpty)
        XCTAssertEqual(plan.finalVersion, 2)
    }

    func testInstallAlreadyMigratedToVersion1OnlyRunsV2Step() {
        // Simulates an install that ran v1 on a previous app launch (already converted to the
        // nativeSidebar preset) and is now upgrading straight to v2. Its stored values no longer
        // match the ancient legacy set (blendMode is withinWindow, not behindWindow), so it must
        // not be re-migrated by v2 — it should be treated as customized/left alone.
        var afterV1 = legacySnapshot
        afterV1["sidebarBlendMode"] = "withinWindow"

        let plan = cmuxApp.sidebarAppearanceMigrationPlan(currentVersion: 1, snapshot: afterV1)
        XCTAssertTrue(plan.v1Writes.isEmpty)
        XCTAssertTrue(plan.v2Writes.isEmpty)
        XCTAssertEqual(plan.finalVersion, 2)
    }
}
