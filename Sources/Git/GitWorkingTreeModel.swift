import Foundation

/// Working-tree git state + actions for one repository root.
/// All git invocations run off-main; published state mutates on the main actor.
@MainActor
final class GitWorkingTreeModel: ObservableObject {
    @Published private(set) var status: GitPorcelainStatus = .empty
    @Published private(set) var isBusy: Bool = false
    @Published var lastErrorLine: String?

    var repoPath: String {
        didSet { if repoPath != oldValue { Task { await refresh() } } }
    }

    private var debounceTask: Task<Void, Never>?

    init(repoPath: String) {
        self.repoPath = repoPath
    }

    // MARK: - Refresh

    func refresh() async {
        let path = repoPath
        guard !path.isEmpty else {
            status = .empty
            return
        }
        let result = await Self.runGit(["status", "--porcelain=v2", "--branch"], in: path)
        switch result {
        case .success(let output):
            status = GitPorcelainStatus.parse(output)
            lastErrorLine = nil
        case .failure(let message):
            // Not a repo (or git missing): show empty state, keep the reason.
            status = .empty
            lastErrorLine = message.isEmpty ? nil : message
        }
    }

    /// Coalesces watcher bursts into one refresh ~300 ms after the last event.
    func scheduleDebouncedRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    // MARK: - Actions

    func stageFile(_ path: String) async { await runAction(["add", "--", path]) }
    func unstageFile(_ path: String) async { await runAction(["restore", "--staged", "--", path]) }

    func discardFile(_ entry: GitStatusEntry) async {
        if entry.status == .untracked {
            await runAction(["clean", "-f", "--", entry.path])
        } else {
            await runAction(["checkout", "--", entry.path])
        }
    }

    func stageAll() async { await runAction(["add", "-A"]) }

    func discardAll() async {
        await runAction(["checkout", "--", "."])
        await runAction(["clean", "-fd"])
    }

    @discardableResult
    func commit(message: String) async -> Bool {
        await runAction(["commit", "-m", message]) != nil
    }

    @discardableResult
    func push() async -> Bool {
        let args: [String]
        if hasUpstream {
            args = ["push"]
        } else if let branch = status.branch {
            args = ["push", "-u", "origin", branch]
        } else {
            lastErrorLine = String(
                localized: "gitPanel.error.detachedPush",
                defaultValue: "Cannot push: detached HEAD."
            )
            return false
        }
        return await runAction(args) != nil
    }

    var hasUpstream: Bool { status.upstream != nil }

    /// Count shown on the green Publish/Push button.
    var publishCount: Int {
        hasUpstream
            ? status.ahead
            : status.staged.count + status.modified.count + status.untracked.count
    }

    // MARK: - Plumbing

    /// Runs a mutating git command, surfaces stderr's first line on failure,
    /// then re-reads status. Returns stdout on success, nil on failure.
    @discardableResult
    private func runAction(_ args: [String]) async -> String? {
        isBusy = true
        defer { isBusy = false }
        let result = await Self.runGit(args, in: repoPath)
        switch result {
        case .success(let output):
            await refresh()
            return output
        case .failure(let message):
            // Refresh first: a successful status read clears `lastErrorLine`,
            // so the action's error must be written after it to survive.
            await refresh()
            lastErrorLine = message
            return nil
        }
    }

    private enum GitResult {
        case success(String)
        case failure(String)
    }

    private nonisolated static func runGit(_ args: [String], in directory: String) async -> GitResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
                process.currentDirectoryURL = URL(fileURLWithPath: directory)
                process.arguments = args
                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: .failure(String(describing: error)))
                    return
                }
                let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    continuation.resume(returning: .success(stdout))
                } else {
                    let firstLine = stderr.split(separator: "\n").first.map(String.init)
                        ?? stdout.split(separator: "\n").first.map(String.init)
                        ?? "git \(args.first ?? "") failed (\(process.terminationStatus))"
                    continuation.resume(returning: .failure(firstLine))
                }
            }
        }
    }
}
