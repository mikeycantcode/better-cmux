import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite struct NotificationWebSocketEventFrameTests {
    @Test func helloEncodesFields() throws {
        let data = try #require(NotificationWebSocketEventFrame.helloData(
            protocolName: "cmux-events", version: 1, latestSequence: 42
        ))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["kind"] as? String == "hello")
        #expect(obj["protocol"] as? String == "cmux-events")
        #expect(obj["version"] as? Int == 1)
        #expect((obj["latest_sequence"] as? NSNumber)?.int64Value == 42)
    }

    @Test func eventRoundTrips() throws {
        let event: [String: Any] = [
            "protocol": "cmux-events", "version": 1, "sequence": 7,
            "name": "notification.created", "category": "notification",
            "payload": ["title": "hi", "body": "there"],
        ]
        let data = try #require(NotificationWebSocketEventFrame.jsonData(forEvent: event))
        let obj = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(obj["name"] as? String == "notification.created")
        #expect((obj["payload"] as? [String: Any])?["title"] as? String == "hi")
    }

    @Test func rejectsNonJSONObject() {
        // A non-JSON-safe value (Date) makes serialization fail gracefully.
        #expect(NotificationWebSocketEventFrame.jsonData(forEvent: ["when": Date()]) == nil)
    }
}
