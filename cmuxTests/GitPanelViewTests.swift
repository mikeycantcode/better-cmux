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
}
