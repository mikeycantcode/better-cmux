# Cloud Agents: remotely start & manage Claude Code instances

Status: proposed. Living spec at `docs/cloud-agents-spec.md` tracks
implementation status; this document is the design rationale and phased plan.

Decisions this design is scoped to (from product):

- **Control surface = MCP tools + scheduled triggers.** No bespoke native/web/
  mobile UI in the first milestones — you drive the fleet from any MCP-capable
  Claude client, and cron-style triggers launch/reap on a schedule.
- **Autonomy = interactive, attach-to-steer.** A launched instance comes up in a
  persistent PTY / agent-session surface and waits. You steer it by sending
  messages over MCP, or attach a full cmux workspace on demand. Not headless.

## 1. Problem

Starting a Claude Code instance in the cloud today is manual and VM-centric:
`cmux vm new` gives you a shell, you type `claude` yourself, and cmux only knows
there's a PTY — it has no concept of "this VM is running a Claude agent on repo
X, task Y, currently blocked on a permission." There is no way to start or triage
an instance without the Mac app in the foreground, and no fleet view of what is
running. The primitives to fix this already exist; what's missing is (a) a
first-class *agent run* object, (b) a remote control surface over it, and (c) a
scheduler.

## 2. Why this is mostly composition, not new infrastructure

Every heavy piece is already in production. The exploration that seeded this plan
found:

| Need | Already exists | Location |
| --- | --- | --- |
| Provision/destroy/exec cloud VM | `VMProvider` interface + E2B/Freestyle drivers | `web/services/vms/drivers/types.ts:76` |
| Pause/resume/snapshot a VM | driver methods (NOT yet exposed) | `web/services/vms/drivers/freestyle.ts:162` |
| Claude Code in the VM | baked image `@anthropic-ai/claude-code@2.1.137` | `web/services/vms/images/manifest.json` |
| Launch an agent on the remote | `agent_launch.go` + `session.open` RPC | `daemon/remote/cmd/cmuxd-remote/agent_launch.go`, `docs/remote-daemon-spec.md` |
| Resume Claude with context | `["claude","--resume",<id>]` builder | `Packages/macOS/CMUXAgentLaunch/Sources/CMUXAgentLaunch/AgentResumeArgv.swift` |
| Persist/restore an agent surface | resume binding + snapshot store | `Packages/macOS/CmuxWorkspaces/.../Session/WorkspaceSurfaceResumeBinding.swift` |
| Native agent-chat surface | `surface.create type: agent-session` | `Packages/macOS/CmuxControlSocket/.../Surface/ControlSurfaceCreateInputs.swift` |
| Status / approvals | Claude `PermissionRequest` → Feed bridge | `docs/agent-hooks.md` |
| Attach as a real workspace | Cloud VM workspace bootstrap | `CLI/cmux.swift:8628`, `Sources/CloudVMActionLauncher.swift` |
| Remote/mobile + push backbone | `remotes.*`, MobileHost, `device_tokens` (APNs) | `web/db/schema.ts:113`, `Sources/Mobile/MobileHostService.swift` |

The genuinely new surface is small: a run registry table, a workflow layer that
wires the above together, an MCP server, and a scheduler. Plus exposing the
already-implemented `pause/resume` through REST/CLI.

## 3. The one new object: a Cloud Agent Run

```
cloud_agent_runs
  id, user_id, billing_team_id
  cloud_vm_id            -> cloud_vms.id   (the host VM)
  agent_kind             "claude" first; extensible (codex/opencode baked too)
  repo_url, branch, workdir
  task_prompt            initial instruction handed to the interactive session
  agent_session_id       Claude Code session id -> enables `claude --resume`
  status                 provisioning|running|waiting_input|idle|
                         completed|failed|paused|destroyed
  last_activity_at, created_at, updated_at
  idempotency_key        (user_id, idempotency_key) unique, like cloud_vms
```

A run *has* a VM (FK) rather than *being* one, so VM lifecycle
(`cloud_vms.status`) and agent lifecycle (`cloud_agent_runs.status`) stay
independent: a run can be `waiting_input` on a `running` VM, or `paused` on a
`paused` VM. Status transitions are driven by relayed Claude hook events, not
polling (§6).

`cloud_agent_schedules` is the second table (cron + task template + idle-reap
policy). `cloud_vm_leases` / `cloud_vm_usage_events` are reused unchanged.

## 4. Control surface: MCP + triggers

### 4.1 Remote MCP server (primary — start when away from your Mac)

A streamable-HTTP MCP endpoint in the Next app, Stack-Auth gated exactly like the
VM routes. Any MCP client (Claude desktop/mobile/web) connects and calls:

- `cmux_agent_launch(repo, task, {image?, branch?, provider?})` → `{runId, status}`
- `cmux_agent_list({status?})` / `cmux_agent_get(runId)` → status, last activity,
  pending-approval flag, transcript tail
- `cmux_agent_message(runId, text)` → write to the agent PTY (this *is* steering,
  and *is* how you answer a permission prompt in the interactive model)
