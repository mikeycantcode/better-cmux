import Foundation

/// Resolves and launches the configured terminal editor.
///
/// The resolution and command-building functions are pure (an `isAvailable`
/// probe is injected) so they are unit-tested without touching `PATH`. The
/// `availableOnPath(_:)` helper performs the real `which` probe in production.
enum EditorLauncher {
    /// Resolves the editor command to run.
    /// - Parameters:
    ///   - stored: the configured command (nil/empty → auto micro→vim).
    ///   - isAvailable: probe returning whether a binary is on `PATH`.
    /// - Returns: `stored` when non-empty, else `"micro"` if available else `"vim"`.
    static func resolveEditorCommand(stored: String?, isAvailable: (String) -> Bool) -> String {
        if let stored, !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return stored.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return isAvailable("micro") ? "micro" : "vim"
    }

    /// Builds a shell command that opens `path` in `editor`, single-quoting the
    /// path (with single-quote escaping) so spaces/specials are safe.
    static func openInEditorCommand(editor: String, path: String) -> String {
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "\(editor) '\(escaped)'"
    }

    /// The short name shown in the bottom bar (leaf of the command's first token).
    static func editorDisplayName(forCommand command: String) -> String {
        let firstToken = command.split(separator: " ").first.map(String.init) ?? command
        return (firstToken as NSString).lastPathComponent
    }

    /// Whether `name` is on `PATH` (`which <name>`), cached per process run.
    /// Used as the default `isAvailable` probe in production.
    static func availableOnPath(_ name: String) -> Bool {
        if let cached = pathCache[name] { return cached }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["which", name]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let ok: Bool
        do {
            try process.run()
            process.waitUntilExit()
            ok = process.terminationStatus == 0
        } catch {
            ok = false
        }
        pathCache[name] = ok
        return ok
    }

    // Process-lifetime cache of `which` results. Main-actor-confined access via
    // the call sites (bar render + open action), which are @MainActor.
    @MainActor private static var pathCache: [String: Bool] = [:]
}
