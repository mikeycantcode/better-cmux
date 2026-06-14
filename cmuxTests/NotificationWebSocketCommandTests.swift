import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct NotificationWebSocketCommandTests {
    @Test func parsesMarkRead() {
        #expect(NotificationWebSocketCommand(json: ["type": "mark_read", "id": "abc"]) == .markRead(id: "abc"))
        #expect(NotificationWebSocketCommand(json: ["type": "mark_read", "tabId": "t1"]) == .markReadSurface(tabId: "t1", surfaceId: nil))
        #expect(NotificationWebSocketCommand(json: ["type": "mark_read", "tabId": "t1", "surfaceId": "s1"]) == .markReadSurface(tabId: "t1", surfaceId: "s1"))
    }

    @Test func parsesOtherTypes() {
        #expect(NotificationWebSocketCommand(json: ["type": "mark_all_read"]) == .markAllRead)
        #expect(NotificationWebSocketCommand(json: ["type": "clear"]) == .clear(id: nil))
        #expect(NotificationWebSocketCommand(json: ["type": "clear", "id": "x"]) == .clear(id: "x"))
        #expect(NotificationWebSocketCommand(json: ["type": "focus", "surfaceId": "s1"]) == .focus(surfaceId: "s1", paneId: nil))
        #expect(NotificationWebSocketCommand(json: ["type": "focus", "paneId": "p1"]) == .focus(surfaceId: nil, paneId: "p1"))
    }

    @Test func rejectsUnknownOrIncomplete() {
        #expect(NotificationWebSocketCommand(json: ["type": "nope"]) == nil)
        #expect(NotificationWebSocketCommand(json: ["type": "mark_read"]) == nil) // no id/tabId
        #expect(NotificationWebSocketCommand(json: ["type": "focus"]) == nil)     // no surfaceId/paneId
        #expect(NotificationWebSocketCommand(json: [:]) == nil)                   // no type
    }

    @Test func parseTextResults() {
        #expect(NotificationWebSocketCommand.parse(text: "{\"type\":\"mark_all_read\"}") == .success(.markAllRead))
        #expect(NotificationWebSocketCommand.parse(text: "not json") == .failure(.invalidJSON))
        #expect(NotificationWebSocketCommand.parse(text: "{\"type\":\"bogus\"}") == .failure(.unrecognized))
    }
}