- `cmux_agent_read(runId, {tail?})` → recent output
- `cmux_agent_pause/resume/stop(runId)`
- `cmux_agent_attach_info(runId)` → `AttachEndpoint` for opening a full workspace
- `cmux_agent_schedule_create/list/delete(...)`

Because the whole run is steerable through `message`/`read`, an MCP client
controls a live interactive Claude instance as a text channel with **no Mac in
the loop** — which is the literal "remotely start & manage" ask.

### 4.2 Local MCP server (drive local/attached instances)

`cmux mcp` starts a stdio MCP server exposing the same tools, translated into
socket verbs against the running app (reusing `CLI/CLISocketPathResolver.swift`
and the existing wire client). Useful for instances that live on your Mac or a
workspace you've attached. Every tool is initially a thin wrapper over
`cmux rpc <method> <json>` so we can validate behavior before typed verbs land.

### 4.3 Scheduled triggers

A cron worker (Cloudflare Cron Trigger under `workers/`, or a Vercel cron)
evaluates `cloud_agent_schedules`: on fire it calls `launchAgentRun`; a periodic
sweep pauses runs idle past `idle_reap_minutes` and destroys runs past a hard
idle ceiling. This covers "every morning launch a Claude instance on repo X to
triage issues" and "don't leave paid VMs running idle."

## 5. Backend workflow layer

`web/services/vms/agentWorkflows.ts` (Effect, sibling to `workflows.ts`) composes
existing driver ops. `launchAgentRun` = `create` → await `running` → `exec`
clone+checkout → start `claude` in a persistent PTY via `session.open` (interactive)
→ persist run + capture `agent_session_id`. `message`/`read` go over
`session.attach`/write RPC. `pause`/`resume` newly expose the driver methods.
`stop` = `destroy` + lease revocation. `attachInfo` returns the existing
`AttachEndpoint`. REST routes mirror `/api/vm/*` under `/api/agent/*`, reusing
`routeHelpers.ts` auth/CSRF/team-scope wholesale.

## 6. Status & approvals without polling

`cmuxd-remote` already carries an RPC channel back to the controller. We relay
Claude's hook events (`PermissionRequest`, activity signals — same bridge that
feeds Feed today, `docs/agent-hooks.md`) over it, and the backend flips run
`status` on receipt. `waiting_input` runs raise the pending-approval flag on
`cmux_agent_get` and, for a registered device, an APNs push
(`device_tokens`, `web/app/api/notifications`). In the interactive model,
answering an approval is just `cmux_agent_message` with the response.

## 7. Attach handoff

`cmux_agent_attach_info` / `cmux agent attach <id>` returns the existing
`AttachEndpoint`, and the Mac opens it through the Cloud VM workspace bootstrap
(`CloudVMActionLauncher`, `CLI/cmux.swift:8628`). The surface resume binding
replays `claude --resume <agent_session_id>`, so attaching drops you into the
live agent with full context — no separate reconnection logic.

## 8. Phased implementation

**Phase 1 — run registry + workflows + REST (backend only).**
`cloud_agent_runs` migration; `agentWorkflows.ts` `launch/list/get/stop`;
`/api/agent/*` routes; expose `pause/resume` on the VM workflow/REST layer;
auth + workflow tests. Deliverable: launch/manage a run via authenticated HTTP.

**Phase 2 — remote MCP server.** `web/app/api/mcp/route.ts` (streamable HTTP,
Stack Auth) exposing the agent tools over Phase 1 workflows; `message`/`read`
over `session.attach`. Deliverable: start & steer a Claude instance from an MCP
client with no Mac.

**Phase 3 — socket/CLI + attach handoff.** `agent.*` socket verbs +
`AgentRunClient`; `cmux agent …` CLI; `cmux mcp` local stdio server; attach path
resuming `claude --resume`. Deliverable: full parity from the Mac + local MCP.

**Phase 4 — scheduled triggers + idle reap.** `cloud_agent_schedules`; cron
worker; schedule MCP tools; reap sweep. Deliverable: unattended launch + cost
control.

**Deferred (see spec §10):** native sidebar section, web `/agents` dashboard, iOS
triage surface, headless autonomy, sub-agent spawning.

## 9. Risks & open questions

- **Billing/limits.** Runs consume paid VMs; enforce active-run limits in the
  same advisory-locked transaction pattern `cloud_vms` uses
  (`web/services/vms/entitlements.ts`), and make idle-reap the default.
- **MCP transport.** Confirm streamable-HTTP + Stack bearer is the intended auth
  for third-party MCP clients, and how token refresh works for long sessions.
- **Steering channel semantics.** Writing to a PTY is line-oriented and racy vs.
  a structured agent API; decide whether `message` targets the raw PTY or a
  structured Claude endpoint if/when one is available in the baked image.
- **Idempotency.** Reuse the `(user_id, idempotency_key)` partial unique index so
  a retried `launch` returns the existing run, not a second paid VM.

## 10. Skills to load before building each phase

`cmux-backend` (Effect, Cloud VM, Postgres, migrations) for Phases 1/2/4;
`cmux-socket-policy` + `cmux-shared-behavior` for Phase 3 socket/CLI verbs;
`cmux-architecture` for package layering; `cmux-testing` for the two-commit
red/green regression policy and test wiring.
