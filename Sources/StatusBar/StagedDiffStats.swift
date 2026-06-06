import Foundation

/// Counts of staged (index) changes for a git repository.
///
/// Produced by ``StagedDiffProvider`` from `git diff --cached --numstat` and
/// shown in the bottom status bar as `⊕<files> +<additions> −<deletions>`.
struct StagedDiffStats: Equatable, Sendable {
    /// Number of files with staged changes.
    let files: Int
    /// Total added lines across staged files (binary files contribute 0).
    let additions: Int
    /// Total deleted lines across staged files (binary files contribute 0).
    let deletions: Int

    /// A stats value representing no staged changes.
    static let empty = StagedDiffStats(files: 0, additions: 0, deletions: 0)

    /// Whether there are no staged changes.
    var isEmpty: Bool { files == 0 && additions == 0 && deletions == 0 }

    /// Parses `git diff --cached --numstat` output.
    ///
    /// Each line is `<additions>\t<deletions>\t<path>`, where a binary file uses
    /// `-` for both counts. Blank/short lines are ignored.
    /// - Parameter output: raw stdout from `git diff --cached --numstat`.
    /// - Returns: summed additions/deletions and a per-line file count.
    static func parseNumstat(_ output: String) -> StagedDiffStats {
        var files = 0
        var additions = 0
        var deletions = 0
        for rawLine in output.split(separator: "\n", omittingEmptySubsequences: true) {
            let parts = rawLine.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            files += 1
            if let add = Int(parts[0]) { additions += add }
            if let del = Int(parts[1]) { deletions += del }
        }
        return StagedDiffStats(files: files, additions: additions, deletions: deletions)
    }
}
