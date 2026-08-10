import AppKit
import XCTest

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

final class FileExplorerVSCodeIconsTests: XCTestCase {
    private func bundledIconExists(_ name: String) -> Bool {
        Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "FileTypeIcons") != nil
    }

    // MARK: - (a) every AUTHORED mapping value resolves to a bundled SVG
    //
    // These assert over the RAW tables on purpose. The production tables run through
    // `validated(_:)` / `validatedFolders(_:)`, which rewrite or drop unbundled values by
    // construction — asserting over those would be tautological and would stay green even if
    // an SVG were deleted from the bundle. Validation remains the runtime degrade-never-break
    // net; these tests assert that the net is never actually needed.

    func testEveryAuthoredExtensionMappingValueIsBundled() {
        let mapping = VSCodeFileIcon.rawTablesForTesting.extensions
        XCTAssertGreaterThan(mapping.count, 120, "extension table should cover the expanded set")
        for (ext, iconName) in mapping {
            XCTAssertTrue(
                bundledIconExists(iconName),
                "extension \"\(ext)\" maps to missing icon \"\(iconName).svg\""
            )
        }
    }

    func testEveryAuthoredFileNameMappingValueIsBundled() {
        let mapping = VSCodeFileIcon.rawTablesForTesting.fileNames
        XCTAssertGreaterThan(mapping.count, 60, "filename table should cover the expanded set")
        for (name, iconName) in mapping {
            XCTAssertTrue(
                bundledIconExists(iconName),
                "file name \"\(name)\" maps to missing icon \"\(iconName).svg\""
            )
        }
    }

    func testEveryAuthoredFolderMappingValueIsBundled() {
        let mapping = VSCodeFileIcon.rawTablesForTesting.folders
        XCTAssertGreaterThan(mapping.count, 20, "folder table should cover the expanded set")
        for (folder, variant) in mapping {
            XCTAssertTrue(
                bundledIconExists(variant.collapsed),
                "folder \"\(folder)\" maps to missing icon \"\(variant.collapsed).svg\""
            )
            XCTAssertTrue(
                bundledIconExists(variant.expanded),
                "folder \"\(folder)\" maps to missing icon \"\(variant.expanded).svg\""
            )
        }
    }

    func testEveryAuthoredPrefixRuleValueIsBundled() {
        for (prefix, iconName) in VSCodeFileIcon.rawTablesForTesting.prefixes {
            XCTAssertTrue(
                bundledIconExists(iconName),
                "prefix \"\(prefix)\" maps to missing icon \"\(iconName).svg\""
            )
        }
    }

    /// Validation must be a no-op today: no authored value should be silently degraded.
    func testValidationNetIsCurrentlyUnused() {
        XCTAssertEqual(
            VSCodeFileIcon.extensionIconNames,
            VSCodeFileIcon.rawTablesForTesting.extensions
        )
        XCTAssertEqual(
            VSCodeFileIcon.fileNameIconNames,
            VSCodeFileIcon.rawTablesForTesting.fileNames
        )
        XCTAssertEqual(
            VSCodeFileIcon.folderIconNames,
            VSCodeFileIcon.rawTablesForTesting.folders
        )
    }

    func testGenericDocumentFallbackIconIsBundled() {
        XCTAssertTrue(bundledIconExists(VSCodeFileIcon.fallbackIconName))
    }

    // MARK: - (b) spot lookups

    func testSpotLookups() {
        let cases: [(String, String)] = [
            ("main.py", "python"),
            ("Dockerfile", "docker"),
            ("dockerfile", "docker"),
            ("App.tsx", "react_ts"),
            ("App.jsx", "react"),
            ("index.ts", "typescript"),
            ("Package.swift", "swift"),
            ("Cargo.toml", "toml"),
            ("go.mod", "go-mod"),
            ("README.md", "readme"),
            ("notes.md", "markdown"),
            ("CMakeLists.txt", "cmake"),
            ("Makefile", "makefile"),
            ("package.json", "nodejs"),
            ("tsconfig.json", "tsconfig"),
            (".gitignore", "git"),
            (".eslintrc.json", "eslint"),
            ("analysis.ipynb", "jupyter"),
            ("logo.png", "image"),
            ("data.csv", "table"),
        ]
        for (fileName, expected) in cases {
            XCTAssertEqual(
                VSCodeFileIcon.iconName(forFileName: fileName),
                expected,
                "unexpected icon for \(fileName)"
            )
        }
    }

    func testFullNameMatchWinsOverExtension() {
        // README.md must resolve to the readme icon, not the generic markdown icon.
        XCTAssertEqual(VSCodeFileIcon.iconName(forFileName: "README.md"), "readme")
        XCTAssertNotEqual(
            VSCodeFileIcon.iconName(forFileName: "README.md"),
            VSCodeFileIcon.iconName(forFileName: "notes.md")
        )
    }

    func testDotEnvPrefixRule() {
        let envIcon = VSCodeFileIcon.iconName(forFileName: ".env")
        XCTAssertEqual(VSCodeFileIcon.iconName(forFileName: ".env.production"), envIcon)
        XCTAssertEqual(VSCodeFileIcon.iconName(forFileName: ".env.local"), envIcon)
    }

    func testEslintAndPrettierPrefixRules() {
        XCTAssertEqual(VSCodeFileIcon.iconName(forFileName: ".eslintrc.cjs"), "eslint")
        XCTAssertEqual(VSCodeFileIcon.iconName(forFileName: ".prettierrc.toml"), "prettier")
    }

    func testUnknownExtensionFallsBackToGenericDocument() {
        XCTAssertEqual(
            VSCodeFileIcon.iconName(forFileName: "mystery.qzxwv"),
            VSCodeFileIcon.fallbackIconName
        )
        XCTAssertEqual(
            VSCodeFileIcon.iconName(forFileName: "NoExtensionHere"),
            VSCodeFileIcon.fallbackIconName
        )
    }

    func testLookupIsCaseInsensitive() {
        XCTAssertEqual(VSCodeFileIcon.iconName(forFileName: "MAIN.PY"), "python")
        XCTAssertEqual(VSCodeFileIcon.iconName(forFileName: "DOCKERFILE"), "docker")
    }

    func testLookupAcceptsPathsAndUsesLastComponent() {
        XCTAssertEqual(VSCodeFileIcon.iconName(forFileName: "/a/b/main.py"), "python")
    }

    // MARK: - (c) folder icons

    func testFolderIconNamesAreDistinctAndBundled() {
        let collapsed = VSCodeFileIcon.folderIconName(expanded: false)
        let expanded = VSCodeFileIcon.folderIconName(expanded: true)
        XCTAssertEqual(collapsed, "folder")
        XCTAssertEqual(expanded, "folder-open")
        XCTAssertNotEqual(collapsed, expanded)
        XCTAssertTrue(bundledIconExists(collapsed))
        XCTAssertTrue(bundledIconExists(expanded))
    }

    func testNamedFolderVariants() {
        XCTAssertEqual(VSCodeFileIcon.folderIconName(forFolderName: "src", expanded: false), "folder-src")
        XCTAssertEqual(VSCodeFileIcon.folderIconName(forFolderName: "src", expanded: true), "folder-src-open")
        XCTAssertEqual(VSCodeFileIcon.folderIconName(forFolderName: "Tests", expanded: false), "folder-test")
        XCTAssertEqual(
            VSCodeFileIcon.folderIconName(forFolderName: "node_modules", expanded: false),
            "folder-node"
        )
        XCTAssertEqual(VSCodeFileIcon.folderIconName(forFolderName: ".git", expanded: false), "folder-git")
        // Unknown folder names fall back to the plain folder icons.
        XCTAssertEqual(
            VSCodeFileIcon.folderIconName(forFolderName: "zzz-unknown", expanded: false),
            "folder"
        )
        XCTAssertEqual(
            VSCodeFileIcon.folderIconName(forFolderName: "zzz-unknown", expanded: true),
            "folder-open"
        )
    }

    // MARK: - loader still works

    func testLoaderProducesImagesForMappedNames() {
        XCTAssertNotNil(VSCodeFileIcon.icon(forFileName: "Main.swift", size: 16))
        XCTAssertNotNil(VSCodeFileIcon.icon(forFileName: "mystery.qzxwv", size: 16))
        XCTAssertNotNil(VSCodeFileIcon.folderIcon(size: 16))
        XCTAssertNotNil(VSCodeFileIcon.folderIcon(forFolderName: "src", expanded: true, size: 16))
    }

    func testLicenseIsBundledAlongsideIcons() {
        XCTAssertNotNil(
            Bundle.main.url(
                forResource: "LICENSE-material-icon-theme",
                withExtension: "md",
                subdirectory: "FileTypeIcons"
            )
        )
    }
}
