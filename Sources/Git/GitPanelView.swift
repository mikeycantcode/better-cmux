import AppKit
import SwiftUI

// MARK: - Pure projection

/// The two VS Code SCM buckets. Untracked files merge into `.changes` (marked
/// `U`), exactly as VS Code presents them.
enum ScmSection: String {
    case staged
    case changes
}

/// Immutable row description handed across the `ForEach` snapshot boundary.
struct ScmRowSnapshot: Identifiable, Equatable {
    let section: ScmSection
    /// Repo-relative path.
    let path: String
    let fileName: String
    /// Dimmed parent path; `""` for files at the repo root.
    let directoryText: String
    let statusLetter: String
    let statusColorHex: String

    var id: String { section.rawValue + path }
}

/// The Git tab of the right sidebar, styled as the VS Code Source Control
/// changes view: a quiet branch toolbar plus collapsible `Staged Changes` and
/// `Changes` sections. No commit box and no push/publish — those live elsewhere.
///
/// This view observes `GitWorkingTreeModel` directly — the `FilesGitPanelView`
/// shell deliberately holds the model as a plain `let` so a debounced git
/// refresh does not invalidate the whole sidebar. The model is read only above
/// the `ForEach`; rows receive `ScmRowSnapshot` values plus closures.
struct GitPanelView: View {
    @ObservedObject var model: GitWorkingTreeModel
    /// Receives an absolute path; the mount site converts from repo-relative.
    let openFile: (String) -> Void
    /// nil until Task 8 lands `GitChangesPanel`; the affordance stays hidden.
    let openChanges: (() -> Void)?

    /// Exactly one confirmation can be pending. Two stacked
    /// `.confirmationDialog` modifiers on the same view silently present only
    /// one on macOS, so the second dialog is modelled as another case here
    /// rather than as another modifier.
    enum PendingConfirm: Identifiable {
        case discardEntries([GitStatusEntry])
        case discardFile(GitStatusEntry)

        var id: String {
            switch self {
            case .discardEntries(let entries): return "all:" + entries.map(\.path).joined(separator: "\u{1}")
            case .discardFile(let entry): return "file:" + entry.path
            }
        }

        var entries: [GitStatusEntry] {
            switch self {
            case .discardEntries(let entries): return entries
            case .discardFile(let entry): return [entry]
            }
        }

        var isBatch: Bool {
            if case .discardEntries = self { return true }
            return false
        }
    }

    @State private var pendingConfirm: PendingConfirm?
    @State private var stagedCollapsed = false
    @State private var changesCollapsed = false

    /// Absolute path for a repo-relative git entry path.
    static func absolutePath(root: String, relative: String) -> String {
        guard !root.isEmpty else { return relative }
        if relative.hasPrefix("/") { return relative }
        return root.hasSuffix("/") ? root + relative : root + "/" + relative
    }

    /// Commit is available only with something staged, a non-blank message, and
    /// no git command in flight. The commit UI lives outside this view; the
    /// rule stays here as the single shared definition.
    static func isCommitEnabled(stagedCount: Int, message: String, isBusy: Bool) -> Bool {
        stagedCount > 0
            && !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isBusy
    }

    /// Push is a no-op when an upstream exists and nothing is ahead; with no
    /// upstream the button always publishes the branch.
    static func isPushEnabled(hasUpstream: Bool, publishCount: Int, isBusy: Bool) -> Bool {
        !isBusy && !(hasUpstream && publishCount == 0)
    }

    static func pushButtonLabel(hasUpstream: Bool, publishCount: Int) -> String {
        hasUpstream
            ? String(localized: "gitPanel.push", defaultValue: "Push (\(publishCount))")
            : String(localized: "gitPanel.publishBranch", defaultValue: "Publish Branch (\(publishCount))")
    }

    /// Pure projection from porcelain status to the two rendered sections.
    /// Rows are sorted by file name, case-insensitively.
    static func scmRows(from status: GitPorcelainStatus) -> (staged: [ScmRowSnapshot], changes: [ScmRowSnapshot]) {
        let staged = status.staged.map { row(for: $0, section: .staged) }
        let changes = (status.modified + status.untracked).map { row(for: $0, section: .changes) }
        return (sorted(staged), sorted(changes))
    }

    private static func sorted(_ rows: [ScmRowSnapshot]) -> [ScmRowSnapshot] {
        rows.sorted { $0.fileName.localizedCaseInsensitiveCompare($1.fileName) == .orderedAscending }
    }

