import SwiftUI

/// The VSCode-style bottom status bar, rendered from an immutable
/// ``BottomBarSnapshot``. Lives in the content region (right of the left
/// sidebar). The rainbow context bar + usage text render only when the snapshot
/// carries ``ContextUsage`` (deferred today).
struct CmuxBottomBar: View {
    let snapshot: BottomBarSnapshot
    var backgroundColor: Color? = nil

    static let height: CGFloat = 24

    var body: some View {
        HStack(spacing: 12) {
            if let branch = snapshot.branch, !branch.isEmpty {
                Label {
                    Text(branch + (snapshot.isDirty ? "*" : ""))
                        .lineLimit(1)
                } icon: {
                    Image(systemName: "arrow.triangle.branch")
                }
                .labelStyle(.titleAndIcon)
            }

            if !snapshot.staged.isEmpty {
                HStack(spacing: 6) {
                    Text("\u{2295}\(snapshot.staged.files)")
                    Text("+\(snapshot.staged.additions)").foregroundColor(.green)
                    Text("\u{2212}\(snapshot.staged.deletions)").foregroundColor(.red)
                }
                .accessibilityLabel(
                    String(
                        localized: "bottomBar.uncommitted.accessibility",
                        defaultValue: "Uncommitted changes"
                    )
                )
            }

            Spacer(minLength: 8)

            if let usage = snapshot.contextUsage {
                RainbowContextBar(fraction: usage.contextFraction)
                if let limitText = usage.limitText, !limitText.isEmpty {
                    Text(limitText).lineLimit(1)
                }
            }

            if !snapshot.editorDisplayName.isEmpty {
                Label {
                    Text(snapshot.editorDisplayName)
                } icon: {
                    Image(systemName: "pencil")
                }
                .labelStyle(.titleAndIcon)
            }

            if !snapshot.appVersion.isEmpty {
                Text("v\(snapshot.appVersion)")
                    .foregroundColor(.secondary)
            }
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity)
        .background {
            if let backgroundColor {
                backgroundColor
            } else {
                Rectangle().fill(.bar)
            }
        }
        .overlay(alignment: .top) {
            Divider().opacity(0.35)
        }
    }
}
