import SwiftUI

/// First-launch prompt shown when cmux runs from outside /Applications —
/// typically a fresh download sitting in ~/Downloads. Offers to relocate the
/// app bundle into /Applications and relaunch, fronted by the animated
/// three-stripe mark.
///
/// Display rules:
/// - Release builds: once per downloaded copy (quarantined bundle outside
///   /Applications), tracked by a UserDefaults flag.
/// - Debug builds never nag on their own; set CMUX_SHOW_MOVE_PROMPT=1 in the
///   environment to preview the prompt.
@MainActor
enum MoveToApplicationsPrompt {
    private static let shownDefaultsKey = "moveToApplications.promptShown.v1"
    private static var windowController: MoveToApplicationsWindowController?

    /// Presents the relocation prompt when the launch context calls for it.
    static func presentIfNeeded() {
        guard shouldShow else { return }
        // Mark immediately: declining must not re-prompt on the next launch,
        // even if this window is destroyed before dismissal completes.
        UserDefaults.standard.set(true, forKey: shownDefaultsKey)
        let controller = MoveToApplicationsWindowController()
        windowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static var shouldShow: Bool {
        if ProcessInfo.processInfo.environment["CMUX_SHOW_MOVE_PROMPT"] == "1" {
            return true
        }
        #if DEBUG
            return false
        #else
            guard !UserDefaults.standard.bool(forKey: shownDefaultsKey) else { return false }
            let bundlePath = Bundle.main.bundlePath
            guard !bundlePath.hasPrefix("/Applications/") else { return false }
            return isQuarantined(bundlePath)
        #endif
    }

    /// Clears the strong reference when the prompt window closes.
    static func clearWindowRef() {
        windowController = nil
    }

    /// bundle arrived from the internet rather than a build or installer.
    private static func isQuarantined(_ path: String) -> Bool {
        getxattr(path, "com.apple.quarantine", nil, 0, 0, 0) > 0
    }

    /// Moves the running bundle into /Applications, replacing any existing
    /// copy. Returns the destination URL on success.
    nonisolated static func relocateBundle() throws -> URL {
        let fileManager = FileManager.default
        let source = Bundle.main.bundleURL
        let applications = fileManager.urls(for: .applicationDirectory, in: .localDomainMask)
            .first ?? URL(fileURLWithPath: "/Applications")
        let destination = applications.appendingPathComponent(source.lastPathComponent)

        if !fileManager.fileExists(atPath: applications.path) {
            try fileManager.createDirectory(at: applications, withIntermediateDirectories: true)
        }
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: source)
        } else {
            try fileManager.moveItem(at: source, to: destination)
        }
        return destination
    }

    /// Relaunches cmux from the given bundle and terminates this instance.
    nonisolated static func relaunch(from bundle: URL) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            NSWorkspace.shared.open(bundle)
            NSApp.terminate(nil)
        }
    }
}

@MainActor
final class MoveToApplicationsWindowController: NSWindowController, NSWindowDelegate {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.center()
        self.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: MoveToApplicationsView(
                onDismiss: { [weak self] in self?.close() },
                onRelocate: { try MoveToApplicationsPrompt.relocateBundle() }
            )
        )
    }

    func windowWillClose(_ notification: Notification) {
        MoveToApplicationsPrompt.clearWindowRef()
    }
}

/// Clean centered card: animated mark, one-line rationale, two actions.
private struct MoveToApplicationsView: View {
    enum Phase {
        case idle
        case moving
        case failed
    }

    var onDismiss: () -> Void
    var onRelocate: () throws -> URL

    @Environment(\.colorScheme) private var colorScheme
    @State private var phase: Phase = .idle

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ThreeStripeMark(size: 76, monochrome: colorScheme == .light)
            Text(String(localized: "moveToApplications.title", defaultValue: "Move cmux to Applications?"))
                .font(.system(size: 19, weight: .semibold))
                .padding(.top, 18)
            Text(String(localized: "moveToApplications.subtitle", defaultValue: "cmux runs best from your Applications folder."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 6)
            Spacer()
            if case .failed = phase {
                Text(String(localized: "moveToApplications.failed", defaultValue: "Couldn't move cmux to Applications."))
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.bottom, 8)
            }
            HStack(spacing: 10) {
                Button(String(localized: "moveToApplications.notNow", defaultValue: "Not Now")) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button {
                    startMove()
                } label: {
                    if phase == .moving {
                        Text(String(localized: "moveToApplications.moving", defaultValue: "Moving…"))
                    } else {
                        Text(String(localized: "moveToApplications.move", defaultValue: "Move to Applications"))
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(phase == .moving)
            }
            .controlSize(.large)
            .padding(.bottom, 22)
        }
        .padding(.horizontal, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func startMove() {
        phase = .moving
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let destination = try onRelocate()
                DispatchQueue.main.async {
                    MoveToApplicationsPrompt.relaunch(from: destination)
                }
            } catch {
                DispatchQueue.main.async {
                    phase = .failed
                }
            }
        }
    }
}
