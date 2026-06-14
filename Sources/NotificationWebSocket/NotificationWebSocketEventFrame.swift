import Foundation

/// Encodes outbound WebSocket text frames for the notification WebSocket server.
///
/// Outbound event frames reuse the `cmux-events` envelope produced by
/// ``CmuxEventBus`` (already JSON-safe), so this is a thin, pure serialization
/// seam that can be unit-tested without a live connection.
enum NotificationWebSocketEventFrame {
    /// Serializes a ``CmuxEventBus`` event dictionary to UTF-8 JSON `Data`, or
    /// `nil` if it is not a valid JSON object.
    static func jsonData(forEvent event: [String: Any]) -> Data? {
        guard JSONSerialization.isValidJSONObject(event) else { return nil }
        return try? JSONSerialization.data(withJSONObject: event)
    }

    /// Builds the `hello` frame sent on connect: advertises the event protocol,
    /// version, and the bus's latest sequence so a client can resume from it.
    static func helloData(protocolName: String, version: Int, latestSequence: Int64) -> Data? {
        let payload: [String: Any] = [
            "kind": "hello",
            "protocol": protocolName,
            "version": version,
            "latest_sequence": latestSequence,
        ]
        return try? JSONSerialization.data(withJSONObject: payload)
    }
}
