import AppKit
import Bonsplit
import CMUXAgentLaunch
import CmuxFoundation
import CmuxSettings
import CmuxSettingsUI
import SwiftUI

private func rightSidebarDebugResponder(_ responder: NSResponder?) -> String {
    guard let responder else { return "nil" }
    return String(describing: type(of: responder))
}

nonisolated enum RightSidebarContentMountPolicy {
    static func shouldMountContent(isRightSidebarVisible: Bool, hasMountedContent: Bool) -> Bool {
        isRightSidebarVisible || hasMountedContent
    }
}

nonisolated enum FileExplorerRootSyncPolicy {
    /// The right sidebar hosts exactly one surface (the Files|Git shell), so the
    /// explorer store follows sidebar visibility alone.
    static func shouldSyncFileExplorerStore(isRightSidebarVisible: Bool) -> Bool {
        isRightSidebarVisible
    }
}

nonisolated enum RightSidebarDirectoryContext {
    static func normalizedDirectory(_ directory: String?) -> String? {
        let trimmed = directory?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Which Files|Git tab a shortcut or remote command wants selected.
nonisolated enum RightSidebarTabShortcut {
    /// Resolves a key event to the Files|Git tab it selects, or `nil`.
    static func tab(
        for event: NSEvent,
        allowingAction: (KeyboardShortcutSettings.Action) -> Bool = { _ in true }
    ) -> FilesGitTab? {
        guard event.type == .keyDown else { return nil }
        for (action, tab) in [
            (KeyboardShortcutSettings.Action.switchRightSidebarToFiles, FilesGitTab.files),
            (KeyboardShortcutSettings.Action.switchRightSidebarToGit, FilesGitTab.git),
        ] {
            guard allowingAction(action),
                  KeyboardShortcutSettings.shortcut(for: action).matches(event: event) else {
                continue
            }
            return tab
        }
        return nil
    }
}

/// Right sidebar root view. Hosts the Files|Git shell plus the sidebar chrome.
struct RightSidebarPanelView: View {
    @ObservedObject var fileExplorerStore: FileExplorerStore
    @ObservedObject var fileExplorerState: FileExplorerState
    /// Not `@ObservedObject` here on purpose: `FilesGitPanelView` observes it, so
    /// git status churn must not invalidate the whole right-sidebar body.
    let gitModel: GitWorkingTreeModel
    let titlebarHeight: CGFloat
    let onOpenFilePreview: (String) -> Void
    let onOpenAsPane: () -> Void
    let onClose: () -> Void

    @State private var focusShortcutHintMonitor = WindowScopedShortcutHintModifierMonitor(activation: .commandOnly)
    @State private var closeShortcutHintMonitor = WindowScopedShortcutHintModifierMonitor(activation: .commandOnly)
    @State private var hasMountedRightSidebarContent = false
    @ObservedObject private var keyboardShortcutSettingsObserver = KeyboardShortcutSettingsObserver.shared
    private let alwaysShowShortcutHints = ShortcutHintDebugSettings().alwaysShowHints
    private let closeShortcutHintXOffset = ShortcutHintDebugSettings.defaultRightSidebarCloseHintX
    private let closeShortcutHintYOffset = ShortcutHintDebugSettings.defaultRightSidebarCloseHintY
    private let focusShortcutHintXOffset = ShortcutHintDebugSettings.defaultRightSidebarFocusHintX
    private let focusShortcutHintYOffset = ShortcutHintDebugSettings.defaultRightSidebarFocusHintY
    @LiveSetting(\.shortcuts.showModifierHoldHints) private var showModifierHoldHints

    private var focusShortcutHintAnimationValue: Bool {
        alwaysShowShortcutHints || (showModifierHoldHints && focusShortcutHintMonitor.isModifierPressed)
    }

    private func startShortcutHintMonitorsIfNeeded() {
        guard showModifierHoldHints else {
            stopShortcutHintMonitors()
            return
        }
        focusShortcutHintMonitor.start()
        closeShortcutHintMonitor.start()
    }

    private func stopShortcutHintMonitors() {
        focusShortcutHintMonitor.stop()
        closeShortcutHintMonitor.stop()
    }

    var body: some View {
        VStack(spacing: 0) {
            chromeBar
                .rightSidebarChromeBottomBorder()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .shortcutHintVisibilityAnimation(value: focusShortcutHintAnimationValue)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RightSidebarKeyboardFocusBridge()
            .frame(width: 1, height: 1)
        )
        .background(
            WindowAccessor(refreshID: showModifierHoldHints) { window in
                let hintWindow = showModifierHoldHints ? window : nil
                focusShortcutHintMonitor.setHostWindow(hintWindow)
                closeShortcutHintMonitor.setHostWindow(hintWindow)
            }
            .frame(width: 0, height: 0)
        )
        .accessibilityIdentifier("RightSidebar")
        .onAppear {
            startShortcutHintMonitorsIfNeeded()
            if fileExplorerState.isVisible { hasMountedRightSidebarContent = true }
        }
        .onDisappear {
            stopShortcutHintMonitors()
        }
        .onChange(of: showModifierHoldHints) { _, _ in
            startShortcutHintMonitorsIfNeeded()
        }
        .onChange(of: fileExplorerState.isVisible) { _, visible in
            if visible { hasMountedRightSidebarContent = true }
        }
    }

    private var chromeBar: some View {
        let _ = keyboardShortcutSettingsObserver.revision
        return ZStack {
            WindowDragHandleView()

            HStack(spacing: RightSidebarChromeMetrics.headerControlSpacing) {
                Spacer(minLength: 0)
                openAsPaneButton
                closeButton
            }
        }
        .rightSidebarChromeBar(leadingPadding: 4, trailingPadding: 6, height: titlebarHeight)
        .overlay(alignment: .topLeading) {
            focusShortcutHintOverlay
        }
        .background(TitlebarDoubleClickMonitorView())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("RightSidebarModeBar")
        .reportRightSidebarChromeGeometryForBonsplitUITest(
            isVisible: true,
            titlebarHeight: titlebarHeight
        )
    }

    private var openAsPaneButton: some View {
        Button {
            onOpenAsPane()
        } label: {
            HeaderChromeIconStyle.symbol("rectangle.split.2x1")
        }
        .buttonStyle(RightSidebarHeaderIconButtonStyle(iconGeometryKeyPrefix: "rightSidebarHeaderOpenAsPaneIcon"))
        .frame(
            width: RightSidebarChromeMetrics.headerControlSize,
            height: RightSidebarChromeMetrics.headerControlSize
        )
        .reportRightSidebarChromeNamedGeometryForBonsplitUITest(
            keyPrefix: "rightSidebarHeaderOpenAsPane",
            isVisible: true
        )
        .rightSidebarHeaderControlAlignment()
        .safeHelp(String(localized: "rightSidebar.openAsPane.tooltip", defaultValue: "Open as pane"))
        .accessibilityLabel(
            String.localizedStringWithFormat(
                String(localized: "rightSidebar.openAsPane.accessibilityLabel", defaultValue: "Open %@ as Pane"),
                FilesGitTab.files.label
            )
        )
        .accessibilityIdentifier("RightSidebar.openAsPaneButton")
        .titlebarInteractiveControl()
    }

    private var closeButton: some View {
        let _ = keyboardShortcutSettingsObserver.revision
        let shortcut = KeyboardShortcutSettings.shortcut(for: .toggleRightSidebar)
        let showsShortcutHint = ShortcutHintTitlebarPolicy.shouldShow(
            shortcut: shortcut,
            alwaysShowShortcutHints: alwaysShowShortcutHints,
            modifierPressed: closeShortcutHintMonitor.isModifierPressed,
            modifierHoldHintsEnabled: showModifierHoldHints
        )
        return ZStack {
            Button(action: onClose) {
                HeaderChromeIconStyle.symbol("xmark")
            }
            .buttonStyle(RightSidebarHeaderIconButtonStyle(iconGeometryKeyPrefix: "rightSidebarHeaderCloseIcon"))
            .frame(
                width: RightSidebarChromeMetrics.headerControlSize,
                height: RightSidebarChromeMetrics.headerControlSize
            )
            .reportRightSidebarChromeNamedGeometryForBonsplitUITest(
                keyPrefix: "rightSidebarHeaderClose",
                isVisible: true
            )
            .safeHelp(
                KeyboardShortcutSettings.Action.toggleRightSidebar.tooltip(
                    String(localized: "rightSidebar.toggle.tooltip", defaultValue: "Toggle right sidebar")
                )
            )
            .accessibilityLabel(String(localized: "rightSidebar.close.accessibilityLabel", defaultValue: "Close Right Sidebar"))
            .accessibilityIdentifier("RightSidebar.closeButton")
        }
        .frame(
            width: RightSidebarChromeMetrics.headerControlSize,
            height: RightSidebarChromeMetrics.headerControlSize
        )
        .overlay(alignment: .top) {
            if showsShortcutHint {
                ShortcutHintPill(shortcut: shortcut, fontSize: 9, emphasis: 1.05)
                    .fixedSize(horizontal: true, vertical: false)
                    .offset(
                        x: CGFloat(ShortcutHintDebugSettings.clamped(closeShortcutHintXOffset)),
                        y: CGFloat(ShortcutHintDebugSettings.clamped(closeShortcutHintYOffset))
                    )
                    .shortcutHintTransition()
                    .accessibilityIdentifier("rightSidebarCloseShortcutHint")
                    .allowsHitTesting(false)
                    .zIndex(10)
            }
        }
        .rightSidebarHeaderControlAlignment()
        .shortcutHintVisibilityAnimation(value: showsShortcutHint)
        .titlebarInteractiveControl()
    }

    @ViewBuilder
    private var focusShortcutHintOverlay: some View {
        let _ = keyboardShortcutSettingsObserver.revision
        let shortcut = KeyboardShortcutSettings.shortcut(for: .focusRightSidebar)
        let showsFocusShortcutHint = ShortcutHintTitlebarPolicy.shouldShow(
            shortcut: shortcut,
            alwaysShowShortcutHints: alwaysShowShortcutHints,
            modifierPressed: focusShortcutHintMonitor.isModifierPressed,
            modifierHoldHintsEnabled: showModifierHoldHints
        )
        if showsFocusShortcutHint {
            ShortcutHintPill(
                shortcut: shortcut,
                fontSize: 9,
                emphasis: 1.05
            )
                .padding(.leading, 6)
                .padding(.top, 5)
                .offset(
                    x: CGFloat(ShortcutHintDebugSettings.clamped(focusShortcutHintXOffset)),
                    y: CGFloat(ShortcutHintDebugSettings.clamped(focusShortcutHintYOffset))
                )
                .shortcutHintTransition()
                .accessibilityIdentifier("rightSidebarFocusShortcutHint")
                .allowsHitTesting(false)
                .zIndex(10)
        }
    }

    @ViewBuilder
    private var content: some View {
        if RightSidebarContentMountPolicy.shouldMountContent(isRightSidebarVisible: fileExplorerState.isVisible, hasMountedContent: hasMountedRightSidebarContent) {
            FilesGitPanelView(
                explorerState: fileExplorerState,
                gitModel: gitModel,
                rootPath: fileExplorerStore.rootPath,
                filesContent: AnyView(
                    FileExplorerPanelView(
                        store: fileExplorerStore,
                        state: fileExplorerState,
                        onOpenFilePreview: onOpenFilePreview
                    )
                ),
                gitContent: AnyView(
                    GitPanelView(
                        model: gitModel,
                        openFile: { [rootPath = fileExplorerStore.rootPath] relativePath in
                            onOpenFilePreview(
                                GitPanelView.absolutePath(root: rootPath, relative: relativePath)
                            )
                        },
                        // Task 8 supplies the GitChangesPanel opener; hidden until then.
                        openChanges: nil
                    )
                )
            )
        } else {
            Color.clear
        }
    }
}

private struct RightSidebarKeyboardFocusBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> RightSidebarKeyboardFocusView {
        let view = RightSidebarKeyboardFocusView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        return view
    }

    func updateNSView(_ nsView: RightSidebarKeyboardFocusView, context: Context) {
        nsView.registerWithKeyboardFocusCoordinatorIfNeeded()
    }
}

final class RightSidebarKeyboardFocusView: NSView {
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        AppDelegate.shared?.keyboardFocusCoordinator(for: window)?.registerRightSidebarHost(self)
#if DEBUG
        dlog(
            "rs.focus.host.attach win=\(window.windowNumber) canAccept=\(cmuxCanAcceptRightSidebarKeyboardFocus ? 1 : 0) " +
            "fr=\(rightSidebarDebugResponder(window.firstResponder))"
        )
#endif
    }

    func registerWithKeyboardFocusCoordinatorIfNeeded() {
        guard let window else { return }
        AppDelegate.shared?.keyboardFocusCoordinator(for: window)?.registerRightSidebarHost(self)
    }

    override func layout() {
        super.layout()
        registerWithKeyboardFocusCoordinatorIfNeeded()
    }

    override func keyDown(with event: NSEvent) {
        if let tab = AppDelegate.shared?.rightSidebarTabShortcut(for: event) {
            _ = AppDelegate.shared?.focusRightSidebarInActiveMainWindow(
                tab: tab,
                focusFirstItem: true,
                preferredWindow: window
            )
            return
        }
        if event.keyCode == 53 {
            if let window,
               AppDelegate.shared?.keyboardFocusCoordinator(for: window)?.focusTerminal() == true {
                return
            }
            window?.makeFirstResponder(nil)
            return
        }
        if let characters = event.charactersIgnoringModifiers, !characters.isEmpty {
            return
        }
        super.keyDown(with: event)
    }

    func focusHostFromCoordinator() -> Bool {
        guard let window else {
#if DEBUG
            dlog("rs.focus.host.focus result=0 reason=noWindow")
#endif
            return false
        }
        let result = window.makeFirstResponder(self)
#if DEBUG
        dlog(
            "rs.focus.host.focus result=\(result ? 1 : 0) win=\(window.windowNumber) " +
            "fr=\(rightSidebarDebugResponder(window.firstResponder))"
        )
#endif
        return result
    }
}

extension NSView {
    var cmuxCanAcceptRightSidebarKeyboardFocus: Bool {
        guard window != nil, !isHiddenOrHasHiddenAncestor else { return false }
        var view: NSView? = self
        while let current = view {
            if current.bounds.width <= 0.5 || current.bounds.height <= 0.5 {
                return false
            }
            view = current.superview
        }
        return true
    }
}
