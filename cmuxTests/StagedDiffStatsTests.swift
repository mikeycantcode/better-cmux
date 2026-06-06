import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct StagedDiffStatsTests {
    @Test func emptyOutputIsZero() {
        let s = StagedDiffStats.parseNumstat("")
        #expect(s.files == 0)
        #expect(s.additions == 0)
        #expect(s.deletions == 0)
    }

    @Test func sumsAddsAndDelsAndCountsFiles() {
        let out = "12\t3\tSources/A.swift\n0\t7\tSources/B.swift\n"
        let s = StagedDiffStats.parseNumstat(out)
        #expect(s.files == 2)
        #expect(s.additions == 12)
        #expect(s.deletions == 10)
    }

    @Test func binaryFilesCountButContributeNoLines() {
        let out = "-\t-\tassets/logo.png\n5\t1\tREADME.md\n"
        let s = StagedDiffStats.parseNumstat(out)
        #expect(s.files == 2)
        #expect(s.additions == 5)
        #expect(s.deletions == 1)
    }

    @Test func isEmptyWhenNothingStaged() {
        #expect(StagedDiffStats.parseNumstat("").isEmpty)
        #expect(!StagedDiffStats.parseNumstat("1\t0\tx").isEmpty)
    }
}
