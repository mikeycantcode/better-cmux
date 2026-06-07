import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct FilePreviewMonacoDecisionTests {
    @Test func usesMonacoForSmallLocalTextFiles() {
        let d = FilePreviewMonacoDecision()
        #expect(d.shouldUseMonaco(isTextMode: true, loadedByteSize: 1024, isRemote: false) == true)
        #expect(d.shouldUseMonaco(isTextMode: true, loadedByteSize: FilePreviewMonacoDecision.largeFileThresholdBytes, isRemote: false) == true)
    }

    @Test func fallsBackForLargeUnknownOrNonText() {
        let d = FilePreviewMonacoDecision()
        #expect(d.shouldUseMonaco(isTextMode: true, loadedByteSize: FilePreviewMonacoDecision.largeFileThresholdBytes + 1, isRemote: false) == false)
        #expect(d.shouldUseMonaco(isTextMode: true, loadedByteSize: nil, isRemote: false) == false)
        #expect(d.shouldUseMonaco(isTextMode: false, loadedByteSize: 10, isRemote: false) == false)
    }

    @Test func fallsBackForRemoteFilesRegardlessOfSize() {
        let d = FilePreviewMonacoDecision()
        // Remote files keep the native explicit-save editor: Monaco's auto-save
        // would write only to the local cache copy, never the remote host.
        #expect(d.shouldUseMonaco(isTextMode: true, loadedByteSize: 1024, isRemote: true) == false)
        #expect(d.shouldUseMonaco(isTextMode: true, loadedByteSize: FilePreviewMonacoDecision.largeFileThresholdBytes, isRemote: true) == false)
        #expect(d.shouldUseMonaco(isTextMode: true, loadedByteSize: 1, isRemote: true) == false)
    }

    @Test func selfWriteSuppression() {
        let d = FilePreviewMonacoDecision()
        #expect(d.isSelfWrite(onDiskHash: 42, lastWrittenHash: 42) == true)
        #expect(d.isSelfWrite(onDiskHash: 42, lastWrittenHash: 7) == false)
        #expect(d.isSelfWrite(onDiskHash: 42, lastWrittenHash: nil) == false)
    }
}
