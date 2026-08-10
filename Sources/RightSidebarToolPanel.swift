import AppKit
import Combine
import SwiftUI

@MainActor
final class RightSidebarToolPanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = .rightSidebarTool

    @Published private(set) var focusFlashToken: Int = 0

    private weak var workspace: Workspace?
    private weak var fileExplorerContainerView: FileExplorerContainerView?
    private var fileExplorerStoreStorage: FileExplorerStore?
    private var fileExplorerStateStorage: FileExplorerState?
    private var gitWorkingTreeModelStorage: GitWorkingTreeModel?
    private var workspaceObservationCancellable: AnyCancellable?

    init(workspace: Workspace) {
        self.id = UUID()
        reattach(to: workspace)
    }

    deinit {
        // Explicit no-op so future teardown has a single home.
    }

    var fileExplorerStore: FileExplorerStore {
        if let store = fileExplorerStoreStorage { return store }
        let store = FileExplorerStore()
        store.showHiddenFiles = true
        // No git poke here: the store's watcher already pokes the root's shared
        // `GitStatusMonitor`, which the Git tab and Changes panel ride. Poking
        // the model too would spend a second `git status` on the same burst.
        fileExplorerStoreStorage = store
        if let workspace {
            syncFileExplorerRoot(from: workspace, store: store)
        }
        return store
    }

    /// The workspace's git model, not a pane-private one: a second model would
    /// diverge from the sidebar's status and stage against a separately-refreshed
    /// snapshot. Captured strongly at `reattach` so the pane keeps rendering the
    /// workspace it belongs to.
    var gitWorkingTreeModel: GitWorkingTreeModel {
        if let model = gitWorkingTreeModelStorage { return model }
        let model = workspace?.gitWorkingTreeModel
            ?? GitWorkingTreeModel(repoPath: fileExplorerStore.rootPath)
        gitWorkingTreeModelStorage = model
        return model
    }

    var fileExplorerState: FileExplorerState {
        if let state = fileExplorerStateStorage { return state }
        let state = FileExplorerState()
        fileExplorerStateStorage = state
        return state
    }

    var displayTitle: String { FilesGitTab.files.label }
    var displayIcon: String? { FilesGitTab.files.symbolName }

    func reattach(to workspace: Workspace) {
        self.workspace = workspace
        // Bind to the new workspace's model (created outside any view body).
        gitWorkingTreeModelStorage = workspace.gitWorkingTreeModel
        observeWorkspaceRootChanges(workspace)
        syncWorkspaceRoot(from: workspace)
    }

    func attachFileExplorerContainer(_ container: FileExplorerContainerView?) {
        fileExplorerContainerView = container
    }

    func syncWorkspaceRoot(from workspace: Workspace) {
        guard let store = fileExplorerStoreStorage else { return }
        syncFileExplorerRoot(from: workspace, store: store)
    }

    func openFilePreview(_ filePath: String) {
        guard let workspace,
              let paneId = workspace.bonsplitController.focusedPaneId ?? workspace.bonsplitController.allPaneIds.first else {
            return
        }
        _ = workspace.openFileSurfaces(
            inPane: paneId,
            filePaths: [filePath],
            focus: true,
            reuseExisting: true
        )
    }

    /// Opens (or focuses) the workspace's Changes panel on this pane's git model.
    func openGitChangesPanel() {
        workspace?.openGitChangesPanel()
    }

    /// Reveals a repo-relative path in an already-open Changes panel.
    /// Returns `false` when none is open.
    func revealInGitChangesPanel(relativePath: String) -> Bool {
        workspace?.revealInGitChangesPanel(relativePath: relativePath) ?? false
    }

    var isFocusedInWorkspace: Bool {
        workspace?.focusedPanelId == id
    }

    func close() {
        fileExplorerContainerView = nil
        fileExplorerStoreStorage?.applyWorkspaceRoot(.none)
        workspaceObservationCancellable = nil
    }

    func focus() {
        _ = fileExplorerContainerView?.focusOutline()
    }

    func unfocus() {}

    func triggerFlash(reason: WorkspaceAttentionFlashReason) {
        _ = reason
        guard NotificationPaneFlashSettings.isEnabled() else { return }
        focusFlashToken += 1
    }

    func ownedFocusIntent(for responder: NSResponder, in window: NSWindow) -> PanelFocusIntent? {
        _ = window
        guard fileExplorerContainerView?.ownsKeyboardFocus(responder) == true else { return nil }
        return .panel
    }

    private func observeWorkspaceRootChanges(_ workspace: Workspace) {
        workspaceObservationCancellable = workspace.$currentDirectory
            .map { _ in () }
            .eraseToAnyPublisher()
            .sink { [weak self, weak workspace] _ in
            Task { @MainActor in
                guard let self, let workspace else { return }
                self.syncWorkspaceRoot(from: workspace)
            }
        }
    }

    private func syncFileExplorerRoot(from workspace: Workspace, store: FileExplorerStore) {
        store.showHiddenFiles = true

        // `repoPath` follows `workspace.currentDirectory` from the workspace
        // itself, so it is deliberately not written here.
        let directory = workspace.currentDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !directory.isEmpty else {
            store.applyWorkspaceRoot(.none)
            return
        }

        store.applyWorkspaceRoot(.local(workspaceId: workspace.id, path: directory))
    }

}

/// Pane-hosted Files surface. Exists as its own view so the store is observed here —
/// the path line in `FilesGitPanelView` must refresh when the workspace root changes.
private struct PaneFilesGitShell: View {
    let panel: RightSidebarToolPanel
    @ObservedObject var store: FileExplorerStore
    let onFocus: () -> Void

