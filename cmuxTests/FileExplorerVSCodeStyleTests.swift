import AppKit
import CmuxFoundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite struct FileExplorerVSCodeStyleTests {

    // MARK: - Metrics

    @Test func vscodeStyleMetricsMatchVSCodeExplorer() {
        let style = FileExplorerStyle.vscode
        #expect(style.rowHeight == GlobalFontMagnification.scaledSize(22))
        #expect(style.indentation == 8)
        #expect(style.iconSize == 16)
        #expect(style.iconToTextSpacing == 6)
        #expect(style.selectionInset == 0)
        #expect(style.selectionRadius == 0)
        #expect(style.nameFont.pointSize == GlobalFontMagnification.systemFont(ofSize: 13, weight: .regular).pointSize)
        #expect(style.usesBorderSelection == false)
    }

    @Test func otherStyleMetricsAreUnchanged() {
        // Regression guard: adding .vscode must not perturb the existing styles.
        #expect(FileExplorerStyle.codika.rowHeight == GlobalFontMagnification.scaledSize(34))
        #expect(FileExplorerStyle.codika.indentation == 16)
        #expect(FileExplorerStyle.vscodeIcons.rowHeight == GlobalFontMagnification.scaledSize(24))
        #expect(FileExplorerStyle.vscodeIcons.selectionInset == 4)
        #expect(FileExplorerStyle.vscodeIcons.selectionRadius == 5)
        #expect(FileExplorerStyle.highDensity.rowHeight == GlobalFontMagnification.scaledSize(20))
    }

    // MARK: - Git colors

    @Test func vscodeGitColorsUseVSCodeHexes() {
        let style = FileExplorerStyle.vscode
        #expect(style.gitColor(for: .modified).fileExplorerHexString == "E2C08D")
        #expect(style.gitColor(for: .untracked).fileExplorerHexString == "73C991")
        #expect(style.gitColor(for: .added).fileExplorerHexString == "81B88B")
        #expect(style.gitColor(for: .deleted).fileExplorerHexString == "C74E39")
        // git renames read as "new path appeared", same tint VS Code gives untracked.
        #expect(style.gitColor(for: .renamed).fileExplorerHexString == "73C991")
    }

    @Test func vscodeConflictColorMatchesVSCode() {
        #expect(FileExplorerStyle.vscodeConflictColor.fileExplorerHexString == "E4676B")
    }

    @Test func vscodeIgnoredAlphaIsFourTenths() {
        #expect(FileExplorerStyle.ignoredAlpha == 0.4)
    }

    @Test func otherStyleGitColorsAreUnchanged() {
        #expect(FileExplorerStyle.codika.gitColor(for: .modified) == .systemYellow)
        #expect(FileExplorerStyle.vscodeIcons.gitColor(for: .added) == .systemGreen)
        #expect(FileExplorerStyle.liquidGlass.gitColor(for: .modified) == .systemOrange)
    }

    // MARK: - Default migration

    @Test func unsetDefaultsKeyResolvesToVSCode() {
        #expect(FileExplorerStyle.resolve(rawValue: nil) == .vscode)
    }

    @Test func explicitlyChosenStyleIsHonored() {
        #expect(FileExplorerStyle.resolve(rawValue: FileExplorerStyle.codika.rawValue) == .codika)
        #expect(FileExplorerStyle.resolve(rawValue: FileExplorerStyle.liquidGlass.rawValue) == .liquidGlass)
        #expect(FileExplorerStyle.resolve(rawValue: FileExplorerStyle.vscode.rawValue) == .vscode)
    }

    @Test func unknownRawValueFallsBackToVSCode() {
        #expect(FileExplorerStyle.resolve(rawValue: 9999) == .vscode)
    }

    // MARK: - Cached current

    @Test func cachedCurrentTracksDefaultsChanges() {
        let key = FileExplorerStyle.defaultsKey
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) } else { defaults.removeObject(forKey: key) }
            FileExplorerStyle.invalidateCachedCurrent()
        }

        defaults.set(FileExplorerStyle.codika.rawValue, forKey: key)
        FileExplorerStyle.invalidateCachedCurrent()
        #expect(FileExplorerStyle.cachedCurrent == .codika)

        defaults.set(FileExplorerStyle.vscode.rawValue, forKey: key)
        #expect(FileExplorerStyle.cachedCurrent == .vscode)

        defaults.removeObject(forKey: key)
        #expect(FileExplorerStyle.cachedCurrent == .vscode)
    }

    @Test func cachedCurrentEqualsCurrent() {
        FileExplorerStyle.invalidateCachedCurrent()
        #expect(FileExplorerStyle.cachedCurrent == FileExplorerStyle.current)
    }

    // MARK: - Decoration building

    @Test func vscodeFileWithStatusGetsStatusLetterBadge() {
        let decoration = FileRowDecoration.make(
            style: .vscode,
            isDirectory: false,
            gitStatus: .modified,
            directoryHasChanges: false,
            isIgnored: false
        )
        #expect(decoration.badge == .statusLetter("M"))
        #expect(decoration.tint?.fileExplorerHexString == "E2C08D")
        #expect(decoration.alpha == 1.0)
    }

    @Test func vscodeStatusLetterCoversEveryStatus() {
        let expected: [GitEntryStatus: String] = [
            .modified: "M", .added: "A", .deleted: "D", .renamed: "R", .untracked: "U",
        ]
        for (status, letter) in expected {
            let decoration = FileRowDecoration.make(
                style: .vscode, isDirectory: false, gitStatus: status,
                directoryHasChanges: false, isIgnored: false
            )
            #expect(decoration.badge == .statusLetter(letter))
        }
    }

    @Test func vscodeDirtyFolderGetsDotNotStatusLetter() {
        let decoration = FileRowDecoration.make(
            style: .vscode,
            isDirectory: true,
            gitStatus: nil,
            directoryHasChanges: true,
            isIgnored: false
        )
        #expect(decoration.badge == .folderDot)
        #expect(decoration.tint?.fileExplorerHexString == "E2C08D")
    }

    @Test func vscodeCleanFolderHasNoBadgeOrTint() {
        let decoration = FileRowDecoration.make(
            style: .vscode, isDirectory: true, gitStatus: nil,
            directoryHasChanges: false, isIgnored: false
        )
        #expect(decoration.badge == .none)
        #expect(decoration.tint == nil)
    }

    @Test func ignoredEntriesDimToFourTenths() {
        let decoration = FileRowDecoration.make(
            style: .vscode, isDirectory: false, gitStatus: nil,
            directoryHasChanges: false, isIgnored: true
        )
        #expect(decoration.alpha == 0.4)
    }

    @Test func nonVSCodeStylesGetNoBadgeAndIgnoreDirectoryChanges() {
        // The Task-2 temporary "dirty directory tints modified" fallback is gone:
        // non-.vscode styles decorate exactly as they did before it landed.
        for style in FileExplorerStyle.allCases where style != .vscode {
            let folder = FileRowDecoration.make(
                style: style, isDirectory: true, gitStatus: nil,
                directoryHasChanges: true, isIgnored: false
            )
            #expect(folder.badge == .none)
            #expect(folder.tint == nil)

            let file = FileRowDecoration.make(
                style: style, isDirectory: false, gitStatus: .modified,
                directoryHasChanges: false, isIgnored: false
            )
            #expect(file.badge == .none)
            #expect(file.tint == style.gitColor(for: .modified))
        }
    }

    // MARK: - Chevron

    @Test func chevronSymbolFollowsExpansion() {
        #expect(FileExplorerStyle.chevronSymbolName(expanded: false) == "chevron.right")
        #expect(FileExplorerStyle.chevronSymbolName(expanded: true) == "chevron.down")
    }

    @Test func stockDisclosureTriangleIsHiddenOnlyForVSCode() {
        #expect(FileExplorerStyle.vscode.usesCustomChevron == true)
        for style in FileExplorerStyle.allCases where style != .vscode {
            #expect(style.usesCustomChevron == false)
        }
    }

    // MARK: - Folder icon expansion wiring

    @Test func expandedFolderUsesOpenFolderIcon() {
        #expect(VSCodeFileIcon.folderIconName(expanded: true) == "folder-open")
        #expect(VSCodeFileIcon.folderIconName(expanded: false) == "folder")
        // Named variants must also flip with expansion.
        let collapsed = VSCodeFileIcon.folderIconName(forFolderName: "src", expanded: false)
        let expanded = VSCodeFileIcon.folderIconName(forFolderName: "src", expanded: true)
        #expect(collapsed != expanded)
    }

    // MARK: - Hex helper

    @Test func hexRoundTrips() {
        #expect(NSColor.fileExplorerHex(0xE2C08D).fileExplorerHexString == "E2C08D")
        #expect(NSColor.fileExplorerHex(0x000000).fileExplorerHexString == "000000")
        #expect(NSColor.fileExplorerHex(0xFFFFFF).fileExplorerHexString == "FFFFFF")
    }
}
