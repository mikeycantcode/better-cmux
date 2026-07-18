import SwiftUI

/// The file-explorer panel hosted in the bottom of the left sidebar.
///
/// Shows a slim section header (the active folder's name + a collapse chevron)
/// above an embedded ``FileExplorerPanelView`` whose root follows the active
/// session. The header's chevron toggles `state.isVisible`; collapsed shows the
/// header only.
/// Double-clicking a file opens it in the configured editor in a new tab.
struct SidebarFileExplorerPanel: View {
    @ObservedObject var store: FileExplorerStore
    @ObservedObject var state: FileExplorerState
    let onOpenFile: (String) -> Void

    @State private var isHeaderHovering = false
    @State private var isReloadHovering = false

    private var folderName: String {
        let trimmed = store.rootPath.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return String(localized: "sidebar.fileExplorer.title", defaultValue: "Explorer")
        }
        return (trimmed as NSString).lastPathComponent
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button {
                    state.isVisible.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: state.isVisible ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                        Text(folderName)
                            .font(.system(size: 11, weight: .semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .foregroundColor(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    state.isVisible
                        ? String(localized: "sidebar.fileExplorer.collapse", defaultValue: "Collapse file explorer")
                        : String(localized: "sidebar.fileExplorer.expand", defaultValue: "Expand file explorer")
                )

                Spacer(minLength: 0)

                Button {
                    store.reload()
                    store.refreshGitStatus()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(isReloadHovering ? 0.08 : 0))
                )
                .foregroundColor(.secondary)
                .opacity(isHeaderHovering ? 1 : 0)
                .help(String(localized: "sidebar.fileExplorer.reload.tooltip", defaultValue: "Reload file tree"))
                .accessibilityLabel(String(localized: "sidebar.fileExplorer.reload.tooltip", defaultValue: "Reload file tree"))
                .onHover { hovering in
                    isReloadHovering = hovering
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 28)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHeaderHovering = hovering
            }

            if state.isVisible {
                if store.rootPath.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text(String(localized: "sidebar.fileExplorer.emptyState", defaultValue: "No folder open"))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    FileExplorerPanelView(
                        store: store,
                        state: state,
                        onOpenFilePreview: { path in
                            onOpenFile(path)
                        },
                        presentation: .files,
                        placement: .pane,
                        showsHeader: false
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
