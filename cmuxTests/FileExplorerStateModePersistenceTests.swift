import Foundation
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// The right sidebar used to persist a `RightSidebarMode` raw value under
/// `rightSidebar.mode`. Files|Git replaced modes; these tests pin the migration
/// so a stored dead mode can never revive a removed surface.
final class FileExplorerStateModePersistenceTests: XCTestCase {
    private let legacyModeKey = "rightSidebar.mode"
    private let filesGitTabKey = FilesGitTab.defaultsKey

    func testDeadStoredModeIsDroppedAndFallsBackToFiles() {
        for deadMode in ["find", "sessions", "feed", "dock", "custom-sidebar", "totally-unknown"] {
            withSavedRightSidebarDefaults {
                let defaults = UserDefaults.standard
                defaults.set(deadMode, forKey: legacyModeKey)
                defaults.removeObject(forKey: filesGitTabKey)

                _ = FileExplorerState()

                XCTAssertNil(
                    defaults.object(forKey: legacyModeKey),
                    "Legacy mode key should be dropped for '\(deadMode)'"
                )
                XCTAssertEqual(FilesGitTab.current(), .files, "'\(deadMode)' must fall back to Files")
            }
        }
    }

    func testMigrationPreservesAnAlreadyChosenFilesGitTab() {
        withSavedRightSidebarDefaults {
            let defaults = UserDefaults.standard
            defaults.set("dock", forKey: legacyModeKey)
            FilesGitTab.select(.git)

            _ = FileExplorerState()

            XCTAssertNil(defaults.object(forKey: legacyModeKey))
            XCTAssertEqual(FilesGitTab.current(), .git)
        }
    }

    func testMigrationIsANoOpWhenNoLegacyValueExists() {
        withSavedRightSidebarDefaults {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: legacyModeKey)
            defaults.removeObject(forKey: filesGitTabKey)

            _ = FileExplorerState()

            XCTAssertNil(defaults.object(forKey: legacyModeKey))
            XCTAssertNil(defaults.object(forKey: filesGitTabKey))
            XCTAssertEqual(FilesGitTab.current(), .files)
        }
    }

    func testCLIArgumentNormalizerAcceptsOnlyFilesAndGit() {
        XCTAssertEqual(FilesGitTab.from(cliArgument: "files"), .files)
        XCTAssertEqual(FilesGitTab.from(cliArgument: " Git "), .git)
        XCTAssertNil(FilesGitTab.from(cliArgument: "find"))
        XCTAssertNil(FilesGitTab.from(cliArgument: "vault"))
        XCTAssertNil(FilesGitTab.from(cliArgument: "sessions"))
        XCTAssertNil(FilesGitTab.from(cliArgument: "feed"))
        XCTAssertNil(FilesGitTab.from(cliArgument: "dock"))
        XCTAssertNil(FilesGitTab.from(cliArgument: "custom-sidebar"))
        XCTAssertNil(FilesGitTab.from(cliArgument: "unknown"))
    }

    private func withSavedRightSidebarDefaults(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let previousMode = defaults.object(forKey: legacyModeKey)
        let previousTab = defaults.object(forKey: filesGitTabKey)
        defer {
            restore(previousMode, forKey: legacyModeKey)
            restore(previousTab, forKey: filesGitTabKey)
        }
        body()
    }

    private func restore(_ value: Any?, forKey key: String) {
        let defaults = UserDefaults.standard
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
