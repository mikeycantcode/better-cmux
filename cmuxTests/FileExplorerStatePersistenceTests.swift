import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite struct FileExplorerStatePersistenceTests {
    @Test func defaultPrefixIsBackwardCompatible() {
        let state = FileExplorerState()
        #expect(state.persistenceKeyPrefix == "fileExplorer")
    }

    @Test func customPrefixIsUsedForWidthKey() {
        let state = FileExplorerState(persistenceKeyPrefix: "sidebar.fileExplorer")
        state.width = 173
        #expect(UserDefaults.standard.double(forKey: "sidebar.fileExplorer.width") == 173)
        UserDefaults.standard.removeObject(forKey: "sidebar.fileExplorer.width")
    }
}
