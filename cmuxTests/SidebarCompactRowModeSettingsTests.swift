import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct SidebarCompactRowModeSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "SidebarCompactRowModeSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func defaultsToCompactWhenUnset() {
        let defaults = makeDefaults()
        #expect(SidebarCompactRowModeSettings.isEnabled(defaults: defaults) == true)
    }

    @Test func respectsExplicitDisable() {
        let defaults = makeDefaults()
        defaults.set(false, forKey: SidebarCompactRowModeSettings.key)
        #expect(SidebarCompactRowModeSettings.isEnabled(defaults: defaults) == false)
    }

    @Test func respectsExplicitEnable() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: SidebarCompactRowModeSettings.key)
        #expect(SidebarCompactRowModeSettings.isEnabled(defaults: defaults) == true)
    }
}
