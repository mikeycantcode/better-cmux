import Foundation

/// Maps a file path to a Monaco language identifier for syntax highlighting.
///
/// The map covers the most common languages; anything unrecognized resolves to
/// `"plaintext"`. Filename-based specials (e.g. `Makefile`, `Dockerfile`) are
/// checked before the extension table.
enum MonacoLanguageMap {
    /// Special-cased exact filenames (lowercased) → Monaco language id.
    private static let byFilename: [String: String] = [
        "makefile": "shell",
        "gnumakefile": "shell",
        "dockerfile": "dockerfile",
        "containerfile": "dockerfile",
        "cmakelists.txt": "shell",
        ".gitignore": "plaintext",
        ".gitattributes": "plaintext",
        ".env": "shell",
        "makefile.am": "shell",
        "makefile.in": "shell",
        "justfile": "shell",
        "rakefile": "ruby",
        "gemfile": "ruby",
        "podfile": "ruby",
        "brewfile": "ruby",
        "package.json": "json",
        "tsconfig.json": "json",
        "cargo.toml": "ini",
        "go.mod": "ini",
        "go.sum": "plaintext",
        "pipfile": "ini",
        ".bashrc": "shell",
        ".bash_profile": "shell",
        ".zshrc": "shell",
        ".profile": "shell",
    ]

    /// File extension (lowercased, no dot) → Monaco language id.
    private static let byExtension: [String: String] = [
        // Apple / systems
        "swift": "swift",
        "c": "c", "h": "c",
        "cpp": "cpp", "cc": "cpp", "cxx": "cpp", "c++": "cpp",
        "hpp": "cpp", "hh": "cpp", "hxx": "cpp", "ipp": "cpp", "inl": "cpp", "cu": "cpp", "cuh": "cpp",
        "m": "objective-c", "mm": "objective-c",
        "rs": "rust",
        "zig": "cpp",
        "go": "go",
        "d": "cpp",
        "asm": "mips", "s": "mips",
        "wgsl": "wgsl",
        // JS / TS / web
        "ts": "typescript", "tsx": "typescript", "mts": "typescript", "cts": "typescript",
        "js": "javascript", "jsx": "javascript", "mjs": "javascript", "cjs": "javascript",
        "json": "json", "jsonc": "json", "json5": "json", "jsonl": "json",
        "html": "html", "htm": "html", "xhtml": "html", "vue": "html", "svelte": "html", "astro": "html",
        "css": "css", "scss": "scss", "sass": "scss", "less": "less",
        "hbs": "handlebars", "handlebars": "handlebars", "mustache": "handlebars",
        "pug": "pug", "jade": "pug",
        "twig": "twig",
        "liquid": "liquid",
        "razor": "razor", "cshtml": "razor",
        "graphql": "graphql", "gql": "graphql",
        "coffee": "coffeescript",
        // JVM / .NET
        "java": "java",
        "kt": "kotlin", "kts": "kotlin",
        "scala": "scala", "sc": "scala",
        "groovy": "java", "gradle": "java",
        "cs": "csharp", "csx": "csharp",
        "fs": "fsharp", "fsi": "fsharp", "fsx": "fsharp",
        "vb": "vb", "bas": "vb",
        "clj": "clojure", "cljs": "clojure", "cljc": "clojure", "edn": "clojure",
        // Scripting / dynamic
        "py": "python", "pyi": "python", "pyw": "python",
        "rb": "ruby", "erb": "ruby", "gemspec": "ruby",
        "php": "php", "phtml": "php",
        "pl": "perl", "pm": "perl", "t": "perl",
        "lua": "lua",
        "r": "r", "rmd": "r",
        "jl": "julia",
        "dart": "dart",
        "ex": "elixir", "exs": "elixir",
        "st": "st",
        "scm": "scheme", "ss": "scheme", "rkt": "scheme",
        "tcl": "tcl",
        "abap": "abap",
        "cls": "apex", "trigger": "apex",
        "sol": "sol",
        "qs": "qsharp",
        "m3": "m3", "i3": "m3",
        "pas": "pascal", "pp": "pascal", "dpr": "pascal",
        "ligo": "cameligo", "mligo": "cameligo", "religo": "pascaligo",
        // Shell / config / infra
        "sh": "shell", "bash": "shell", "zsh": "shell", "fish": "shell", "ksh": "shell", "zshrc": "shell",
        "bat": "bat", "cmd": "bat",
        "ps1": "powershell", "psm1": "powershell", "psd1": "powershell",
        "dockerfile": "dockerfile",
        "tf": "hcl", "tfvars": "hcl", "hcl": "hcl", "nomad": "hcl",
        "bicep": "bicep",
        "proto": "proto",
        "yaml": "yaml", "yml": "yaml",
        "toml": "ini", "ini": "ini", "cfg": "ini", "conf": "ini", "properties": "ini", "editorconfig": "ini",
        "xml": "xml", "plist": "xml", "svg": "xml", "xsd": "xml", "xsl": "xml", "wsdl": "xml",
        "storyboard": "xml", "xib": "xml", "csproj": "xml", "pbxproj": "plaintext",
        "tsp": "typespec",
        "csp": "csp",
        // Data / query
        "sql": "sql", "mysql": "mysql", "pgsql": "pgsql", "psql": "pgsql", "ddl": "sql",
        "sparql": "sparql", "rq": "sparql",
        "cypher": "cypher", "cql": "cypher",
        "redis": "redis",
        "dax": "msdax",
        "pq": "powerquery",
        "ecl": "ecl",
        // Docs / markup
        "md": "markdown", "markdown": "markdown", "mdown": "markdown", "mkd": "markdown",
        "mdx": "mdx",
        "rst": "restructuredtext",
        "ftl": "freemarker2",
        "tex": "plaintext", "bib": "plaintext",
        // Misc
        "sv": "systemverilog", "svh": "systemverilog", "v": "verilog", "vh": "verilog",
        "sb": "sb",
        "flow": "flow9",
        "azcli": "azcli",
        "lex": "lexon",
        "dats": "postiats",
        "pla": "pla",
        "sophia": "aes", "aes": "aes",
        "diff": "plaintext", "patch": "plaintext",
        "txt": "plaintext", "text": "plaintext", "log": "plaintext",
    ]

    /// Every language id this map can produce (for validation against the set of
    /// grammars Monaco actually registers).
    static var allLanguageIds: Set<String> {
        Set(byFilename.values).union(byExtension.values)
    }

    /// Returns the Monaco language id for a file path, defaulting to `"plaintext"`.
    static func languageId(forPath path: String) -> String {
        let filename = (path as NSString).lastPathComponent.lowercased()
        if let byName = byFilename[filename] { return byName }
        let ext = (filename as NSString).pathExtension
        guard !ext.isEmpty, let language = byExtension[ext] else { return "plaintext" }
        return language
    }
}
