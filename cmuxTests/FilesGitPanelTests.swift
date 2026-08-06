import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
struct FilesGitPanelTests {
    @Test func abbreviatesHomePaths() {
        let home = NSHomeDirectory()
        #expect(FilesGitPanelView.abbreviatedPath(home) == "~")
        #expect(FilesGitPanelView.abbreviatedPath(home + "/x/y") == "~/x/y")
        #expect(FilesGitPanelView.abbreviatedPath("/tmp/z") == "/tmp/z")
    }

    @Test func tabRawValuesRoundTrip() {
        #expect(FilesGitTab(rawValue: "files") == .files)
        #expect(FilesGitTab(rawValue: "git") == .git)
        #expect(FilesGitTab(rawValue: "bogus") == nil)
    }
}
