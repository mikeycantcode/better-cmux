import CmuxSettings
import Foundation
import Testing

#if canImport(cmux_DEV)
    @testable import cmux_DEV
#elseif canImport(cmux)
    @testable import cmux
#endif

struct SidebarShortcutDefaultsTests {
    @Test func hideShowSidebarDefaults() {
        let hide = KeyboardShortcutSettings.Action.hideSidebar.defaultShortcut
        let show = KeyboardShortcutSettings.Action.showSidebar.defaultShortcut
        #expect(hide == StoredShortcut(key: "[", command: true, shift: false, option: false, control: false))
        #expect(show == StoredShortcut(key: "]", command: true, shift: false, option: false, control: false))
    }

    /// hideSidebar/showSidebar (application-wide, non-priority) share their
    /// default Cmd+[ / Cmd+] keystrokes with browserBack/browserForward
    /// (browser-focus-scoped). Runtime resolves this by manual ordering in
    /// `handleCustomShortcut` (browser actions checked first), and the
    /// Settings conflict detector must not report a false "already in use"
    /// warning for this pair — it relies on `browserBack`/`browserForward`
    /// being marked `hasPriorityShortcutRouting`, the same mechanism the
    /// sidebar-mode ⌃1…5 vs Select-Surface ⌃1…9 pair uses.
    @Test func hideSidebarDoesNotCollideWithBrowserBack() {
        #expect(ShortcutAction.browserBack.hasPriorityShortcutRouting)
        #expect(ShortcutAction.browserForward.hasPriorityShortcutRouting)
        #expect(!ShortcutAction.hideSidebar.hasPriorityShortcutRouting)
        #expect(!ShortcutAction.showSidebar.hasPriorityShortcutRouting)

        let collidesBack = ShortcutWhenClause.bindingsCollide(
            ShortcutAction.hideSidebar.defaultFocusWhenClause,
            lhsHasPriority: ShortcutAction.hideSidebar.hasPriorityShortcutRouting,
            ShortcutAction.browserBack.defaultFocusWhenClause,
            rhsHasPriority: ShortcutAction.browserBack.hasPriorityShortcutRouting
        )
        #expect(!collidesBack)

        let collidesForward = ShortcutWhenClause.bindingsCollide(
            ShortcutAction.showSidebar.defaultFocusWhenClause,
            lhsHasPriority: ShortcutAction.showSidebar.hasPriorityShortcutRouting,
            ShortcutAction.browserForward.defaultFocusWhenClause,
            rhsHasPriority: ShortcutAction.browserForward.hasPriorityShortcutRouting
        )
        #expect(!collidesForward)
    }

    @Test func focusHistoryMovedToOption() {
        let back = KeyboardShortcutSettings.Action.focusHistoryBack.defaultShortcut
        let forward = KeyboardShortcutSettings.Action.focusHistoryForward.defaultShortcut
        #expect(back == StoredShortcut(key: "[", command: true, shift: false, option: true, control: false))
        #expect(forward == StoredShortcut(key: "]", command: true, shift: false, option: true, control: false))
    }
}
