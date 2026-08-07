import AppKit
import CmuxFoundation
import Foundation
import SwiftUI

/// Shared visual constants for the herdr left sidebar.
///
/// Typography is exposed as size/weight/design constants only — never as a
/// prebuilt `Font`. Consumers must apply the magnification-aware
/// `.cmuxFont(size:weight:design:)` *modifier*, so every herdr label honors the
/// global font magnification setting.
enum HerdrSidebarStyle {

    // MARK: - Palette

    static func color(for status: AgentSidebarStatus) -> Color {
        switch status {
        case .blocked: return Color(red: 0.94, green: 0.55, blue: 0.62)
        case .working: return Color(red: 0.95, green: 0.85, blue: 0.55)
        case .idle: return Color(red: 0.60, green: 0.80, blue: 0.55)
        case .unknown: return Color(nsColor: .tertiaryLabelColor)
        }
    }

    /// Dim dot color used when a workspace has no agents, or an unknown rollup.
    static let dimColor = Color(nsColor: .tertiaryLabelColor)

    // MARK: - Status words

    static func statusWord(for status: AgentSidebarStatus) -> String {
        switch status {
        case .blocked:
            return String(localized: "herdr.status.blocked", defaultValue: "blocked")
        case .working:
            return String(localized: "herdr.status.working", defaultValue: "working")
        case .idle:
            return String(localized: "herdr.status.idle", defaultValue: "idle")
        case .unknown:
            return String(localized: "herdr.status.unknown", defaultValue: "unknown")
        }
    }

    // MARK: - Typography

    static let headerFontSize: CGFloat = 13
    static let headerFontWeight: Font.Weight = .semibold
    static let rowFontSize: CGFloat = 13
    static let rowFontWeight: Font.Weight = .semibold
    static let subFontSize: CGFloat = 12
    static let subFontWeight: Font.Weight = .regular
    /// Shared font design for every herdr sidebar label.
    static let fontDesign: Font.Design = .monospaced

    // MARK: - Metrics

    static let rowHeight: CGFloat = 28
    static let horizontalPadding: CGFloat = 8
    static let glyphSize: CGFloat = 12
    static let glyphSpacing: CGFloat = 6
    static let selectionCornerRadius: CGFloat = 5
    static let selectionOpacity: Double = 0.08
}

// MARK: - Status glyph

/// Per-status status indicator. The animated `working` variant is the *only*
/// branch that installs a `TimelineView`; every other status renders statically
/// with zero timers.
struct AgentStatusGlyph: View {
    let status: AgentSidebarStatus
    let size: CGFloat

    /// Distinct phase offsets so the four working dots shimmer out of sync.
    private static let workingPhases: [Double] = [0.0, 1.1, 2.3, 3.7]

    var body: some View {
        switch status {
        case .blocked:
            blockedGlyph
        case .working:
            // Animation is confined to this branch only.
            TimelineView(.animation(minimumInterval: 0.15)) { context in
                workingGlyph(time: context.date.timeIntervalSinceReferenceDate)
            }
        case .idle:
            idleGlyph
        case .unknown:
            unknownGlyph
        }
    }

    private var color: Color { HerdrSidebarStyle.color(for: status) }

    private var blockedGlyph: some View {
        ZStack {
            Circle()
                .strokeBorder(color, lineWidth: max(1, size * 0.12))
            Circle()
                .fill(color)
                .frame(width: size * 0.45, height: size * 0.45)
        }
        .frame(width: size, height: size)
    }

