import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct ClaudeResumeLastTests {
    private struct Item {
        let isClaude: Bool
        let resumable: Bool
        let modified: Date
        let tag: String
    }

    private func date(_ t: TimeInterval) -> Date { Date(timeIntervalSince1970: t) }

    @Test func picksNewestMatching() {
        let items = [
            Item(isClaude: true, resumable: true, modified: date(100), tag: "old"),
            Item(isClaude: true, resumable: true, modified: date(300), tag: "newest"),
            Item(isClaude: true, resumable: true, modified: date(200), tag: "mid"),
        ]
        let picked = ClaudeResumeLast.mostRecent(items, matching: { $0.isClaude && $0.resumable }, modifiedAt: { $0.modified })
        #expect(picked?.tag == "newest")
    }

    @Test func excludesNonMatching() {
        let items = [
            Item(isClaude: false, resumable: true, modified: date(500), tag: "codex-newest"),
            Item(isClaude: true, resumable: false, modified: date(400), tag: "claude-not-resumable"),
            Item(isClaude: true, resumable: true, modified: date(100), tag: "claude-resumable"),
        ]
        let picked = ClaudeResumeLast.mostRecent(items, matching: { $0.isClaude && $0.resumable }, modifiedAt: { $0.modified })
        #expect(picked?.tag == "claude-resumable")
    }

    @Test func nilWhenNoneMatch() {
        let items = [Item(isClaude: false, resumable: true, modified: date(1), tag: "x")]
        let picked = ClaudeResumeLast.mostRecent(items, matching: { $0.isClaude && $0.resumable }, modifiedAt: { $0.modified })
        #expect(picked == nil)
    }
}
