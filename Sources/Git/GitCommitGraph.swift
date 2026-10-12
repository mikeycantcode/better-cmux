import Foundation

/// One commit as read from `git log`.
struct GitGraphCommit: Equatable, Sendable {
    let hash: String
    let parents: [String]
    let subject: String
    let author: String
    let relativeDate: String
    /// Decorations (`%D`) split into ref names, e.g. `["HEAD -> main", "origin/main"]`.
    let refs: [String]

    var shortHash: String { String(hash.prefix(7)) }
    var isHead: Bool { refs.contains { $0 == "HEAD" || $0.hasPrefix("HEAD -> ") } }

    /// Branch/tag names shown as badges. `HEAD -> main` collapses to `main`.
    var badgeNames: [String] {
        refs.compactMap { ref in
            if ref == "HEAD" { return nil }
            if ref.hasPrefix("HEAD -> ") { return String(ref.dropFirst("HEAD -> ".count)) }
            if ref.hasPrefix("tag: ") { return String(ref.dropFirst("tag: ".count)) }
            return ref
        }
    }

    /// Field and record separators used by ``logArguments`` and ``parse(_:)``.
    static let fieldSeparator = "\u{1f}"
    static let recordSeparator = "\u{1e}"

    static func logArguments(limit: Int) -> [String] {
        [
            "log", "--topo-order", "-n", String(limit), "--decorate=short",
            "--format=%H\u{1f}%P\u{1f}%s\u{1f}%an\u{1f}%ar\u{1f}%D\u{1e}",
            "HEAD",
        ]
    }

    static func parse(_ output: String) -> [GitGraphCommit] {
        output.components(separatedBy: recordSeparator).compactMap { record in
            let trimmed = record.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let fields = trimmed.components(separatedBy: fieldSeparator)
            guard fields.count >= 6, !fields[0].isEmpty else { return nil }
            return GitGraphCommit(
                hash: fields[0],
                parents: fields[1].split(separator: " ").map(String.init),
                subject: fields[2],
                author: fields[3],
                relativeDate: fields[4],
                refs: fields[5]
                    .components(separatedBy: ", ")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            )
        }
    }
}

/// A line segment inside one graph row, in lane units.
/// `y` is 0 at the row's top edge, 0.5 at the node, and 1 at the bottom edge.
struct GitGraphEdge: Equatable, Sendable {
    let fromLane: Int
    let fromY: Double
    let toLane: Int
    let toY: Double
    /// Lane whose color the edge takes.
    let colorLane: Int
}

/// Immutable per-row value handed to graph rows (snapshot-boundary rule).
struct GitGraphRow: Identifiable, Equatable, Sendable {
    let commit: GitGraphCommit
    let lane: Int
    let laneCount: Int
    let edges: [GitGraphEdge]

    var id: String { commit.hash }
}

/// Assigns lanes to commits in `git log --topo-order` order.
///
/// `lanes[i]` holds the hash lane `i` is waiting for. A commit lands in the
/// first lane waiting for it (or a fresh one), every other lane waiting for it
/// converges into the node, and its parents take over the lanes below it.
enum GitGraphLayout {
    static func rows(for commits: [GitGraphCommit]) -> [GitGraphRow] {
        var lanes: [String?] = []
        var rows: [GitGraphRow] = []
        rows.reserveCapacity(commits.count)

        for commit in commits {
            let wasExpected = lanes.contains(commit.hash)
            let lane: Int
            if let existing = lanes.firstIndex(of: commit.hash) {
                lane = existing
            } else {
                lane = Self.claimFreeLane(&lanes, for: commit.hash)
            }

            var edges: [GitGraphEdge] = []
            // Top half: lanes entering this row.
            for (index, expected) in lanes.enumerated() {
                guard let expected else { continue }
                if expected == commit.hash {
                    if index == lane && !wasExpected { continue }
                    edges.append(GitGraphEdge(fromLane: index, fromY: 0, toLane: lane, toY: 0.5, colorLane: index))
                } else {
                    edges.append(GitGraphEdge(fromLane: index, fromY: 0, toLane: index, toY: 0.5, colorLane: index))
                }
            }

            for index in lanes.indices where lanes[index] == commit.hash {
                lanes[index] = nil
            }

            // Lanes still waiting on other commits continue straight down.
            for (index, expected) in lanes.enumerated() where expected != nil {
                edges.append(GitGraphEdge(fromLane: index, fromY: 0.5, toLane: index, toY: 1, colorLane: index))
            }

            // Bottom half: parents leave the node.
            if let first = commit.parents.first {
                lanes[lane] = first
                edges.append(GitGraphEdge(fromLane: lane, fromY: 0.5, toLane: lane, toY: 1, colorLane: lane))
            }
            for parent in commit.parents.dropFirst() {
                let target: Int
                if let existing = lanes.firstIndex(of: parent) {
                    target = existing
                } else {
                    target = Self.claimFreeLane(&lanes, for: parent)
                }
                guard target != lane else { continue }
                edges.append(GitGraphEdge(fromLane: lane, fromY: 0.5, toLane: target, toY: 1, colorLane: target))
            }

            while let last = lanes.last, last == nil { lanes.removeLast() }

            let laneCount = max(
                lane + 1,
                edges.map { max($0.fromLane, $0.toLane) + 1 }.max() ?? 1
            )
            rows.append(GitGraphRow(commit: commit, lane: lane, laneCount: laneCount, edges: edges))
        }
        return rows
    }

    private static func claimFreeLane(_ lanes: inout [String?], for hash: String) -> Int {
        if let free = lanes.firstIndex(where: { $0 == nil }) {
            lanes[free] = hash
            return free
        }
        lanes.append(hash)
        return lanes.count - 1
    }
}