    private func workingGlyph(time: TimeInterval) -> some View {
        let dot = max(2, size * 0.28)
        let gap = size - dot
        return ZStack {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .fill(color)
                    .frame(width: dot, height: dot)
                    .opacity(Self.dotOpacity(time: time, index: index))
                    .offset(
                        x: (index % 2 == 0 ? -gap : gap) / 2,
                        y: (index < 2 ? -gap : gap) / 2
                    )
            }
        }
        .frame(width: size, height: size)
    }

    /// Pure function of time so it is deterministic and side-effect free.
    static func dotOpacity(time: TimeInterval, index: Int) -> Double {
        let phase = workingPhases[index % workingPhases.count]
        return 0.35 + 0.65 * abs(sin(time * 1.7 + phase))
    }

    private var idleGlyph: some View {
        Image(systemName: "checkmark")
            .font(.system(size: size * 0.85, weight: .bold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
    }

    private var unknownGlyph: some View {
        Circle()
            .strokeBorder(color, lineWidth: max(1, size * 0.12))
            .frame(width: size, height: size)
    }
}

// MARK: - Selection background

private struct HerdrSelectionBackground: View {
    let isSelected: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: HerdrSidebarStyle.selectionCornerRadius, style: .continuous)
            .fill(
                isSelected
                    ? Color.primary.opacity(HerdrSidebarStyle.selectionOpacity)
                    : Color.clear
            )
    }
}

// MARK: - Spaces row

/// Pure value view: holds no store reference (snapshot-boundary rule).
struct SpacesRowView: View, Equatable {
    let title: String
    /// `nil` means the workspace has no agents → dim dot.
    let rollup: AgentSidebarStatus?
    let isSelected: Bool
    let onSelect: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title
            && lhs.rollup == rhs.rollup
            && lhs.isSelected == rhs.isSelected
    }

    private var dotColor: Color {
        guard let rollup, rollup != .unknown else { return HerdrSidebarStyle.dimColor }
        return HerdrSidebarStyle.color(for: rollup)
    }

    var body: some View {
        HStack(spacing: HerdrSidebarStyle.glyphSpacing) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)
            Text(title)
                .cmuxFont(
                    size: HerdrSidebarStyle.rowFontSize,
                    weight: HerdrSidebarStyle.rowFontWeight,
                    design: HerdrSidebarStyle.fontDesign
                )
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, HerdrSidebarStyle.horizontalPadding)
        .frame(height: HerdrSidebarStyle.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HerdrSelectionBackground(isSelected: isSelected))
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Agent row

/// Pure value view: holds no store reference (snapshot-boundary rule).
struct AgentRowView: View, Equatable {
    let snapshot: AgentRowSnapshot
    let isSelected: Bool
    let onActivate: () -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.snapshot == rhs.snapshot && lhs.isSelected == rhs.isSelected
    }

    private var statusWord: String { HerdrSidebarStyle.statusWord(for: snapshot.status) }

    /// Combined VoiceOver label: title, status word, agent name.
    var accessibilityLabelText: String {
        "\(snapshot.workspaceTitle), \(statusWord), \(snapshot.agentName)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: HerdrSidebarStyle.glyphSpacing) {
                AgentStatusGlyph(status: snapshot.status, size: HerdrSidebarStyle.glyphSize)
                titleLine
                Spacer(minLength: 0)
            }
            HStack(spacing: 4) {
                Text(statusWord)
                    .foregroundStyle(HerdrSidebarStyle.color(for: snapshot.status))
                Text(verbatim: "·")
                Text(snapshot.agentName)
                Spacer(minLength: 0)
            }
            .cmuxFont(
                size: HerdrSidebarStyle.subFontSize,
                weight: HerdrSidebarStyle.subFontWeight,
                design: HerdrSidebarStyle.fontDesign
            )
            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            .lineLimit(1)
            .padding(.leading, HerdrSidebarStyle.glyphSize + HerdrSidebarStyle.glyphSpacing)
        }
        .padding(.horizontal, HerdrSidebarStyle.horizontalPadding)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HerdrSelectionBackground(isSelected: isSelected))
        .contentShape(Rectangle())
        .onTapGesture(perform: onActivate)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabelText))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var titleLine: some View {
        HStack(spacing: 0) {
            Text(snapshot.workspaceTitle)
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
            if snapshot.workspaceAgentCount > 1 {
                Text(verbatim: " · \(snapshot.workspaceAgentCount)")
                    .foregroundStyle(Color.secondary)
            }
        }
        .cmuxFont(
            size: HerdrSidebarStyle.rowFontSize,
            weight: HerdrSidebarStyle.rowFontWeight,
            design: HerdrSidebarStyle.fontDesign
        )
    }
}
