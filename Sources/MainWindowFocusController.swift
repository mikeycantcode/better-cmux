import AppKit
import CmuxFoundation
import CmuxTerminal

@MainActor
final class MainWindowFocusController {
    private enum EffectiveFocusOwner {
        case mainPanel
        case rightSidebar
        case unknown
    }

    private enum RightSidebarFocusTarget: Equatable {
        case host
        case outline
        case searchField
        case firstItem
    }

    private struct RightSidebarFocusRequest: Equatable {
        let id: UInt64
        let target: RightSidebarFocusTarget
    }

    private enum RightSidebarFocusState: Equatable {
        case inactive
        case requested(RightSidebarFocusRequest)
        case focused(target: RightSidebarFocusTarget)

        var isActive: Bool {
            if case .inactive = self { return false }
            return true
        }

        var request: RightSidebarFocusRequest? {
            if case .requested(let request) = self {
                return request
            }
            return nil
        }
    }

    let windowId: UUID

    private weak var window: NSWindow?
    private weak var tabManager: TabManager?
    private weak var fileExplorerState: FileExplorerState?
    private weak var rightSidebarHost: RightSidebarKeyboardFocusView?
    private weak var fileExplorerHost: FileExplorerContainerView?
    private weak var feedHost: FeedKeyboardFocusView?

    private(set) var intent: MainWindowKeyboardFocusIntent? {
        didSet {
            syncBonsplitTabShortcutHintEligibility()
        }
    }
    private var nextRightSidebarFocusRequestId: UInt64 = 0
    private var rightSidebarFocusState: RightSidebarFocusState = .inactive
    /// Whether the right sidebar currently owns keyboard focus. Surfaces the
    /// private focus state for the `sidebarFocus` keyboard-shortcut context key.
    var isRightSidebarFocusActive: Bool {
        rightSidebarFocusState.isActive
    }
    private var feedSelectedItemId: UUID?
    private var lastPublishedFeedFocusSnapshot = FeedFocusSnapshot()

    init(
        windowId: UUID,
        window: NSWindow?,
        tabManager: TabManager,
        fileExplorerState: FileExplorerState?
    ) {
        self.windowId = windowId
        self.window = window
        self.tabManager = tabManager
        self.fileExplorerState = fileExplorerState
        syncBonsplitTabShortcutHintEligibility()
    }

    func update(
        window: NSWindow?,
        tabManager: TabManager,
        fileExplorerState: FileExplorerState?
    ) {
        self.window = window
        self.tabManager = tabManager
        self.fileExplorerState = fileExplorerState
        syncBonsplitTabShortcutHintEligibility()
        publishFeedFocusSnapshot()
    }

    func registerRightSidebarHost(_ host: RightSidebarKeyboardFocusView) {
        rightSidebarHost = host
        focusRegisteredRightSidebarEndpointIfNeeded()
    }

    func registerFileExplorerHost(_ host: FileExplorerContainerView) {
        fileExplorerHost = host
        focusRegisteredRightSidebarEndpointIfNeeded()
    }

    func registerFeedHost(_ host: FeedKeyboardFocusView) {
        feedHost = host
        publishFeedFocusSnapshot(force: true)
    }

    func noteRightSidebarInteraction() {
        rightSidebarFocusState = .focused(target: .host)
        intent = .rightSidebar
        if !isFeedResponderFocused() {
            feedSelectedItemId = nil
        }
        publishFeedFocusSnapshot()
    }

    func noteTerminalInteraction(workspaceId: UUID, panelId: UUID) {
        noteMainPanelInteraction(workspaceId: workspaceId, panelId: panelId)
    }

    func noteMainPanelInteraction(workspaceId: UUID, panelId: UUID) {
        rightSidebarFocusState = .inactive
        intent = .mainPanel(workspaceId: workspaceId, panelId: panelId)
        publishFeedFocusSnapshot()
    }

    func allowsTerminalFocus(workspaceId: UUID, panelId: UUID) -> Bool {
        if GhosttyApp.terminalSurfaceRegistry.isRightSidebarDockSurface(id: panelId) {
            return true
        }
        switch intent {
        case .rightSidebar:
            return false
        case .mainPanel, nil:
            return true
        }
    }

    func allowsBonsplitTabShortcutHints(workspaceId: UUID) -> Bool {
        guard ShortcutHintDebugSettings().modifierHoldHintsEnabled else { return false }
        guard tabManager?.selectedTabId == workspaceId else { return false }
        switch intent {
        case .rightSidebar:
            return false
        case .mainPanel(let focusedWorkspaceId, _):
            return focusedWorkspaceId == workspaceId
        case nil:
            return true
        }
    }

