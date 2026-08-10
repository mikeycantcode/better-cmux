import AppKit

/// Maps file names, extensions and folder names to VS Code-style icons sourced from the
/// MIT-licensed Material Icon Theme (PKief/vscode-material-icon-theme).
///
/// SVGs are bundled in `Resources/FileTypeIcons/` and loaded at runtime. The lookup tables
/// below are validated at table-build time: any entry whose SVG is not actually bundled is
/// rewritten to `fallbackIconName`, so a mapping can never point at a missing resource.
enum VSCodeFileIcon {
    /// Generic icon used whenever nothing more specific is known (or bundled).
    static let fallbackIconName = "document"

    /// Collapsed/expanded icon pair for a folder.
    struct FolderIconVariant: Equatable {
        let collapsed: String
        let expanded: String
    }

    static let defaultFolderIconName = "folder"
    static let defaultFolderOpenIconName = "folder-open"

    /// Raw, unvalidated tables. Exposed so tests can assert that every authored mapping value
    /// is genuinely bundled — asserting over the validated tables below would be tautological,
    /// since `validated(_:)` rewrites unbundled values by construction.
    static var rawTablesForTesting: (
        extensions: [String: String],
        fileNames: [String: String],
        folders: [String: FolderIconVariant],
        prefixes: [String: String]
    ) {
        (rawExtensionIconNames, rawFileNameIconNames, rawFolderIconNames, rawPrefixIconNames)
    }

    /// Extension (without dot, lowercased) -> icon filename (without .svg)
    static let extensionIconNames: [String: String] = validated(rawExtensionIconNames)

    /// Full file name (lowercased) -> icon filename (without .svg)
    static let fileNameIconNames: [String: String] = validated(rawFileNameIconNames)

    /// Folder name (lowercased) -> collapsed/expanded icon pair.
    static let folderIconNames: [String: FolderIconVariant] = validatedFolders(rawFolderIconNames)

    // MARK: - Pure lookups

    /// Resolves the icon name for a file name (or path; only the last component is used).
    /// Never returns a name that is not bundled.
    static func iconName(forFileName name: String) -> String {
        let component = String(name.split(separator: "/").last ?? Substring(name)).lowercased()
        guard !component.isEmpty else { return fallbackIconName }

        if let exact = fileNameIconNames[component] {
            return exact
        }
        if let prefixed = prefixRuleIconName(for: component) {
            return prefixed
        }

        // Longest-suffix extension match, so `foo.tar.gz` and `foo.d.ts` behave sensibly.
        let parts = component.split(separator: ".", omittingEmptySubsequences: false)
        if parts.count > 1 {
            for start in 1..<parts.count {
                let candidate = parts[start...].joined(separator: ".")
                if let icon = extensionIconNames[candidate] {
                    return icon
                }
            }
        }
        return fallbackIconName
    }

    /// Plain folder icon name.
    static func folderIconName(expanded: Bool) -> String {
        expanded ? defaultFolderOpenIconName : defaultFolderIconName
    }

    /// Per-name folder icon, falling back to the plain folder icons.
    static func folderIconName(forFolderName name: String, expanded: Bool) -> String {
        let component = String(name.split(separator: "/").last ?? Substring(name)).lowercased()
        guard let variant = folderIconNames[component] else {
            return folderIconName(expanded: expanded)
        }
        return expanded ? variant.expanded : variant.collapsed
    }

    /// Files whose names start with a known prefix (`.env.local`, `.eslintrc.cjs`, ...).
    private static func prefixRuleIconName(for component: String) -> String? {
        for (prefix, icon) in prefixRules where component.hasPrefix(prefix) {
            return icon
        }
        return nil
    }

    /// Ordered longest-first so more specific prefixes win.
    private static let prefixRules: [(String, String)] = {
        let raw = [".env.", ".eslintrc", ".prettierrc", "docker-compose.", "compose."]
        return raw
            .sorted { $0.count > $1.count }
            .map { ($0, resolvedIconName(rawPrefixIconNames[$0] ?? fallbackIconName)) }
    }()

    private static let rawPrefixIconNames: [String: String] = [
        ".env.": "tune",
        ".eslintrc": "eslint",
        ".prettierrc": "prettier",
        "docker-compose.": "docker",
        "compose.": "docker",
    ]

