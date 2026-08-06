import CmuxCommandPalette
import Foundation
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class RightSidebarCommandPaletteTests: XCTestCase {
    func testCommandPaletteIncludesFilesAndGitTabs() throws {
        let contributions = ContentView.commandPaletteRightSidebarTabCommandContributions()
        let contributionsByID = Dictionary(uniqueKeysWithValues: contributions.map { ($0.commandId, $0) })
        let context = CommandPaletteContextSnapshot()

        for tab in FilesGitTab.allCases {
            let commandID = ContentView.commandPaletteRightSidebarTabCommandID(tab)
            let contribution = try XCTUnwrap(
                contributionsByID[commandID],
                "Expected command palette contribution for \(tab.rawValue)"
            )

            XCTAssertEqual(
                contribution.title(context),
                ContentView.commandPaletteRightSidebarTabAction(tab).label
            )
            XCTAssertEqual(
                contribution.subtitle(context),
                String(localized: "command.rightSidebarMode.subtitle", defaultValue: "Right Sidebar")
            )
            XCTAssertTrue(contribution.keywords.contains("right"))
            XCTAssertTrue(contribution.keywords.contains("sidebar"))
            XCTAssertTrue(contribution.keywords.contains(tab.rawValue))
            XCTAssertTrue(contribution.when(context))
            XCTAssertTrue(contribution.enablement(context))
        }

        XCTAssertEqual(contributions.count, 2)
    }

    func testRetiredRightSidebarModeCommandsAreGone() {
        for commandID in [
            "palette.showRightSidebarFind",
            "palette.showRightSidebarSessions",
            "palette.showRightSidebarFeed",
            "palette.showRightSidebarDock",
            "palette.showRightSidebarCustomSidebar",
            "palette.openFindPane",
            "palette.openVaultPane",
        ] {
            XCTAssertNil(
                ContentView.commandPaletteRightSidebarTabCommandContributions()
                    .first(where: { $0.commandId == commandID }),
                "\(commandID) should no longer be contributed"
            )
            XCTAssertNil(
                ContentView.commandPaletteShortcutAction(forCommandID: commandID),
                "\(commandID) should no longer map to a shortcut action"
            )
        }
    }

    func testCommandPaletteRightSidebarActionsUseTabShortcutActions() {
        for tab in FilesGitTab.allCases {
            XCTAssertEqual(
                ContentView.commandPaletteShortcutAction(
                    forCommandID: ContentView.commandPaletteRightSidebarTabCommandID(tab)
                ),
                ContentView.commandPaletteRightSidebarTabAction(tab)
            )
        }
    }

    func testCommandPaletteUnreadActionsUseConfigurableShortcutActions() {
        XCTAssertEqual(
            ContentView.commandPaletteShortcutAction(forCommandID: "palette.toggleUnread"),
            .toggleUnread
        )
        XCTAssertEqual(
            ContentView.commandPaletteShortcutAction(forCommandID: "palette.markOldestUnreadAndJumpNext"),
            .markOldestUnreadAndJumpNext
        )
    }
}
