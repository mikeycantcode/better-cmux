# WebSocket Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** A loopback WebSocket server that streams cmux's `CmuxEventBus` events (notifications + agent + report) to local clients and accepts a small set of action commands (mark read / clear / focus).

**Architecture:** A standalone `@MainActor NotificationWebSocketServer` (Network.framework `NWListener` + `NWProtocolWebSocket`, bound to `127.0.0.1`), modeled structurally on `Sources/Mobile/MobileHostService.swift`. Outbound = per-connection `CmuxEventBus` subscription forwarded as JSON text frames (reusing the `cmux-events` envelope). Inbound = parsed command frames routed to existing handlers. Off by default; opt-in via `notifications.webSocket.enabled`.

**Tech Stack:** Swift 6, Network.framework (`NWListener`/`NWConnection`/`NWProtocolWebSocket`), `CmuxEventBus`, Swift Testing.

**Spec:** `docs/superpowers/specs/2026-06-07-websocket-notifications-design.md`

**Reference (read before the relevant task):**
- `Sources/Mobile/MobileHostService.swift` — the NWListener/connection/lifecycle template: `bindReadyCandidate` (~534), `startListener` (~674), `portApplyDecision` (~277/470, pure + unit-tested — REUSE it), `configuredPort` (~421), loopback guard (~873-895), `stop` (~728), `syncToSettings` (~832), connection registry (~96-160), `sendEvent`/frame send (~2053-2067).
- `Sources/CmuxEventBus.swift` — `publish(...)` (~164), subscription + replay-from-sequence (~242-299), `latestSequence`, the `cmux-events` envelope (`protocol`/`version`/`sequence`/`name`/`category`/`source`/`payload`). Find the subscription API a consumer uses (the method that returns a subscription you can drain).
- `Sources/CmuxEventPublishing.swift` — existing publishers: `publishNotificationCreated/Read/Removed/Cleared` (~336-388), `agent.hook.*` (~423), `publishSurfaceFocused/Closed` (~228-245). Mirror these for `report.*`.
- `Sources/TerminalNotificationStore.swift` — action handlers: `markRead(id:)` (~1643), `markRead(forTabId:surfaceId:)` (~1690), `markAllRead()` (~1768), clear.
- `Packages/CmuxSettings/.../Keys/NotificationsCatalogSection.swift`; `Packages/CmuxSettingsUI/.../Sections/` (notifications UI); `Sources/KeyboardShortcutSettingsFileStore.swift` (notifications parse); `Sources/CmuxSettingsJSONPathSupport.swift`; `web/data/cmux.schema.json`.
- `Sources/AppDelegate.swift` — MobileHostService start/stop/sync wiring (~1910 configure, ~6931 start, ~1866 stop, ~8457 sync) as the lifecycle template.

**pbxproj policy:** each new `Sources/NotificationWebSocket/*.swift` → app-target Sources entry (one `cmux`-target build file; tests reach it via `@testable import`); each `cmuxTests/*.swift` → cmux-unit. Valid 24-char UPPERCASE-HEX ids. Run `python3 scripts/normalize-pbxproj.py …`, `./scripts/check-pbxproj.sh`, `./scripts/lint-pbxproj-test-wiring.sh`.

**Build verification (controller-run, between phases):** implementers DO NOT build. Controller runs `CMUX_SKIP_ZIG_BUILD=1 xcodebuild -project cmux.xcodeproj -scheme cmux-unit -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-ws build-for-testing`. Tests run on CI.

**Localization:** new user-facing strings get en + ja in `Resources/Localizable.xcstrings` (controller does this centrally; implementers use `String(localized:defaultValue:)` at call sites and do NOT edit the xcstrings file).

**Test-quality policy:** unit-test pure seams (frame encode, command parse, port decision) — runtime behavior, not source text.

---

## Task 1: Settings — `notifications.webSocket.enabled` + `.port`

