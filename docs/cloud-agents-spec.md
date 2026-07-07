# Cloud Agents Living Spec

Last updated: July 7, 2026
Owner: remote-instance-management workstream
Design doc: `plans/feat-cloud-agents/DESIGN.md`

This is a **living implementation spec**: a status-tracked (`DONE`, `IN PROGRESS`,
`TODO`) source of truth for remotely starting and managing Claude Code instances
on cmux Cloud VMs, driven primarily through an MCP server and scheduled triggers.
Nothing here is built yet; every item is `TODO` until a PR lands it.

## 1. Objective

Let a user **start a Claude Code instance on a cloud VM and manage it from any
MCP-capable Claude client** (desktop, mobile, web) — without needing the macOS
app in the foreground. The instance is **interactive and attach-to-steer**: it
comes up in a persistent PTY / agent-session surface and waits; the user drives
it by sending messages over MCP tools, or attaches a full cmux workspace on
demand. Scheduled triggers can launch instances on a cron and reap idle ones.

Concretely the feature must provide:

1. A durable **Cloud Agent Run** object: "VM X runs a Claude Code agent on repo
   Y, task Z, session S, state = provisioning/running/waiting_input/idle/…".
2. An **MCP server** exposing launch / list / get / message / read / attach /
   pause / resume / stop tools over that object.
3. **Scheduled triggers**: cron-style launch rules plus an idle auto-reap policy.
4. **Attach handoff**: any run can be opened as a normal cmux remote workspace,
   resuming Claude with full context via `claude --resume <session>`.

Non-goals for the first milestones: a bespoke native sidebar UI, a web
dashboard, and fully-headless autonomy. Those are tracked in §7 as follow-ups.

## 2. Current State (what already exists to build on)

The control plane this feature composes is already in production. None of this is
new work; it is the substrate.

- `DONE` (pre-existing) Cloud VM control plane: `create/destroy/exec/pause/resume/snapshot/restore/openAttach/openSSH`
  behind one `VMProvider` interface (`web/services/vms/drivers/types.ts:76`),
  providers E2B + Freestyle (`drivers/e2b.ts`, `drivers/freestyle.ts`).
- `DONE` (pre-existing) REST surface `/api/vm/*` (`web/app/api/vm/**`), Stack-Auth
  gated (`web/services/vms/routeHelpers.ts`, `auth.ts`), team-scoped billing
  (`billingGateway.ts`, `entitlements.ts`).
- `DONE` (pre-existing) Postgres state: `cloud_vms`, `cloud_vm_leases`,
  `cloud_vm_usage_events`, `cloud_vm_billing_grants` (`web/db/schema.ts:26`).
- `DONE` (pre-existing) Claude Code baked into VM images
  (`@anthropic-ai/claude-code@2.1.137`, `web/services/vms/images/manifest.json`).
- `DONE` (pre-existing) Remote daemon `cmuxd-remote` with persistent PTY,
  session RPC (`session.open/attach/resize/detach/status/close`), CLI relay, and
  an agent-launch entry point (`daemon/remote/cmd/cmuxd-remote/agent_launch.go`);
  spec `docs/remote-daemon-spec.md`.
- `DONE` (pre-existing) Agent resume plumbing:
  `CMUXAgentLaunch/AgentResumeArgv.swift` builds `["claude","--resume",<id>]`
  through the cmux Claude wrapper; `WorkspaceSurfaceResumeBinding` + session
  snapshot store persist/restore it.
- `DONE` (pre-existing) Native agent-session surface: `surface.create`
  `type: agent-session` with `provider_id`/`renderer_kind`
  (`CmuxControlSocket/.../Surface/ControlSurfaceCreateInputs.swift`), backed by
  `Packages/Shared/CmuxAgentChat`.
- `DONE` (pre-existing) Agent hooks feeding status/approvals:
  Claude `PermissionRequest` → Feed bridge, notifications (`docs/agent-hooks.md`).
- `DONE` (pre-existing) VM socket verbs `vm.list/create/destroy/exec/ssh_info/attach_info`
  (`Sources/Cloud/VMClientSocketCommands.swift`) and CLI `cmux vm …`
  (`CLI/cmux.swift:3605`).