    func ownsRightSidebarFocus(_ responder: NSResponder) -> Bool {
        if let host = rightSidebarHost, responder === host {
            return true
        }
        if responder is FeedKeyboardFocusResponder {
            return true
        }
        if fileExplorerHost?.ownsKeyboardFocus(responder) == true {
            return true
        }
        if feedHost?.ownsKeyboardFocus(responder) == true {
            return true
        }
        return false
    }

    func shouldRestoreTerminalFocusWhenRightSidebarHides(currentResponder: NSResponder?) -> Bool {
        if case .rightSidebar = intent {
            return true
        }
        guard let currentResponder else { return false }
        return ownsRightSidebarFocus(currentResponder)
    }

    @discardableResult
    func restoreTerminalFocusAfterRightSidebarHiddenIfNeeded() -> Bool {
        guard shouldRestoreTerminalFocusWhenRightSidebarHides(currentResponder: window?.firstResponder) else {
            return false
        }
        return focusTerminalOrReleaseRightSidebarFocus(clearUnavailableIntent: true)
    }

    @discardableResult
    func restoreFocusedPanelFocusFromRightSidebarIfNeeded(currentResponder: NSResponder? = nil) -> Bool {
        let responder = currentResponder ?? window?.firstResponder
        let ownsResponder = responder.map(ownsRightSidebarFocus) ?? false
        let ownsIntent: Bool = {
            if case .rightSidebar = intent {
                return true
            }
            return false
        }()
        guard ownsResponder || ownsIntent else {
            return false
        }

        guard let tabManager,
              let workspace = tabManager.selectedWorkspace,
              let panelId = workspace.focusedPanelId,
              let panel = workspace.panels[panelId] else {
            return focusTerminalOrReleaseRightSidebarFocus(clearUnavailableIntent: true)
        }

        rightSidebarFocusState = .inactive

        if panel is TerminalPanel {
            return focusTerminal()
        }

        intent = .mainPanel(workspaceId: workspace.id, panelId: panelId)
        if let window,
           let responder,
           ownsRightSidebarFocus(responder) {
            _ = window.makeFirstResponder(nil)
        }
        publishFeedFocusSnapshot()
        workspace.focusPanel(panelId)
        return panel.restoreFocusIntent(panel.preferredFocusIntentForActivation())
    }

    @discardableResult
    func restoreTargetAfterWindowBecameKey() -> Bool {
        switch intent {
        case .rightSidebar:
            return restoreRightSidebarTargetAfterWindowBecameKey()
        case .mainPanel:
            return restoreMainPanelTargetAfterWindowBecameKey()
        case nil:
            return false
        }
    }

    @discardableResult
    private func restoreRightSidebarTargetAfterWindowBecameKey() -> Bool {
        if let responder = window?.firstResponder,
           ownsRightSidebarFocus(responder) {
            publishFeedFocusSnapshot()
            return true
        }
        if let request = rightSidebarFocusState.request {
            return focusRightSidebar(target: request.target)
        }
        return focusRightSidebar(focusFirstItem: false)
    }

    @discardableResult
    private func restoreMainPanelTargetAfterWindowBecameKey() -> Bool {
        guard let window,
              let tabManager,
              let workspace = tabManager.selectedWorkspace,
              let panelId = workspace.focusedPanelId,
              let panel = workspace.panels[panelId] else {
            return false
        }

        if let responder = window.firstResponder {
            if panel.ownedFocusIntent(for: responder, in: window) != nil {
                noteMainPanelInteraction(workspaceId: workspace.id, panelId: panelId)
                return true
            }
            if liveRightSidebarFocusOwner(responder, in: window) {
                syncAfterResponderChange(responder: responder)
                return true
            }
            if terminalFocusRequest(for: responder) == nil,
               selectedFocusedPanelRequest(owning: responder) == nil,
               shouldRespectForeignFirstResponder(responder, in: window, isRightSidebarOwner: {
                   liveRightSidebarFocusOwner($0, in: window)
               }) {
                return false
            }
        }

        rightSidebarFocusState = .inactive
        intent = .mainPanel(workspaceId: workspace.id, panelId: panelId)
        publishFeedFocusSnapshot()
        workspace.focusPanel(panelId)
        return panel.restoreFocusIntent(panel.preferredFocusIntentForActivation())
    }

    private func liveRightSidebarFocusOwner(
        _ responder: NSResponder,
        in window: NSWindow
    ) -> Bool {
        guard (responder as? NSView)?.window === window else { return false }
        return ownsRightSidebarFocus(responder)
    }

