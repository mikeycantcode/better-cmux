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

    // MARK: - (a) every mapping value resolves to a bundled SVG

    func testEveryExtensionMappingValueResolvesToBundledSVG() {
        let mapping = VSCodeFileIcon.extensionIconNames
        XCTAssertGreaterThan(mapping.count, 120, "extension table should cover the expanded set")
        for (ext, iconName) in mapping {
            XCTAssertTrue(
                bundledIconExists(iconName),
                "extension \"\(ext)\" maps to missing icon \"\(iconName).svg\""
            )
        }
    }

    func testEveryFileNameMappingValueResolvesToBundledSVG() {
        let mapping = VSCodeFileIcon.fileNameIconNames
        XCTAssertGreaterThan(mapping.count, 60, "filename table should cover the expanded set")
        for (name, iconName) in mapping {
            XCTAssertTrue(
                bundledIconExists(iconName),
                "file name \"\(name)\" maps to missing icon \"\(iconName).svg\""
            )
        }
    }

    func testEveryFolderMappingValueResolvesToBundledSVG() {
        for (folder, variant) in VSCodeFileIcon.folderIconNames {
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
        XCTAssertNotNil(VSCodeFileIcon.icon(forExtension: "swift", size: 16))
        XCTAssertNotNil(VSCodeFileIcon.folderIcon(size: 16))
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
