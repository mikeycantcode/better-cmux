import Combine
import Foundation

/// Commit history for the left sidebar's Source Control Graph.
///
/// Follows the active workspace root. Reloads when the root changes and when
/// the root's ``GitStatusMonitor`` publishes (a commit, checkout, pull, or
/// push all change porcelain: staged files, branch, or ahead/behind).
@MainActor
final class GitCommitGraphModel: ObservableObject {
    @Published private(set) var rows: [GitGraphRow] = []
    @Published private(set) var branch: String?
    @Published private(set) var isRepository = false

    static let commitLimit = 200

    private var rootPath = ""
    private var monitor: GitStatusMonitor?
    private var monitorCancellable: AnyCancellable?
    private var loadTask: Task<Void, Never>?
    private var generation = 0

    func setRootPath(_ path: String) {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != rootPath else { return }
        rootPath = trimmed
        monitorCancellable = nil
        monitor = nil
        guard !trimmed.isEmpty else {
            generation += 1
            loadTask?.cancel()
            rows = []
            branch = nil
            isRepository = false
            return
        }
        let monitor = GitStatusMonitor.shared(forRepoRoot: trimmed)
        self.monitor = monitor
        monitorCancellable = monitor.$porcelain
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] porcelain in
                self?.branch = porcelain.branch
                self?.reload()
            }
        reload()
    }

    func reload() {
        let root = rootPath
        guard !root.isEmpty else { return }
        generation += 1
        let token = generation
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            let result = await GitWorkingTreeModel.runGit(
                GitGraphCommit.logArguments(limit: Self.commitLimit),
                in: root
            )
            // Layout is O(commits × lanes); keep it off the main actor too.
            let rows: [GitGraphRow]? = await Task.detached(priority: .userInitiated) {
                guard case .success(let output) = result else { return nil }
                return GitGraphLayout.rows(for: GitGraphCommit.parse(output))
            }.value
            guard let self, !Task.isCancelled, token == self.generation else { return }
            self.isRepository = rows != nil
            let next = rows ?? []
            if next != self.rows { self.rows = next }
        }
    }
}
