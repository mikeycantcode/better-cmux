import Foundation

/// Selects the most-recently-active item matching a predicate.
///
/// Used by the "Resume Last Claude Session" command to pick the newest resumable
/// Claude session from the session index. Kept generic and pure so the selection
/// is unit-tested without constructing a full `SessionEntry`.
enum ClaudeResumeLast {
    /// Returns the element matching `matching` with the latest `modifiedAt`, or
    /// `nil` if none match.
    /// - Parameters:
    ///   - items: The candidates to choose from.
    ///   - matching: Whether a candidate is eligible (e.g. Claude + resumable).
    ///   - modifiedAt: The recency key; the largest wins.
    static func mostRecent<T>(
        _ items: [T],
        matching: (T) -> Bool,
        modifiedAt: (T) -> Date
    ) -> T? {
        items.filter(matching).max(by: { modifiedAt($0) < modifiedAt($1) })
    }
}
