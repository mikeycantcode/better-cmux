import Foundation

/// Context-window usage for the active agent, used by the bottom bar's rainbow
/// context bar and usage text.
struct ContextUsage: Equatable, Sendable {
    /// Fraction of the context window in use, clamped to `0...1`.
    let contextFraction: Double
    /// Optional usage/limit text (e.g. session/rate-limit summary), or `nil`.
    let limitText: String?
}

/// Supplies ``ContextUsage`` for a workspace's active agent.
///
/// cmux has no native agent context/usage data today, so the production binding
/// uses ``NullContextUsageProvider`` (always `nil` → the rainbow bar is hidden).
/// A future provider (transcript parsing or an external `ccusage`-style command)
/// can replace it at the composition root without touching the bar view.
protocol ContextUsageProviding {
    /// Returns usage for the workspace with the given working directory and
    /// active agent, or `nil` when unavailable.
    func usage(workingDirectory: String?, agentActive: Bool) -> ContextUsage?
}

/// The default provider: always returns `nil` (feature deferred).
struct NullContextUsageProvider: ContextUsageProviding {
    func usage(workingDirectory: String?, agentActive: Bool) -> ContextUsage? { nil }
}
