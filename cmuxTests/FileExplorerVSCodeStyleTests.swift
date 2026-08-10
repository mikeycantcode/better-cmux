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

    // MARK: - Debug style picker

    @Test func pickerShowsVSCodeSelectedWhenNothingWasEverChosen() {
        // @AppStorage can't express "key absent", so the picker stores a sentinel and
        // must resolve it the same way the store does.
        #expect(
            FileExplorerStylePickerModel.selectedStyle(
                storedRawValue: FileExplorerStylePickerModel.unsetSentinel
            ) == .vscode
        )
    }

    @Test func pickerSentinelIsNotAValidStyleRawValue() {
        let sentinel = FileExplorerStylePickerModel.unsetSentinel
        #expect(FileExplorerStyle.allCases.allSatisfy { $0.rawValue != sentinel })
    }

    @Test func pickerHonorsEveryExplicitlyChosenStyle() {
        for style in FileExplorerStyle.allCases {
            #expect(FileExplorerStylePickerModel.selectedStyle(storedRawValue: style.rawValue) == style)
        }
    }

    @Test func pickerAgreesWithStoreResolution() {
        // A fresh install must not show one style selected while rendering another.
        #expect(
            FileExplorerStylePickerModel.selectedStyle(
                storedRawValue: FileExplorerStylePickerModel.unsetSentinel
            ) == FileExplorerStyle.resolve(rawValue: nil)
        )
    }

    // MARK: - Badge metrics

    @Test func statusLetterBadgeWidthScalesWithFontMagnification() {
        #expect(FileExplorerCellView.statusLetterBadgeWidth(magnifiedBy: { $0 }) == 14)
        #expect(FileExplorerCellView.statusLetterBadgeWidth(magnifiedBy: { $0 * 1.5 }) == 21)
        // The real column must track GlobalFontMagnification, since the badge font does.
        #expect(
            FileExplorerCellView.statusLetterBadgeWidth() == GlobalFontMagnification.scaledSize(14)
        )
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

    // MARK: - Header create: name validation

    private func makeTempDirectory() throws -> String {
        let path = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("cmux-explorer-create-\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        return path
    }

    @Test func validationRejectsEmptyAndWhitespaceOnlyNames() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        #expect(FileExplorerStore.validateNewEntryName("", inDirectory: dir) == .failure(.emptyName))
        #expect(FileExplorerStore.validateNewEntryName("   ", inDirectory: dir) == .failure(.emptyName))
    }

    @Test func validationRejectsPathSeparatorsAndDotNames() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        #expect(FileExplorerStore.validateNewEntryName("/", inDirectory: dir) == .failure(.invalidName))
        #expect(FileExplorerStore.validateNewEntryName("a/b", inDirectory: dir) == .failure(.invalidName))
        #expect(FileExplorerStore.validateNewEntryName(".", inDirectory: dir) == .failure(.invalidName))
        #expect(FileExplorerStore.validateNewEntryName("..", inDirectory: dir) == .failure(.invalidName))
    }

    @Test func validationRejectsNamesAlreadyPresentInDirectory() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let existing = (dir as NSString).appendingPathComponent("taken.txt")
        #expect(FileManager.default.createFile(atPath: existing, contents: nil))

        #expect(
            FileExplorerStore.validateNewEntryName("taken.txt", inDirectory: dir)
                == .failure(.alreadyExists("taken.txt"))
        )
        // Existing directories collide too.
        try FileManager.default.createDirectory(
            atPath: (dir as NSString).appendingPathComponent("sub"),
            withIntermediateDirectories: false
        )
        #expect(
            FileExplorerStore.validateNewEntryName("sub", inDirectory: dir) == .failure(.alreadyExists("sub"))
        )
    }

    @Test func validationTrimsAndAcceptsFreeNames() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }

        #expect(FileExplorerStore.validateNewEntryName("  notes.md ", inDirectory: dir) == .success("notes.md"))
        #expect(FileExplorerStore.validateNewEntryName(".hidden", inDirectory: dir) == .success(".hidden"))
    }

    // MARK: - Header create: real FileManager creation

    private func makeLocalStore(root: String) -> FileExplorerStore {
        let store = FileExplorerStore()
        store.provider = LocalFileExplorerProvider()
        store.rootPath = root
        return store
    }

    @Test func createFileWritesAnEmptyFileAndReturnsItsPath() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = makeLocalStore(root: dir)

        let result = store.createFile(named: "hello.swift", inDirectory: dir)
        let created = try #require(try? result.get())
        #expect(created == (dir as NSString).appendingPathComponent("hello.swift"))

        var isDirectory: ObjCBool = true
        #expect(FileManager.default.fileExists(atPath: created, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue == false)
    }

    @Test func createFolderMakesADirectory() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = makeLocalStore(root: dir)

        let created = try #require(try? store.createFolder(named: "Sources", inDirectory: dir).get())
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: created, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test func createRejectsDuplicatesWithoutOverwriting() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = makeLocalStore(root: dir)
        let path = (dir as NSString).appendingPathComponent("keep.txt")
        try "original".write(toFile: path, atomically: true, encoding: .utf8)

        let result = store.createFile(named: "keep.txt", inDirectory: dir)
        switch result {
        case .success:
            Issue.record("expected duplicate name to fail")
        case .failure(let error):
            #expect(error as? FileExplorerCreateError == .alreadyExists("keep.txt"))
        }
        #expect(try String(contentsOfFile: path, encoding: .utf8) == "original")
    }

    @Test func createFailsWhenProviderIsNotLocal() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = FileExplorerStore()
        store.rootPath = dir

        switch store.createFile(named: "nope.txt", inDirectory: dir) {
        case .success:
            Issue.record("expected creation to fail without a local provider")
        case .failure:
            break
        }
        #expect(!FileManager.default.fileExists(atPath: (dir as NSString).appendingPathComponent("nope.txt")))
    }

    // MARK: - Create target directory resolution

    @Test func createTargetIsRootWhenNothingIsSelected() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = makeLocalStore(root: dir)
        #expect(store.createTargetDirectory() == dir)
    }

    @Test func createTargetIsTheSelectedFolderItself() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let sub = (dir as NSString).appendingPathComponent("sub")
        try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: false)
        let store = makeLocalStore(root: dir)
        store.select(node: FileExplorerNode(name: "sub", path: sub, isDirectory: true))
        #expect(store.createTargetDirectory() == sub)
    }

    @Test func createTargetIsTheParentOfASelectedFile() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let sub = (dir as NSString).appendingPathComponent("sub")
        try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: false)
        let file = (sub as NSString).appendingPathComponent("a.txt")
        #expect(FileManager.default.createFile(atPath: file, contents: nil))
        let store = makeLocalStore(root: dir)
        store.select(node: FileExplorerNode(name: "a.txt", path: file, isDirectory: false))
        #expect(store.createTargetDirectory() == sub)
    }

    @Test func createTargetFallsBackToRootWhenSelectionIsStale() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let store = makeLocalStore(root: dir)
        let gone = (dir as NSString).appendingPathComponent("deleted/child.txt")
        store.select(node: FileExplorerNode(name: "child.txt", path: gone, isDirectory: false))
        #expect(store.createTargetDirectory() == dir)
    }

    @Test func createTargetIsNilWithoutARoot() {
        let store = FileExplorerStore()
        #expect(store.createTargetDirectory() == nil)
    }

    // MARK: - Collapse-all signal

    @Test func requestCollapseAllClearsExpandedPathsAndBumpsToken() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let sub = (dir as NSString).appendingPathComponent("sub")
        try FileManager.default.createDirectory(atPath: sub, withIntermediateDirectories: false)
        let store = makeLocalStore(root: dir)
        store.expand(node: FileExplorerNode(name: "sub", path: sub, isDirectory: true))
        #expect(store.expandedPaths.contains(sub))

        let before = store.collapseAllRequestToken
        store.requestCollapseAll()
        #expect(store.expandedPaths.isEmpty)
        #expect(store.collapseAllRequestToken == before &+ 1)
    }

    // MARK: - Reveal after create

    @Test func revealSelectsThePathAndExpandsItsAncestors() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(atPath: dir) }
        let deep = (dir as NSString).appendingPathComponent("a/b")
        try FileManager.default.createDirectory(atPath: deep, withIntermediateDirectories: true)
        let file = (deep as NSString).appendingPathComponent("new.txt")
        #expect(FileManager.default.createFile(atPath: file, contents: nil))
        let store = makeLocalStore(root: dir)

        store.revealAndSelect(path: file)
        #expect(store.selectedPath == file)
        #expect(store.expandedPaths.contains((dir as NSString).appendingPathComponent("a")))
        #expect(store.expandedPaths.contains(deep))
        // The root itself is implicit and never stored as an expanded path.
        #expect(!store.expandedPaths.contains(dir))
    }

    // MARK: - Header section title

    @Test func sectionTitleIsTheUppercasedRootFolderName() {
        #expect(FileExplorerHeaderView.sectionTitle(forDisplayPath: "~/code/my-app") == "MY-APP")
        #expect(FileExplorerHeaderView.sectionTitle(forDisplayPath: "/Users/x/Repo/") == "REPO")
        #expect(FileExplorerHeaderView.sectionTitle(forDisplayPath: "  /tmp/scratch  ") == "SCRATCH")
    }

    @Test func sectionTitleFallsBackToExplorerWithoutARoot() {
        let fallback = String(localized: "sidebar.fileExplorer.title", defaultValue: "Explorer").uppercased()
        #expect(FileExplorerHeaderView.sectionTitle(forDisplayPath: "") == fallback)
        #expect(FileExplorerHeaderView.sectionTitle(forDisplayPath: "   ") == fallback)
        #expect(FileExplorerHeaderView.sectionTitle(forDisplayPath: "/") == fallback)
    }
}