    @discardableResult
    func selectFeedItem(_ id: UUID, focusFeed: Bool) -> Bool {
        feedSelectedItemId = id
        rightSidebarFocusState = .focused(target: .host)
        intent = .rightSidebar
        publishFeedFocusSnapshot()

        guard focusFeed else {
            return true
        }
        return feedHost?.focusHostFromCoordinator() == true
    }

    func feedFocusSnapshot() -> FeedFocusSnapshot {
        guard feedSelectedItemId != nil else {
            return FeedFocusSnapshot()
        }
        return FeedFocusSnapshot(
            selectedItemId: feedSelectedItemId,
            isKeyboardActive: isFeedKeyboardIntentActive()
        )
    }

    func syncAfterResponderChange() {
        syncAfterResponderChange(responder: window?.firstResponder)
    }

#if DEBUG
    var debugHasPendingRightSidebarFocusRequest: Bool {
        rightSidebarFocusState.request != nil
    }

    func debugSyncAfterResponderChange(responder: NSResponder?) {
        syncAfterResponderChange(responder: responder)
    }
#endif

    private func syncAfterResponderChange(responder: NSResponder?) {
        guard let responder else {
            publishFeedFocusSnapshot()
            return
        }
        if let terminal = terminalFocusRequest(for: responder) {
            if rightSidebarFocusState.request != nil {
                publishFeedFocusSnapshot()
                return
            }
            noteTerminalInteraction(workspaceId: terminal.workspaceId, panelId: terminal.panelId)
            return
        }
        if ownsRightSidebarFocus(responder) {
            let isFallbackSidebarHost = rightSidebarHost.map { responder === $0 } ?? false
            if !canAcceptRightSidebarResponderFocus(isFallbackSidebarHost: isFallbackSidebarHost) {
                publishFeedFocusSnapshot()
                return
            }
            completeRightSidebarFocusFromResponder(isFallbackSidebarHost: isFallbackSidebarHost)
            intent = .rightSidebar
            if !isFeedResponderFocused(responder) {
                feedSelectedItemId = nil
            }
            publishFeedFocusSnapshot()
            return
        }
        if rightSidebarFocusState.request != nil {
            publishFeedFocusSnapshot()
            return
        }
        if let mainPanel = selectedFocusedPanelRequest(owning: responder) {
            noteMainPanelInteraction(workspaceId: mainPanel.workspaceId, panelId: mainPanel.panelId)
            return
        }
        publishFeedFocusSnapshot()
    }

    private func canAcceptRightSidebarResponderFocus(isFallbackSidebarHost: Bool) -> Bool {
        guard let request = rightSidebarFocusState.request else {
            return true
        }
        if isFallbackSidebarHost, request.target != .host {
            return false
        }
        return true
    }

    private func completeRightSidebarFocusFromResponder(isFallbackSidebarHost: Bool) {
        guard let request = rightSidebarFocusState.request else {
            rightSidebarFocusState = .focused(target: .host)
            return
        }
        if isFallbackSidebarHost, request.target != .host {
            return
        }
        rightSidebarFocusState = .focused(target: request.target)
    }

    @discardableResult
    func focusRightSidebar(tab requestedTab: FilesGitTab? = nil, focusFirstItem: Bool = true) -> Bool {
        let target: RightSidebarFocusTarget = focusFirstItem ? .outline : .host
        return focusRightSidebar(
            tab: requestedTab,
            target: target,
            terminalYieldReason: "rightSidebarFocus"
        )
    }

    @discardableResult
    private func focusRightSidebar(
        tab requestedTab: FilesGitTab? = nil,
        target: RightSidebarFocusTarget,
        terminalYieldReason: String = "rightSidebarFocus"
    ) -> Bool {
        guard let state = fileExplorerState else { return false }
        if let requestedTab {
            FilesGitTab.select(requestedTab)
        }
        beginRightSidebarFocusRequest(target: target)
        intent = .rightSidebar
        feedSelectedItemId = nil
        publishFeedFocusSnapshot()
        yieldCurrentTerminalSurfaceFocus(reason: terminalYieldReason)
        state.setVisible(true)

        let endpointResult = focusRightSidebarEndpoint(target: target)
        if endpointResult {
            rightSidebarFocusState = .focused(target: target)
        }
        let fallbackResult = endpointResult ? false : focusFallbackRightSidebarHost()
        if fallbackResult, target == .host {
            rightSidebarFocusState = .focused(target: .host)
        }
        let result = endpointResult || fallbackResult || rightSidebarFocusState.request != nil
        publishFeedFocusSnapshot()
        return result
    }

