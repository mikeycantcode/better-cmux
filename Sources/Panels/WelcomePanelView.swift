import SwiftUI

/// The better cmux welcome screen: the bundled app-icon asset for the current appearance
/// (AppIconDark / AppIconLight), title, credits, and a "+ New Terminal" button.
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

/// The brand mark: three parallel white capsules leaning right (///).
///
/// Proportions come from the shared brand contract on the 0–1024 canvas:
/// stroke 88/1024 ≈ 8.6% of side, length 620/1024 ≈ 60.5%, center spacing
/// 192/1024 = 18.75%, lean 18° clockwise from vertical.
struct ThreeStripeMark: View {
    var size: CGFloat
    /// True when the mark should render in near-black (light backgrounds).
    var monochrome: Bool

    /// Seconds between gloss sweeps.
    private static let sheenPeriod: TimeInterval = 3.2
    /// Sweep duration and pre-sweep pause, derived from the period.
    private static let sheenSweep: TimeInterval = 3.2 * 0.45
    private static let sheenDelay: TimeInterval = 0.2

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stripesIn = false
    @State private var sheenProgress: CGFloat = -1

    private var stripeWidth: CGFloat { size * 88 / 1024 }
    private var stripeLength: CGFloat { size * 620 / 1024 }
    private var stripeSpacing: CGFloat { size * 192 / 1024 }
    private var stripeColor: Color {
        monochrome ? Color(red: 0x11 / 255, green: 0x11 / 255, blue: 0x14 / 255) : .white
    }

    var body: some View {
        Group {
            if reduceMotion {
                stripes(opacity: 1, yOffset: 0)
            } else {
                stripes(opacity: stripesIn ? 1 : 0, yOffset: stripesIn ? 0 : -14)
                    .overlay {
                        // Gloss sweep: a full-strength copy of the mark, revealed
                        // only where a narrow band crosses it. The band parks fully
                        // off-content between cycles, so the mark itself never blinks.
                        TimelineView(.periodic(from: .now, by: Self.sheenPeriod)) { context in
                            stripes(opacity: 1, yOffset: 0)
                                .opacity(stripesIn ? 1 : 0)
                                .mask {
                                    LinearGradient(
                                        colors: [.clear, .white.opacity(0.9), .clear],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                    .frame(width: size * 0.7)
                                    .offset(x: sheenProgress * size * 1.5)
                                }
                                .task(id: context.date) {
                                    var instant = Transaction()
                                    instant.disablesAnimations = true
                                    withTransaction(instant) { sheenProgress = -1 }
                                    withAnimation(.linear(duration: Self.sheenSweep).delay(Self.sheenDelay)) {
                                        sheenProgress = 1
                                    }
                                }
                        }
                        .allowsHitTesting(false)
                    }
                    .onAppear {
                        stripesIn = true
                    }
            }
        }
    }

    @ViewBuilder
    private func stripes(opacity: Double, yOffset: CGFloat) -> some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(stripeColor)
                    .frame(width: stripeWidth, height: stripeLength)
                    .rotationEffect(.degrees(18))
                    .offset(x: CGFloat(i - 1) * stripeSpacing, y: yOffset)
                    .animation(
                        reduceMotion ? nil :
                            .spring(response: 0.5, dampingFraction: 0.8)
                            .delay(Double(i) * 0.09),
                        value: stripesIn
                    )
            }
        }
    }
}

