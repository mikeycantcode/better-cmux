import Foundation
import CmuxSidebar
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct CompactRowStatusResolverTests {
    private func entry(key: String, color: String?, priority: Int) -> SidebarStatusEntry {
        SidebarStatusEntry(key: key, value: key, color: color, priority: priority)
    }

    @Test func returnsNilForNoEntries() {
        #expect(CompactRowStatusResolver.dotColorHex(for: []) == nil)
    }

    @Test func picksFirstEntryWithUsableColor() {
        let entries = [
            entry(key: "running", color: "34C759", priority: 10),
            entry(key: "ports", color: "FF0000", priority: 5),
        ]
        #expect(CompactRowStatusResolver.dotColorHex(for: entries) == "34C759")
    }

    @Test func skipsLeadingEntriesWithoutColor() {
        let entries = [
            entry(key: "idle", color: nil, priority: 10),
            entry(key: "needsInput", color: "FF9500", priority: 8),
        ]
        #expect(CompactRowStatusResolver.dotColorHex(for: entries) == "FF9500")
    }

    @Test func treatsEmptyColorStringAsNoColor() {
        let entries = [entry(key: "idle", color: "", priority: 10)]
        #expect(CompactRowStatusResolver.dotColorHex(for: entries) == nil)
    }
}