    /// ⌘⇧F. The file search bar lives inside the Files tab, so this selects Files
    /// and focuses the search field.
    @discardableResult
    func focusFileSearch() -> Bool {
        return focusRightSidebar(
            tab: .files,
            target: .searchField,
            terminalYieldReason: "fileSearchFocus"
        )
    }

    @discardableResult
    func toggleRightSidebarOrTerminalFocus(
        tab requestedTab: FilesGitTab? = nil,
        focusFirstItem: Bool = true
    ) -> Bool {
        switch focusToggleDestination() {
        case .terminal:
            return restoreFocusedPanelFocusFromRightSidebarIfNeeded(currentResponder: window?.firstResponder)
        case .rightSidebar:
            return focusRightSidebar(tab: requestedTab, focusFirstItem: focusFirstItem)
        }
    }

    func focusToggleDestination(currentResponder: NSResponder? = nil) -> MainWindowFocusToggleDestination {
        switch effectiveFocusOwner(currentResponder: currentResponder) {
        case .rightSidebar:
            return .terminal
        case .mainPanel, .unknown:
            return .rightSidebar
        }
    }

    func findShortcutTarget(currentResponder: NSResponder? = nil) -> MainWindowFindShortcutTarget {
        let responder = currentResponder ?? window?.firstResponder
        if let responder {
            if ownsRightSidebarFocus(responder) {
                return .rightSidebarFileSearch
            }
            if terminalFocusRequest(for: responder) != nil {
                return .mainPanelFind
            }
            if selectedFocusedPanelIsBrowser() {
                return .mainPanelFind
            }
            if case .rightSidebar = intent {
                return .rightSidebarFileSearch
            }
            return .mainPanelFind
        }

        if case .rightSidebar = intent {
            return .rightSidebarFileSearch
        }
        return .mainPanelFind
    }

    @discardableResult
    func focusTerminal() -> Bool {
        guard let tabManager,
              let workspace = tabManager.selectedWorkspace else {
            return false
        }
        let terminalPanel: TerminalPanel? = {
            if let focusedPanelId = workspace.focusedPanelId,
               let terminalPanel = workspace.terminalPanel(for: focusedPanelId) {
                return terminalPanel
            }
            return workspace.focusedTerminalPanel
        }()
        guard let terminalPanel else { return false }
        rightSidebarFocusState = .inactive
        intent = .mainPanel(workspaceId: workspace.id, panelId: terminalPanel.id)
        publishFeedFocusSnapshot()
        workspace.focusPanel(terminalPanel.id)
        terminalPanel.hostedView.ensureFocus(
            for: workspace.id,
            surfaceId: terminalPanel.id,
            respectForeignFirstResponder: false
        )
        return terminalPanel.hostedView.isSurfaceViewFirstResponder()
    }

    private func selectedFocusedPanelIsBrowser() -> Bool {
        selectedFocusedBrowserPanelRequest() != nil
    }

    private struct FocusedPanelRequest {
        let workspaceId: UUID
        let panelId: UUID
    }

    private func selectedFocusedPanelRequest(owning responder: NSResponder) -> FocusedPanelRequest? {
        guard let window,
              let tabManager,
              let workspace = tabManager.selectedWorkspace else {
            return nil
        }
        if let panelId = workspace.focusedPanelId,
           let panel = workspace.panels[panelId],
           panel.ownedFocusIntent(for: responder, in: window) != nil {
            return FocusedPanelRequest(workspaceId: workspace.id, panelId: panelId)
        }
        for (panelId, panel) in workspace.panels {
            guard panelId != workspace.focusedPanelId,
                  panel.ownedFocusIntent(for: responder, in: window) != nil else {
                continue
            }
            return FocusedPanelRequest(workspaceId: workspace.id, panelId: panelId)
        }
        return nil
    }

    private func selectedFocusedBrowserPanelRequest() -> FocusedPanelRequest? {
        guard let tabManager,
              let workspace = tabManager.selectedWorkspace,
              let panelId = workspace.focusedPanelId,
              let panel = workspace.panels[panelId] else {
            return nil
        }
        guard panel is BrowserPanel else {
            return nil
        }
        return FocusedPanelRequest(workspaceId: workspace.id, panelId: panelId)
    }