**Files:** `Packages/CmuxSettings/Sources/CmuxSettings/Keys/NotificationsCatalogSection.swift`, `Packages/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/<NotificationsUI>.swift`, `Sources/KeyboardShortcutSettingsFileStore.swift`, `Sources/CmuxSettingsJSONPathSupport.swift`, `web/data/cmux.schema.json`; new `Sources/NotificationWebSocket/NotificationWebSocketSettings.swift` + `cmuxTests/NotificationWebSocketSettingsTests.swift`.

- [ ] **Step 1:** Add two keys to `NotificationsCatalogSection` (match the existing key style there): `webSocketEnabled` (Bool, default `false`, id `notifications.webSocket.enabled`) and `webSocketPort` (Int, default `51763`, id `notifications.webSocket.port`). `///`-document both (package docs rule).
- [ ] **Step 2:** Settings UI: add a toggle ("Notification WebSocket server") + a port field, in the notifications settings area. Subtitle MUST state it's **loopback-only with no authentication — any local process can read notifications and send actions while enabled**. `configurationReview: .json(...)` for both. `String(localized:defaultValue:)` at call sites (no xcstrings edit).
- [ ] **Step 3:** `KeyboardShortcutSettingsFileStore` notifications parse: read `webSocket.enabled` (bool) and `webSocket.port` (int, validate 1–65535; ignore invalid), store under the managed-defaults keys. Mirror the existing notifications parsing.
- [ ] **Step 4:** Add `notifications.webSocket.enabled` + `notifications.webSocket.port` to `CmuxSettingsJSONPathSupport.supportedSettingsJSONPaths`.
- [ ] **Step 5:** `web/data/cmux.schema.json`: add a `webSocket` object under `notifications` (`enabled` bool default false; `port` int default 51763 min 1 max 65535; descriptions).
- [ ] **Step 6:** Write `NotificationWebSocketSettings` (enum, like other settings readers): `enabledKey`, `portKey`, `isEnabled(defaults:) -> Bool` (default false), `port(defaults:) -> Int` (default 51763, clamped to 1–65535). Pure → unit test it.
- [ ] **Step 7:** Test `NotificationWebSocketSettingsTests` (Swift Testing, import guard): default disabled; reads enabled/port; clamps invalid port to default. Wire test into pbxproj (cmux-unit). normalize/check/lint.
- [ ] **Step 8:** Commit `WS notifications: settings (enabled/port) end-to-end`.

---

## Task 2: Outbound event frame + inbound command (pure seams)

**Files:** `Sources/NotificationWebSocket/NotificationWebSocketEventFrame.swift`, `NotificationWebSocketCommand.swift`; tests `cmuxTests/NotificationWebSocketEventFrameTests.swift`, `cmuxTests/NotificationWebSocketCommandTests.swift`.

- [ ] **Step 1 (event frame):** Implement `enum NotificationWebSocketEventFrame` with `static func jsonData(forEvent event: [String: Any]) -> Data?` (JSONSerialization of the bus event dict; the bus already sanitizes to JSON-safe values) and `static func helloData(latestSequence: Int64, protocolName: String, version: Int) -> Data?` producing `{"kind":"hello","protocol":…,"version":…,"latest_sequence":…}`. Pure.
- [ ] **Step 2:** Tests: hello encodes the fields; an event dict round-trips to JSON with its keys intact.
- [ ] **Step 3 (command):** Implement `enum NotificationWebSocketCommand: Equatable` with cases `markRead(id: String)`, `markReadSurface(tabId: String, surfaceId: String?)`, `markAllRead`, `clear(id: String?)`, `focus(surfaceId: String?, paneId: String?)`, and `init?(json: [String: Any])` parsing `{"type":"mark_read"|"mark_all_read"|"clear"|"focus", …}`. Unknown type or missing required field → nil. Provide `static func parse(text: String) -> Result<NotificationWebSocketCommand, NotificationWebSocketCommandError>` (JSON-decode then init?). Pure.
- [ ] **Step 4:** Tests: each command type parses; unknown/malformed → error; missing id → error.
- [ ] **Step 5:** Wire both sources + both tests into pbxproj. normalize/check/lint.
- [ ] **Step 6:** Commit `WS notifications: event-frame encoder + command parser (+ tests)`.

