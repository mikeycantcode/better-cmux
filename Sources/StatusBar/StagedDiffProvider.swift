import Foundation

/// Computes staged-diff stats for a directory's git repository, off the main
/// actor.
///
/// Mirrors ``FileExplorerStore``'s `runGit` Process pattern. Pure parsing lives
/// in ``StagedDiffStats/parseNumstat(_:)`` so it is unit-tested without a git
/// process.
actor StagedDiffProvider {
    /// Returns staged stats for the git repo containing `directory`, or `nil`
    /// when the directory is not in a git repo.
    /// - Parameter directory: any path inside the working tree.
    func stagedStats(in directory: String) -> StagedDiffStats? {
        let trimmed = directory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let repoRoot = Self.runGit(in: trimmed, arguments: ["rev-parse", "--show-toplevel"])?
            .trimmingCharacters(in: .whitespacesAndNewlines), !repoRoot.isEmpty else {
            return nil
        }
        guard let numstat = Self.runGit(in: repoRoot, arguments: ["diff", "--cached", "--numstat"]) else {
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
            let data = ProcessPipeReader.readDataToEndOfFileOrEmpty(from: pipe.fileHandleForReading)
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
