import Foundation
import Testing
import CmuxTerminal

#if canImport(cmux_DEV)
    @testable import cmux_DEV
#elseif canImport(cmux)
    @testable import cmux
#endif

@Suite(.serialized)
struct ShellStartupMatrixTests {
    private struct ProcessRunResult {
        let status: Int32
        let stdout: String
        let stderr: String
        let timedOut: Bool
        let duration: TimeInterval
    }

    @Test
    func zshStartupPreservesUserZdotdirAndLoadsGhosttyIntegration() throws {
        let bundled = try makeBundledIntegrationDir(files: [".zshenv": "# cmux zsh bootstrap stub\n"])
        defer { try? FileManager.default.removeItem(at: bundled.root) }
        let integrationDir = bundled.integrationDir
        var environment = [
            "ZDOTDIR": "/Users/example/.zsh",
            "GHOSTTY_RESOURCES_DIR": "/Applications/Ghostty.app/Contents/Resources",
        ]
        var protectedKeys: Set<String> = []

        let command = TerminalSurface.applyManagedShellSpecificStartupEnvironment(
            shell: "/bin/zsh",
            integrationDir: integrationDir,
            userGhosttyShellIntegrationMode: "detect",
            to: &environment,
            protectedKeys: &protectedKeys
        )

        expectEqual(command, nil)
        expectEqual(environment["ZDOTDIR"], integrationDir)
        expectEqual(environment["CMUX_ZSH_ZDOTDIR"], "/Users/example/.zsh")
        expectEqual(environment["CMUX_LOAD_GHOSTTY_ZSH_INTEGRATION"], "1")
        expectTrue(protectedKeys.isSuperset(of: ["ZDOTDIR", "CMUX_ZSH_ZDOTDIR", "CMUX_LOAD_GHOSTTY_ZSH_INTEGRATION"]))
    }

    @Test
    func zshStartupDoesNotPreserveGhosttyInjectedZdotdir() throws {
        let bundled = try makeBundledIntegrationDir(files: [".zshenv": "# cmux zsh bootstrap stub\n"])
        defer { try? FileManager.default.removeItem(at: bundled.root) }
        let ghosttyResources = "/Applications/Ghostty.app/Contents/Resources"
        var environment = [
            "ZDOTDIR": "\(ghosttyResources)/shell-integration/zsh",
            "GHOSTTY_RESOURCES_DIR": ghosttyResources,
        ]
        var protectedKeys: Set<String> = []

        _ = TerminalSurface.applyManagedShellSpecificStartupEnvironment(
            shell: "/bin/zsh",
            integrationDir: bundled.integrationDir,
            userGhosttyShellIntegrationMode: "detect",
            to: &environment,
            protectedKeys: &protectedKeys
        )

        expectEqual(environment["CMUX_ZSH_ZDOTDIR"], nil)
        expectFalse(protectedKeys.contains("CMUX_ZSH_ZDOTDIR"))
    }

    @Test
    func bashStartupUsesBundledPromptCommandAndHonorsGhosttyMode() {
        let integrationDir = "/Applications/cmux.app/Contents/Resources/shell-integration"
        var environment: [String: String] = [:]
        var protectedKeys: Set<String> = []

        _ = TerminalSurface.applyManagedShellSpecificStartupEnvironment(
            shell: "/opt/homebrew/bin/bash",
            integrationDir: integrationDir,
            userGhosttyShellIntegrationMode: "none",
            to: &environment,
            protectedKeys: &protectedKeys,
            readFile: { path in
                expectEqual(path, "\(integrationDir)/cmux-bash-bootstrap.bash")
                return """
                # comment

                export CMUX_TEST=1
                   # indented comment
                cmux-test-command
                """
            }
        )

        expectEqual(environment["CMUX_LOAD_GHOSTTY_BASH_INTEGRATION"], nil)
        expectEqual(environment["PROMPT_COMMAND"], "export CMUX_TEST=1\ncmux-test-command")
        expectTrue(protectedKeys.contains("PROMPT_COMMAND"))
        expectFalse(protectedKeys.contains("CMUX_LOAD_GHOSTTY_BASH_INTEGRATION"))
    }

    @Test
    func fishStartupReturnsManagedCommandAndPreservesUserConfigHome() throws {
        let bundled = try makeBundledIntegrationDir(files: ["fish/config.fish": "# cmux fish bootstrap stub\n"])
        defer { try? FileManager.default.removeItem(at: bundled.root) }
        let integrationDir = bundled.integrationDir
        let shell = "/opt/homebrew/bin/fish"
        var environment = ["XDG_CONFIG_HOME": "/Users/example/.config"]
        var protectedKeys: Set<String> = []

        let command = TerminalSurface.applyManagedShellSpecificStartupEnvironment(
            shell: shell,
            integrationDir: integrationDir,
            userGhosttyShellIntegrationMode: "detect",
            to: &environment,
            protectedKeys: &protectedKeys
        )

        expectEqual(command, TerminalSurface.managedFishShellCommand(shell: shell))
        expectEqual(environment["XDG_CONFIG_HOME"], "/Users/example/.config")
        expectEqual(environment["CMUX_FISH_INTEGRATION_FILE"], "\(integrationDir)/fish/config.fish")
        expectEqual(environment["CMUX_FISH_USER_CONFIG_ALREADY_LOADED"], "1")
    }