    // MARK: - Table validation

    private static func iconIsBundled(_ name: String) -> Bool {
        Bundle.main.url(forResource: name, withExtension: "svg", subdirectory: "FileTypeIcons") != nil
    }

    private static func resolvedIconName(_ name: String) -> String {
        iconIsBundled(name) ? name : fallbackIconName
    }

    private static func validated(_ table: [String: String]) -> [String: String] {
        table.mapValues(resolvedIconName)
    }

    private static func validatedFolders(_ table: [String: FolderIconVariant]) -> [String: FolderIconVariant] {
        table.compactMapValues { variant in
            guard iconIsBundled(variant.collapsed), iconIsBundled(variant.expanded) else { return nil }
            return variant
        }
    }

    // MARK: - Image loading

    /// Cache of loaded icon images keyed by "name@size".
    private static var iconCache: [String: NSImage] = [:]

    /// Returns the icon for a full file name. Always resolves (falls back to the generic document icon).
    static func icon(forFileName name: String, size: CGFloat = 16) -> NSImage? {
        loadIcon(named: iconName(forFileName: name), size: size)
    }

    /// Returns an icon for a folder.
    static func folderIcon(size: CGFloat = 16) -> NSImage? {
        loadIcon(named: folderIconName(expanded: false), size: size)
    }

    /// Returns the icon for a named folder in its collapsed or expanded state.
    static func folderIcon(forFolderName name: String, expanded: Bool = false, size: CGFloat = 16) -> NSImage? {
        loadIcon(named: folderIconName(forFolderName: name, expanded: expanded), size: size)
    }

    /// Loads an icon from the cache or from the resource bundle.
    private static func loadIcon(named name: String, size: CGFloat) -> NSImage? {
        let cacheKey = "\(name)@\(Int(size))"
        if let cached = iconCache[cacheKey] {
            return cached
        }

        let bundle = Bundle.main
        guard let url = bundle.url(forResource: name, withExtension: "svg", subdirectory: "FileTypeIcons") else {
            return nil
        }

        guard let data = try? Data(contentsOf: url),
              let image = NSImage(data: data) else {
            return nil
        }

        image.size = NSSize(width: size, height: size)
        iconCache[cacheKey] = image
        return image
    }

    /// Clears the internal icon cache. Useful when the style or icon size changes.
    static func clearCache() {
        iconCache.removeAll()
    }

    // MARK: - Raw tables (generated from material-icon-theme 5.37.0)