### Known gaps this feature must close

- `TODO` Provider `pause/resume/snapshot/restore` exist on the driver interface
  (`drivers/freestyle.ts:162`) but are **not** exposed via REST/CLI/workflow.
  Attach-to-steer fleet management needs cheap "park an idle instance and resume
  it later," so this surface is net-new.
- `TODO` There is no product **MCP server** in the repo today.
- `TODO` There is no **scheduler** in the repo today.
- `TODO` There is no notion of an **agent run** (VM + agent + repo + task +
  session + status) — only VMs and leases.

## 3. Data Model

- `TODO` New table `cloud_agent_runs` (sibling of `cloud_vms` in
  `web/db/schema.ts`): `id`, `user_id`, `billing_team_id`, `cloud_vm_id` (FK),
  `agent_kind` (`"claude"` first), `repo_url`, `branch`, `workdir`,
  `task_prompt`, `agent_session_id` (for `claude --resume`), `status`
  (`provisioning|running|waiting_input|idle|completed|failed|paused|destroyed`),
  `last_activity_at`, `created_at`, `updated_at`, `idempotency_key`.
- `TODO` New table `cloud_agent_schedules`: `id`, `user_id`, `billing_team_id`,
  `cron`, `repo_url`, `branch`, `task_prompt`, `image`, `enabled`,
  `idle_reap_minutes`, `last_fired_at`, `next_fire_at`.
- `TODO` Reuse `cloud_vm_leases` and `cloud_vm_usage_events` unchanged; add an
  `agent_run` usage-event category for launch/message/stop audit + billing.

## 4. MCP Server (primary control surface)

Two transports over the same run registry. Both are `TODO`.

### 4.1 Remote MCP server (hosted, the "start when away from your Mac" path)

- `TODO` Streamable-HTTP MCP endpoint in the Next app (e.g.
  `web/app/api/mcp/route.ts`) authenticated with Stack Auth (reuse
  `services/vms/auth.ts` bearer + `X-Stack-Refresh-Token` + `X-Cmux-Team-Id`).
- `TODO` Tools map 1:1 to agent-run workflows (§5):
  `cmux_agent_launch`, `cmux_agent_list`, `cmux_agent_get`,
  `cmux_agent_message`, `cmux_agent_read`, `cmux_agent_attach_info`,
  `cmux_agent_pause`, `cmux_agent_resume`, `cmux_agent_stop`,
  `cmux_agent_schedule_create/list/delete`.
- `TODO` A run is steered entirely through `cmux_agent_message` (write to the
  agent PTY) + `cmux_agent_read` (tail transcript), so an MCP client controls the
  interactive Claude instance as a text channel with no Mac in the loop.

### 4.2 Local MCP server (drive local/attached instances)

- `TODO` `cmux mcp` subcommand starts a stdio MCP server that translates the
  same tool set into socket verbs (§6) against the running app. Reuses the CLI's
  existing socket resolution (`CLI/CLISocketPathResolver.swift`) and wire client.
- `TODO` Prototyping shortcut: all tools are thin wrappers over `cmux rpc
  <method> <json>` before typed verbs land.

## 5. Backend Workflows (`web/services/vms/agentWorkflows.ts`, new)

Composed from existing `VMProvider` ops + the run repository. All `TODO`.

- `TODO` `launchAgentRun(repo, task, {image, branch, provider})`:
  `provider.create()` → await `running` → `provider.exec()` clone + checkout →
  start `claude` in a persistent PTY via `session.open` RPC (interactive; not
  headless) → persist run + `agent_session_id`.
- `TODO` `listAgentRuns(filter)`, `getAgentRun(id)` (join `cloud_agent_runs` ⨝
  `cloud_vms` for live status + last activity + pending-approval flag).
- `TODO` `messageAgentRun(id, text)` — write to the agent PTY over
  `session.attach`/write RPC.
- `TODO` `readAgentRun(id, {tail})` — return recent transcript/output.
- `TODO` `pauseAgentRun/resumeAgentRun` — expose `provider.pause/resume`
  (net-new REST/workflow, see §2 gap).
