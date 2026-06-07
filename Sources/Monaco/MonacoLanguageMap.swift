import Foundation

/// Maps a file path to a Monaco language identifier for syntax highlighting.
///
/// The map covers the most common languages; anything unrecognized resolves to
/// `"plaintext"`. Filename-based specials (e.g. `Makefile`, `Dockerfile`) are
/// checked before the extension table.
enum MonacoLanguageMap {
    /// Special-cased exact filenames (lowercased) → Monaco language id.
    private static let byFilename: [String: String] = [
        "makefile": "makefile",
        "gnumakefile": "makefile",
        "dockerfile": "dockerfile",
        "containerfile": "dockerfile",
        "cmakelists.txt": "cmake",
        ".gitignore": "plaintext",
        ".gitattributes": "plaintext",
        ".env": "plaintext",
    ]

    /// File extension (lowercased, no dot) → Monaco language id.
    private static let byExtension: [String: String] = [
        "swift": "swift",
        "ts": "typescript", "tsx": "typescript", "mts": "typescript", "cts": "typescript",
        "js": "javascript", "jsx": "javascript", "mjs": "javascript", "cjs": "javascript",
        "json": "json", "jsonc": "json", "json5": "json",
        "py": "python", "pyi": "python",
        "rb": "ruby",
        "go": "go",
        "rs": "rust",
        "java": "java",
        "kt": "kotlin", "kts": "kotlin",
        "c": "c", "h": "c",
        "cpp": "cpp", "cc": "cpp", "cxx": "cpp", "hpp": "cpp", "hh": "cpp",
        "m": "objective-c", "mm": "objective-c",
        "cs": "csharp",
        "php": "php",
        "scala": "scala",
        "sh": "shell", "bash": "shell", "zsh": "shell", "fish": "shell",
        "html": "html", "htm": "html",
        "css": "css", "scss": "scss", "less": "less",
        "xml": "xml", "plist": "xml", "svg": "xml",
        "yaml": "yaml", "yml": "yaml",
        "toml": "ini", "ini": "ini", "cfg": "ini", "conf": "ini",
        "md": "markdown", "markdown": "markdown",
        "sql": "sql",
        "lua": "lua",
        "r": "r",
        "dart": "dart",
        "pl": "perl", "pm": "perl",
        "ps1": "powershell",
        "dockerfile": "dockerfile",
        "graphql": "graphql", "gql": "graphql",
        "vue": "html",
        "txt": "plaintext", "text": "plaintext", "log": "plaintext",
    ]

    /// Returns the Monaco language id for a file path, defaulting to `"plaintext"`.
    static func languageId(forPath path: String) -> String {
        let filename = (path as NSString).lastPathComponent.lowercased()
        if let byName = byFilename[filename] { return byName }
        let ext = (filename as NSString).pathExtension
        guard !ext.isEmpty, let language = byExtension[ext] else { return "plaintext" }
        return language
    }
}
