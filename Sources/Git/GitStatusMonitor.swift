import Combine
import Foundation

/// Flattening rules shared by every consumer of `GitPorcelainStatus`.
///
/// A file can appear twice in a porcelain read — once for its index (X) column
/// and once for its worktree (Y) column — with different statuses. The explorer
/// paints exactly one color per row, so the two must collapse to one status.
enum GitStatusFlattening {
    /// Attention ordering: conflict > deleted > added/untracked > modified > renamed.
    ///
    /// `GitPorcelainStatus.parse` skips unmerged (`u `) records today, so there is
    /// no `conflict` case to rank; the slot is reserved so adding one later only
    /// means adding a rank here.
    static func severity(_ status: GitEntryStatus) -> Int {
        switch status {
        case .deleted: return 4
        case .added, .untracked: return 3
        case .modified: return 2
        case .renamed: return 1
        }
    }

    /// The more attention-worthy of two statuses. Ties keep `lhs` so the result
    /// is stable regardless of the order entries arrive in.
    static func worse(_ lhs: GitEntryStatus, _ rhs: GitEntryStatus) -> GitEntryStatus {
        severity(rhs) > severity(lhs) ? rhs : lhs
    }

    /// Absolute path → flattened status for every entry in `porcelain`.
    ///
    /// `base` is the repo root spelled the way the caller's paths are spelled
    /// (see ``repoRootSpelling(requestedRoot:toplevel:)``). Rename entries are
    /// keyed by their *new* path only: the original path no longer exists on
    /// disk, so it has no row to decorate.
    static func statusByPath(_ porcelain: GitPorcelainStatus, base: String) -> [String: GitEntryStatus] {
        var result: [String: GitEntryStatus] = [:]
        for entry in porcelain.staged + porcelain.modified + porcelain.untracked {
            let absolute = absolutePath(entry.path, base: base)
            if let existing = result[absolute] {
                result[absolute] = worse(existing, entry.status)
            } else {
                result[absolute] = entry.status
            }
        }
        return result
    }

    /// Every ancestor directory of a changed path, up to and including `base`
    /// (the repo root) and excluding the repo root's parent.
    ///
    /// An untracked *directory* (porcelain reports it with a trailing slash) is
    /// itself a changed directory, not just an ancestor of one.
    static func directoryHasChanges(paths: some Sequence<String>, base: String) -> Set<String> {
        let normalizedBase = normalize(base)
        var result: Set<String> = []
        for raw in paths {
            var current = normalize(raw)
            if raw.hasSuffix("/") { result.insert(current) }
            while current != normalizedBase, current.count > normalizedBase.count,
                  current.hasPrefix(normalizedBase + "/") {
                current = (current as NSString).deletingLastPathComponent
                result.insert(current)
            }
        }
        return result
    }

    /// The repo root spelled the way `requestedRoot` spells it.
    ///
    /// `git rev-parse --show-toplevel` returns the symlink-resolved worktree
    /// root (`/private/var/...`), but explorer node paths are built from the
    /// requested root's spelling (`/var/...`). Keying the map by the resolved
    /// spelling would make every decoration silently miss.
    ///
    /// - When the requested root *is* the worktree root, its own spelling wins.
    /// - When the requested root is a subdirectory of the worktree root, the
    ///   subdirectory suffix is peeled off the requested spelling.
    /// - Otherwise (unrelated spellings) the resolved toplevel is used as-is.
    static func repoRootSpelling(requestedRoot: String, toplevel: String) -> String {
        repoRootSpelling(
            requestedRoot: requestedRoot,
            toplevel: toplevel,
            resolvedRequested: URL(fileURLWithPath: requestedRoot).resolvingSymlinksInPath().path
        )
    }

    /// Filesystem-free core of ``repoRootSpelling(requestedRoot:toplevel:)``.
    /// `resolvedRequested` is the symlink-resolved spelling of `requestedRoot`.
    static func repoRootSpelling(
        requestedRoot: String, toplevel: String, resolvedRequested: String
    ) -> String {
        let requested = normalize(requestedRoot)
        let top = normalize(toplevel)
        guard !requested.isEmpty else { return top }
        let resolved = normalize(resolvedRequested)
        if resolved == top { return requested }
        guard resolved.hasPrefix(top + "/") else { return top }
        let suffix = String(resolved.dropFirst(top.count))  // "/sub/dir"
        guard requested.hasSuffix(suffix) else { return top }
        let peeled = String(requested.dropLast(suffix.count))
        return peeled.isEmpty ? "/" : peeled
    }

    /// Absolute paths of every changed entry, preserving the trailing slash that
    /// marks an untracked directory.
    static func changedAbsolutePaths(_ porcelain: GitPorcelainStatus, base: String) -> [String] {
        (porcelain.staged + porcelain.modified + porcelain.untracked).map {
            join(base: base, relative: $0.path)
        }
    }

    private static func absolutePath(_ relative: String, base: String) -> String {
        normalize(join(base: base, relative: relative))
    }

