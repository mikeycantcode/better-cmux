import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct CodeEditorPreferenceSettingsTests {
    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "monaco-test-\(UUID().uuidString)")!
    }

    @Test func defaultsToMonaco() {
        #expect(CodeEditorPreferenceSettings.resolved(defaults: defaults()) == .monaco)
    }

    @Test func readsTerminal() {
        let d = defaults()
        d.set("terminal", forKey: CodeEditorPreferenceSettings.key)
        #expect(CodeEditorPreferenceSettings.resolved(defaults: d) == .terminal)
    }

    @Test func unknownFallsBackToMonaco() {
        let d = defaults()
        d.set("emacs-in-a-bottle", forKey: CodeEditorPreferenceSettings.key)
        #expect(CodeEditorPreferenceSettings.resolved(defaults: d) == .monaco)
    }
}