    private func focusTerminalOrReleaseRightSidebarFocus(clearUnavailableIntent: Bool) -> Bool {
        let focused = focusTerminal()
        if focused {
            return true
        }

        if let window,
           let responder = window.firstResponder,
           ownsRightSidebarFocus(responder) {
            window.makeFirstResponder(nil)
        }

        rightSidebarFocusState = .inactive
        if clearUnavailableIntent, case .rightSidebar = intent {
            intent = nil
        }
        publishFeedFocusSnapshot()
        return false
    }

    private func effectiveFocusOwner(currentResponder: NSResponder? = nil) -> EffectiveFocusOwner {
        if let responder = currentResponder ?? window?.firstResponder {
            if terminalFocusRequest(for: responder) != nil {
                return .mainPanel
            }
            if ownsRightSidebarFocus(responder) {
                return .rightSidebar
            }
            if selectedFocusedPanelRequest(owning: responder) != nil {
                return .mainPanel
            }
        }

        switch intent {
        case .mainPanel:
            return .mainPanel
        case .rightSidebar:
            return .rightSidebar
        case nil:
            return .unknown
        }
    }

    private func focusRegisteredRightSidebarEndpointIfNeeded() {
        guard let request = rightSidebarFocusState.request else {
            return
        }
        guard case .rightSidebar = intent else {
            return
        }
        let result = focusRightSidebarEndpoint(target: request.target)
        if result {
            rightSidebarFocusState = .focused(target: request.target)
        } else if request.target == .host, focusFallbackRightSidebarHost() {
            rightSidebarFocusState = .focused(target: .host)
        }
        publishFeedFocusSnapshot()
    }

    private func beginRightSidebarFocusRequest(target: RightSidebarFocusTarget) {
        nextRightSidebarFocusRequestId &+= 1
        rightSidebarFocusState = .requested(
            RightSidebarFocusRequest(
                id: nextRightSidebarFocusRequestId,
                target: target
            )
        )
    }

    private func focusRightSidebarEndpoint(target: RightSidebarFocusTarget) -> Bool {
        switch target {
        case .searchField:
            return fileExplorerHost?.focusSearchField() == true
        case .outline, .firstItem:
            return fileExplorerHost?.focusOutline() == true
        case .host:
            return false
        }
    }

    private func focusFallbackRightSidebarHost() -> Bool {
        guard let window,
              let host = rightSidebarHost else {
            return false
        }
        return window.makeFirstResponder(host)
    }

    private func yieldCurrentTerminalSurfaceFocus(reason: String) {
        guard let tabManager,
              let workspace = tabManager.selectedWorkspace else {
            return
        }
        let terminalPanel: TerminalPanel? = {
            if let focusedPanelId = workspace.focusedPanelId,
               let terminalPanel = workspace.terminalPanel(for: focusedPanelId) {
                return terminalPanel
            }
            return workspace.focusedTerminalPanel
        }()
        terminalPanel?.hostedView.yieldTerminalSurfaceFocusForForeignResponder(reason: reason)
    }

    private func isFeedKeyboardIntentActive() -> Bool {
        isFeedResponderFocused()
    }

    private func isFeedResponderFocused(_ candidate: NSResponder? = nil) -> Bool {
        guard let responder = candidate ?? window?.firstResponder else { return false }
        if responder is FeedKeyboardFocusResponder { return true }
        return feedHost?.ownsKeyboardFocus(responder) == true
    }

    private func publishFeedFocusSnapshot(force: Bool = false) {
        let snapshot = feedFocusSnapshot()
        guard force || snapshot != lastPublishedFeedFocusSnapshot else { return }
        lastPublishedFeedFocusSnapshot = snapshot
        feedHost?.applyFocusSnapshotFromController(snapshot)
    }

    func syncBonsplitTabShortcutHintEligibility() {
        guard let tabManager else { return }
        for workspace in tabManager.tabs {
            let enabled = allowsBonsplitTabShortcutHints(workspaceId: workspace.id)
            if workspace.bonsplitController.tabShortcutHintsEnabled != enabled {
                workspace.bonsplitController.tabShortcutHintsEnabled = enabled
            }
        }
    }

    private struct TerminalFocusRequest {
        let workspaceId: UUID
        let panelId: UUID
    }

    private func terminalFocusRequest(for responder: NSResponder?) -> TerminalFocusRequest? {
        guard let ghosttyView = cmuxOwningGhosttyView(for: responder),
              let workspaceId = ghosttyView.tabId,
              let panelId = ghosttyView.terminalSurface?.id else {
            return nil
        }
        if GhosttyApp.terminalSurfaceRegistry.isRightSidebarDockSurface(id: panelId) {
            return nil
        }
        return TerminalFocusRequest(workspaceId: workspaceId, panelId: panelId)
    }
}
