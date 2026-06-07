import Foundation
import Testing
#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct NotificationWebSocketSettingsTests {
    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "ws-test-\(UUID())")!
    }

    @Test func defaultsToDisabled() {
        let defaults = makeDefaults()
        #expect(NotificationWebSocketSettings.isEnabled(defaults: defaults) == false)
    }

    @Test func defaultsToCanonicalPort() {
        let defaults = makeDefaults()
        #expect(NotificationWebSocketSettings.port(defaults: defaults) == 51763)
    }

    @Test func readsStoredEnabledAndPort() {
        let defaults = makeDefaults()
        defaults.set(true, forKey: NotificationWebSocketSettings.enabledKey)
        defaults.set(8080, forKey: NotificationWebSocketSettings.portKey)
        #expect(NotificationWebSocketSettings.isEnabled(defaults: defaults) == true)
        #expect(NotificationWebSocketSettings.port(defaults: defaults) == 8080)
    }

    @Test func clampsZeroPortToDefault() {
        let defaults = makeDefaults()
        defaults.set(0, forKey: NotificationWebSocketSettings.portKey)
        #expect(NotificationWebSocketSettings.port(defaults: defaults) == 51763)
    }

    @Test func clampsOutOfRangePortToDefault() {
        let defaults = makeDefaults()
        defaults.set(99999, forKey: NotificationWebSocketSettings.portKey)
        #expect(NotificationWebSocketSettings.port(defaults: defaults) == 51763)
    }
}
