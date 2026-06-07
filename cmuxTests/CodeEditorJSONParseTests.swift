import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Verifies that the `app.codeEditor` value in `cmux.json` is parsed by
/// `KeyboardShortcutSettingsFileStore` into the managed `UserDefaults` key that
/// `CodeEditorPreferenceSettings` reads. The store writes managed settings into
/// `UserDefaults.standard`, so this suite is serialized and preserves/restores
/// the keys it touches.
@Suite(.serialized) struct CodeEditorJSONParseTests {
    private static let codeEditorKey = CodeEditorPreferenceSettings.key
    private static let backupsKey = "cmux.settingsFile.backups.v1"
    private static let importedManagedDefaultsKey = "cmux.settingsFile.importedManagedDefaults.v1"

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "cmux-codeeditor-parse-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeSettingsFile(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func preservingDefaults(keys: [String], _ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let previousValues = keys.map { (key: $0, value: defaults.object(forKey: $0)) }
        defer {
            for previous in previousValues {
                if let value = previous.value {
                    defaults.set(value, forKey: previous.key)
                } else {
                    defaults.removeObject(forKey: previous.key)
                }
            }
        }
        try body()
    }

    /// Loads a `cmux.json` whose `app.codeEditor` is set, then returns what
    /// `CodeEditorPreferenceSettings.resolved` reads back from `UserDefaults.standard`.
    private func resolvedChoice(forCodeEditorJSON jsonValue: String) throws -> CodeEditorChoice {
        let defaults = UserDefaults.standard
        var resolved: CodeEditorChoice = .monaco
        try preservingDefaults(keys: [Self.codeEditorKey, Self.backupsKey, Self.importedManagedDefaultsKey]) {
            defaults.removeObject(forKey: Self.codeEditorKey)
            defaults.removeObject(forKey: Self.backupsKey)
            defaults.removeObject(forKey: Self.importedManagedDefaultsKey)

            let directoryURL = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: directoryURL) }

            let settingsFileURL = directoryURL.appendingPathComponent("cmux.json", isDirectory: false)
            try writeSettingsFile(
                """
                {
                  "app": {
                    "codeEditor": "\(jsonValue)"
                  }
                }
                """,
                to: settingsFileURL
            )

            _ = KeyboardShortcutSettingsFileStore(
                primaryPath: settingsFileURL.path,
                fallbackPath: nil,
                additionalFallbackPaths: [],
                startWatching: false
            )

            resolved = CodeEditorPreferenceSettings.resolved(defaults: defaults)
        }
        return resolved
    }

    @Test func terminalValueResolvesToTerminal() throws {
        #expect(try resolvedChoice(forCodeEditorJSON: "terminal") == .terminal)
    }

    @Test func invalidValueLeavesMonaco() throws {
        #expect(try resolvedChoice(forCodeEditorJSON: "emacs-in-a-bottle") == .monaco)
    }
}
