import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct MonacoBridgeMessageTests {
    @Test func parsesReady() {
        #expect(MonacoBridgeMessage(body: ["type": "ready"]) == .ready)
    }

    @Test func parsesChangeAndSave() {
        #expect(MonacoBridgeMessage(body: ["type": "change", "content": "abc"]) == .change(content: "abc"))
        #expect(MonacoBridgeMessage(body: ["type": "requestSave", "content": "x"]) == .requestSave(content: "x"))
    }

    @Test func parsesFocusBlur() {
        #expect(MonacoBridgeMessage(body: ["type": "focus"]) == .focus)
        #expect(MonacoBridgeMessage(body: ["type": "blur"]) == .blur)
    }

    @Test func rejectsUnknownAndMalformed() {
        #expect(MonacoBridgeMessage(body: ["type": "nope"]) == nil)
        #expect(MonacoBridgeMessage(body: ["type": "change"]) == nil) // missing content
        #expect(MonacoBridgeMessage(body: [String: Any]()) == nil)
        #expect(MonacoBridgeMessage(body: "not a dict") == nil)
    }
}
