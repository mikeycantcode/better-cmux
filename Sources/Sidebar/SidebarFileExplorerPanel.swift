import SwiftUI

/// The file-explorer panel hosted in the bottom of the left sidebar.
///
/// Shows a slim section header (the active folder's name + a collapse chevron)
/// above an embedded ``FileExplorerPanelView`` whose root follows the active
/// session. The header's chevron toggles `state.isVisible`; collapsed shows the
/// header only. Double-clicking a file inserts its path into the active
/// session's terminal.
struct SidebarFileExplorerPanel: View {
    @ObservedObject var store: FileExplorerStore
    @ObservedObject var state: FileExplorerState

    private var folderName: String {
        let trimmed = store.rootPath.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return String(localized: "sidebar.fileExplorer.title", defaultValue: "Explorer")
        }
        return (trimmed as NSString).lastPathComponent
    }

    var body: some View {
        VStack(spacing: 0) {
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
                    Spacer(minLength: 0)
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(
                state.isVisible
                    ? String(localized: "sidebar.fileExplorer.collapse", defaultValue: "Collapse file explorer")
                    : String(localized: "sidebar.fileExplorer.expand", defaultValue: "Expand file explorer")
            )

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
                            FileExplorerTerminalPathInsertion.insert(
                                paths: [path],
                                relativeToRootPath: store.rootPath,
                                intoTerminalFor: nil
                            )
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
