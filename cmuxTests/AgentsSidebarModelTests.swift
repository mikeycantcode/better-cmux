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

@MainActor
final class AgentsSidebarModelTests: XCTestCase {
    private let now = Date(timeIntervalSinceReferenceDate: 1_000_000)

    private func input(
        workspaceId: UUID,
        title: String,
        panels: [UUID: [String: AgentHibernationLifecycleState]]
    ) -> AgentsSidebarWorkspaceInput {
        AgentsSidebarWorkspaceInput(
            workspaceId: workspaceId,
            title: title,
            panelLifecycles: panels
        )
    }

    // (a) lifecycle -> status mapping
    func testLifecycleMapping() {
        XCTAssertEqual(AgentSidebarStatus(lifecycle: .needsInput), .blocked)
        XCTAssertEqual(AgentSidebarStatus(lifecycle: .running), .working)
        XCTAssertEqual(AgentSidebarStatus(lifecycle: .idle), .idle)
        XCTAssertEqual(AgentSidebarStatus(lifecycle: .unknown), .unknown)
        XCTAssertTrue(AgentSidebarStatus.blocked < AgentSidebarStatus.working)
        XCTAssertTrue(AgentSidebarStatus.working < AgentSidebarStatus.idle)
        XCTAssertTrue(AgentSidebarStatus.idle < AgentSidebarStatus.unknown)
    }

    // (b) per-panel merge precedence
    func testPerPanelMergePrecedence() {
        let workspaceId = UUID()
        let idleNeedsInput = UUID()
        let runningNeedsInput = UUID()
        let unknownIdle = UUID()

        let result = AgentsSidebarModel.buildRows(
            workspaces: [
                input(
                    workspaceId: workspaceId,
                    title: "W",
                    panels: [
                        idleNeedsInput: ["a": .idle, "b": .needsInput],
                        runningNeedsInput: ["a": .running, "b": .needsInput],
                        unknownIdle: ["a": .unknown, "b": .idle],
                    ]
                )
            ],
            previousChangeDates: [:],
            now: now
        )

        let byPanel = Dictionary(uniqueKeysWithValues: result.rows.map { ($0.panelId, $0.status) })
        XCTAssertEqual(byPanel[idleNeedsInput], .blocked)
        XCTAssertEqual(byPanel[runningNeedsInput], .working)
        XCTAssertEqual(byPanel[unknownIdle], .unknown)
    }

    // (c) rollup is worst-first across the workspace
    func testRollupPicksWorstStatus() {
        let blockedWorkspace = UUID()
        let idleWorkspace = UUID()
        let emptyWorkspace = UUID()

        let result = AgentsSidebarModel.buildRows(
            workspaces: [
                input(
                    workspaceId: blockedWorkspace,
                    title: "A",
                    panels: [UUID(): ["codex": .running], UUID(): ["codex": .needsInput]]
                ),
                input(
                    workspaceId: idleWorkspace,
                    title: "B",
                    panels: [UUID(): ["codex": .idle], UUID(): ["codex": .unknown]]
                ),
                input(workspaceId: emptyWorkspace, title: "C", panels: [UUID(): [:]]),
            ],
            previousChangeDates: [:],
            now: now
        )

        XCTAssertEqual(result.rollups[blockedWorkspace], .blocked)
        XCTAssertEqual(result.rollups[idleWorkspace], .idle)
        XCTAssertNil(result.rollups[emptyWorkspace])
    }

    // (d) sort order: status first, then newest statusChangedAt
    func testSortOrder() {
        let workspaceId = UUID()
        let blocked = UUID()
        let workingOld = UUID()
        let workingNew = UUID()
        let idle = UUID()

        let previous: [UUID: (AgentSidebarStatus, Date)] = [
            workingOld: (.working, now.addingTimeInterval(-500)),
            workingNew: (.working, now.addingTimeInterval(-10)),
        ]

        let result = AgentsSidebarModel.buildRows(
            workspaces: [
                input(
                    workspaceId: workspaceId,
                    title: "W",
                    panels: [
                        idle: ["codex": .idle],
                        workingOld: ["codex": .running],
                        blocked: ["codex": .needsInput],
                        workingNew: ["codex": .running],
                    ]
                )
            ],
            previousChangeDates: previous,
            now: now
        )

        XCTAssertEqual(result.rows.map(\.panelId), [blocked, workingNew, workingOld, idle])
    }

