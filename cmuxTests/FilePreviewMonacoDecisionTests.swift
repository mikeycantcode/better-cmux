import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct FilePreviewMonacoDecisionTests {
    @Test func usesMonacoForSmallTextFiles() {
        let d = FilePreviewMonacoDecision()
        #expect(d.shouldUseMonaco(isTextMode: true, loadedByteSize: 1024) == true)
        #expect(d.shouldUseMonaco(isTextMode: true, loadedByteSize: FilePreviewMonacoDecision.largeFileThresholdBytes) == true)
    }

    @Test func fallsBackForLargeUnknownOrNonText() {
        let d = FilePreviewMonacoDecision()
        #expect(d.shouldUseMonaco(isTextMode: true, loadedByteSize: FilePreviewMonacoDecision.largeFileThresholdBytes + 1) == false)
        #expect(d.shouldUseMonaco(isTextMode: true, loadedByteSize: nil) == false)
        #expect(d.shouldUseMonaco(isTextMode: false, loadedByteSize: 10) == false)
    }

    @Test func selfWriteSuppression() {
        let d = FilePreviewMonacoDecision()
        #expect(d.isSelfWrite(onDiskHash: 42, lastWrittenHash: 42) == true)
        #expect(d.isSelfWrite(onDiskHash: 42, lastWrittenHash: 7) == false)
        #expect(d.isSelfWrite(onDiskHash: 42, lastWrittenHash: nil) == false)
    }
}
