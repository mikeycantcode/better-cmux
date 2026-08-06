import Foundation

enum GitEntryStatus: Character, Sendable {
    case modified = "M", added = "A", deleted = "D", renamed = "R", untracked = "U"
}

struct GitStatusEntry: Identifiable, Hashable, Sendable {
    let path: String
    let originalPath: String?
    let status: GitEntryStatus
    var id: String { path }
}

/// Parses `git status --porcelain=v2 --branch` output.
struct GitPorcelainStatus: Sendable, Equatable {
    let branch: String?
    let upstream: String?
    let ahead: Int
    let behind: Int
    let staged: [GitStatusEntry]
    let modified: [GitStatusEntry]
    let untracked: [GitStatusEntry]

    static let empty = GitPorcelainStatus(
        branch: nil, upstream: nil, ahead: 0, behind: 0,
        staged: [], modified: [], untracked: []
    )

    static func parse(_ output: String) -> GitPorcelainStatus {
        var branch: String?
        var upstream: String?
        var ahead = 0, behind = 0
        var staged: [GitStatusEntry] = []
        var modified: [GitStatusEntry] = []
        var untracked: [GitStatusEntry] = []

        for line in output.split(separator: "\n", omittingEmptySubsequences: true) {
            if line.hasPrefix("# branch.head ") {
                let value = String(line.dropFirst("# branch.head ".count))
                branch = value == "(detached)" ? nil : value
            } else if line.hasPrefix("# branch.upstream ") {
                upstream = String(line.dropFirst("# branch.upstream ".count))
            } else if line.hasPrefix("# branch.ab ") {
                // "# branch.ab +3 -1"
                let parts = line.dropFirst("# branch.ab ".count).split(separator: " ")
                for part in parts {
                    if part.hasPrefix("+") { ahead = Int(part.dropFirst()) ?? 0 }
                    if part.hasPrefix("-") { behind = Int(part.dropFirst()) ?? 0 }
                }
            } else if line.hasPrefix("1 ") {
                // "1 XY sub mH mI mW hH hI path"
                let fields = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: false)
                guard fields.count >= 9 else { continue }
                let xy = fields[1]
                let path = unquote(String(fields[8]))
                appendEntry(xy: xy, path: path, originalPath: nil,
                            staged: &staged, modified: &modified)
            } else if line.hasPrefix("2 ") {
                // "2 XY sub mH mI mW hH hI Xscore path\torigPath"
                let fields = line.split(separator: " ", maxSplits: 9, omittingEmptySubsequences: false)
                guard fields.count >= 10 else { continue }
                let xy = fields[1]
                let pathField = String(fields[9])
                let tabSplit = pathField.split(separator: "\t", maxSplits: 1)
                let path = unquote(String(tabSplit.first ?? ""))
                let orig = tabSplit.count > 1 ? unquote(String(tabSplit[1])) : nil
                appendEntry(xy: xy, path: path, originalPath: orig,
                            staged: &staged, modified: &modified)
            } else if line.hasPrefix("? ") {
                let path = unquote(String(line.dropFirst(2)))
                untracked.append(GitStatusEntry(path: path, originalPath: nil, status: .untracked))
            }
            // "u " (unmerged) and "! " (ignored) records intentionally skipped in v1.
        }

        return GitPorcelainStatus(
            branch: branch, upstream: upstream, ahead: ahead, behind: behind,
            staged: staged, modified: modified, untracked: untracked
        )
    }

    private static func appendEntry(
        xy: Substring, path: String, originalPath: String?,
        staged: inout [GitStatusEntry], modified: inout [GitStatusEntry]
    ) {
        let index = xy.first ?? "."
        let worktree = xy.dropFirst().first ?? "."
        if index != ".", let status = entryStatus(for: index) {
            staged.append(GitStatusEntry(path: path, originalPath: originalPath, status: status))
        }
        if worktree != ".", let status = entryStatus(for: worktree) {
            modified.append(GitStatusEntry(path: path, originalPath: originalPath, status: status))
        }
    }

    private static func entryStatus(for char: Character) -> GitEntryStatus? {
        switch char {
        case "M", "T": return .modified
        case "A", "C": return .added
        case "D": return .deleted
        case "R": return .renamed
        default: return nil
        }
    }

    /// Git C-style quoting: paths with specials arrive as "..." with backslash escapes.
    private static func unquote(_ raw: String) -> String {
        guard raw.hasPrefix("\""), raw.hasSuffix("\""), raw.count >= 2 else { return raw }
        let inner = raw.dropFirst().dropLast()
        var result = ""
        var iterator = inner.makeIterator()
        while let ch = iterator.next() {
            guard ch == "\\", let escaped = iterator.next() else {
                result.append(ch)
                continue
            }
            switch escaped {
            case "t": result.append("\t")
            case "n": result.append("\n")
            case "\\": result.append("\\")
            case "\"": result.append("\"")
            default: result.append(escaped)
            }
        }
        return result
    }
}
