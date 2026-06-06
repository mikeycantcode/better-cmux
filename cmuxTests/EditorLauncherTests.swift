import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct EditorLauncherTests {
    @Test func autoPrefersMicroWhenAvailable() {
        let cmd = EditorLauncher.resolveEditorCommand(stored: nil, isAvailable: { $0 == "micro" })
        #expect(cmd == "micro")
    }

    @Test func autoFallsBackToVimWhenNoMicro() {
        let cmd = EditorLauncher.resolveEditorCommand(stored: "", isAvailable: { _ in false })
        #expect(cmd == "vim")
    }

    @Test func customCommandOverridesAuto() {
        let cmd = EditorLauncher.resolveEditorCommand(stored: "nvim", isAvailable: { _ in true })
        #expect(cmd == "nvim")
    }

    @Test func openCommandQuotesPath() {
        let cmd = EditorLauncher.openInEditorCommand(editor: "micro", path: "/Users/me/a b.txt")
        #expect(cmd == "micro '/Users/me/a b.txt'")
    }

    @Test func openCommandEscapesSingleQuotes() {
        let cmd = EditorLauncher.openInEditorCommand(editor: "vim", path: "/tmp/it's.txt")
        #expect(cmd == "vim '/tmp/it'\\''s.txt'")
    }

    @Test func editorDisplayNameIsLeafOfCommand() {
        #expect(EditorLauncher.editorDisplayName(forCommand: "/opt/homebrew/bin/micro --flag") == "micro")
        #expect(EditorLauncher.editorDisplayName(forCommand: "vim") == "vim")
    }
}