---

## Task 3: The server + connection (NWProtocolWebSocket, loopback, bus stream)

**Files:** `Sources/NotificationWebSocket/NotificationWebSocketServer.swift`, `NotificationWebSocketConnection.swift`.

**Read `MobileHostService.swift` first and mirror its NW patterns precisely.**

- [ ] **Step 1:** `@MainActor final class NotificationWebSocketServer`:
  - State: `private var listener: NWListener?`, a connection registry, current bound port.
  - `func start()`: if `NotificationWebSocketSettings.isEnabled()`, build `NWParameters(tls: nil, tcp: NWProtocolTCP.Options())`, set `parameters.requiredInterfaceType`/loopback as MobileHostService does, prepend a `NWProtocolWebSocket.Options()` (with `autoReplyPing = true`) to `parameters.defaultProtocolStack.applicationProtocols`, create `NWListener(using:on:)` on the configured `NWEndpoint.Port`, set `stateUpdateHandler` + `newConnectionHandler` (wrap each `NWConnection` in `NotificationWebSocketConnection`, add to registry, start it), then `listener.start(queue:)`. On bind failure (port in use), fall back to `.any` (ephemeral) OR log and stop — match MobileHostService.
  - `func stop()`: nil handlers, cancel listener, tear down all connections, clear registry.
  - `func syncToSettings()`: use `MobileHostService.portApplyDecision(...)` semantics to decide start/stop/rebind on enabled/port change.
  - **Loopback guard:** in `newConnectionHandler`, defensively verify the remote endpoint is loopback; reject otherwise (mirror MobileHostService ~873-895).
- [ ] **Step 2:** `@MainActor final class NotificationWebSocketConnection`:
  - Holds the `NWConnection`, a `weak` server ref, and a `Task` draining a `CmuxEventBus` subscription.
  - `start()`: send a `hello` frame; parse `?since=` from the connection's initial request path if available (else from latest); open a `CmuxEventBus` subscription (replay from `since`); drain it on a `Task`, sending each event via `send(data:opcode:.text)`. Begin a receive loop for inbound frames.
  - WebSocket send: use `NWConnection.send` with `NWProtocolWebSocket.Metadata(opcode: .text)` in a `ContentContext`. Receive: `receiveMessage` loop; on a `.text` message, hand the bytes to the command router (Task 4) and reply with the router's `ack`/`error` frame.
  - `cancel()`: cancel the drain task, cancel the connection, remove self from the server registry.
  - Concurrency: `@MainActor`; the NWConnection callbacks hop to MainActor for registry/state mutation; document any `nonisolated`/Sendable per repo rules. Off-main JSON serialize event frames before sending.
- [ ] **Step 3:** Controller checkpoint build. Expected: BUILD SUCCEEDED. (No unit test — live socket; covered by pure seams + manual dogfood.)
- [ ] **Step 4:** Commit `WS notifications: loopback WebSocket server + connection streaming CmuxEventBus`.

---

## Task 4: Inbound command router → existing handlers

**Files:** `Sources/NotificationWebSocket/NotificationWebSocketCommandRouter.swift`; wire into the connection's receive path.

- [ ] **Step 1:** `@MainActor final class NotificationWebSocketCommandRouter` constructed with closures or references to the action surface (resolve via `AppDelegate.shared` like other socket handlers do): `notificationStore` for `markRead(id:)`, `markRead(forTabId:surfaceId:)`, `markAllRead()`, clear; workspace focus for `focus`.
  - `func handle(_ command: NotificationWebSocketCommand) -> [String: Any]` returning an `ack` (`{"kind":"ack","type":…}`) or `error` payload.
  - **Focus policy:** `focus` changes selection WITHOUT activating the app / raising windows (per the socket focus policy). All other commands are non-focus and must not steal focus.
  - Map UUID strings → `UUID(uuidString:)`; invalid → error.