    @Test(arguments: ["/bin/sh", "/bin/dash", "/bin/ksh", "/bin/tcsh", "/bin/csh", "/usr/local/bin/nu", "/usr/local/bin/pwsh"])
    func unsupportedLocalShellsKeepEnvironmentUnchanged(shell: String) {
        let originalEnvironment = ["CUSTOM": "1"]
        var environment = originalEnvironment
        var protectedKeys: Set<String> = []

        let command = TerminalSurface.applyManagedShellSpecificStartupEnvironment(
            shell: shell,
            integrationDir: "/Applications/cmux.app/Contents/Resources/shell-integration",
            userGhosttyShellIntegrationMode: "detect",
            to: &environment,
            protectedKeys: &protectedKeys
        )

        expectEqual(command, nil)
        expectEqual(environment, originalEnvironment)
        expectTrue(protectedKeys.isEmpty)
    }



    private func writeExecutableShellFile(at url: URL, capturePath: URL) throws {
        try """
        #!/bin/sh
        {
          printf 'ARGS=%s\\n' "$*"
          printf 'PATH=%s\\n' "$PATH"
          printf 'CMUX_SOCKET_PATH=%s\\n' "$CMUX_SOCKET_PATH"
          printf 'GHOSTTY_SHELL_FEATURES=%s\\n' "$GHOSTTY_SHELL_FEATURES"
          printf 'CMUX_SHELL_INTEGRATION_DIR=%s\\n' "$CMUX_SHELL_INTEGRATION_DIR"
          printf 'ZDOTDIR=%s\\n' "$ZDOTDIR"
          printf 'CMUX_REAL_ZDOTDIR=%s\\n' "$CMUX_REAL_ZDOTDIR"
          printf 'CMUX_FISH_INTEGRATION_FILE=%s\\n' "$CMUX_FISH_INTEGRATION_FILE"
          printf 'CMUX_FISH_USER_CONFIG_ALREADY_LOADED=%s\\n' "$CMUX_FISH_USER_CONFIG_ALREADY_LOADED"
          if [ -r "$CMUX_SHELL_INTEGRATION_DIR/cmux-zsh-integration.zsh" ] && grep -q 'cmux_zsh_marker=1' "$CMUX_SHELL_INTEGRATION_DIR/cmux-zsh-integration.zsh"; then
            printf 'ZSH_INTEGRATION_HAS_MARKER=yes\\n'
          fi
          if [ -r "$CMUX_SHELL_INTEGRATION_DIR/cmux-bash-integration.bash" ] && grep -q 'cmux_bash_marker=1' "$CMUX_SHELL_INTEGRATION_DIR/cmux-bash-integration.bash"; then
            printf 'BASH_INTEGRATION_HAS_MARKER=yes\\n'
          fi
          if [ -r "$CMUX_FISH_INTEGRATION_FILE" ] && grep -q 'CMUX_FISH_MARKER' "$CMUX_FISH_INTEGRATION_FILE"; then
            printf 'FISH_HAS_MARKER=yes\\n'
          fi
        } > "\(capturePath.path)"
        """
        .write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }


    /// Creates a real on-disk stand-in for the app bundle's
    /// `Resources/shell-integration` dir containing the given relative files,
    /// since the production code now verifies the bundled bootstrap exists
    /// before redirecting shell startup at it.
    private func makeBundledIntegrationDir(
        files: [String: String]
    ) throws -> (root: URL, integrationDir: String) {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("cmux-shell-matrix-bundle-\(UUID().uuidString)")
        let integrationDir = root.appendingPathComponent("shell-integration")
        for (relativePath, contents) in files {
            let fileURL = integrationDir.appendingPathComponent(relativePath)
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        }
        return (root, integrationDir.path)
    }

    private func formatSeconds(_ value: TimeInterval) -> String {
        String(format: "%.3fs", value)
    }

    private func runProcess(
        executablePath: String,
        arguments: [String],
        timeout: TimeInterval
    ) -> ProcessRunResult {
        let process = Process()
        let start = Date()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            return ProcessRunResult(
                status: -1,
                stdout: "",
                stderr: error.localizedDescription,
                timedOut: false,
                duration: Date().timeIntervalSince(start)
            )
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        let timedOut = process.isRunning
        if timedOut { process.terminate() }
        process.waitUntilExit()
        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
        return ProcessRunResult(
            status: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? "",
            timedOut: timedOut,
            duration: Date().timeIntervalSince(start)
        )
    }
}