    private static func join(base: String, relative: String) -> String {
        let normalizedBase = normalize(base)
        return normalizedBase == "/" ? "/" + relative : normalizedBase + "/" + relative
    }

    /// Trailing-slash-free spelling. `/` stays `/`.
    static func normalize(_ path: String) -> String {
        var value = path
        while value.count > 1, value.hasSuffix("/") { value.removeLast() }
        return value
    }
}

/// The single `git status` pipeline for one repository root.
///
/// Both the file explorer's decorations and the Git tab's porcelain view read
/// from here, so a change burst costs exactly one `git status` subprocess
/// instead of one per consumer. Instances are shared per normalized root.
///
/// Every publish is equality-guarded (no emission when the value is unchanged),
/// and every read carries a generation token so a slow read can never land on
/// top of a newer one.
@MainActor
final class GitStatusMonitor: ObservableObject {
    /// Absolute path → flattened status (worst of the index/worktree columns).
    @Published private(set) var statusByPath: [String: GitEntryStatus] = [:]
    /// Absolute directory paths with at least one dirty descendant.
    @Published private(set) var directoryHasChanges: Set<String> = []
    /// The full parse, for the Git tab.
    @Published private(set) var porcelain: GitPorcelainStatus = .empty
    /// First stderr line of the last failed read, or nil.
    @Published private(set) var lastErrorLine: String?

    /// The root this monitor was created for, normalized.
    let repoRoot: String

    typealias GitRunner = @Sendable ([String], String) async -> GitWorkingTreeModel.GitResult

    private let runGit: GitRunner
    /// Repo root in the requested root's spelling; nil until a successful resolve.
    private var cachedBase: String?
    private var debounceTask: Task<Void, Never>?
    private var generation = 0

    static let debounceNanoseconds: UInt64 = 300_000_000

    private static var instances: [String: GitStatusMonitor] = [:]

    /// One monitor per normalized repo root, shared by every consumer.
    static func shared(forRepoRoot root: String) -> GitStatusMonitor {
        let key = GitStatusFlattening.normalize(root)
        if let existing = instances[key] { return existing }
        let monitor = GitStatusMonitor(repoRoot: key)
        instances[key] = monitor
        return monitor
    }

    init(
        repoRoot: String,
        runGit: @escaping GitRunner = { await GitWorkingTreeModel.runGit($0, in: $1) }
    ) {
        self.repoRoot = GitStatusFlattening.normalize(repoRoot)
        self.runGit = runGit
    }

    // MARK: - Refresh

    /// Coalesces a change burst into one read ~300 ms after the last event.
    func scheduleRefresh() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounceNanoseconds)
            guard !Task.isCancelled else { return }
            await self?.refreshNow()
        }
    }

    func refreshNow() async {
        generation &+= 1
        let token = generation

        guard !repoRoot.isEmpty else {
            applyEmpty(errorLine: nil)
            return
        }

        guard let base = await resolveBase() else {
            guard token == generation else { return }
            applyEmpty(errorLine: nil)
            return
        }
        guard token == generation else { return }

        let result = await runGit(["status", "--porcelain=v2", "--branch"], base)
        // A newer read started while this one was in flight: drop this result
        // rather than letting the stale snapshot overwrite the fresh one.
        guard token == generation else { return }

        switch result {
        case .success(let output):
            apply(GitPorcelainStatus.parse(output), base: base, errorLine: nil)
        case .failure(let message):
            applyEmpty(errorLine: message.isEmpty ? nil : message)
        }
    }

    /// Resolves (and caches) the worktree root in the requested root's spelling.
    /// Returns nil when the root is not inside a git repository.
    private func resolveBase() async -> String? {
        if let cachedBase { return cachedBase }
        guard case .success(let output) = await runGit(["rev-parse", "--show-toplevel"], repoRoot) else {
            return nil
        }
        let toplevel = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !toplevel.isEmpty else { return nil }
        let base = GitStatusFlattening.repoRootSpelling(requestedRoot: repoRoot, toplevel: toplevel)
        cachedBase = base
        return base
    }

    // MARK: - Publishing

    /// Recomputes the derived maps and publishes only what actually changed.
    func apply(_ newPorcelain: GitPorcelainStatus, base: String, errorLine: String?) {
        let newStatusByPath = GitStatusFlattening.statusByPath(newPorcelain, base: base)
        let newDirectories = GitStatusFlattening.directoryHasChanges(
            paths: GitStatusFlattening.changedAbsolutePaths(newPorcelain, base: base),
            base: base
        )

        if porcelain != newPorcelain { porcelain = newPorcelain }
        if statusByPath != newStatusByPath { statusByPath = newStatusByPath }
        if directoryHasChanges != newDirectories { directoryHasChanges = newDirectories }
        if lastErrorLine != errorLine { lastErrorLine = errorLine }
    }

    private func applyEmpty(errorLine: String?) {
        if porcelain != .empty { porcelain = .empty }
        if !statusByPath.isEmpty { statusByPath = [:] }
        if !directoryHasChanges.isEmpty { directoryHasChanges = [] }
        if lastErrorLine != errorLine { lastErrorLine = errorLine }
    }
}