- [ ] **Step 2:** In `NotificationWebSocketConnection`, on a received text frame: `NotificationWebSocketCommand.parse(text:)` → on success route via the router and send the reply frame; on failure send an `error` frame.
- [ ] **Step 3:** Controller checkpoint build.
- [ ] **Step 4:** Commit `WS notifications: inbound action command router (mark read / clear / focus)`.

---

## Task 5: Publish `report.*` events to CmuxEventBus

**Files:** `Sources/CmuxEventPublishing.swift` (+ call sites in `Sources/TerminalController.swift` where `report_*` are handled).

- [ ] **Step 1:** Find where `report_git_branch`, `report_pr`/`report_review`, `report_ports`, `report_pwd`, `report_shell_state` are handled (TerminalController `report_*`). Add `CmuxEventPublishing` methods `publishReportBranch/Pr/Ports/Pwd/ShellState(...)` that call `CmuxEventBus.shared.publish(name: "report.branch"|…, category: "report", source: "report.\(cmd)", payload: [...])` mirroring the existing publisher style (workspace/surface ids, values). Off-main per the socket-telemetry policy (these are telemetry hot-ish paths — do not add `DispatchQueue.main.sync`).
- [ ] **Step 2:** Call the new publishers from the `report_*` handlers (after they apply state).
- [ ] **Step 3:** Controller checkpoint build.
- [ ] **Step 4:** Commit `WS notifications: publish report.* events to the event bus`.

---

## Task 6: AppDelegate wiring + entitlement (if needed)

**Files:** `Sources/AppDelegate.swift`; possibly `cmux.entitlements` + `cmux.release.entitlements` + `cmux.nightly.entitlements`.

- [ ] **Step 1:** Own a `NotificationWebSocketServer` instance on `AppDelegate` (constructor/composition root). `start()` it in `applicationDidFinishLaunching` after the main window bootstrap (alongside the MobileHostService start path). `stop()` in `applicationWillTerminate`. Subscribe to the settings-changed notification (the notifications settings did-change, mirroring MobileHostService's sync) → `syncToSettings()`.
- [ ] **Step 2:** Controller verifies a loopback listener binds. If binding fails with a sandbox/entitlement error, add `com.apple.security.network.server` (`<true/>`) to all variant entitlements; otherwise leave entitlements untouched. (Loopback usually needs nothing.)
- [ ] **Step 3:** Controller checkpoint build + a manual loopback smoke (controller may `nc`/`websocat` to 127.0.0.1:port to confirm a hello frame — optional).
- [ ] **Step 4:** Commit `WS notifications: AppDelegate lifecycle wiring`.

---

## Task 7: Localization + final review

- [ ] **Step 1 (controller):** Add en + ja for every new string (settings label/subtitle/port label) to `Resources/Localizable.xcstrings`.
- [ ] **Step 2:** Localization audit (every new user-facing surface has en+ja; rg changed Swift for bare strings).
- [ ] **Step 3:** Full `cmux-unit` build; pbxproj normalized + checks pass.
- [ ] **Step 4:** Adversarial review of the diff (loopback enforcement, no-token implications documented, connection/task teardown leaks, focus policy on `focus`, off-main serialization, port-apply correctness). Fix confirmed issues.
- [ ] **Step 5:** `superpowers:finishing-a-development-branch`.

---

## Self-review notes

- Spec coverage: settings (T1), frame+command seams (T2), server/connection (T3), inbound router (T4), report.* (T5), lifecycle/entitlement (T6), localization+review (T7). Covered.
- Type consistency: `NotificationWebSocketServer/Connection/Command/CommandRouter/EventFrame/Settings`; `CmuxEventBus` subscription API confirmed in T3; `portApplyDecision` reused from MobileHostService.
- Risks: NWProtocolWebSocket send/receive ContentContext details (mirror MobileHostService send + Apple's WS metadata API); per-connection bus subscription must be cancelled on close (leak/backpressure); loopback guard must reject non-loopback; no-token is an accepted, documented tradeoff.
