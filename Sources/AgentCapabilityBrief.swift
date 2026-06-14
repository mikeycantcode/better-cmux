import Foundation

/// The capability brief cmux injects into coding agents (via the `claude` wrapper's
/// `--append-system-prompt`) so they discover cmux's layout commands automatically.
///
/// This is the single source of truth for the brief text. It is exposed to agents
/// through the `CMUX_AGENT_CAPABILITY_BRIEF` environment variable, gated by the
/// `automation.agentCapabilityBrief` setting. Edit ``text`` to change what every
/// agent is told.
struct AgentCapabilityBrief {
    /// The verbatim brief appended to the agent's system prompt.
    ///
    /// Kept short and prescriptive (≤6 lines) on purpose: it tells the agent to lean
    /// on `cmux open` for file display and `cmux snapshot` / `cmux move-tab` /
    /// `cmux reorder-tab` / `cmux swap-panes` for rearranging, without overthinking
    /// orientation or flags.
    static let text = """
    You're inside cmux (a terminal with split panes). When the user asks to show, pull up, open, or look at a file, just run `cmux open <FILE>`. cmux automatically places it in a split beside you (or reuses it if already open) — do NOT choose orientation, inspect the layout, or pass flags. Use a flag only for an explicit override: `--here` (a tab in your pane) or `--split up|down` (stack instead of beside). To rearrange existing panes/tabs: run `cmux snapshot` to see the layout, then `cmux move-tab <tab> --to-pane <left|right|up|down>`, `cmux reorder-tab`, or `cmux swap-panes`. Use these only when the user asks to view or arrange things.
    """
}