    private static let rawExtensionIconNames: [String: String] = [
        "7z": "zip",
        "a": "lib",
        "aac": "audio",
        "astro": "astro",
        "avi": "video",
        "avif": "image",
        "bash": "console",
        "bat": "console",
        "bazel": "bazel",
        "bib": "bibliography",
        "bin": "hex",
        "bmp": "image",
        "bz2": "zip",
        "bzl": "bazel",
        "c": "c",
        "cc": "cpp",
        "cfg": "settings",
        "cjs": "javascript",
        "clj": "clojure",
        "cljs": "clojure",
        "cmake": "cmake",
        "cmd": "console",
        "conf": "settings",
        "cpp": "cpp",
        "cs": "csharp",
        "css": "css",
        "csv": "table",
        "cts": "typescript",
        "cxx": "cpp",
        "dart": "dart",
        "db": "database",
        "diff": "diff",
        "dll": "dll",
        "dockerignore": "docker",
        "dylib": "lib",
        "editorconfig": "editorconfig",
        "egg": "python-misc",
        "el": "lisp",
        "elm": "elm",
        "entitlements": "xml",
        "env": "tune",
        "eot": "font",
        "erl": "erlang",
        "ex": "elixir",
        "exe": "exe",
        "exs": "elixir",
        "fish": "console",
        "flac": "audio",
        "fs": "fsharp",
        "fsi": "fsharp",
        "fsx": "fsharp",
        "gemspec": "ruby",
        "gif": "image",
        "go": "go",
        "gql": "graphql",
        "gradle": "gradle",
        "graphql": "graphql",
        "groovy": "groovy",
        "gz": "zip",
        "h": "h",
        "hh": "hpp",
        "hpp": "hpp",
        "hs": "haskell",
        "htm": "html",
        "html": "html",
        "ico": "image",
        "ini": "settings",
        "ipynb": "jupyter",
        "java": "java",
        "jl": "julia",
        "jpeg": "image",
        "jpg": "image",
        "js": "javascript",
        "json": "json",
        "jsonc": "json",
        "jsx": "react",
        "julia": "julia",
        "kt": "kotlin",
        "kts": "kotlin",
        "less": "less",
        "lock": "lock",
        "log": "log",
        "lua": "lua",
        "m": "objective-c",
        "map": "javascript-map",
        "md": "markdown",
        "mdc": "image",
        "mdx": "mdx",
        "mjs": "javascript",
        "mkv": "video",
        "mm": "objective-cpp",
        "mov": "video",
        "mp3": "audio",
        "mp4": "video",
        "mts": "typescript",
        "nim": "nim",
        "npmrc": "settings",
        "o": "3d",
        "ogg": "video",
        "orc": "database",
        "otf": "font",
        "parquet": "database",
        "patch": "git",
        "pbxproj": "swift",
        "pdf": "pdf",
        "php": "php",
        "pkl": "pkl",
        "pl": "prolog",
        "plist": "xml",
        "pm": "perl",
        "png": "image",
        "podspec": "ruby",
        "prisma": "prisma",
        "proto": "proto",
        "ps1": "powershell",
        "py": "python",
        "pyc": "python-misc",
        "pyd": "python-misc",
        "pyi": "python",
        "pyo": "python-misc",
        "r": "r",
        "rake": "ruby",
        "rar": "zip",
        "rb": "ruby",
        "rs": "rust",
        "rst": "markdown",
        "ru": "ruby",
        "sass": "sass",
        "scala": "scala",
        "scss": "sass",
        "sh": "console",
        "so": "dll",
        "sol": "solidity",
        "sql": "database",
        "sqlite": "database",
        "sqlite3": "database",
        "storyboard": "xml",
        "strings": "xml",
        "svelte": "svelte",
        "svg": "svg",
        "swift": "swift",
        "tar": "zip",
        "tex": "tex",
        "tf": "terraform",
        "tfstate": "terraform",
        "tfvars": "terraform",
        "tiff": "image",
        "toml": "toml",
        "ts": "typescript",
        "tsv": "table",
        "tsx": "react_ts",
        "ttf": "font",
        "txt": "document",
        "vim": "vim",
        "vue": "vue",
        "wasm": "webassembly",
        "wav": "audio",
        "webm": "video",
        "webp": "image",
        "whl": "python-misc",
        "woff": "font",
        "woff2": "font",
        "xcconfig": "settings",
        "xcodeproj": "swift",
        "xcstrings": "xml",
        "xib": "xml",
        "xml": "xml",
        "xz": "zip",
        "yaml": "yaml",
        "yml": "yaml",
        "zig": "zig",
        "zip": "zip",
        "zsh": "console",
    ]

