import SwiftUI

/// A thin rainbow gradient bar whose filled width reflects context-window usage.
///
/// Rendered only when ``ContextUsage`` is available; deferred today (the
/// production provider returns `nil`, so the bottom bar omits this view).
struct RainbowContextBar: View {
    /// Fraction filled, clamped to `0...1`.
    let fraction: Double

    private static let gradient = LinearGradient(
        colors: [.red, .orange, .yellow, .green, .blue, .purple],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                Capsule()
                    .fill(Self.gradient)
                    .frame(width: max(0, proxy.size.width * clamped))
            }
        }
        .frame(width: 80, height: 4)
    }
}
