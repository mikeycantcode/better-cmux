import AppKit
import Bonsplit
import CmuxAppKitSupportUI
import QuartzCore
import SwiftUI

/// Visual constants for the stage card: the rounded glass pane `cmux open`
/// content and new terminals land in. The card *is* the pane: Bonsplit insets
/// and clips the whole pane (tab bar + content) to it via `PaneDecoration`.
enum StagePaneCardMetrics {
    static let cornerRadius: CGFloat = 14

    static let decoration = PaneDecoration(
        top: 6,
        leading: 6,
        bottom: 10,
        trailing: 10,
        cornerRadius: cornerRadius
    )
}

private struct StagePortalCornerRadiusKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Bottom-corner radius portal-hosted content clips to. Non-zero only in a
    /// stage card; read by the terminal and browser representables.
    var stagePortalCornerRadius: CGFloat {
        get { self[StagePortalCornerRadiusKey.self] }
        set { self[StagePortalCornerRadiusKey.self] = newValue }
    }
}

extension View {
    /// Tells portal-hosted content inside a stage card to round its corners.
    /// SwiftUI content is never clipped: any `clipShape` above a platform view
    /// makes SwiftUI misplace that view's container, and window portals (which
    /// clip to ancestor bounds) then lose part of their area. SwiftUI content
    /// draws on the terminal background, so its square corners are invisible.
    func stagePaneContent(isStage: Bool) -> some View {
        environment(\.stagePortalCornerRadius, isStage ? StagePaneCardMetrics.cornerRadius : 0)
    }
}


/// Rounds and blooms window-portal-hosted views (terminal surfaces, web view
/// slots). They draw above the SwiftUI layer, so Bonsplit's card clip never
/// reaches them; this is their half of the card. Only the bottom corners round:
/// the card's top edge belongs to the tab bar.
@MainActor
enum StagePortalStyling {
    static func apply(cornerRadius: CGFloat, to view: NSView) {
        view.wantsLayer = true
        guard let layer = view.layer, layer.cornerRadius != cornerRadius else { return }
        let isBecomingStage = layer.cornerRadius == 0 && cornerRadius > 0
        layer.cornerRadius = cornerRadius
        layer.cornerCurve = .continuous
        // Unflipped layer space: MinY is the bottom edge.
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer.masksToBounds = true
        if isBecomingStage && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            bloom(layer)
        }
    }

    /// Fade up while settling a few points: the portal half of the bloom.
    private static func bloom(_ layer: CALayer) {
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        fade.duration = 0.42
        fade.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1)

        let settle = CASpringAnimation(keyPath: "transform.translation.y")
        settle.fromValue = 10
        settle.toValue = 0
        settle.damping = 14
        settle.stiffness = 170
        settle.mass = 1
        settle.duration = settle.settlingDuration

        let group = CAAnimationGroup()
        group.animations = [fade, settle]
        group.duration = max(fade.duration, settle.duration)
        group.beginTime = CACurrentMediaTime() + 0.06
        group.fillMode = .backwards
        layer.add(group, forKey: "cmux.stage.bloom")
    }
}

/// The card's chrome, handed to Bonsplit through `paneDecorationView`.
struct StageCardChrome: View {
    let layer: PaneDecorationLayer

    @State private var bloomed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var settled: Bool { bloomed || reduceMotion }
    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: StagePaneCardMetrics.cornerRadius, style: .continuous)
    }

    var body: some View {
        Group {
            switch layer {
            case .background:
                ZStack {
                    StageBloomHalo(shape: shape, bloomed: settled)
                    StageCardGlass(shape: shape)
                        .scaleEffect(settled ? 1 : 0.94)
                        .opacity(settled ? 1 : 0)
                        .blur(radius: settled ? 0 : 12)
                    // The rim rides just outside the card, in the margin:
                    // inside it, portal-hosted terminals and web views (which
                    // draw above SwiftUI) would cover it on the content edges.
                    StageCardRim(shape: shape, bloomed: settled)
                        .padding(-StageCardRim.width)
                }
            case .overlay:
                Color.clear
            }
        }
        .onAppear {
            guard !bloomed else { return }
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.55, dampingFraction: 0.68)) {
                    bloomed = true
                }
            }
        }
    }
}

/// The card body: Liquid Glass on macOS 26, material elsewhere. No drop
/// shadow: the margin around the card must stay the exact terminal backdrop
/// color (a shadow darkened it into a visible strip); the rim draws the edge.
private struct StageCardGlass: View {
    let shape: RoundedRectangle

    var body: some View {
        glass
    }

    @ViewBuilder
    private var glass: some View {
#if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            shape
                .fill(Color.clear)
                .glassEffect(.regular, in: shape)
        } else {
            fallback
        }
#else
        fallback
#endif
    }

    private var fallback: some View {
        shape.fill(.ultraThinMaterial)
    }
}

/// Liquid-glass rim: one continuous, slowly shifting gradient around the whole
/// card (tab strip included) that never fades out on any edge. During the
/// bloom it flashes fully iridescent, then settles.
private struct StageCardRim: View {
    static let width: CGFloat = 1

    let shape: RoundedRectangle
    let bloomed: Bool

    var body: some View {
        ZStack {
            shape
                .strokeBorder(
                    AngularGradient(
                        colors: [
                            Color.white.opacity(0.30),
                            Color(red: 0.62, green: 0.78, blue: 1.0).opacity(0.22),
                            Color.white.opacity(0.16),
                            Color(red: 0.86, green: 0.70, blue: 1.0).opacity(0.22),
                            Color.white.opacity(0.24),
                            Color(red: 0.70, green: 0.92, blue: 0.95).opacity(0.20),
                            Color.white.opacity(0.30),
                        ],
                        center: .center,
                        angle: .degrees(-45)
                    ),
                    lineWidth: Self.width
                )
            shape
                .strokeBorder(
                    AngularGradient(
                        colors: StageIridescence.colors,
                        center: .center,
                        angle: .degrees(bloomed ? 200 : 0)
                    ),
                    lineWidth: 1.5
                )
                .opacity(bloomed ? 0 : 0.9)
                .animation(.easeOut(duration: 1.1), value: bloomed)
        }
    }
}

