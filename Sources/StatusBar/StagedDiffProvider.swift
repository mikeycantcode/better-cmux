import Foundation
import CmuxFoundation

/// Computes uncommitted-diff stats for a directory's git repository, off the
/// main actor.
///
/// Counts all uncommitted changes to tracked files (staged + unstaged) versus
/// `HEAD` — i.e. `git diff HEAD --numstat` — so the bottom bar shows numbers
/// whenever there are edits, not only after `git add`. Mirrors
/// ``FileExplorerStore``'s `runGit` Process pattern. Pure parsing lives in
/// ``StagedDiffStats/parseNumstat(_:)`` so it is unit-tested without a git process.
actor StagedDiffProvider {
    /// Returns uncommitted stats (vs `HEAD`) for the git repo containing
    /// `directory`, or `nil` when the directory is not in a git repo (or has no
    /// commits yet).
    /// - Parameter directory: any path inside the working tree.
    func stagedStats(in directory: String) -> StagedDiffStats? {
        let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let repoRoot = Self.runGit(in: trimmed, arguments: ["rev-parse", "--show-toplevel"])?
            .trimmingCharacters(in: .whitespacesAndNewlines), !repoRoot.isEmpty else {
            return nil
        }
        // `diff HEAD` = working tree vs last commit = staged + unstaged changes to
        // tracked files (untracked files are not counted, matching `git diff`).
        guard let numstat = Self.runGit(in: repoRoot, arguments: ["diff", "HEAD", "--numstat"]) else {
            return nil
        }
        return StagedDiffStats.parseNumstat(numstat)
    }

    /// Runs `git` with `arguments` in `directory`, capturing stdout.
    private static func runGit(in directory: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFileOrEmpty()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
