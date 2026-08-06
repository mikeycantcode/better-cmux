import AppKit
import CmuxCommandPalette
import CmuxSidebar
import CmuxSwiftRender

extension ContentView {
    static func commandPaletteShortcutAction(forCommandID commandId: String) -> KeyboardShortcutSettings.Action? {
        if let rightSidebarTabAction = commandPaletteRightSidebarTabShortcutAction(forCommandID: commandId) {
            return rightSidebarTabAction
        }

        switch commandId {
        case "palette.newWorkspace":
            return .newTab
        case "palette.newBrowserWorkspace":
            return .newBrowserWorkspace
        case "palette.newWindow":
            return .newWindow
        case "palette.openFolder":
            return .openFolder
        case "palette.reopenPreviousSession":
            return .reopenPreviousSession
        case "palette.reopenClosedBrowserTab":
            return .reopenClosedBrowserPanel
        case "palette.newTerminalTab":
            return .newSurface
        case "palette.newBrowserTab":
            return .openBrowser
        case "palette.closeWindow":
            return .closeWindow
        case "palette.toggleSidebar":
            return .toggleSidebar
        case "palette.showNotifications":
            return .showNotifications
        case "palette.jumpUnread":
            return .jumpToUnread
        case "palette.toggleUnread":
            return .toggleUnread
        case "palette.markOldestUnreadAndJumpNext":
            return .markOldestUnreadAndJumpNext
        case "palette.renameTab":
            return .renameTab
        case "palette.renameWorkspace":
            return .renameWorkspace
        case "palette.editWorkspaceDescription":
            return .editWorkspaceDescription
        case "palette.nextWorkspace":
            return .nextSidebarTab
        case "palette.previousWorkspace":
            return .prevSidebarTab
        case "palette.nextTabInPane":
            return .nextSurface
        case "palette.previousTabInPane":
            return .prevSurface
        case "palette.browserToggleDevTools":
            return .toggleBrowserDeveloperTools
        case "palette.browserConsole":
            return .showBrowserJavaScriptConsole
        case "palette.browserReactGrab":
            return .toggleReactGrab
        case "palette.browserSplitRight", "palette.terminalSplitBrowserRight":
            return .splitBrowserRight
        case "palette.browserSplitDown", "palette.terminalSplitBrowserDown":
            return .splitBrowserDown
        case "palette.terminalSplitRight":
            return .splitRight
        case "palette.terminalSplitDown":
            return .splitDown
        case "palette.findInDirectory":
            return .findInDirectory
        case "palette.terminalFind":
            return .find
        case "palette.terminalFindNext":
            return .findNext
        case "palette.terminalFindPrevious":
            return .findPrevious
        case "palette.terminalHideFind":
            return .hideFind
        case "palette.terminalUseSelectionForFind":
            return .useSelectionForFind
        case "palette.terminalFocusTextBoxInput":
            return .focusTextBoxInput
        case "palette.terminalAttachTextBoxFile":
            return .attachTextBoxFile
        case "palette.terminalSendCtrlF":
            return .sendCtrlFToTerminal
        case "palette.terminalClearScreenKeepScrollback":
            return .clearScreenKeepScrollback
        case "palette.toggleSplitZoom":
            return .toggleSplitZoom
        case "palette.equalizeSplits":
            return .equalizeSplits
        case "palette.triggerFlash":
            return .triggerFlash
        default:
            return nil
        }
    }

    static func commandPaletteRightSidebarTabCommandContributions() -> [CommandPaletteCommandContribution] {
        func constant(_ value: String) -> (CommandPaletteContextSnapshot) -> String {
            { _ in value }
        }

        return FilesGitTab.allCases.map { tab in
            CommandPaletteCommandContribution(
                commandId: Self.commandPaletteRightSidebarTabCommandID(tab),
                title: constant(Self.commandPaletteRightSidebarTabAction(tab).label),
                subtitle: constant(String(localized: "command.rightSidebarMode.subtitle", defaultValue: "Right Sidebar")),
                keywords: ["right", "sidebar", "show", "switch", "focus", tab.rawValue]
            )
        }
    }

    static func commandPaletteRightSidebarToolPaneCommandContributions() -> [CommandPaletteCommandContribution] {
        func constant(_ value: String) -> (CommandPaletteContextSnapshot) -> String {
            { _ in value }
        }

        return commandPaletteRightSidebarToolPaneCommandDescriptors().map { descriptor in
            CommandPaletteCommandContribution(
                commandId: descriptor.commandId,
                title: constant(descriptor.title),
                subtitle: constant(String(localized: "command.openRightSidebarToolAsPane.subtitle", defaultValue: "Pane")),
                keywords: ["open", "pane", "tool", "right", "sidebar", "files", "git"]
            )
        }
    }

    static func commandPaletteRightSidebarTabCommandID(_ tab: FilesGitTab) -> String {
        switch tab {
        case .files:
            return "palette.showRightSidebarFiles"
        case .git:
            return "palette.showRightSidebarGit"
        }
    }

    static func commandPaletteRightSidebarTabAction(_ tab: FilesGitTab) -> KeyboardShortcutSettings.Action {
        switch tab {
        case .files:
            return .switchRightSidebarToFiles
        case .git:
            return .switchRightSidebarToGit
        }
    }

    static func commandPaletteRightSidebarToolPaneCommandDescriptors() -> [(commandId: String, title: String)] {
        [(
            commandId: "palette.openFilesPane",
            title: String(localized: "command.openFilesPane.title", defaultValue: "Open Files as Pane")
        )]
    }

