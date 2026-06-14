# WebSocket notifications — design

**Date:** 2026-06-07
**Status:** Approved design (pre-implementation)
**Branch:** `websocket-notifications`

## Problem

cmux emits notifications, agent-state changes, and `report_*` events internally,
but there's no way for a local client (a web dashboard, a phone via a bridge, a
script, an agent) to receive them. The user wants cmux to run a **WebSocket
server that streams these events to connected local clients**, and lets those
clients send back a few actions (mark read / dismiss / focus).

## Decisions (locked via Q&A)

1. **Access:** loopback-only (`127.0.0.1`), **no token**. Any local process may
   connect. (User accepted the reduced-safety tradeoff for simplicity.)
2. **Stream scope:** **notifications + agent + report** events.
3. **Direction:** **bidirectional** — outbound event stream **and** inbound
   action commands.
4. **Default:** **off** (it's a network surface); opt-in via a setting.

## Feasibility finding (drives architecture)

cmux already has the pieces:

- **`CmuxEventBus`** (`Sources/CmuxEventBus.swift`) is an app-wide event bus with
  a versioned wire protocol (`cmux-events`, v1): every event carries
  `protocol`/`version`/`sequence`/`name`/`category`/`source`/`payload`, events are
  retained, and subscriptions support **replay from a sequence number**.
  `CmuxEventPublishing.swift` already publishes `notification.created/read/removed/cleared`
  (category `notification`), `agent.hook.*` (category `agent`), and
  `surface.focused/closed` + workspace/workstream events.
  **Gap:** `report_*` (git branch / PR / ports / pwd / shell-state) are **not**
  published to the bus yet (`CmuxEventPublishing.swift` has no report events).
- **`MobileHostService`** (`Sources/Mobile/MobileHostService.swift`) is a proven
  `@MainActor` `NWListener`-based local service with a connection registry,
  start/stop/`syncToSettings`/`configure` lifecycle, and a **unit-tested**
  `portApplyDecision(enabled:currentBoundPort:requestedPort:isAvailable:)` for
  bind/restart logic. It is raw TCP + StackAuth (mobile app), so it is **not**
  reused as the transport — but its structure is the template.
- **Action handlers** already exist: `TerminalNotificationStore.markRead(id:)`,
  `markRead(forTabId:surfaceId:)`, `markAllRead()`, notification clear, and
  workspace focus methods.
- Network.framework provides **`NWProtocolWebSocket`** — native WebSocket framing,
  so no hand-rolled handshake/framing.

**Therefore:** build a small standalone **`NotificationWebSocketServer`** that is
a WebSocket transport adapter over `CmuxEventBus` (outbound) plus a small action
router (inbound), modeled structurally on `MobileHostService`. Add `report.*`
publishing to the bus so report events stream too.

## Architecture

New folder `Sources/NotificationWebSocket/` (one type per file), wired into the
cmux app target + (for testable seams) cmux-unit.

### 1. Server — `NotificationWebSocketServer`
- `@MainActor final class`, singleton-free: constructed at the app composition
  root (`AppDelegate`) and injected; `start()` / `stop()` / `syncToSettings()`.
- `NWListener` with `NWParameters` whose `applicationProtocols` include
  `NWProtocolWebSocket.Options()` (set `autoReplyPing = true`), bound to
  **loopback** (`127.0.0.1`) on the configured port. Mirror MobileHostService's
  `bindReadyCandidate` / `startListener` / `portApplyDecision` (reuse the latter's
  pure decision helper) and loopback restriction.
- Owns a connection registry (`[ObjectIdentifier: NotificationWebSocketConnection]`).
- Lifecycle: started in `applicationDidFinishLaunching` when enabled, stopped in
  `applicationWillTerminate`, re-synced on the settings-changed notification.

### 2. Connection — `NotificationWebSocketConnection`
- Wraps one `NWConnection`. On open: optionally parse `?since=<sequence>` from the
  request path, create a **`CmuxEventBus` subscription** (replaying from `since`
  if given), and forward each event as a WebSocket text frame
  (`NWProtocolWebSocket.Metadata(opcode: .text)`).
- Receives inbound WebSocket text frames → parse as a command → hand to the router.
- Cancels its bus-subscription task on close; removed from the registry.

### 3. Outbound frame — reuse the `cmux-events` envelope
- Each forwarded event is the `CmuxEventBus` event dict (already
  `{protocol, version, sequence, name, category, source, payload, timestamp}`),
  JSON-serialized. A `hello` frame on connect advertises protocol/version and the
  current latest sequence. **Testable seam:** the envelope/serialization is a pure
  function over an event dict.

### 4. Inbound command — `NotificationWebSocketCommand` + `…CommandRouter`
- `NotificationWebSocketCommand` (pure, `Codable`/parsed from the frame dict):
  v1 set — `mark_read {id|tabId+surfaceId|all}`, `clear {id|all}`,
  `focus {surfaceId|paneId}`. Unknown/malformed → an `error` reply frame.
  **Testable seam:** parsing/validation is pure.
- `…CommandRouter` (`@MainActor`): maps a parsed command to existing handlers
  (`TerminalNotificationStore.markRead/markAllRead/clear`, workspace focus). Honors
  the socket **focus policy** (only explicit-focus commands may move focus). Sends
  an `ack`/`error` reply frame.

### 5. Settings — `notifications.webSocket.*`
- `enabled` (Bool, default **false**) + `port` (Int, default a fixed high port,
  e.g. `51763`). Wired through every layer (shared-behavior policy):
  - `Packages/CmuxSettings` `NotificationsCatalogSection` — two keys.
  - `Packages/CmuxSettingsUI` — a row (toggle + port field) in the notifications
    settings UI (`AppSection` notifications area or a new `NotificationsSection`).
  - `Sources/KeyboardShortcutSettingsFileStore` `parseNotificationsSection` —
    parse + validate (port range), store in managed defaults.
  - `Sources/CmuxSettingsJSONPathSupport` — add the two paths.
  - `web/data/cmux.schema.json` — `notifications.webSocket` object.
  - `Resources/Localizable.xcstrings` — en + ja for label/subtitle/port.
- A small `NotificationWebSocketSettings` reader (enabled/port) + reuse
  `MobileHostService.portApplyDecision` for apply/restart.

### 6. `report.*` bus publishing (the one gap to close)
- Add `CmuxEventBus` publishing for the `report_*` handlers (git branch, PR,
  ports, pwd, shell-state) in their handler path
  (`Sources/TerminalController.swift` `report_*` / `Sources/CmuxEventPublishing.swift`),
  as `report.branch` / `report.pr` / `report.ports` / `report.pwd` /
  `report.shellState` (category `report`). This makes them stream over the WS
  (and benefits any other bus consumer). Off-main per the socket-telemetry policy.

## Non-goals (v1)

- Authentication / TLS (`wss`) / non-loopback binding.
- A bundled web client (the endpoint is the deliverable; clients are external).
- Streaming terminal bytes/render grid (that's MobileHostService's domain).
- Arbitrary command execution — only the curated action set.
- Per-client topic selection beyond the fixed category set. The server filters its
  bus subscription to `notification` + `agent` + `report` categories (it does NOT
  stream the whole bus — no browser URLs, workspace cwds, etc.). A client-tunable
  `categories=` filter is a fast follow if needed.

## Security & constraints

- **Loopback-only** bind; reject non-loopback connections defensively (mirror
  MobileHostService's loopback guard). No token by explicit decision — documented
  in the setting's subtitle that any local process can read notifications and send
  actions while enabled.
- Default off. Enabling opens the port; disabling stops the listener and drops
  connections.
- Swift 6 concurrency: `@MainActor` server/router; per-connection bus-subscription
  drained on a `Task`/`AsyncStream`; no locks/Combine in new code beyond the
  carve-outs Network.framework forces (mirror MobileHostService's documented
  patterns). Off-main JSON serialization for event frames.
- Network entitlement: loopback `NWListener` works without
  `com.apple.security.network.server` (the app is effectively unsandboxed; verify
  during the plan and add the entitlement to all variants only if binding fails).
- New `Sources/NotificationWebSocket/**` wired into pbxproj (app target; test
  seams reachable from cmux-unit); normalize + check.

## Files touched

**New:** `Sources/NotificationWebSocket/NotificationWebSocketServer.swift`,
`NotificationWebSocketConnection.swift`, `NotificationWebSocketCommand.swift`,
`NotificationWebSocketCommandRouter.swift`, `NotificationWebSocketSettings.swift`,
`NotificationWebSocketEventFrame.swift`; tests for command-parse, event-frame,
and the settings/port decision.

**Modified:** `Sources/AppDelegate.swift` (own + start/stop/sync the server);
`Sources/CmuxEventPublishing.swift` (+ `Sources/TerminalController.swift`) for
`report.*` publishing; `Packages/CmuxSettings` + `Packages/CmuxSettingsUI` +
`KeyboardShortcutSettingsFileStore.swift` + `CmuxSettingsJSONPathSupport.swift` +
`web/data/cmux.schema.json` + `Resources/Localizable.xcstrings`;
`cmux.xcodeproj/project.pbxproj`.

## Sequencing

1. Settings (`notifications.webSocket.enabled/port`) end-to-end + reader.
2. Event-frame encoder + inbound command parser (+ unit tests).
3. `NotificationWebSocketServer` + connection (NWProtocolWebSocket, loopback,
   bus subscription → forward), modeled on MobileHostService.
4. Inbound command router → existing handlers (mark read / clear / focus).
5. `report.*` bus publishing.
6. AppDelegate wiring (start/stop/sync) + entitlement only if needed.
7. Localization + audit; final review.

## Open questions for the plan stage

- Exact default port (pick a stable, unlikely-to-collide value).
- Whether the inbound `focus` action should activate the app (NO per focus policy —
  data/selection change without app activation).
- Precise `report.*` publish points (where `report_*` are handled today).
