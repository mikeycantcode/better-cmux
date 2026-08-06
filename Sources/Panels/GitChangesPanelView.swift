import AppKit
import SwiftUI
import WebKit

/// Hosts the Changes panel: the stacked-diff web view on the left, the native
/// staging checklist rail on the right.
struct GitChangesPanelView: View {
    @ObservedObject var panel: GitChangesPanel
    let appearance: PanelAppearance
    let onRequestPanelFocus: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    /// Fixed rail width; the diff column takes the rest.
    private static let railWidth: CGFloat = 240

    var body: some View {
        HStack(spacing: 0) {
            GitChangesWebViewRepresentable(controller: panel.webController)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            rail
                .frame(width: Self.railWidth)
        }
        .background(Color(nsColor: appearance.backgroundColor))
        .simultaneousGesture(TapGesture().onEnded { onRequestPanelFocus() })
        .onAppear { panel.webController.setTheme(colorScheme == .dark ? "vs-dark" : "vs") }
        .onChange(of: colorScheme) { _, newValue in
            panel.webController.setTheme(newValue == .dark ? "vs-dark" : "vs")
        }
        .confirmationDialog(
            String(
                localized: "gitChanges.revert.confirm",
                defaultValue: "Discard changes to this file? This cannot be undone."
            ),
            isPresented: Binding(
                get: { panel.pendingRevertPath != nil },
                set: { if !$0 { panel.pendingRevertPath = nil } }
            ),
            presenting: panel.pendingRevertPath
        ) { path in
            Button(
                String(localized: "gitChanges.revert.confirmButton", defaultValue: "Discard"),
                role: .destructive
            ) {
                panel.confirmRevert(path: path)
            }
        }
    }

    // MARK: - Checklist rail
    //
    // Everything below the `ForEach` boundary receives value snapshots plus a
    // closure bundle — never the panel or the git model.

    private var rail: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "gitChanges.rail.title", defaultValue: "Files"))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Self.groups(for: panel.files), id: \.name) { group in
                        if !group.name.isEmpty {
                            Text(verbatim: group.name)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 12)
                                .padding(.top, 8)
                                .padding(.bottom, 2)
                        }
                        ForEach(group.files) { file in
                            GitChangesRailRow(file: file, actions: actions)
                        }
                    }
                }
            }
        }
    }

    /// Action bundle handed to rows so they never hold the panel.
    private var actions: GitChangesRailRowActions {
        GitChangesRailRowActions(
            toggleStaged: { path, isStaged in panel.toggleStaged(path: path, isStaged: isStaged) },
            reveal: { path in panel.revealFile(path: path) }
        )
    }

    struct FileGroup {
        let name: String
        let files: [GitChangesFile]
    }

    /// Groups files by top-level directory, preserving card order.
    static func groups(for files: [GitChangesFile]) -> [FileGroup] {
        var order: [String] = []
        var buckets: [String: [GitChangesFile]] = [:]
        for file in files {
            let name = file.groupName
            if buckets[name] == nil { order.append(name) }
            buckets[name, default: []].append(file)
        }
        return order.map { FileGroup(name: $0, files: buckets[$0] ?? []) }
    }
}

/// Closure bundle for a rail row — the snapshot-boundary contract.
struct GitChangesRailRowActions {
    let toggleStaged: (String, Bool) -> Void
    let reveal: (String) -> Void
}

private struct GitChangesRailRow: View {
    let file: GitChangesFile
    let actions: GitChangesRailRowActions

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Toggle(
                isOn: Binding(
                    get: { file.staged },
                    set: { _ in actions.toggleStaged(file.path, file.staged) }
                )
            ) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help(
                    file.staged
                        ? String(localized: "gitChanges.unstage", defaultValue: "Unstage")
                        : String(localized: "gitChanges.stage", defaultValue: "Stage")
                )
            Text(verbatim: file.fileName)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if file.additions > 0 {
                Text(verbatim: "+\(file.additions)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.green)
            }
            if file.deletions > 0 {
                Text(verbatim: "−\(file.deletions)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .background(hovering ? Color.primary.opacity(0.05) : .clear)
        .onHover { hovering = $0 }
        .onTapGesture { actions.reveal(file.path) }
        .help(file.path)
    }
}

/// Mounts the panel-owned `WKWebView`. The controller owns the view, so SwiftUI
/// recreating this representable never rebuilds the web content process.
private struct GitChangesWebViewRepresentable: NSViewRepresentable {
    let controller: GitChangesWebController

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let webView = controller.makeWebView()
        webView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
