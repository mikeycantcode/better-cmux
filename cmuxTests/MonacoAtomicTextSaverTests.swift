import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct MonacoAtomicTextSaverTests {
    private func makeTempDir() throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("monaco-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func writesAtomicallyAndReportsHash() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        let saver = MonacoAtomicTextSaver()
        let result = try await saver.save(content: "héllo\n", to: file.path, encoding: .utf8)
        let read = try String(contentsOf: file, encoding: .utf8)
        #expect(read == "héllo\n")
        #expect(result.contentHash == MonacoAtomicTextSaver.hash(of: "héllo\n", encoding: .utf8))
    }

    @Test func preservesNonUTF8Encoding() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.txt")
        let saver = MonacoAtomicTextSaver()
        _ = try await saver.save(content: "café", to: file.path, encoding: .isoLatin1)
        let raw = try Data(contentsOf: file)
        #expect(raw == "café".data(using: .isoLatin1))
    }

    @Test func hashIsStableAndContentSensitive() {
        #expect(MonacoAtomicTextSaver.hash(of: "abc", encoding: .utf8) == MonacoAtomicTextSaver.hash(of: "abc", encoding: .utf8))
        #expect(MonacoAtomicTextSaver.hash(of: "abc", encoding: .utf8) != MonacoAtomicTextSaver.hash(of: "abd", encoding: .utf8))
    }
}
