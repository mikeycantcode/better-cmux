import AppKit
import SwiftUI

/// The file-explorer panel hosted in the bottom of the left sidebar.
///
/// Shows a slim section header (the active folder's name + a collapse chevron)
/// above an embedded ``FileExplorerPanelView`` whose root follows the active
/// session. The header's chevron toggles `state.isVisible`; collapsed shows the
/// header only. A `+` button in the header creates a new file at the explorer root.
/// Double-clicking a file opens it in the configured editor in a new tab.
struct SidebarFileExplorerPanel: View {
    @ObservedObject var store: FileExplorerStore
    @ObservedObject var state: FileExplorerState
    let onOpenFile: (String) -> Void

    @State private var isHeaderHovered = false

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
                HStack(spacing: 4) {
                    Image(systemName: state.isVisible ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text(folderName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .onTapGesture { state.isVisible.toggle() }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(
                    state.isVisible
                        ? String(localized: "sidebar.fileExplorer.collapse", defaultValue: "Collapse file explorer")
                        : String(localized: "sidebar.fileExplorer.expand", defaultValue: "Expand file explorer")
                )

                if store.canCreateFile {
                    Button(action: promptNewFile) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .medium))
                            .frame(width: 16, height: 16)
                            .contentShape(Rectangle())
                            .opacity(isHeaderHovered ? 1 : 0.55)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        String(localized: "sidebar.fileExplorer.newFile", defaultValue: "New File")
                    )
                    .help(String(localized: "sidebar.fileExplorer.newFile", defaultValue: "New File"))
                }
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .onHover { isHeaderHovered = $0 }

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

    /// Prompts for a file name and creates an empty file at the explorer root.
    private func promptNewFile() {
        let alert = NSAlert()
        alert.messageText = String(localized: "sidebar.fileExplorer.newFile.title", defaultValue: "New File")
        alert.informativeText = String(
            localized: "sidebar.fileExplorer.newFile.message",
            defaultValue: "Enter a name for the new file."
        )
        let input = NSTextField(string: "")
        input.placeholderString = String(
            localized: "sidebar.fileExplorer.newFile.placeholder",
            defaultValue: "File name"
        )
        input.frame = NSRect(x: 0, y: 0, width: 240, height: 22)
        alert.accessoryView = input
        alert.addButton(withTitle: String(localized: "common.create", defaultValue: "Create"))
        alert.addButton(withTitle: String(localized: "common.cancel", defaultValue: "Cancel"))
        alert.window.initialFirstResponder = input

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        if let error = store.createFile(named: input.stringValue) {
            let errorAlert = NSAlert()
            errorAlert.alertStyle = .warning
            errorAlert.messageText = String(
                localized: "sidebar.fileExplorer.newFile.failed",
                defaultValue: "Could not create file"
            )
            errorAlert.informativeText = error
            errorAlert.addButton(withTitle: String(localized: "common.ok", defaultValue: "OK"))
            errorAlert.runModal()
        }
    }
}
