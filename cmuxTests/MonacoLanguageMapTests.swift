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
        #expect(MonacoLanguageMap.languageId(forPath: "/proj/Makefile") == "makefile")
        #expect(MonacoLanguageMap.languageId(forPath: "/proj/Dockerfile") == "dockerfile")
        #expect(MonacoLanguageMap.languageId(forPath: "CMakeLists.txt") == "cmake")
    }

    @Test func defaultsToPlaintext() {
        #expect(MonacoLanguageMap.languageId(forPath: "x.unknownext") == "plaintext")
        #expect(MonacoLanguageMap.languageId(forPath: "noext") == "plaintext")
        #expect(MonacoLanguageMap.languageId(forPath: "") == "plaintext")
    }
}
