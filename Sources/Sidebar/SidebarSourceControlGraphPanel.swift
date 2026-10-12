import AppKit
import CmuxFoundation
import SwiftUI

/// VS Code-style "Source Control Graph" section for the left sidebar: a
/// collapsible header plus the HEAD commit history drawn as lanes.
///
/// Observes ``GitCommitGraphModel`` here and hands rows immutable
/// ``GitGraphRow`` values (snapshot-boundary rule).
struct SidebarSourceControlGraphPanel: View {
    @ObservedObject var model: GitCommitGraphModel
    let repoName: String
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var header: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 12)
                Text(String(localized: "sidebar.scmGraph.title", defaultValue: "Source Control Graph").uppercased())
                    .cmuxFont(size: 11, weight: .semibold)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 6)
                if let branch = model.branch, !branch.isEmpty {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9, weight: .medium))
                        Text(branch)
                            .cmuxFont(size: 11)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                } else if model.isRepository && !repoName.isEmpty {
                    Text(repoName)
                        .cmuxFont(size: 11)
                        .lineLimit(1)
                        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
                }
            }
            .foregroundStyle(Color.secondary)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            isExpanded
                ? String(localized: "sidebar.scmGraph.collapse", defaultValue: "Collapse source control graph")
                : String(localized: "sidebar.scmGraph.expand", defaultValue: "Expand source control graph")
        )
    }

    @ViewBuilder
    private var content: some View {
        if !model.isRepository {
            Text(String(localized: "sidebar.scmGraph.noRepository", defaultValue: "No git repository"))
                .cmuxFont(size: 11)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let rows = model.rows
            let graphLanes = min(GitGraphRowView.maxDrawnLanes, rows.map(\.laneCount).max() ?? 1)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        GitGraphRowView(row: row, graphLanes: graphLanes)
                            .equatable()
                    }
                }
                .padding(.bottom, 6)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.never)
        }
    }
}

/// One commit row: lane graph, subject, and ref badges.
struct GitGraphRowView: View, Equatable {
    let row: GitGraphRow
    let graphLanes: Int

    static let rowHeight: CGFloat = 22
    static let laneWidth: CGFloat = 11
    static let maxDrawnLanes = 5

    static let palette: [Color] = [
        Color(red: 0.31, green: 0.64, blue: 0.65),
        Color(red: 0.84, green: 0.66, blue: 0.31),
        Color(red: 0.69, green: 0.50, blue: 0.84),
        Color(red: 0.37, green: 0.66, blue: 0.91),
        Color(red: 0.88, green: 0.48, blue: 0.37),
        Color(red: 0.51, green: 0.72, blue: 0.55),
    ]

    static func color(forLane lane: Int) -> Color {
        palette[lane % palette.count]
    }

    var body: some View {
        HStack(spacing: 6) {
            graph
                .frame(width: CGFloat(graphLanes) * Self.laneWidth + 4, height: Self.rowHeight)
            Text(row.commit.subject)
                .cmuxFont(size: 12, weight: row.commit.isHead ? .semibold : .regular)
                .foregroundStyle(row.commit.isHead ? Color.primary : Color.primary.opacity(0.78))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            // The badge claims its width (capped) before the subject truncates.
            if let name = row.commit.badgeNames.first {
                badge(name)
                    .layoutPriority(1)
            }
        }
        .padding(.leading, 8)
        .padding(.trailing, 8)
        .frame(height: Self.rowHeight)
        .contentShape(Rectangle())
        .help("\(row.commit.shortHash) · \(row.commit.author) · \(row.commit.relativeDate)\n\(row.commit.subject)")
        .contextMenu {
            Button(String(localized: "sidebar.scmGraph.copyHash", defaultValue: "Copy Commit Hash")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.commit.hash, forType: .string)
            }
            Button(String(localized: "sidebar.scmGraph.copySubject", defaultValue: "Copy Commit Message")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(row.commit.subject, forType: .string)
            }
        }
    }

    private var graph: some View {
        Canvas { context, size in
            let laneWidth = Self.laneWidth
            func x(_ lane: Int) -> CGFloat { CGFloat(lane) * laneWidth + laneWidth / 2 + 2 }
            func y(_ fraction: Double) -> CGFloat { size.height * CGFloat(fraction) }

            for edge in row.edges where edge.fromLane < Self.maxDrawnLanes && edge.toLane < Self.maxDrawnLanes {
                var path = Path()
                let start = CGPoint(x: x(edge.fromLane), y: y(edge.fromY))
                let end = CGPoint(x: x(edge.toLane), y: y(edge.toY))
                path.move(to: start)
                if edge.fromLane == edge.toLane {
                    path.addLine(to: end)
                } else {
                    let midY = (start.y + end.y) / 2
                    path.addCurve(
                        to: end,
                        control1: CGPoint(x: start.x, y: midY),
                        control2: CGPoint(x: end.x, y: midY)
                    )
                }
                context.stroke(
                    path,
                    with: .color(Self.color(forLane: edge.colorLane)),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round)
                )
            }

            guard row.lane < Self.maxDrawnLanes else { return }
            let center = CGPoint(x: x(row.lane), y: y(0.5))
            let color = Self.color(forLane: row.lane)
            if row.commit.isHead {
                let outer = CGRect(x: center.x - 5, y: center.y - 5, width: 10, height: 10)
                context.fill(Path(ellipseIn: outer), with: .color(Color(nsColor: .windowBackgroundColor)))
                context.stroke(Path(ellipseIn: outer), with: .color(color), lineWidth: 2.2)
            } else {
                let dot = CGRect(x: center.x - 3.5, y: center.y - 3.5, width: 7, height: 7)
                context.fill(Path(ellipseIn: dot), with: .color(color))
            }
        }
    }

    private func badge(_ name: String) -> some View {
        let color = Self.color(forLane: row.lane)
        let isRemote = name.contains("/")
        return HStack(spacing: 3) {
            Image(systemName: isRemote ? "cloud" : "smallcircle.filled.circle")
                .font(.system(size: 9, weight: .semibold))
            Text(name)
                .cmuxFont(size: 10.5, weight: .medium)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .foregroundStyle(isRemote ? color : Color.white.opacity(0.95))
        .background(
            Capsule(style: .continuous)
                .fill(isRemote ? color.opacity(0.16) : color.opacity(0.85))
        )
        .frame(maxWidth: 84)
        .fixedSize(horizontal: false, vertical: true)
    }
}