    private static func row(for entry: GitStatusEntry, section: ScmSection) -> ScmRowSnapshot {
        let ns = entry.path as NSString
        let parent = ns.deletingLastPathComponent
        return ScmRowSnapshot(
            section: section,
            path: entry.path,
            fileName: ns.lastPathComponent,
            directoryText: parent,
            statusLetter: String(entry.status.rawValue),
            // One shared palette with the file explorer: the `.vscode` style is
            // the single definition of these hexes.
            statusColorHex: FileExplorerStyle.vscode.gitColor(for: entry.status).fileExplorerHexString ?? "CCCCCC"
        )
    }

    var body: some View {
        let rows = Self.scmRows(from: model.status)
        return VStack(spacing: 0) {
            toolbar
            if let error = model.lastErrorLine {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    if !rows.staged.isEmpty {
                        stagedSection(rows.staged)
                    }
                    changesSection(rows.changes)
                }
            }
        }
        .confirmationDialog(
            pendingConfirm?.isBatch == true
                ? String(
                    localized: "gitPanel.discardAll.confirm",
                    defaultValue: "Discard all changes? This cannot be undone."
                )
                : String(
                    localized: "gitPanel.discardFile.confirm",
                    defaultValue: "Discard changes to this file? This cannot be undone."
                ),
            isPresented: Binding(
                get: { pendingConfirm != nil },
                set: { if !$0 { pendingConfirm = nil } }
            ),
            presenting: pendingConfirm
        ) { pending in
            Button(
                pending.isBatch
                    ? String(localized: "gitPanel.discardAll.confirmButton", defaultValue: "Discard All")
                    : String(localized: "gitPanel.discardFile.confirmButton", defaultValue: "Discard"),
                role: .destructive
            ) {
                let entries = pending.entries
                Task { await model.discardFiles(entries) }
            }
        }
        .task { await model.refresh() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 11))
            Text(model.status.branch ?? String(localized: "gitPanel.detached", defaultValue: "detached"))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            if model.status.ahead > 0 {
                Text(verbatim: "↑\(model.status.ahead)").font(.system(size: 11))
            }
            if model.status.behind > 0 {
                Text(verbatim: "↓\(model.status.behind)").font(.system(size: 11))
            }
            Spacer(minLength: 8)
            if let openChanges {
                ScmIconButton(
                    systemName: "plusminus",
                    size: 12,
                    help: String(localized: "gitPanel.openChanges.tooltip", defaultValue: "Open Changes"),
                    action: openChanges
                )
            }
            ScmIconButton(
                systemName: "arrow.clockwise",
                size: 12,
                help: String(localized: "gitPanel.refresh.tooltip", defaultValue: "Refresh"),
                action: { Task { await model.refresh() } }
            )
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .frame(height: 28)
    }

    // MARK: - Sections
    //
    // The model is read here, above the `ForEach`. Everything below receives
    // `ScmRowSnapshot` values plus action closures — never the model itself.

    @ViewBuilder
    private func stagedSection(_ rows: [ScmRowSnapshot]) -> some View {
        ScmSectionHeader(
            title: String(localized: "gitPanel.section.stagedChanges", defaultValue: "Staged Changes"),
            count: rows.count,
            collapsed: stagedCollapsed,
            toggle: { stagedCollapsed.toggle() },
            actions: [
                ScmSectionAction(
                    systemName: "minus.circle",
                    help: String(localized: "gitPanel.action.unstageAll", defaultValue: "Unstage All"),
                    perform: {
                        let paths = model.status.staged.map(\.path)
                        Task { await model.unstageFiles(paths) }
                    }
                )
            ]
        )
        if !stagedCollapsed {
            ForEach(rows) { row in
                ScmRowView(
                    row: row,
                    open: openFile,
                    actions: [
                        ScmSectionAction(
                            systemName: "doc",
                            help: String(localized: "gitPanel.row.openFile", defaultValue: "Open File"),
                            perform: { openFile(row.path) }
                        ),
                        ScmSectionAction(
                            systemName: "minus",
                            help: String(localized: "gitPanel.row.unstage", defaultValue: "Unstage"),
                            perform: { Task { await model.unstageFile(row.path) } }
                        ),
                    ]
                )
                .equatable()
            }
        }
    }

    @ViewBuilder
    private func changesSection(_ rows: [ScmRowSnapshot]) -> some View {
        ScmSectionHeader(
            title: String(localized: "gitPanel.section.changes", defaultValue: "Changes"),
            count: rows.count,
            collapsed: changesCollapsed,
            toggle: { changesCollapsed.toggle() },
            actions: [
                ScmSectionAction(
                    systemName: "arrow.uturn.backward.circle",
                    help: String(localized: "gitPanel.action.discardAll", defaultValue: "Discard All Changes"),
                    perform: {
                        // Scoped to this section: `model.discardAll()` would also
                        // touch anything not listed here.
                        pendingConfirm = .discardEntries(model.status.modified + model.status.untracked)
                    }
                ),
                ScmSectionAction(
                    systemName: "plus.circle",
                    help: String(localized: "gitPanel.action.stageAll", defaultValue: "Stage All Changes"),
                    perform: {
                        // Scoped to this section: `model.stageAll()` runs `add -A`,
                        // which would also stage anything not listed here.
                        let paths = (model.status.modified + model.status.untracked).map(\.path)
                        Task { await model.stageFiles(paths) }
                    }
                ),
            ]
        )
        if !changesCollapsed {
            ForEach(rows) { row in
                ScmRowView(
                    row: row,
                    open: openFile,
                    actions: [
                        ScmSectionAction(
                            systemName: "doc",
                            help: String(localized: "gitPanel.row.openFile", defaultValue: "Open File"),
                            perform: { openFile(row.path) }
                        ),
                        ScmSectionAction(
                            systemName: "arrow.uturn.backward",
                            help: String(localized: "gitPanel.row.discard", defaultValue: "Discard"),
                            perform: { pendingConfirm = .discardFile(entry(for: row)) }
                        ),
                        ScmSectionAction(
                            systemName: "plus",
                            help: String(localized: "gitPanel.row.stage", defaultValue: "Stage"),
                            perform: { Task { await model.stageFile(row.path) } }
                        ),
                    ]
                )
                .equatable()
            }
        }
    }

    /// Discard needs the original entry (the model deletes untracked files and
    /// checks out tracked ones from the entry's status).
    private func entry(for row: ScmRowSnapshot) -> GitStatusEntry {
        (model.status.modified + model.status.untracked).first { $0.path == row.path }
            ?? GitStatusEntry(path: row.path, originalPath: nil, status: .modified)
    }
}

