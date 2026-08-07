import AppKit
import CmuxAppKitSupportUI
import CmuxFoundation
import SwiftUI
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class HerdrSidebarRowsTests: XCTestCase {

    private func makeSnapshot(
        workspaceId: UUID = UUID(),
        panelId: UUID = UUID(),
        workspaceTitle: String = "cmux",
        agentName: String = "claude",
        workspaceAgentCount: Int = 1,
        status: AgentSidebarStatus = .working,
        statusChangedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> AgentRowSnapshot {
        AgentRowSnapshot(
            workspaceId: workspaceId,
            panelId: panelId,
            workspaceTitle: workspaceTitle,
            agentName: agentName,
            workspaceAgentCount: workspaceAgentCount,
            status: status,
            statusChangedAt: statusChangedAt
        )
    }

    // MARK: - Palette

    func testStatusColorsAreDistinctPerStatus() {
        let all: [AgentSidebarStatus] = [.blocked, .working, .idle, .unknown]
        let colors = all.map { HerdrSidebarStyle.color(for: $0) }
        for i in colors.indices {
            for j in colors.indices where j > i {
                XCTAssertNotEqual(
                    colors[i],
                    colors[j],
                    "Status colors for \(all[i]) and \(all[j]) must differ"
                )
            }
        }
    }

    func testUnknownStatusUsesTertiaryLabelColor() {
        XCTAssertEqual(
            HerdrSidebarStyle.color(for: .unknown),
            Color(nsColor: .tertiaryLabelColor)
        )
    }

    func testBlockedWorkingIdleUseMockPalette() {
        XCTAssertEqual(
            HerdrSidebarStyle.color(for: .blocked),
            Color(red: 0.94, green: 0.55, blue: 0.62)
        )
        XCTAssertEqual(
            HerdrSidebarStyle.color(for: .working),
            Color(red: 0.95, green: 0.85, blue: 0.55)
        )
        XCTAssertEqual(
            HerdrSidebarStyle.color(for: .idle),
            Color(red: 0.60, green: 0.80, blue: 0.55)
        )
    }

    // MARK: - Status words

    func testStatusWordsAreNonEmptyLowercaseAndDistinct() {
        let all: [AgentSidebarStatus] = [.blocked, .working, .idle, .unknown]
        var seen = Set<String>()
        for status in all {
            let word = HerdrSidebarStyle.statusWord(for: status)
            XCTAssertFalse(word.isEmpty, "status word for \(status) must not be empty")
            XCTAssertEqual(word, word.lowercased(), "status word for \(status) must be lowercase")
            XCTAssertTrue(seen.insert(word).inserted, "status word \(word) must be unique")
        }
    }

    // MARK: - SpacesRowView equality

    func testSpacesRowViewEqualityIgnoresClosures() {
        var sideEffect = 0
        let a = SpacesRowView(title: "cmux", rollup: .blocked, isSelected: true, onSelect: {})
        let b = SpacesRowView(
            title: "cmux",
            rollup: .blocked,
            isSelected: true,
            onSelect: { sideEffect += 1 }
        )
        XCTAssertEqual(a, b)
        XCTAssertEqual(sideEffect, 0)
    }

    func testSpacesRowViewEqualityDistinguishesData() {
        let base = SpacesRowView(title: "cmux", rollup: .blocked, isSelected: false, onSelect: {})
        XCTAssertNotEqual(
            base,
            SpacesRowView(title: "cmux", rollup: .blocked, isSelected: true, onSelect: {})
        )
        XCTAssertNotEqual(
            base,
            SpacesRowView(title: "other", rollup: .blocked, isSelected: false, onSelect: {})
        )
        XCTAssertNotEqual(
            base,
            SpacesRowView(title: "cmux", rollup: .idle, isSelected: false, onSelect: {})
        )
        XCTAssertNotEqual(
            base,
            SpacesRowView(title: "cmux", rollup: nil, isSelected: false, onSelect: {})
        )
    }

    // MARK: - AgentRowView equality

    func testAgentRowViewEqualityIgnoresClosures() {
        var sideEffect = 0
        let snapshot = makeSnapshot()
        let a = AgentRowView(snapshot: snapshot, isSelected: false, onActivate: {})
        let b = AgentRowView(snapshot: snapshot, isSelected: false, onActivate: { sideEffect += 1 })
        XCTAssertEqual(a, b)
        XCTAssertEqual(sideEffect, 0)
    }

    func testAgentRowViewEqualityDistinguishesData() {
        let snapshot = makeSnapshot()
        let base = AgentRowView(snapshot: snapshot, isSelected: false, onActivate: {})
        XCTAssertNotEqual(
            base,
            AgentRowView(snapshot: snapshot, isSelected: true, onActivate: {})
        )
        let otherStatus = makeSnapshot(
            workspaceId: snapshot.workspaceId,
            panelId: snapshot.panelId,
            status: .blocked
        )
        XCTAssertNotEqual(
            base,
            AgentRowView(snapshot: otherStatus, isSelected: false, onActivate: {})
        )
    }
}
