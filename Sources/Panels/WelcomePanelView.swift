import SwiftUI

/// The better cmux welcome screen: red app-icon logo, title, credits, and a "+ New Terminal" button.
struct WelcomePanelView: View {
    @ObservedObject var panel: WelcomePanel
    let appearance: PanelAppearance

    private let originalURL = URL(string: "https://github.com/manaflow-ai/cmux")!
    private let buildURL = URL(string: "https://github.com/mikeycantcode")!

    private var isDark: Bool { !appearance.backgroundColor.isLightColor }
    private var logoImage: NSImage {
        NSImage(named: isDark ? "AppIconDark" : "AppIconLight") ?? NSApplication.shared.applicationIconImage
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(nsImage: logoImage)
                .resizable()
                .frame(width: 88, height: 88)
            Text(String(localized: "welcome.title", defaultValue: "better cmux"))
                .font(.system(size: 26, weight: .bold))
            VStack(spacing: 4) {
                Text(String(localized: "welcome.creditOriginal", defaultValue: "Built on cmux by manaflow-ai — all credit to the original team."))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Text(String(localized: "welcome.creditBuildPrefix", defaultValue: "This build:"))
                        .foregroundStyle(.secondary)
                    Link("github.com/mikeycantcode", destination: buildURL)
                }
                Link(String(localized: "welcome.originalLink", defaultValue: "github.com/manaflow-ai/cmux"), destination: originalURL)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .font(.callout)
            Button {
                panel.onNewTerminal?()
            } label: {
                Label(String(localized: "welcome.newTerminal", defaultValue: "New Terminal"), systemImage: "plus")
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
            }
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
            if panel.hasPreviousSession {
                Button(String(localized: "welcome.restorePrevious", defaultValue: "Restore previous session")) {
                    panel.onRestoreSession?()
                }
                .controlSize(.regular)
            }
            Text(String(localized: "welcome.shortcutHint", defaultValue: "⌘T also opens a terminal"))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: appearance.backgroundColor))
    }
}
