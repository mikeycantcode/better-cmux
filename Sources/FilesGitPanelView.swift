import SwiftUI

nonisolated enum FilesGitTab: String, Codable {
    case files
    case git
}

/// The right sidebar: a Files | Git pill header, the ~-abbreviated root path,
/// and the active tab's content.
struct FilesGitPanelView: View {
    // Deliberately not `@ObservedObject`: neither is read in `body`, so observing them
    // would invalidate the whole shell on every debounced git refresh for nothing.
    // Task 6's `GitPanelView` observes `gitModel` itself.
    let explorerState: FileExplorerState
    let gitModel: GitWorkingTreeModel
    let rootPath: String
    let filesContent: AnyView          // FileExplorerPanelView supplied by the mount site
    let gitContent: AnyView            // GitPanelView supplied by the mount site (Task 6)

    @AppStorage("rightSidebar.filesGitTab") private var tabRaw: String = FilesGitTab.files.rawValue

    private var tab: FilesGitTab { FilesGitTab(rawValue: tabRaw) ?? .files }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.vertical, 8)
            if !rootPath.isEmpty {
                pathLine
                    .padding(.bottom, 6)
            }
            Divider().opacity(0.35)
            switch tab {
            case .files: filesContent
            case .git: gitContent
            }
        }
    }

    private var header: some View {
        HStack(spacing: 2) {
            segment(
                .files,
                label: String(localized: "filesGitPanel.tab.files", defaultValue: "Files"),
                symbol: "doc.on.doc"
            )
            segment(
                .git,
                label: String(localized: "filesGitPanel.tab.git", defaultValue: "Git"),
                symbol: "arrow.triangle.branch"
            )
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
        .frame(maxWidth: .infinity)
        .titlebarInteractiveControl()
    }

    private func segment(_ value: FilesGitTab, label: String, symbol: String) -> some View {
        Button {
            tabRaw = value.rawValue
        } label: {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .medium))
                Text(label).font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(tab == value ? Color.primary.opacity(0.12) : .clear)
            )
            .foregroundStyle(tab == value ? .primary : .secondary)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("FilesGitPanel.tab.\(value.rawValue)")
    }

    private var pathLine: some View {
        Text(Self.abbreviatedPath(rootPath))
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
    }

    static func abbreviatedPath(_ path: String) -> String {
        let home = NSHomeDirectory()
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}
