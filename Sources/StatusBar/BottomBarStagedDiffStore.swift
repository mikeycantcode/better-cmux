import CmuxFoundation
import Foundation

/// Owns the bottom bar's staged-diff state for the active workspace directory,
/// refreshing off-main via ``StagedDiffProvider`` and re-running when the repo's
/// files change (a `FileWatcher` on the directory, throttled — catches `git add`).
@MainActor
final class BottomBarStagedDiffStore: ObservableObject {
    @Published private(set) var stats: StagedDiffStats = .empty

    private let provider = StagedDiffProvider()
    private var directory: String = ""
    private var watcher: FileWatcher?
    private var watchTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?

    /// Points the store at `directory` (the active workspace's cwd). No-op when
    /// unchanged. Empty clears the bar's staged segment.
    func activate(directory newDirectory: String) {
        let trimmed = newDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != directory else { return }
        directory = trimmed
        stopWatching()
        guard !trimmed.isEmpty else {
            stats = .empty
            return
        }
        let w = FileWatcher(path: trimmed, throttle: .milliseconds(300))
        watcher = w
        let events = w.events
        watchTask = Task { @MainActor [weak self] in
            for await _ in events {
                self?.refresh()
            }
        }
        refresh()
    }

    /// Recomputes staged stats off-main and publishes the result.
    func refresh() {
        let dir = directory
        guard !dir.isEmpty else { stats = .empty; return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self, provider] in
            let next = await provider.stagedStats(in: dir) ?? .empty
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in self?.stats = next }
        }
    }

    private func stopWatching() {
        watchTask?.cancel(); watchTask = nil
        watcher = nil
    }
}
