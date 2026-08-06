import Foundation

/// Working-tree git state + actions for one repository root.
/// All git invocations run off-main; published state mutates on the main actor.
@MainActor
final class GitWorkingTreeModel: ObservableObject {
    @Published private(set) var status: GitPorcelainStatus = .empty
    @Published private(set) var isBusy: Bool = false
    @Published var lastErrorLine: String?

    /// Workspace root. Changing it schedules a refresh through the same
    /// cancel-token machinery as watcher events, so rapid workspace switches
    /// coalesce into one read and a stale result can never land over a fresh one.
    var repoPath: String {
        didSet { if repoPath != oldValue { scheduleDebouncedRefresh() } }
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
            // `-d` so untracked *directories* discard too (matches `discardAll`).
            await runAction(["clean", "-fd", "--", entry.path])
        } else {
            await runAction(["checkout", "--", entry.path])
        }
    }

    // MARK: Batch actions
    //
    // Each of these is ONE `runAction`-style call: at most two git invocations,
    // a single refresh, and a single error surface. Looping the per-file actions
    // instead would spawn 2N processes and let a later iteration's successful
    // refresh wipe an earlier failure's `lastErrorLine` — reporting success for
    // a partially failed batch.

    /// Stages exactly `paths` (pathspec-scoped; never `add -A`).
    func stageFiles(_ paths: [String]) async {
        guard !paths.isEmpty else { return }
        await runActions([["add", "--"] + paths])
    }

    /// Unstages exactly `paths`.
    func unstageFiles(_ paths: [String]) async {
        guard !paths.isEmpty else { return }
        await runActions([["restore", "--staged", "--"] + paths])
    }

    /// Discards exactly `entries`: tracked paths are restored from HEAD and
    /// untracked paths are removed, in at most two git invocations.
    func discardFiles(_ entries: [GitStatusEntry]) async {
        guard !entries.isEmpty else { return }
        let tracked = entries.filter { $0.status != .untracked }.map(\.path)
        let untracked = entries.filter { $0.status == .untracked }.map(\.path)
        var commands: [[String]] = []
        if !tracked.isEmpty { commands.append(["checkout", "--"] + tracked) }
        if !untracked.isEmpty { commands.append(["clean", "-fd", "--"] + untracked) }
        await runActions(commands)
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

    /// Runs a batch of git commands as one logical action: stops at the first
    /// failure, refreshes exactly once, and surfaces exactly one error line.
    /// Returns true when every command succeeded.
    @discardableResult
    private func runActions(_ commands: [[String]]) async -> Bool {
        guard !commands.isEmpty else { return true }
        isBusy = true
        defer { isBusy = false }
        var failure: String?
        for args in commands {
            if case .failure(let message) = await Self.runGit(args, in: repoPath) {
                failure = message
                break
            }
        }
        // Refresh first: a successful status read clears `lastErrorLine`, so the
        // action's error must be written after it to survive.
        await refresh()
        if let failure {
            lastErrorLine = failure
            return false
        }
        return true
    }

    /// Result of one git invocation. Internal (not private) because
    /// ``GitChangesPanel`` reuses ``runGit(_:in:)`` for its read-only diff payload
    /// instead of standing up a second process-spawning helper.
    enum GitResult {
        case success(String)
        case failure(String)
    }

    /// Runs `git args` in `directory` off-main and returns stdout, or the first
    /// stderr line on failure. Read-only callers (the Changes panel's
    /// `git show HEAD:<path>` / `git diff --numstat`) use this directly; mutating
    /// callers must go through `runAction`/`runActions` so status refresh and
    /// error surfacing stay on one path.
    nonisolated static func runGit(_ args: [String], in directory: String) async -> GitResult {
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
                // Both pipes must be drained concurrently: a sequential
                // read-to-EOF deadlocks as soon as the other pipe's 64KB buffer
                // fills (realistic for `push` progress or a large `clean`).
                var outData = Data()
                var errData = Data()
                let group = DispatchGroup()
                let reader = DispatchQueue(label: "com.cmux.git.pipe-drain", attributes: .concurrent)
                reader.async(group: group) {
                    outData = out.fileHandleForReading.readDataToEndOfFile()
                }
                reader.async(group: group) {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                }
                group.wait()
                process.waitUntilExit()
                let stdout = String(data: outData, encoding: .utf8) ?? ""
                let stderr = String(data: errData, encoding: .utf8) ?? ""
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
