import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct MonacoLanguageMapTests {
    @Test func mapsCommonExtensions() {
        #expect(MonacoLanguageMap.languageId(forPath: "/a/b/Foo.swift") == "swift")
        #expect(MonacoLanguageMap.languageId(forPath: "x.ts") == "typescript")
        #expect(MonacoLanguageMap.languageId(forPath: "x.tsx") == "typescript")
        #expect(MonacoLanguageMap.languageId(forPath: "x.py") == "python")
        #expect(MonacoLanguageMap.languageId(forPath: "x.json") == "json")
        #expect(MonacoLanguageMap.languageId(forPath: "x.rs") == "rust")
        #expect(MonacoLanguageMap.languageId(forPath: "x.go") == "go")
    }

    @Test func mapsSpecialFilenames() {
        // Monaco ships no makefile/cmake grammar, so those fall back to the
        // nearest registered one (`shell`) rather than an unknown language id.
        #expect(MonacoLanguageMap.languageId(forPath: "/proj/Makefile") == "shell")
        #expect(MonacoLanguageMap.languageId(forPath: "/proj/Dockerfile") == "dockerfile")
        #expect(MonacoLanguageMap.languageId(forPath: "CMakeLists.txt") == "shell")
    }

    /// Every id the map can produce must be a language Monaco actually registers;
    /// an unknown id silently drops highlighting.
    @Test func onlyProducesRegisteredLanguageIds() {
        let registered: Set<String> = [
            "plaintext", "abap", "aes", "apex", "azcli", "bat", "bicep", "c", "cameligo",
            "clojure", "coffeescript", "cpp", "csharp", "csp", "css", "cypher", "dart",
            "dockerfile", "ecl", "elixir", "flow9", "freemarker2", "fsharp", "go", "graphql",
            "handlebars", "hcl", "html", "ini", "java", "javascript", "json", "julia",
            "kotlin", "less", "lexon", "liquid", "lua", "m3", "markdown", "mdx", "mips",
            "msdax", "mysql", "objective-c", "pascal", "pascaligo", "perl", "pgsql", "php",
            "pla", "postiats", "powerquery", "powershell", "proto", "pug", "python", "qsharp",
            "r", "razor", "redis", "redshift", "restructuredtext", "ruby", "rust", "sb",
            "scala", "scheme", "scss", "shell", "sol", "sparql", "sql", "st", "swift",
            "systemverilog", "tcl", "twig", "typescript", "typespec", "vb", "verilog",
            "wgsl", "xml", "yaml",
        ]
        for id in MonacoLanguageMap.allLanguageIds {
            #expect(registered.contains(id), "unregistered Monaco language id: \(id)")
        }
    }

    @Test func mapsBroadLanguageCoverage() {
        #expect(MonacoLanguageMap.languageId(forPath: "a.cpp") == "cpp")
        #expect(MonacoLanguageMap.languageId(forPath: "a.ex") == "elixir")
        #expect(MonacoLanguageMap.languageId(forPath: "a.jl") == "julia")
        #expect(MonacoLanguageMap.languageId(forPath: "a.clj") == "clojure")
        #expect(MonacoLanguageMap.languageId(forPath: "a.tf") == "hcl")
        #expect(MonacoLanguageMap.languageId(forPath: "a.proto") == "proto")
        #expect(MonacoLanguageMap.languageId(forPath: "a.sol") == "sol")
        #expect(MonacoLanguageMap.languageId(forPath: "a.sh") == "shell")
        #expect(MonacoLanguageMap.languageId(forPath: "a.toml") == "ini")
    }

    @Test func defaultsToPlaintext() {
        #expect(MonacoLanguageMap.languageId(forPath: "x.unknownext") == "plaintext")
        #expect(MonacoLanguageMap.languageId(forPath: "noext") == "plaintext")
        #expect(MonacoLanguageMap.languageId(forPath: "") == "plaintext")
    }
}
