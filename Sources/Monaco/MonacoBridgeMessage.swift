import Foundation

/// A message posted from the Monaco shell JS to Swift via the `cmuxMonacoBridge`
/// `WKScriptMessageHandler`.
///
/// Parsing is a pure function over the `WKScriptMessage.body` dictionary so it can
/// be unit tested without a live web view.
enum MonacoBridgeMessage: Equatable, Sendable {
    /// The editor finished loading and is ready to receive content.
    case ready
    /// The editor content changed (debounced); carries the full buffer for auto-save.
    case change(content: String)
    /// An explicit save was requested (e.g. Cmd+S or a flush before close).
    case requestSave(content: String)
    /// The user typed (first keystroke of an edit burst), fired before the
    /// debounced save so the panel can mark a local edit in flight.
    case editing
    /// The editor widget gained focus.
    case focus
    /// The editor widget lost focus.
    case blur

    /// Parses a `WKScriptMessage.body` value. Returns `nil` for anything
    /// unrecognized or missing required fields.
    init?(body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        switch type {
        case "ready": self = .ready
        case "editing": self = .editing
        case "focus": self = .focus
        case "blur": self = .blur
        case "change":
            guard let content = dict["content"] as? String else { return nil }
            self = .change(content: content)
        case "requestSave":
            guard let content = dict["content"] as? String else { return nil }
            self = .requestSave(content: content)
        default:
            return nil
        }
    }
}