    private static let rawFileNameIconNames: [String: String] = [
        ".babelrc": "babel",
        ".browserslistrc": "browserlist",
        ".clang-format": "settings",
        ".dockerignore": "docker",
        ".editorconfig": "editorconfig",
        ".env": "tune",
        ".env.example": "tune",
        ".env.local": "tune",
        ".eslintignore": "eslint",
        ".eslintrc": "eslint",
        ".eslintrc.js": "eslint",
        ".eslintrc.json": "eslint",
        ".eslintrc.yml": "eslint",
        ".gitattributes": "git",
        ".gitignore": "git",
        ".gitkeep": "git",
        ".gitmodules": "git",
        ".node-version": "nodejs",
        ".npmignore": "npm",
        ".npmrc": "npm",
        ".nvmrc": "nodejs",
        ".prettierignore": "prettier",
        ".prettierrc": "prettier",
        ".prettierrc.json": "prettier",
        ".prettierrc.yml": "prettier",
        ".python-version": "python-misc",
        ".ruby-version": "ruby",
        ".swift-format": "swift",
        ".swiftlint.yml": "yaml",
        ".tool-versions": "settings",
        "babel.config.js": "babel",
        "build.gradle": "gradle",
        "build.zig": "zig",
        "bun.lock": "bun",
        "bun.lockb": "bun",
        "cargo.lock": "lock",
        "cargo.toml": "toml",
        "changelog.md": "changelog",
        "cmakelists.txt": "cmake",
        "code_of_conduct.md": "conduct",
        "compose.yaml": "docker",
        "compose.yml": "docker",
        "contributing.md": "contributing",
        "docker-compose.yaml": "docker",
        "docker-compose.yml": "docker",
        "dockerfile": "docker",
        "eslint.config.js": "eslint",
        "gemfile": "gemfile",
        "gemfile.lock": "lock",
        "go.mod": "go-mod",
        "go.sum": "go-mod",
        "info.plist": "xml",
        "jest.config.js": "jest",
        "jsconfig.json": "jsconfig",
        "justfile": "just",
        "licence": "license",
        "license": "license",
        "license.md": "license",
        "makefile": "makefile",
        "next.config.js": "next",
        "package-lock.json": "nodejs",
        "package.json": "nodejs",
        "package.resolved": "lock",
        "package.swift": "swift",
        "pnpm-lock.yaml": "pnpm",
        "poetry.lock": "poetry",
        "pom.xml": "maven",
        "prettier.config.js": "prettier",
        "procfile": "heroku",
        "pyproject.toml": "python-misc",
        "readme.md": "readme",
        "requirements.txt": "python-misc",
        "rollup.config.js": "rollup",
        "security.md": "lock",
        "settings.gradle": "gradle",
        "setup.py": "python",
        "tailwind.config.js": "tailwindcss",
        "taskfile.yml": "taskfile",
        "tsconfig.json": "tsconfig",
        "uv.lock": "uv",
        "vite.config.ts": "vite",
        "vitest.config.ts": "vitest",
        "webpack.config.js": "webpack",
        "yarn.lock": "yarn",
    ]

    private static let rawFolderIconNames: [String: FolderIconVariant] = [
        ".git": FolderIconVariant(collapsed: "folder-git", expanded: "folder-git-open"),
        "app": FolderIconVariant(collapsed: "folder-app", expanded: "folder-app-open"),
        "assets": FolderIconVariant(collapsed: "folder-resource", expanded: "folder-resource-open"),
        "bin": FolderIconVariant(collapsed: "folder-dist", expanded: "folder-dist-open"),
        "build": FolderIconVariant(collapsed: "folder-dist", expanded: "folder-dist-open"),
        "components": FolderIconVariant(collapsed: "folder-components", expanded: "folder-components-open"),
        "config": FolderIconVariant(collapsed: "folder-config", expanded: "folder-config-open"),
        "coverage": FolderIconVariant(collapsed: "folder-coverage", expanded: "folder-coverage-open"),
        "dist": FolderIconVariant(collapsed: "folder-dist", expanded: "folder-dist-open"),
        "docs": FolderIconVariant(collapsed: "folder-docs", expanded: "folder-docs-open"),
        "images": FolderIconVariant(collapsed: "folder-images", expanded: "folder-images-open"),
        "include": FolderIconVariant(collapsed: "folder-include", expanded: "folder-include-open"),
        "lib": FolderIconVariant(collapsed: "folder-lib", expanded: "folder-lib-open"),
        "node_modules": FolderIconVariant(collapsed: "folder-node", expanded: "folder-node-open"),
        "out": FolderIconVariant(collapsed: "folder-dist", expanded: "folder-dist-open"),
        "public": FolderIconVariant(collapsed: "folder-public", expanded: "folder-public-open"),
        "scripts": FolderIconVariant(collapsed: "folder-scripts", expanded: "folder-scripts-open"),
        "src": FolderIconVariant(collapsed: "folder-src", expanded: "folder-src-open"),
        "target": FolderIconVariant(collapsed: "folder-target", expanded: "folder-target-open"),
        "temp": FolderIconVariant(collapsed: "folder-temp", expanded: "folder-temp-open"),
        "test": FolderIconVariant(collapsed: "folder-test", expanded: "folder-test-open"),
        "tests": FolderIconVariant(collapsed: "folder-test", expanded: "folder-test-open"),
        "tmp": FolderIconVariant(collapsed: "folder-temp", expanded: "folder-temp-open"),
        "vendor": FolderIconVariant(collapsed: "folder-lib", expanded: "folder-lib-open"),
        "views": FolderIconVariant(collapsed: "folder-views", expanded: "folder-views-open"),
    ]
}
