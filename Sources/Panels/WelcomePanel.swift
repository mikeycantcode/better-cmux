import AppKit
import Combine
import Foundation
import SwiftUI

/// A non-terminal panel shown as the initial surface on a fresh launch: the better cmux
/// branding, credits, and a "+ New Terminal" button. The owning workspace sets ``onNewTerminal``
/// to create a terminal in this pane and close the welcome surface.
@MainActor
final class WelcomePanel: ObservableObject, Panel {
    let id = UUID()
    let workspaceId: UUID
    /// Invoked by the "+ New Terminal" button; the workspace wires this to create a terminal in
    /// this panel's pane and then close this welcome surface.
    var onNewTerminal: (() -> Void)?
    /// True when a restorable previous session exists; drives the "Restore previous session" button.
    @Published var hasPreviousSession = false
    /// Invoked by the "Restore previous session" button; the app applies the saved session.
    var onRestoreSession: (() -> Void)?

    // Reuse the closest existing kind; distinguished from FilePreviewPanel by instance at dispatch.
    let panelType: PanelType = .filePreview
    var displayTitle: String { String(localized: "welcome.tabTitle", defaultValue: "Welcome") }
    var displayIcon: String? { "sparkles" }
    var isDirty: Bool { false }

    init(workspaceId: UUID) {
        self.workspaceId = workspaceId
    }

    func close() {}
    func focus() {}
    func unfocus() {}
    func triggerFlash(reason: WorkspaceAttentionFlashReason) { _ = reason }
}