/// The "bubble": an iridescent glow that swells past the card and dissolves.
private struct StageBloomHalo: View {
    let shape: RoundedRectangle
    let bloomed: Bool

    var body: some View {
        shape
            .fill(
                AngularGradient(
                    colors: StageIridescence.colors,
                    center: .center,
                    angle: .degrees(bloomed ? 160 : 0)
                )
            )
            .blur(radius: 18)
            .scaleEffect(bloomed ? 1.05 : 0.9)
            .opacity(bloomed ? 0 : 0.6)
            .animation(.easeOut(duration: 0.95), value: bloomed)
    }
}

private enum StageIridescence {
    static let colors: [Color] = [
        Color(red: 0.45, green: 0.85, blue: 1.0),
        Color(red: 0.62, green: 0.55, blue: 1.0),
        Color(red: 1.0, green: 0.58, blue: 0.86),
        Color(red: 1.0, green: 0.84, blue: 0.62),
        Color(red: 0.45, green: 0.85, blue: 1.0),
    ]
}

/// The window root backdrop, made gradually translucent over the stage side
/// of the window (titlebar and pane margins included) while a stage is live:
/// fully opaque over the home pane, fading to frosted glass toward the stage.
/// Only active with a stage; otherwise it is the plain root backdrop.
struct StageTranslucentRootBackdrop: View {
    @ObservedObject var regionModel: StageRegionModel
    let appearance: WindowAppearanceSnapshot
    /// Off in fullscreen: there is no desktop behind the window, so the
    /// backdrop stays fully opaque everywhere.
    let isEnabled: Bool
    let onTranslucencyChange: (Bool) -> Void

    /// Opacity of the root color where the stage side is most translucent.
    static let farOpacity: Double = 0.42
    /// Opacity just past the stage edge.
    static let nearOpacity: Double = 0.62
    /// Distance before the stage edge where the fade starts.
    static let fadeLead: CGFloat = 48
    /// Distance past the stage edge where `nearOpacity` is reached.
    static let fadeTrail: CGFloat = 64

    var body: some View {
        let region = isEnabled ? regionModel.region : nil
        ZStack {
            if let region {
                StageBackdropBlur()
                    .mask { Self.blurMask(region: region) }
            }
            WindowBackdropLayer(role: .windowRoot, snapshot: appearance)
                .mask { Self.colorMask(region: region) }
        }
        .onAppear { onTranslucencyChange(region != nil) }
        .onChange(of: region != nil) { _, translucent in
            onTranslucencyChange(translucent)
        }
    }

    /// Opaque everywhere except the stage side, which fades toward glass.
    private static func colorMask(region: StageRegionModel.Region?) -> some View {
        Canvas { context, size in
            let full = CGRect(origin: .zero, size: size)
            context.fill(Path(full), with: .color(.black))
            guard let region else { return }
            context.blendMode = .copy
            switch region.placement {
            case .trailing:
                let start = max(0, region.frame.minX - fadeLead)
                let rect = CGRect(x: start, y: 0, width: size.width - start, height: size.height)
                context.fill(Path(rect), with: .linearGradient(
                    Gradient(stops: stops(length: rect.width, edgeOffset: region.frame.minX - start)),
                    startPoint: CGPoint(x: rect.minX, y: 0),
                    endPoint: CGPoint(x: rect.maxX, y: 0)
                ))
            case .top:
                // Fade upward from the stage's bottom edge, over the content
                // columns only (the sidebar keeps its own backdrop).
                let end = min(size.height, region.frame.maxY + fadeLead)
                let rect = CGRect(x: region.frame.minX, y: 0, width: size.width - region.frame.minX, height: end)
                context.fill(Path(rect), with: .linearGradient(
                    Gradient(stops: stops(length: rect.height, edgeOffset: end - region.frame.maxY)),
                    startPoint: CGPoint(x: 0, y: rect.maxY),
                    endPoint: CGPoint(x: 0, y: rect.minY)
                ))
            }
        }
    }

    /// The blur only needs to exist where the color fades.
    private static func blurMask(region: StageRegionModel.Region) -> some View {
        Canvas { context, size in
            let rect: CGRect
            switch region.placement {
            case .trailing:
                let start = max(0, region.frame.minX - fadeLead)
                rect = CGRect(x: start, y: 0, width: size.width - start, height: size.height)
            case .top:
                rect = CGRect(x: region.frame.minX, y: 0, width: size.width - region.frame.minX,
                              height: min(size.height, region.frame.maxY + fadeLead))
            }
            context.fill(Path(rect), with: .color(.black))
        }
    }

    /// Stops along a fade of `length`, whose stage edge sits `edgeOffset` in.
    private static func stops(length: CGFloat, edgeOffset: CGFloat) -> [Gradient.Stop] {
        guard length > 0 else { return [.init(color: .black, location: 0)] }
        let near = min(1, max(0, (edgeOffset + fadeTrail) / length))
        return [
            .init(color: .black, location: 0),
            .init(color: .black.opacity(nearOpacity), location: near),
            .init(color: .black.opacity(farOpacity), location: 1),
        ]
    }
}

/// Behind-window blur for the translucent stage side.
private struct StageBackdropBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
