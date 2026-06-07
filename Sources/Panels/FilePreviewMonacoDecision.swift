import Foundation

/// Pure decisions for routing `FilePreviewPanel`'s text mode to the Monaco web
/// editor versus the native `NSTextView` fallback, plus the self-write
/// suppression comparison used by the file-watcher reload path.
///
/// Kept value-typed and free of AppKit/`FilePreviewPanel` references so it can be
/// unit-tested without launching the app. The panel holds one instance and asks
/// it the routing questions; no global state is involved.
struct FilePreviewMonacoDecision: Sendable {
    /// Files at or below this many bytes render in Monaco; larger text files fall
    /// back to the native `NSTextView` editor (Monaco loads the whole buffer into
    /// the web view, so a hard ceiling avoids pathological memory/latency).
    static let largeFileThresholdBytes: UInt64 = 2 * 1024 * 1024

    /// The byte ceiling for Monaco routing. Defaults to
    /// ``largeFileThresholdBytes``; injectable for tests.
    let largeFileThresholdBytes: UInt64

    /// Creates a decision helper.
    /// - Parameter largeFileThresholdBytes: The Monaco byte ceiling. Defaults to
    ///   ``FilePreviewMonacoDecision/largeFileThresholdBytes``.
    init(largeFileThresholdBytes: UInt64 = FilePreviewMonacoDecision.largeFileThresholdBytes) {
        self.largeFileThresholdBytes = largeFileThresholdBytes
    }

    /// Whether the Monaco editor should back text mode for the loaded file.
    ///
    /// - Parameters:
    ///   - isTextMode: `true` when the resolved preview mode is `.text`.
    ///   - loadedByteSize: The decoded file's byte size, if known. `nil` means the
    ///     size could not be determined; the decision is then conservative and
    ///     uses the native fallback.
    /// - Returns: `true` to route to Monaco, `false` to keep the native editor.
    func shouldUseMonaco(isTextMode: Bool, loadedByteSize: UInt64?) -> Bool {
        guard isTextMode, let loadedByteSize else { return false }
        return loadedByteSize <= largeFileThresholdBytes
    }

    /// Whether an on-disk change should be suppressed because it is this panel's
    /// own write echoing back through the file watcher.
    ///
    /// - Parameters:
    ///   - onDiskHash: Hash of the content just read from disk.
    ///   - lastWrittenHash: Hash recorded by the panel's most recent save, or
    ///     `nil` if the panel has not written yet.
    /// - Returns: `true` when the reload is the panel's own write and should be
    ///   ignored (prevents a write → watch → reload loop).
    func isSelfWrite(onDiskHash: Int, lastWrittenHash: Int?) -> Bool {
        guard let lastWrittenHash else { return false }
        return onDiskHash == lastWrittenHash
    }
}
