import Foundation

/// Persists editor text to disk atomically, preserving the file's encoding.
///
/// Unlike the legacy non-atomic `FilePreviewTextSaver`, this writer uses
/// `Data.write(options: [.atomic])` (temp file + rename) so a crash mid-write
/// cannot truncate the user's file. It also returns a content hash the panel uses
/// to suppress the file-watcher reload triggered by its own write.
actor MonacoAtomicTextSaver {
    /// The outcome of a successful save.
    struct SaveResult: Sendable {
        /// A stable hash of the written content, for self-write suppression.
        let contentHash: Int
    }

    /// Errors thrown by ``save(content:to:encoding:)``.
    enum SaveError: Error {
        /// The content could not be encoded with the requested encoding.
        case encodingFailed
    }

    /// Atomically writes `content` to `path` using `encoding`.
    /// - Returns: A ``SaveResult`` carrying the content hash.
    /// - Throws: ``SaveError/encodingFailed`` if encoding fails, or a filesystem
    ///   error if the write fails.
    func save(content: String, to path: String, encoding: String.Encoding) throws -> SaveResult {
        guard let data = content.data(using: encoding) else { throw SaveError.encodingFailed }
        try data.write(to: URL(fileURLWithPath: path), options: [.atomic])
        return SaveResult(contentHash: Self.hash(of: content, encoding: encoding))
    }

    /// A stable FNV-1a hash of `content` encoded with `encoding`. Deterministic
    /// across processes, so it can be compared against a freshly read file.
    static func hash(of content: String, encoding: String.Encoding) -> Int {
        let data = content.data(using: encoding) ?? Data(content.utf8)
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data {
            hash ^= UInt64(byte)
            hash = hash &* 0x100_0000_01b3
        }
        return Int(bitPattern: UInt(truncatingIfNeeded: hash))
    }
}