// MARK: - Row / header value views

/// A hover-revealed or always-visible icon button in the SCM view.
struct ScmSectionAction: Identifiable, Equatable {
    let systemName: String
    let help: String
    let perform: () -> Void

    var id: String { systemName }

    static func == (lhs: ScmSectionAction, rhs: ScmSectionAction) -> Bool {
        lhs.systemName == rhs.systemName && lhs.help == rhs.help
    }
}

private struct ScmIconButton: View {
    let systemName: String
    var size: CGFloat = 16
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size))
                .foregroundStyle(.secondary)
                .frame(width: size + 6, height: size + 6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// 22pt collapsible section header: chevron, title, count pill, hover actions.
private struct ScmSectionHeader: View {
    let title: String
    let count: Int
    let collapsed: Bool
    let toggle: () -> Void
    let actions: [ScmSectionAction]

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 6)
            if hovering {
                HStack(spacing: 2) {
                    ForEach(actions) { action in
                        ScmIconButton(systemName: action.systemName, help: action.help, action: action.perform)
                    }
                }
            }
            Text(verbatim: "\(count)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color(nsColor: .fileExplorerHex(0x4D4D4D))))
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: toggle)
    }
}

/// Snapshot-boundary row: value snapshot + closures only, no store reference.
private struct ScmRowView: View, Equatable {
    let row: ScmRowSnapshot
    let open: (String) -> Void
    let actions: [ScmSectionAction]

    @State private var hovering = false

    static func == (lhs: ScmRowView, rhs: ScmRowView) -> Bool {
        lhs.row == rhs.row && lhs.actions == rhs.actions
    }

    private var statusColor: Color {
        Color(nsColor: .fileExplorerHex(UInt32(row.statusColorHex, radix: 16) ?? 0xCCCCCC))
    }

    var body: some View {
        HStack(spacing: 6) {
            FileTypeIconView(fileName: row.fileName, size: 16)
            Text(row.fileName)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if !row.directoryText.isEmpty {
                Text(row.directoryText)
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: 4)
            if hovering {
                HStack(spacing: 2) {
                    ForEach(actions) { action in
                        ScmIconButton(systemName: action.systemName, help: action.help, action: action.perform)
                    }
                }
            }
            Text(row.statusLetter)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 14)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
        .onHover { hovering = $0 }
        .onTapGesture { open(row.path) }
        .help(row.path)
    }
}

/// SwiftUI wrapper over the bundled VS Code file-type icon loader.
struct FileTypeIconView: View {
    let fileName: String
    var size: CGFloat = 16

    var body: some View {
        Group {
            if let image = VSCodeFileIcon.icon(forFileName: fileName, size: size) {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: "doc").resizable().foregroundStyle(.secondary)
            }
        }
        .scaledToFit()
        .frame(width: size, height: size)
    }
}
