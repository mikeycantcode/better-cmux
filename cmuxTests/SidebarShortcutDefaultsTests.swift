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

    @Test func focusHistoryMovedToOption() {
        let back = KeyboardShortcutSettings.Action.focusHistoryBack.defaultShortcut
        let forward = KeyboardShortcutSettings.Action.focusHistoryForward.defaultShortcut
        #expect(back == StoredShortcut(key: "[", command: true, shift: false, option: true, control: false))
        #expect(forward == StoredShortcut(key: "]", command: true, shift: false, option: true, control: false))
    }
}
