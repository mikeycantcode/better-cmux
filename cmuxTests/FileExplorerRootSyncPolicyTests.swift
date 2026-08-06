import AppKit
import CmuxSettings
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite("File explorer root sync policy")
struct FileExplorerRootSyncPolicyTests {
    @Test("Hidden right sidebar keeps file explorer root lazy")
    func hiddenRightSidebarKeepsFileExplorerRootLazy() {
        #expect(
            FileExplorerRootSyncPolicy.shouldSyncFileExplorerStore(isRightSidebarVisible: false) == false
        )
    }

    @Test("Visible right sidebar syncs the file explorer root")
    func visibleRightSidebarSyncsFileExplorerRoot() {
        #expect(FileExplorerRootSyncPolicy.shouldSyncFileExplorerStore(isRightSidebarVisible: true))
    }
}

@Suite("Right sidebar directory context")
struct RightSidebarDirectoryContextTests {
    @Test("Blank directories normalize to nil")
    func blankDirectoriesNormalizeToNil() {
        #expect(RightSidebarDirectoryContext.normalizedDirectory("   ") == nil)
        #expect(RightSidebarDirectoryContext.normalizedDirectory(nil) == nil)
    }

    @Test("Directories are trimmed")
    func directoriesAreTrimmed() {
        #expect(RightSidebarDirectoryContext.normalizedDirectory(" /remote/project ") == "/remote/project")
    }
}

/// Task 7 removed the Find / Vault / Feed / Dock right-sidebar modes. The sidebar
/// is strictly Files | Git, so the shortcut catalog must not carry the dead actions.
@Suite("Right sidebar mode removal")
struct RightSidebarModeRemovalTests {
    @Test("Dead right-sidebar shortcut actions are gone")
    func deadRightSidebarShortcutsAreGone() {
        let ids = KeyboardShortcutSettings.Action.allCases.map(\.rawValue)
        #expect(!ids.contains("switchRightSidebarToFind"))
        #expect(!ids.contains("switchRightSidebarToSessions"))
        #expect(!ids.contains("switchRightSidebarToFeed"))
        #expect(!ids.contains("switchRightSidebarToDock"))
        #expect(ids.contains("switchRightSidebarToFiles"))
        #expect(ids.contains("switchRightSidebarToGit"))
    }

    @Test("The shared settings catalog matches the app's action list")
    func sharedShortcutCatalogMatchesAppActions() {
        let sharedIDs = Set(ShortcutAction.allCases.map(\.rawValue))
        #expect(!sharedIDs.contains("switchRightSidebarToFind"))
        #expect(!sharedIDs.contains("switchRightSidebarToSessions"))
        #expect(!sharedIDs.contains("switchRightSidebarToFeed"))
        #expect(!sharedIDs.contains("switchRightSidebarToDock"))
        #expect(sharedIDs.contains("switchRightSidebarToGit"))
    }

    @Test("Both Files|Git shortcuts are editable in Settings")
    func filesAndGitShortcutsAreSettingsVisible() {
        let visible = KeyboardShortcutSettings.settingsVisibleActions
        #expect(visible.contains(.switchRightSidebarToFiles))
        #expect(visible.contains(.switchRightSidebarToGit))
    }

    @Test("Show Sidebar Git ships unbound")
    func showSidebarGitShipsUnbound() {
        #expect(KeyboardShortcutSettings.Action.switchRightSidebarToGit.defaultShortcut.isUnbound)
        #expect(ShortcutAction.switchRightSidebarToGit.defaultStroke == nil)
    }
}

@MainActor
@Suite("Right sidebar keyboard navigation")
struct RightSidebarKeyboardNavigationTests {
    @Test("Return and keypad Enter open the selected item")
    func returnAndKeypadEnterOpenSelection() throws {
        for keyCode in [UInt16(36), UInt16(76)] {
            let event = try #require(Self.keyEvent(keyCode: keyCode, modifierFlags: []))
            #expect(event.isFileExplorerOpenSelectionShortcut(in: FileExplorerPanelPlacement.rightSidebar))
        }
    }

    @Test("Command Down opens the selected item")
    func commandDownOpensSelection() throws {
        let event = try #require(Self.keyEvent(keyCode: 125, modifierFlags: [.command]))
        #expect(event.isFileExplorerOpenSelectionShortcut(in: FileExplorerPanelPlacement.rightSidebar))
    }

    @Test("Plain Down, Shift Return, and Command Return keep their existing routes")
    func nonActivationKeysDoNotOpenSelection() throws {
        let plainDown = try #require(Self.keyEvent(keyCode: 125, modifierFlags: []))
        let shiftReturn = try #require(Self.keyEvent(keyCode: 36, modifierFlags: [.shift]))
        let commandReturn = try #require(Self.keyEvent(keyCode: 36, modifierFlags: [.command]))

        #expect(!plainDown.isFileExplorerOpenSelectionShortcut(in: FileExplorerPanelPlacement.rightSidebar))
        #expect(!shiftReturn.isFileExplorerOpenSelectionShortcut(in: FileExplorerPanelPlacement.rightSidebar))
        #expect(!commandReturn.isFileExplorerOpenSelectionShortcut(in: FileExplorerPanelPlacement.rightSidebar))
    }

    private static func keyEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: keyCode
        )
    }
}
