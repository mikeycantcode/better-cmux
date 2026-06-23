import CmuxEditPreview
import CMUXAgentLaunch
import SwiftUI

/// The body for an ``EditReviewPanel``: a header, the Monaco diff, and the decision toolbar.
struct EditReviewPanelView: View {
    @ObservedObject var panel: EditReviewPanel
    let appearance: PanelAppearance

    private var isDark: Bool {
        !appearance.backgroundColor.isLightColor
    }

    private var language: String {
        MonacoLanguageMap.languageId(forPath: panel.diff.filePath)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            MonacoDiffView(
                controller: panel.monacoController,
                original: panel.diff.originalText,
                modified: panel.diff.modifiedText,
                language: language,
                isDark: isDark
            )
            toolbar
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(panel.displayTitle)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
            if panel.diff.isNewFile {
                Text(String(localized: "editReview.newFile", defaultValue: "new file"))
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Spacer()
            Button(String(localized: "editReview.reject", defaultValue: "Reject")) {
                panel.onDecision?(.deny)
            }
            .keyboardShortcut(.cancelAction)
            Button(String(localized: "editReview.always", defaultValue: "Always Allow Edits")) {
                panel.onDecision?(.always)
            }
            Button(String(localized: "editReview.accept", defaultValue: "Accept")) {
                panel.onDecision?(.once)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
