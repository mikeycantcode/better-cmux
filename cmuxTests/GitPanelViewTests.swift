import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
struct GitPanelViewTests {
    @Test func joinsRepoRelativePathToRoot() {
        #expect(
            GitPanelView.absolutePath(root: "/Users/me/repo", relative: "Sources/App.swift")
                == "/Users/me/repo/Sources/App.swift"
        )
    }

    @Test func doesNotDoubleSlashWhenRootHasTrailingSlash() {
        #expect(
            GitPanelView.absolutePath(root: "/Users/me/repo/", relative: "a.txt")
                == "/Users/me/repo/a.txt"
        )
    }

    @Test func passesThroughAlreadyAbsolutePaths() {
        #expect(GitPanelView.absolutePath(root: "/Users/me/repo", relative: "/etc/hosts") == "/etc/hosts")
    }

    @Test func returnsRelativePathWhenRootIsEmpty() {
        #expect(GitPanelView.absolutePath(root: "", relative: "a.txt") == "a.txt")
    }

    // MARK: - Commit enablement

    @Test func commitEnabledWithStagedFilesAndMessage() {
        #expect(GitPanelView.isCommitEnabled(stagedCount: 1, message: "fix", isBusy: false))
    }

    @Test func commitDisabledWithEmptyMessage() {
        #expect(!GitPanelView.isCommitEnabled(stagedCount: 3, message: "", isBusy: false))
    }

    @Test func commitDisabledWithWhitespaceOnlyMessage() {
        #expect(!GitPanelView.isCommitEnabled(stagedCount: 3, message: "  \n\t ", isBusy: false))
    }

    @Test func commitDisabledWithNothingStaged() {
        #expect(!GitPanelView.isCommitEnabled(stagedCount: 0, message: "fix", isBusy: false))
    }

    @Test func commitDisabledWhileBusy() {
        #expect(!GitPanelView.isCommitEnabled(stagedCount: 1, message: "fix", isBusy: true))
    }

    // MARK: - Push button

    @Test func pushLabelWithUpstreamShowsAheadCount() {
        #expect(GitPanelView.pushButtonLabel(hasUpstream: true, publishCount: 3) == "Push (3)")
    }

    @Test func publishLabelWithoutUpstreamShowsPendingCount() {
        #expect(
            GitPanelView.pushButtonLabel(hasUpstream: false, publishCount: 7) == "Publish Branch (7)"
        )
    }

    @Test func pushDisabledWithUpstreamAndNothingAhead() {
        #expect(!GitPanelView.isPushEnabled(hasUpstream: true, publishCount: 0, isBusy: false))
    }

    @Test func pushEnabledWithUpstreamAndCommitsAhead() {
        #expect(GitPanelView.isPushEnabled(hasUpstream: true, publishCount: 2, isBusy: false))
    }

    @Test func publishEnabledWithoutUpstreamEvenWithZeroCount() {
        #expect(GitPanelView.isPushEnabled(hasUpstream: false, publishCount: 0, isBusy: false))
    }

    @Test func pushDisabledWhileBusy() {
        #expect(!GitPanelView.isPushEnabled(hasUpstream: true, publishCount: 2, isBusy: true))
    }

    // MARK: - Pending confirmation state

    @Test func batchConfirmCarriesEveryEntryAndIsMarkedBatch() {
        let entries = [
            GitStatusEntry(path: "a.swift", originalPath: nil, status: .modified),
            GitStatusEntry(path: "b.swift", originalPath: nil, status: .deleted),
        ]
        let pending = GitPanelView.PendingConfirm.discardEntries(entries)
        #expect(pending.isBatch)
        #expect(pending.entries.map(\.path) == ["a.swift", "b.swift"])
    }

    @Test func singleFileConfirmCarriesOneEntryAndIsNotBatch() {
        let entry = GitStatusEntry(path: "a.swift", originalPath: nil, status: .untracked)
        let pending = GitPanelView.PendingConfirm.discardFile(entry)
        #expect(!pending.isBatch)
        #expect(pending.entries.map(\.path) == ["a.swift"])
        #expect(pending.id != GitPanelView.PendingConfirm.discardEntries([entry]).id)
    }
}
