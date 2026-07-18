import AppKit

/// Maps file extensions to VS Code-style icons sourced from the Material Icon Theme.
///
/// SVGs are bundled in Resources/FileTypeIcons/ and loaded at runtime.
/// Icons that can't be resolved fall back to the system's `doc` SF Symbol.
enum VSCodeFileIcon {
    /// Extension (without dot) → icon filename (without .svg)
    private static let extensionMapping: [String: String] = [
        "swift": "swift",
        "ts": "typescript",
        "tsx": "react_ts",
        "js": "javascript",
        "jsx": "react",
        "mjs": "javascript",
        "cjs": "javascript",
        "py": "python",
        "go": "go",
        "rs": "rust",
        "rb": "ruby",
        "c": "c",
        "cpp": "cpp",
        "h": "h",
        "hpp": "hpp",
        "cs": "csharp",
        "java": "java",
        "kt": "kotlin",
        "scala": "scala",
        "dart": "dart",
        "php": "php",
        "pl": "prolog",
        "lua": "lua",
        "r": "r",
        "zig": "zig",
        "elm": "elm",
        "clj": "clojure",
        "ex": "elixir",
        "exs": "elixir",
        "hs": "haskell",
        "erl": "erlang",
        "fs": "fsharp",
        "fsx": "fsharp",
        "m": "objective-c",
        "mm": "objective-cpp",
        "html": "html",
        "css": "css",
        "scss": "sass",
        "sass": "sass",
        "less": "less",
        "vue": "vue",
        "svelte": "svelte",
        "astro": "astro",
        "json": "json",
        "yaml": "yaml",
        "yml": "yaml",
        "toml": "toml",
        "xml": "xml",
        "md": "markdown",
        "mdx": "mdx",
        "csv": "table",
        "env": "tune",
        "ini": "settings",
        "cfg": "settings",
        "conf": "settings",
        "plist": "xml",
        "sh": "console",
        "bash": "console",
        "zsh": "console",
        "fish": "console",
        "ps1": "powershell",
        "bat": "console",
        "dockerfile": "docker",
        "makefile": "makefile",
        "gradle": "gradle",
        "bazel": "bazel",
        "cmake": "cmake",
        "lock": "lock",
        "sql": "database",
        "db": "database",
        "sqlite": "database",
        "png": "image",
        "jpg": "image",
        "jpeg": "image",
        "gif": "image",
        "svg": "svg",
        "webp": "image",
        "ico": "image",
        "mp4": "video",
        "mp3": "audio",
        "wav": "audio",
        "ogg": "audio",
        "pdf": "pdf",
        "txt": "document",
        "log": "log",
        "graphql": "graphql",
        "prisma": "prisma",
        "proto": "proto",
        "tf": "terraform",
        "tfvars": "terraform",
        "tfstate": "terraform",
        "ipynb": "jupyter",
        "pyc": "python-misc",
        "pyd": "python-misc",
    ]

    /// File names (full match, no extension) that map to specific icons.
    private static let fileNameMapping: [String: String] = [
        "dockerfile": "docker",
        "makefile": "makefile",
        "cmakelists.txt": "cmake",
        "gemfile": "ruby",
        ".gitignore": "git",
        ".gitattributes": "git",
        ".gitmodules": "git",
        ".env": "tune",
        ".env.example": "tune",
        "docker-compose.yml": "docker",
        "docker-compose.yaml": "docker",
        "package.json": "nodejs",
        "tsconfig.json": "tsconfig",
    ]

    /// Cache of loaded icon images keyed by SVG filename.
    private static var iconCache: [String: NSImage] = [:]

    /// Returns the VS Code-style icon for a given file extension, or nil if unavailable.
    /// - Parameters:
    ///   - extension: The file extension (e.g., "swift", "ts"). Pass an empty string for files with no extension.
    ///   - size: The desired icon size in points.
    /// - Returns: An NSImage with the icon, or nil if not found.
    static func icon(forExtension ext: String, size: CGFloat = 16) -> NSImage? {
        let iconName = extensionMapping[ext.lowercased()] ?? ext.lowercased()
        return loadIcon(named: iconName, size: size)
    }

    /// Returns the VS Code-style icon for a given file name (matched by full name).
    static func icon(forFileName name: String, size: CGFloat = 16) -> NSImage? {
        let lower = name.lowercased()
        if let iconName = fileNameMapping[lower] {
            return loadIcon(named: iconName, size: size)
        }
        // Also try loading by the last path component directly
        if let iconName = fileNameMapping[String(lower.split(separator: "/").last ?? "")] {
            return loadIcon(named: iconName, size: size)
        }
        return nil
    }

    /// Returns an icon for a folder. Uses a bundled folder.svg when available.
    static func folderIcon(size: CGFloat = 16) -> NSImage? {
        loadIcon(named: "folder", size: size)
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
}