    // (d2) ties in both status and statusChangedAt fall back to uuidString order
    func testSortTieBreaksOnPanelIdUUIDString() {
        let workspaceId = UUID()
        let sameDate = now.addingTimeInterval(-60)
        // Three panels, identical status and statusChangedAt.
        let panelIds = (0..<3).map { _ in UUID() }
        var previous: [UUID: (AgentSidebarStatus, Date)] = [:]
        var panels: [UUID: [String: AgentHibernationLifecycleState]] = [:]
        for panelId in panelIds {
            previous[panelId] = (.working, sameDate)
            panels[panelId] = ["codex": .running]
        }

        let result = AgentsSidebarModel.buildRows(
            workspaces: [input(workspaceId: workspaceId, title: "W", panels: panels)],
            previousChangeDates: previous,
            now: now
        )

        XCTAssertEqual(result.rows.map(\.statusChangedAt), Array(repeating: sameDate, count: 3))
        XCTAssertEqual(
            result.rows.map(\.panelId),
            panelIds.sorted { $0.uuidString < $1.uuidString }
        )
    }

    // (e) statusChangedAt preservation / reset
    func testStatusChangedAtPreservedAndReset() {
        let workspaceId = UUID()
        let stable = UUID()
        let flipped = UUID()
        let old = now.addingTimeInterval(-900)

        let previous: [UUID: (AgentSidebarStatus, Date)] = [
            stable: (.working, old),
            flipped: (.idle, old),
        ]

        let result = AgentsSidebarModel.buildRows(
            workspaces: [
                input(
                    workspaceId: workspaceId,
                    title: "W",
                    panels: [
                        stable: ["codex": .running],
                        flipped: ["codex": .needsInput],
                    ]
                )
            ],
            previousChangeDates: previous,
            now: now
        )

        let byPanel = Dictionary(uniqueKeysWithValues: result.rows.map { ($0.panelId, $0) })
        XCTAssertEqual(byPanel[stable]?.statusChangedAt, old)
        XCTAssertEqual(byPanel[flipped]?.statusChangedAt, now)
        XCTAssertEqual(result.changeDates[stable]?.1, old)
        XCTAssertEqual(result.changeDates[flipped]?.1, now)
        XCTAssertEqual(result.changeDates[flipped]?.0, .blocked)
    }

    // (f) empty dicts yield no rows and are excluded from workspaceAgentCount
    func testWorkspaceAgentCountCountsOnlyAgentPanels() {
        let workspaceId = UUID()
        let agentA = UUID()
        let agentB = UUID()
        let plainPanel = UUID()

        let result = AgentsSidebarModel.buildRows(
            workspaces: [
                input(
                    workspaceId: workspaceId,
                    title: "Workspace Title",
                    panels: [
                        agentA: ["codex": .running],
                        agentB: ["claude_code": .idle],
                        plainPanel: [:],
                    ]
                )
            ],
            previousChangeDates: [:],
            now: now
        )

        XCTAssertEqual(result.rows.count, 2)
        XCTAssertFalse(result.rows.contains { $0.panelId == plainPanel })
        XCTAssertTrue(result.rows.allSatisfy { $0.workspaceAgentCount == 2 })
        XCTAssertTrue(result.rows.allSatisfy { $0.workspaceTitle == "Workspace Title" })
        XCTAssertTrue(result.rows.allSatisfy { $0.workspaceId == workspaceId })
        XCTAssertEqual(result.rows.first(where: { $0.panelId == agentA })?.agentName, "codex")
        XCTAssertEqual(result.rows.first(where: { $0.panelId == agentB })?.agentName, "claude")
    }

    // (g) agent display names
    func testAgentDisplayName() {
        XCTAssertEqual(AgentsSidebarModel.agentDisplayName(statusKeys: ["claude_code"]), "claude")
        XCTAssertEqual(AgentsSidebarModel.agentDisplayName(statusKeys: ["claude_code.2"]), "claude")
        XCTAssertEqual(AgentsSidebarModel.agentDisplayName(statusKeys: ["codex"]), "codex")
        XCTAssertEqual(AgentsSidebarModel.agentDisplayName(statusKeys: ["hermes-agent"]), "hermes")
        XCTAssertEqual(AgentsSidebarModel.agentDisplayName(statusKeys: []), "agent")
        XCTAssertEqual(
            AgentsSidebarModel.agentDisplayName(statusKeys: ["codex", "claude_code"]),
            "claude"
        )
    }

    func testRowIdentityIsPanelId() {
        let panelId = UUID()
        let result = AgentsSidebarModel.buildRows(
            workspaces: [input(workspaceId: UUID(), title: "W", panels: [panelId: ["codex": .idle]])],
            previousChangeDates: [:],
            now: now
        )
        XCTAssertEqual(result.rows.first?.id, panelId)
    }

    // Spaces region grows with content: n rows + (n-1) gaps, zero when empty.
    @MainActor
    func testSpacesContentHeightGrowsWithRowCount() {
        XCTAssertEqual(HerdrSidebarView.spacesContentHeight(rowCount: 0), 0)
        XCTAssertEqual(
            HerdrSidebarView.spacesContentHeight(rowCount: 1),
            HerdrSidebarStyle.rowHeight
        )
        XCTAssertEqual(
            HerdrSidebarView.spacesContentHeight(rowCount: 3),
            3 * HerdrSidebarStyle.rowHeight + 4
        )
    }
}