- `TODO` `stopAgentRun(id)` — `provider.destroy()` + lease revocation +
  usage event.
- `TODO` `attachInfoAgentRun(id)` — return the existing `AttachEndpoint` so a Mac
  opens a full workspace and resumes Claude with `--resume <agent_session_id>`.
- `TODO` REST routes mirroring `/api/vm/*`: `/api/agent`, `/api/agent/:id`,
  `/api/agent/:id/message`, `/api/agent/:id/read`, `/api/agent/:id/pause`,
  `/api/agent/:id/resume`, `/api/agent/:id/attach-endpoint`.

## 6. Native / Socket + Attach handoff

- `TODO` Socket verbs `agent.launch/list/get/message/read/attach_info/pause/resume/stop`
  alongside `vm.*` (`Sources/Cloud/VMClientSocketCommands.swift`), backed by a
  Swift `AgentRunClient` mirroring `Sources/Cloud/VMClient.swift`.
- `TODO` CLI verbs `cmux agent launch|ls|get|msg|read|attach|pause|resume|stop`
  (`CLI/cmux.swift`), documented in `docs/cli-contract.md`.
- `TODO` Attach reuses the Cloud VM workspace bootstrap
  (`CLI/cmux.swift:8628`, `CloudVMActionLauncher.swift`) so an attached run is a
  normal remote workspace; the surface resume binding replays
  `claude --resume <agent_session_id>` (`WorkspaceSurfaceResumeBinding`).

## 7. Scheduled Triggers

- `TODO` Cron worker (Cloudflare Cron Trigger under `workers/`, or Vercel cron)
  evaluates `cloud_agent_schedules` and calls `launchAgentRun` on fire.
- `TODO` Idle auto-reap: a periodic sweep pauses runs idle past
  `idle_reap_minutes` (via `pauseAgentRun`) and destroys runs idle past a hard
  ceiling, emitting usage events.
- `TODO` MCP tools `cmux_agent_schedule_create/list/delete` manage schedules.

## 8. Status & Approvals (interactive steering)

- `TODO` `cmuxd-remote` relays Claude hook events (`PermissionRequest`, activity)
  over the daemon RPC channel; the backend flips run `status`
  `running ↔ waiting_input ↔ idle` without polling.
- `TODO` `waiting_input` runs are surfaced to MCP clients via `cmux_agent_get`
  (pending-approval flag) and, when a device is registered, an APNs push
  (`device_tokens`, `web/app/api/notifications`).
- `TODO` Approving is `cmux_agent_message` with the approval response; no
  separate approve tool required for the interactive model.

## 9. Acceptance Tests

- `TODO` `web/tests/agent-run-workflows.test.ts`: launch → run row created with
  `agent_session_id`; message writes to PTY; stop destroys VM + revokes leases.
- `TODO` `web/tests/agent-route-auth.test.ts`: every `/api/agent/*` route returns
  `401` before any workflow when unauthenticated; cross-site cookie mutations
  rejected (mirror `web/tests/vm-route-auth.test.ts`).
- `TODO` `web/tests/agent-mcp.test.ts`: MCP tool calls require auth and are
  team-scoped; `cmux_agent_launch` is idempotent under a repeated idempotency key.
- `TODO` MCP round-trip: `launch` → `message("run the tests")` → `read` shows
  output → `attach_info` returns a valid endpoint → `stop`.
- `TODO` Schedule fire test: a due `cloud_agent_schedules` row triggers exactly
  one `launchAgentRun`; idle reap pauses then destroys per policy.
- `TODO` Attach resume test (Swift): attaching a run replays
  `claude --resume <id>` (extend `tests/test_session_relaunch_resumes_agent_sessions.py`).

## 10. Deferred (explicit follow-ups)

- `TODO` Native sidebar "Cloud Agents" section (snapshot-boundary-safe list).
- `TODO` Web dashboard `/agents` page in the Next app.
- `TODO` iOS launch/triage surface over the `remotes.*`/MobileHost backbone.
- `TODO` Fully-headless autonomy mode (`claude -p`) with a stricter approval gate.
- `TODO` Sub-agent spawning from inside a run via the CLI relay.
