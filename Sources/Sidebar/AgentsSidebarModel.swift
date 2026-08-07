import Combine
import Foundation

/// Sidebar-facing status for a single agent panel. Ordered worst-first so
/// `Comparable`/`min` produce the workspace rollup directly.
enum AgentSidebarStatus: Int, Comparable, Sendable {
    case blocked = 0
    case working = 1
    case idle = 2
    case unknown = 3

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    init(lifecycle: AgentHibernationLifecycleState) {
        switch lifecycle {
        case .needsInput: self = .blocked
        case .running: self = .working
        case .idle: self = .idle
        case .unknown: self = .unknown
        }
    }
}

/// Immutable per-row value snapshot handed to sidebar rows (snapshot-boundary rule:
/// rows never hold a reference to the model).
struct AgentRowSnapshot: Identifiable, Equatable, Sendable {
    var id: UUID { panelId }
    let workspaceId: UUID
    let panelId: UUID
    let workspaceTitle: String
    /// Lowercase display token: "claude", "codex", …
    let agentName: String
    /// Number of agent panels in this workspace.
    let workspaceAgentCount: Int
    let status: AgentSidebarStatus
    let statusChangedAt: Date
}

/// Value input for the pure projection core — no `Workspace` reference.
struct AgentsSidebarWorkspaceInput: Sendable {
    let workspaceId: UUID
    let title: String
    let panelLifecycles: [UUID: [String: AgentHibernationLifecycleState]]
}

@MainActor
final class AgentsSidebarModel: ObservableObject {
    @Published private(set) var agentRows: [AgentRowSnapshot] = []
    @Published private(set) var workspaceRollups: [UUID: AgentSidebarStatus] = [:]

    private var changeDates: [UUID: (AgentSidebarStatus, Date)] = [:]
    private var tabsCancellable: AnyCancellable?
    private var workspaceCancellables: [AnyCancellable] = []
    private weak var attachedTabManager: TabManager?

    // MARK: - Pure core

    /// Merges each panel's lifecycle dict with the existing precedence
    /// (running > needsInput > unknown > idle — same shape as
    /// `Workspace.agentHibernationLifecycleState(panelId:fallback:)`), maps to
    /// `AgentSidebarStatus`, then sorts worst-first / newest-first.
    static func buildRows(
        workspaces: [AgentsSidebarWorkspaceInput],
        previousChangeDates: [UUID: (AgentSidebarStatus, Date)],
        now: Date
    ) -> (
        rows: [AgentRowSnapshot],
        rollups: [UUID: AgentSidebarStatus],
        changeDates: [UUID: (AgentSidebarStatus, Date)]
    ) {
        var rows: [AgentRowSnapshot] = []
        var rollups: [UUID: AgentSidebarStatus] = [:]
        var nextChangeDates: [UUID: (AgentSidebarStatus, Date)] = [:]

        for workspace in workspaces {
            let agentPanels = workspace.panelLifecycles.filter { !$0.value.isEmpty }
            guard !agentPanels.isEmpty else { continue }
            let agentCount = agentPanels.count

            for (panelId, lifecycles) in agentPanels {
                let status = AgentSidebarStatus(lifecycle: mergedLifecycle(lifecycles))
                let statusChangedAt: Date
                if let previous = previousChangeDates[panelId], previous.0 == status {
                    statusChangedAt = previous.1
                } else {
                    statusChangedAt = now
                }
                nextChangeDates[panelId] = (status, statusChangedAt)
                rows.append(
                    AgentRowSnapshot(
                        workspaceId: workspace.workspaceId,
                        panelId: panelId,
                        workspaceTitle: workspace.title,
                        agentName: agentDisplayName(statusKeys: Set(lifecycles.keys)),
                        workspaceAgentCount: agentCount,
                        status: status,
                        statusChangedAt: statusChangedAt
                    )
                )
                if let existing = rollups[workspace.workspaceId] {
                    rollups[workspace.workspaceId] = min(existing, status)
                } else {
                    rollups[workspace.workspaceId] = status
                }
            }
        }

        rows.sort { lhs, rhs in
            if lhs.status != rhs.status { return lhs.status < rhs.status }
            if lhs.statusChangedAt != rhs.statusChangedAt {
                return lhs.statusChangedAt > rhs.statusChangedAt
            }
            return lhs.panelId.uuidString < rhs.panelId.uuidString
        }

        return (rows, rollups, nextChangeDates)
    }

    /// Existing per-panel precedence, applied to value inputs.
    private static func mergedLifecycle(
        _ lifecycles: [String: AgentHibernationLifecycleState]
    ) -> AgentHibernationLifecycleState {
        let states = Array(lifecycles.values)
        if states.contains(.running) { return .running }
        if states.contains(.needsInput) { return .needsInput }
        if states.contains(.unknown) { return .unknown }
        if states.contains(.idle) { return .idle }
        return .unknown
    }

    /// Lowercase display token for a panel's status keys. Discriminator suffixes
    /// (`claude_code.2`) are stripped; multiple keys resolve alphabetically for
    /// determinism.
    static func agentDisplayName(statusKeys: Set<String>) -> String {
        let bases = statusKeys.map { key -> String in
            guard let dotIndex = key.firstIndex(of: ".") else { return key }
            return String(key[..<dotIndex])
        }
        guard let base = bases.sorted().first else { return "agent" }
        switch base {
        case "claude_code": return "claude"
        case "hermes-agent": return "hermes"
        default: return base
        }
    }

    // MARK: - Live plumbing

    /// Idempotent: re-attaching replaces the previous subscriptions.
    func attach(tabManager: TabManager) {
        attachedTabManager = tabManager
        workspaceCancellables.removeAll()
        tabsCancellable = tabManager.tabsPublisher
            .sink { [weak self] tabs in
                // `tabsPublisher` emits from `workspaceTabsWillChange`, i.e. during
                // willSet before `tabManager.tabs` storage updates — so rebuild from
                // the emitted array, never by re-reading the (still stale) property.
                self?.resubscribe(to: tabs)
                self?.rebuild(workspaces: tabs)
            }
    }

    private func resubscribe(to workspaces: [Workspace]) {
        workspaceCancellables.removeAll()
        for workspace in workspaces {
            let revisions = workspace.$agentLifecycleRevision.map { _ in () }
            let titles = workspace.$title.map { _ in () }
            let cancellable = revisions
                .merge(with: titles)
                .debounce(for: .milliseconds(40), scheduler: RunLoop.main)
                .sink { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, let tabManager = self.attachedTabManager else { return }
                        self.rebuild(workspaces: tabManager.tabs)
                    }
                }
            workspaceCancellables.append(cancellable)
        }
    }

    private func rebuild(workspaces: [Workspace]) {
        let inputs = workspaces.map { workspace in
            AgentsSidebarWorkspaceInput(
                workspaceId: workspace.id,
                title: workspace.title,
                panelLifecycles: workspace.agentLifecycleStatesByPanelId
            )
        }
        let result = Self.buildRows(
            workspaces: inputs,
            previousChangeDates: changeDates,
            now: Date()
        )
        changeDates = result.changeDates
        if agentRows != result.rows { agentRows = result.rows }
        if workspaceRollups != result.rollups { workspaceRollups = result.rollups }
    }
}
