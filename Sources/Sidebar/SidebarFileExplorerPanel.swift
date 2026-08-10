import SwiftUI

/// The file-explorer panel hosted in the bottom of the left sidebar.
///
/// Shows the shared VS Code-style section header (``FileExplorerSectionHeader``:
/// collapse chevron + uppercased root name + hover actions) above an embedded
/// ``FileExplorerPanelView`` whose root follows the active session. The header's
/// chevron toggles `state.isVisible`; collapsed shows the header only.
/// Double-clicking a file opens it in the configured editor in a new tab.
struct SidebarFileExplorerPanel: View {
    @ObservedObject var store: FileExplorerStore
    @ObservedObject var state: FileExplorerState
    let onOpenFile: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            FileExplorerSectionHeader(
                store: store,
                isExpanded: state.isVisible,
                onToggle: { state.isVisible.toggle() }
            )
            // No explicit height: the hosted view's own magnification-aware height
            // constraint drives the size, so the row tracks font magnification live.
            .frame(maxWidth: .infinity)
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
                            onOpenFile(path)
                        },
                        placement: .pane,
                        showsHeader: false
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}