    func handleCommandPaletteRightSidebarTab(_ tab: FilesGitTab, observedWindow: NSWindow?) {
        FilesGitTab.select(tab)
        if AppDelegate.shared?.focusRightSidebarInActiveMainWindow(
            tab: tab,
            focusFirstItem: true,
            preferredWindow: observedWindow ?? NSApp.keyWindow ?? NSApp.mainWindow
        ) != true {
            fileExplorerState.setVisible(true)
        }
    }

    func handleCommandPaletteRightSidebarToolPane() {
        openRightSidebarToolPane()
    }

    func openCustomSidebarPane(_ name: String) {
        guard let workspace = tabManager.selectedWorkspace else {
            NSSound.beep()
            return
        }

        sidebarSelectionState.selection = .tabs
        workspace.clearSplitZoom()
        if let focusedPanelId = workspace.focusedPanelId,
           workspace.openOrFocusCustomSidebarSplit(from: focusedPanelId, name: name) != nil {
            return
        }
        guard let paneId = workspace.bonsplitController.focusedPaneId ?? workspace.bonsplitController.allPaneIds.first,
              workspace.openOrFocusCustomSidebarSurface(inPane: paneId, name: name, focus: true) != nil else {
            NSSound.beep()
            return
        }
    }

    private static func commandPaletteRightSidebarTabShortcutAction(
        forCommandID commandID: String
    ) -> KeyboardShortcutSettings.Action? {
        guard let tab = FilesGitTab.allCases.first(where: { tab in
            Self.commandPaletteRightSidebarTabCommandID(tab) == commandID
        }) else {
            return nil
        }
        return Self.commandPaletteRightSidebarTabAction(tab)
    }

    func rightSidebarCustomSidebarDataContext(now: Date) -> [String: SwiftValue] {
        let selectedId = tabManager.selectedTabId
        let workspaces = tabManager.tabs.enumerated().map { index, workspace in
            rightSidebarCustomSidebarWorkspaceSnapshot(workspace, index: index, selectedId: selectedId)
        }
        let selectedWorkspace = tabManager.tabs.first { $0.id == selectedId }
        let snapshot = CustomSidebarContextSnapshot(
            workspaces: workspaces,
            selectedWorkspaceId: selectedId,
            selectedWorkspaceTitle: selectedWorkspace?.customTitle ?? selectedWorkspace?.title ?? "",
            totalUnreadCount: sidebarUnread.totalUnreadCount,
            now: now
        )
        return CustomSidebarDataContextBuilder().dataContext(for: snapshot)
    }

    private func rightSidebarCustomSidebarWorkspaceSnapshot(
        _ workspace: Workspace,
        index: Int,
        selectedId: UUID?
    ) -> CustomSidebarWorkspaceSnapshot {
        let focusedPanelId = workspace.focusedPanelId
        let firstBranch = workspace.sidebarGitBranchesInDisplayOrder().first
        let progress = workspace.progress.map {
            CustomSidebarWorkspaceSnapshot.Progress(value: $0.value, label: $0.label)
        }
        let remote: CustomSidebarWorkspaceSnapshot.Remote? = nil
        return CustomSidebarWorkspaceSnapshot(
            id: workspace.id,
            title: workspace.customTitle ?? workspace.title,
            isSelected: workspace.id == selectedId,
            isPinned: workspace.isPinned,
            index: index,
            directory: workspace.currentDirectory,
            listeningPorts: workspace.listeningPorts,
            unreadCount: sidebarUnread.unreadCount(forWorkspaceId: workspace.id),
            surfaces: rightSidebarCustomSidebarSurfaceSnapshots(workspace, focusedPanelId: focusedPanelId),
            surfaceCount: workspace.bonsplitController.allPaneIds.reduce(0) { $0 + workspace.bonsplitController.tabs(inPane: $1).count },
            customDescription: workspace.customDescription,
            customColor: workspace.customColor,
            gitBranch: firstBranch?.branch,
            gitIsDirty: firstBranch?.isDirty ?? false,
            pullRequestValues: workspace.customSidebarPullRequestValues(),
            progress: progress,
            latestConversationMessage: workspace.latestConversationMessage,
            latestSubmittedMessage: workspace.latestSubmittedMessage,
            latestSubmittedAt: workspace.latestSubmittedAt,
            remote: remote
        )
    }

    private func rightSidebarCustomSidebarSurfaceSnapshots(
        _ workspace: Workspace,
        focusedPanelId: UUID?
    ) -> [CustomSidebarSurfaceSnapshot] {
        var surfaces: [CustomSidebarSurfaceSnapshot] = []
        for paneId in workspace.bonsplitController.allPaneIds {
            for tab in workspace.bonsplitController.tabs(inPane: paneId) {
                guard let panelId = workspace.panelIdFromSurfaceId(tab.id) else { continue }
                let git = workspace.panelGitBranches[panelId]
                surfaces.append(
                    CustomSidebarSurfaceSnapshot(
                        panelId: panelId,
                        title: tab.title,
                        isFocused: panelId == focusedPanelId,
                        isPinned: workspace.pinnedPanelIds.contains(panelId),
                        directory: workspace.panelDirectories[panelId],
                        gitBranch: git?.branch,
                        gitIsDirty: git?.isDirty ?? false,
                        listeningPorts: workspace.surfaceListeningPorts[panelId] ?? []
                    )
                )
            }
        }
        return surfaces
    }
}