    var body: some View {
        FilesGitPanelView(
            explorerState: panel.fileExplorerState,
            gitModel: panel.gitWorkingTreeModel,
            rootPath: store.rootPath,
            filesContent: AnyView(
                FileExplorerPanelView(
                    store: store,
                    state: panel.fileExplorerState,
                    onOpenFilePreview: panel.openFilePreview,
                    placement: .pane,
                    onFocus: onFocus,
                    onContainerChange: panel.attachFileExplorerContainer
                )
            ),
            gitContent: AnyView(
                GitPanelView(
                    model: panel.gitWorkingTreeModel,
                    // Row clicks land in the Changes panel when one is open, and
                    // fall back to a file preview otherwise.
                    openFile: { [rootPath = store.rootPath] relativePath in
                        guard !panel.revealInGitChangesPanel(relativePath: relativePath) else { return }
                        panel.openFilePreview(
                            GitPanelView.absolutePath(root: rootPath, relative: relativePath)
                        )
                    },
                    openChanges: panel.openGitChangesPanel
                )
            )
        )
    }
}

struct RightSidebarToolPanelView: View {
    @ObservedObject var panel: RightSidebarToolPanel
    let isFocused: Bool
    let isVisibleInUI: Bool
    let appearance: PanelAppearance
    let onRequestPanelFocus: () -> Void

    @State private var focusFlashOpacity: Double = 0.0
    @State private var focusFlashAnimationGeneration: Int = 0

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: appearance.backgroundColor))
            .overlay {
                WorkspaceAttentionFlashRingView(opacity: focusFlashOpacity)
            }
            .simultaneousGesture(TapGesture().onEnded { requestPanelFocusIfNeeded() })
            .onChange(of: panel.focusFlashToken) { _, _ in
                triggerFocusFlashAnimation()
            }
    }

    private var content: some View {
        PaneFilesGitShell(
            panel: panel,
            store: panel.fileExplorerStore,
            onFocus: requestPanelFocusIfNeeded
        )
    }

    private func requestPanelFocusIfNeeded() {
        guard !panel.isFocusedInWorkspace else { return }
        onRequestPanelFocus()
    }

    private func triggerFocusFlashAnimation() {
        focusFlashAnimationGeneration &+= 1
        let generation = focusFlashAnimationGeneration
        focusFlashOpacity = FocusFlashPattern.values.first ?? 0

        for segment in FocusFlashPattern.segments {
            DispatchQueue.main.asyncAfter(deadline: .now() + segment.delay) {
                guard focusFlashAnimationGeneration == generation else { return }
                withAnimation(focusFlashAnimation(for: segment.curve, duration: segment.duration)) {
                    focusFlashOpacity = segment.targetOpacity
                }
            }
        }
    }

    private func focusFlashAnimation(for curve: FocusFlashCurve, duration: TimeInterval) -> Animation {
        switch curve {
        case .easeIn:
            return .easeIn(duration: duration)
        case .easeOut:
            return .easeOut(duration: duration)
        }
    }
}

struct RightSidebarToolFocusAnchor: NSViewRepresentable {
    final class Coordinator {
        var onViewChange: (RightSidebarToolFocusAnchorView?) -> Void
        weak var attachedView: RightSidebarToolFocusAnchorView?

        init(onViewChange: @escaping (RightSidebarToolFocusAnchorView?) -> Void) {
            self.onViewChange = onViewChange
        }

        func attach(_ view: RightSidebarToolFocusAnchorView) {
            guard attachedView !== view else { return }
            attachedView = view
            onViewChange(view)
        }

        func detach(_ view: RightSidebarToolFocusAnchorView) {
            guard attachedView === view else { return }
            attachedView = nil
            onViewChange(nil)
        }
    }

    let onViewChange: (RightSidebarToolFocusAnchorView?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onViewChange: onViewChange)
    }

    func makeNSView(context: Context) -> RightSidebarToolFocusAnchorView {
        let view = RightSidebarToolFocusAnchorView()
        context.coordinator.attach(view)
        return view
    }

    func updateNSView(_ nsView: RightSidebarToolFocusAnchorView, context: Context) {
        context.coordinator.onViewChange = onViewChange
        context.coordinator.attach(nsView)
    }

    static func dismantleNSView(_ nsView: RightSidebarToolFocusAnchorView, coordinator: Coordinator) {
        coordinator.detach(nsView)
    }
}

final class RightSidebarToolFocusAnchorView: NSView {
    override var acceptsFirstResponder: Bool { true }

    func ownsKeyboardFocus(_ responder: NSResponder) -> Bool {
        if responder === self { return true }
        guard let responderView = Self.view(for: responder) else { return false }
        guard let root = focusRootView else { return false }
        return responderView === root || responderView.isDescendant(of: root)
    }

    private static func view(for responder: NSResponder) -> NSView? {
        if let view = responder as? NSView {
            return view
        }
        if let textView = responder as? NSTextView,
           let delegateView = textView.delegate as? NSView {
            return delegateView
        }
        return nil
    }

    private var focusRootView: NSView? {
        guard let superview else { return nil }
        var current: NSView? = superview
        while let view = current {
            let typeName = String(describing: type(of: view))
            if typeName.contains("NSHosting") || typeName.contains("ViewHost") {
                return view
            }
            current = view.superview
        }
        return superview
    }
}
