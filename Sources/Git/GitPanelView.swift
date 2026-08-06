import SwiftUI

/// The Git tab of the right sidebar: branch/ahead-behind toolbar, staged /
/// modified / untracked sections with per-file actions, and a commit box.
///
/// This view observes `GitWorkingTreeModel` directly — the `FilesGitPanelView`
/// shell deliberately holds the model as a plain `let` so a debounced git
/// refresh does not invalidate the whole sidebar.
struct GitPanelView: View {
    @ObservedObject var model: GitWorkingTreeModel
    /// Receives an absolute path; the mount site converts from repo-relative.
    let openFile: (String) -> Void
    /// nil until Task 8 lands `GitChangesPanel`; the affordance stays hidden.
    let openChanges: (() -> Void)?

    @State private var commitMessage: String = ""
    @State private var confirmDiscardAll = false
    @State private var pendingDiscard: GitStatusEntry?

    /// Absolute path for a repo-relative git entry path.
    static func absolutePath(root: String, relative: String) -> String {
        guard !root.isEmpty else { return relative }
        if relative.hasPrefix("/") { return relative }
        return root.hasSuffix("/") ? root + relative : root + "/" + relative
    }

    var body: some View {
        VStack(spacing: 0) {
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
                    stagedSection
                    modifiedSection
                    untrackedSection
                }
            }
            commitBox
        }
        .confirmationDialog(
            String(
                localized: "gitPanel.discardAll.confirm",
                defaultValue: "Discard all changes? This cannot be undone."
            ),
            isPresented: $confirmDiscardAll
        ) {
            Button(
                String(localized: "gitPanel.discardAll.confirmButton", defaultValue: "Discard All"),
                role: .destructive
            ) {
                Task { await model.discardAll() }
            }
        }
        .confirmationDialog(
            String(
                localized: "gitPanel.discardFile.confirm",
                defaultValue: "Discard changes to this file? This cannot be undone."
            ),
            isPresented: Binding(
                get: { pendingDiscard != nil },
                set: { if !$0 { pendingDiscard = nil } }
            ),
            presenting: pendingDiscard
        ) { entry in
            Button(
                String(localized: "gitPanel.discardFile.confirmButton", defaultValue: "Discard"),
                role: .destructive
            ) {
                Task { await model.discardFile(entry) }
            }
        }
        .task { await model.refresh() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 11))
            Text(model.status.branch ?? String(localized: "gitPanel.detached", defaultValue: "detached"))
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            if model.status.ahead > 0 {
                Text(verbatim: "↑\(model.status.ahead)")
                    .font(.system(size: 11))
                    .foregroundStyle(.green)
            }
            if model.status.behind > 0 {
                Text(verbatim: "↓\(model.status.behind)")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
            Spacer()
            if let openChanges {
                Button(action: openChanges) { Image(systemName: "plusminus") }
                    .buttonStyle(.plain)
                    .help(String(localized: "gitPanel.openChanges.tooltip", defaultValue: "Open Changes"))
            }
            Button { Task { await model.refresh() } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .help(String(localized: "gitPanel.refresh.tooltip", defaultValue: "Refresh"))
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Sections
    //
    // Everything below the `ForEach` boundary receives value snapshots
    // (`GitStatusEntry`) plus action closures — never the model itself.

    @ViewBuilder
    private var stagedSection: some View {
        section(
            title: String(localized: "gitPanel.section.staged", defaultValue: "STAGED"),
            entries: model.status.staged,
            trailing: AnyView(
                sectionAction(
                    String(localized: "gitPanel.action.unstageAll", defaultValue: "Unstage All")
                ) {
                    let paths = model.status.staged.map(\.path)
                    Task { for path in paths { await model.unstageFile(path) } }
                }
            ),
            perRow: { entry in
                rowActions(
                    entry,
                    primarySymbol: "minus",
                    primaryHelp: String(localized: "gitPanel.row.unstage", defaultValue: "Unstage"),
                    primary: { Task { await model.unstageFile(entry.path) } }
                )
            }
        )
    }

    @ViewBuilder
    private var modifiedSection: some View {
        section(
            title: String(localized: "gitPanel.section.modified", defaultValue: "MODIFIED"),
            entries: model.status.modified,
            trailing: AnyView(
                HStack(spacing: 10) {
                    sectionAction(
                        String(localized: "gitPanel.action.discardAll", defaultValue: "Discard All")
                    ) { confirmDiscardAll = true }
                    sectionAction(
                        String(localized: "gitPanel.action.stageAll", defaultValue: "Stage All")
                    ) { Task { await model.stageAll() } }
                }
            ),
            perRow: { entry in
                rowActions(
                    entry,
                    primarySymbol: "plus",
                    primaryHelp: String(localized: "gitPanel.row.stage", defaultValue: "Stage"),
                    primary: { Task { await model.stageFile(entry.path) } }
                )
            }
        )
    }

    @ViewBuilder
    private var untrackedSection: some View {
        section(
            title: String(localized: "gitPanel.section.untracked", defaultValue: "UNTRACKED"),
            entries: model.status.untracked,
            trailing: AnyView(
                sectionAction(
                    String(localized: "gitPanel.action.stageAll", defaultValue: "Stage All")
                ) { Task { await model.stageAll() } }
            ),
            perRow: { entry in
                rowActions(
                    entry,
                    primarySymbol: "plus",
                    primaryHelp: String(localized: "gitPanel.row.stage", defaultValue: "Stage"),
                    primary: { Task { await model.stageFile(entry.path) } }
                )
            }
        )
    }

    @ViewBuilder
    private func section(
        title: String,
        entries: [GitStatusEntry],
        trailing: AnyView,
        perRow: @escaping (GitStatusEntry) -> AnyView
    ) -> some View {
        if !entries.isEmpty {
            HStack {
                Text(verbatim: "\(title) (\(entries.count))")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                trailing
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 4)
            ForEach(entries) { entry in
                GitFileRow(entry: entry, open: openFile, actions: perRow(entry))
            }
        }
    }

    private func sectionAction(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func rowActions(
        _ entry: GitStatusEntry,
        primarySymbol: String,
        primaryHelp: String,
        primary: @escaping () -> Void
    ) -> AnyView {
        AnyView(
            HStack(spacing: 8) {
                Button(action: primary) {
                    Image(systemName: primarySymbol).font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help(primaryHelp)
                Button { pendingDiscard = entry } label: {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help(String(localized: "gitPanel.row.discard", defaultValue: "Discard"))
            }
        )
    }

    // MARK: - Commit box

    private var commitBox: some View {
        VStack(spacing: 8) {
            TextField(
                String(localized: "gitPanel.commitMessage.placeholder", defaultValue: "Commit message…"),
                text: $commitMessage,
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .lineLimit(2...4)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.06)))
            HStack(spacing: 8) {
                Button {
                    let message = commitMessage
                    Task { if await model.commit(message: message) { commitMessage = "" } }
                } label: {
                    Text(String(localized: "gitPanel.commit", defaultValue: "Commit"))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    model.isBusy
                    || model.status.staged.isEmpty
                    || commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
                Button {
                    Task { await model.push() }
                } label: {
                    Text(pushButtonLabel)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(model.isBusy || (model.publishCount == 0 && model.hasUpstream))
            }
            .controlSize(.small)
        }
        .padding(12)
    }

    private var pushButtonLabel: String {
        let count = model.publishCount
        return model.hasUpstream
            ? String(localized: "gitPanel.push", defaultValue: "Push (\(count))")
            : String(localized: "gitPanel.publishBranch", defaultValue: "Publish Branch (\(count))")
    }
}

/// Snapshot-boundary row: value entry + closures only, no store reference.
private struct GitFileRow: View {
    let entry: GitStatusEntry
    let open: (String) -> Void
    let actions: AnyView

    @State private var hovering = false

    private var letterColor: Color {
        switch entry.status {
        case .modified: return .orange
        case .added: return .green
        case .deleted: return .red
        case .renamed: return .blue
        case .untracked: return .gray
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(verbatim: String(entry.status.rawValue))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(letterColor)
                .frame(width: 12)
            Text(verbatim: (entry.path as NSString).lastPathComponent)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if hovering { actions }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
        .onHover { hovering = $0 }
        .onTapGesture { open(entry.path) }
        .help(entry.path)
    }
}
