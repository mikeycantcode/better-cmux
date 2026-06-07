import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

/// Runtime behavior tests for ``FilePreviewTextLoader``'s encoding detection.
///
/// These exercise the pure decode seam directly (no app launch) to prove that a
/// non-BOM Latin-1 byte stream is not misdetected as UTF-16 — which would cause
/// the first auto-save to overwrite the file with UTF-16 garbage.
@Suite struct FilePreviewTextDecodeTests {
    @Test func decodesUTF8First() throws {
        let data = Data("héllo\n".utf8)
        let decoded = try #require(FilePreviewTextLoader.decodeText(data))
        #expect(decoded.encoding == .utf8)
        #expect(decoded.content == "héllo\n")
    }

    @Test func nonBOMLatin1DecodesAsLatin1NotUTF16() throws {
        // 0xE9 is "é" in ISO Latin-1 and an invalid standalone UTF-8 byte, so the
        // stream is not valid UTF-8. Without a UTF-16 BOM it must NOT be decoded as
        // UTF-16 (which would silently produce garbage and corrupt the file on
        // save); it falls through to ISO Latin-1, which round-trips.
        let data = Data([0x63, 0x61, 0x66, 0xE9]) // "café" in Latin-1
        let decoded = try #require(FilePreviewTextLoader.decodeText(data))
        #expect(decoded.encoding == .isoLatin1)
        #expect(decoded.content == "café")
        // Round-trips: re-encoding with the detected encoding reproduces the bytes.
        #expect(decoded.content.data(using: decoded.encoding) == data)
    }

    @Test func utf16WithBOMDecodesAsUTF16() throws {
        let original = "hello world"
        let data = try #require(original.data(using: .utf16)) // includes a BOM
        #expect(FilePreviewTextLoader.hasUTF16ByteOrderMark(data))
        let decoded = try #require(FilePreviewTextLoader.decodeText(data))
        #expect(decoded.encoding == .utf16)
        #expect(decoded.content == original)
    }

    @Test func detectsByteOrderMark() {
        #expect(FilePreviewTextLoader.hasUTF16ByteOrderMark(Data([0xFF, 0xFE, 0x41, 0x00])))
        #expect(FilePreviewTextLoader.hasUTF16ByteOrderMark(Data([0xFE, 0xFF, 0x00, 0x41])))
        #expect(!FilePreviewTextLoader.hasUTF16ByteOrderMark(Data([0x63, 0x61])))
        #expect(!FilePreviewTextLoader.hasUTF16ByteOrderMark(Data([0xFF])))
    }
}
