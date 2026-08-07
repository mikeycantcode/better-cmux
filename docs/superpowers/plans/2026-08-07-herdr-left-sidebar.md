# herdr Left Sidebar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the built-in left sidebar content with the herdr layout: a minimal `spaces` list (state dot + workspace name) above an `agents` list (one row per live agent panel with an animated working/blocked/idle glyph), priority-ordered, driven by the existing agent-hook lifecycle.

**Architecture:** A new `AgentsSidebarModel` projects `Workspace.agentLifecycleStatesByPanelId` into immutable `AgentRowSnapshot`s and per-workspace rollups (coalesced publisher + equality guard, pattern: `SidebarUnreadModel`). New SwiftUI views (`HerdrSidebarView`, `SpacesRowView`, `AgentRowView`, `AgentStatusGlyph`) render inside the existing `VerticalTabsSidebar` shell, replacing only the built-in-provider branch. The old rich-row pipeline (`TabItemView`, metadata, explorer split) is bypassed for the built-in provider, not deleted.

**Tech Stack:** Swift / SwiftUI / Combine, XCTest via the `cmux-unit` scheme.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-07-herdr-left-sidebar-design.md`. Branch `big-cleanup`.
- Lifecycle mapping is exactly: `needsInput` → blocked, `running` → working, `idle` → idle, `unknown` → unknown.
- Per-panel status merge keeps the existing precedence: running > needsInput > unknown > idle (see `Workspace.agentHibernationLifecycleState(panelId:fallback:)`, `Sources/Workspace.swift:4353`), THEN maps to `AgentSidebarStatus`.
- Workspace rollup precedence (worst-first): blocked > working > idle > unknown.
- Agent-row sort: blocked, working, idle, unknown; ties by most recent `statusChangedAt` first.
- Snapshot-boundary rule (CLAUDE.md): no `ObservableObject` references below any `ForEach`/`LazyVStack` boundary — rows take immutable value snapshots + closures only, are `Equatable`, and use `.equatable()`.
- No state mutation inside view-body computations (CLAUDE.md).
- The working-glyph animation must be confined to the glyph subview; no per-frame invalidation of rows or the list.
- All user-facing strings via `String(localized:defaultValue:)` with entries in `Resources/Localizable.xcstrings` for en + ja (other locales copy en). Section headers `spaces`/`agents`/`priority` and status words `blocked`/`working`/`idle` are user-facing. Agent names (`claude`, `codex`, …) are product names — not localized.
- Extension and custom sidebar providers, sidebar resize, visibility toggling, and minimal presentation mode must be untouched.
- New test files must be wired into `cmux.xcodeproj/project.pbxproj` with FRESH unique 24-char uppercase-hex IDs (4 entries; template: `TitlebarControlsClusterTests.swift` at pbxproj L883/L1870/L2968/L4358). After editing: `python3 scripts/normalize-pbxproj.py && ./scripts/check-pbxproj.sh && ./scripts/lint-pbxproj-test-wiring.sh`.
- Tests run with: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild -project cmux.xcodeproj -scheme cmux-unit -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-herdr-tests test -only-testing:cmuxTests/<ClassName>`. The `cmux` scheme silently runs 0 tests — never use it for tests.
- Build check: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-herdr build`.
- Commit after each task; end commit messages with `Co-Authored-By:` trailer per repo convention.

---

### Task 1: `AgentSidebarStatus` + `AgentsSidebarModel` projection

**Files:**
- Create: `Sources/Sidebar/AgentsSidebarModel.swift`
- Modify: `Sources/Workspace.swift` (~L4305-4350: bump a revision counter on lifecycle writes)
- Test: `cmuxTests/AgentsSidebarModelTests.swift` (new; wire into pbxproj)

**Interfaces:**
- Consumes: `AgentHibernationLifecycleState` (`Sources/AgentHibernation/AgentHibernationLifecycleState.swift`), `Workspace.agentLifecycleStatesByPanelId: [UUID: [String: AgentHibernationLifecycleState]]` (`Sources/Workspace.swift:2361`), `AgentHibernationLifecycleStatusKeys.allowedStatusKeys`.
- Produces (later tasks rely on these exact names):

```swift
enum AgentSidebarStatus: Int, Comparable, Sendable {
    case blocked = 0, working = 1, idle = 2, unknown = 3
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    init(lifecycle: AgentHibernationLifecycleState) {
        switch lifecycle {
        case .needsInput: self = .blocked
        case .running: self = .working
        case .idle: self = .idle
        case .unknown: self = .unknown
        }
    }
}

struct AgentRowSnapshot: Identifiable, Equatable, Sendable {
    var id: UUID { panelId }
    let workspaceId: UUID
    let panelId: UUID
    let workspaceTitle: String
    let agentName: String        // "claude", "codex", … lowercase display token
    let workspaceAgentCount: Int // number of agent panels in this workspace
    let status: AgentSidebarStatus
    let statusChangedAt: Date
}

@MainActor final class AgentsSidebarModel: ObservableObject {
    @Published private(set) var agentRows: [AgentRowSnapshot] = []
    @Published private(set) var workspaceRollups: [UUID: AgentSidebarStatus] = [:]
    // Pure, static, test-visible core:
    static func buildRows(
        workspaces: [AgentsSidebarWorkspaceInput],
        previousChangeDates: [UUID: (AgentSidebarStatus, Date)],
        now: Date
    ) -> (rows: [AgentRowSnapshot], rollups: [UUID: AgentSidebarStatus],
          changeDates: [UUID: (AgentSidebarStatus, Date)])
    static func agentDisplayName(statusKeys: Set<String>) -> String
    func attach(tabManager: TabManager)  // subscribes; used by Task 4
}

struct AgentsSidebarWorkspaceInput: Sendable {
    let workspaceId: UUID
    let title: String
    let panelLifecycles: [UUID: [String: AgentHibernationLifecycleState]]
}
```

**Details:**

- A panel yields a row iff its `[String: AgentHibernationLifecycleState]` dict is non-empty. Per-panel status: apply the existing precedence over the dict's values (running > needsInput > unknown > idle — copy the logic shape from `Workspace.swift:4353`, do NOT call the instance method, the pure core takes value inputs), then `AgentSidebarStatus(lifecycle:)`.
- `agentDisplayName(statusKeys:)`: strip everything after the first `.` in each key (the discriminator convention from `Workspace+PanelLifecycle.swift:35`), map `"claude_code"` → `"claude"`, `"hermes-agent"` → `"hermes"`, else use the key verbatim (already lowercase tokens: `codex`, `cursor`, `gemini`, …). Multiple distinct keys on one panel: pick the alphabetically first for determinism. Empty set → `"agent"`.
- `workspaceAgentCount` = number of row-yielding panels in that workspace.
- `statusChangedAt`: look up `previousChangeDates[panelId]`; if absent or its status differs from the new status, use `now`; else keep the stored date. Return the updated map.
- Rollup = min over the workspace's row statuses (Comparable makes blocked smallest). Workspaces with zero rows get no entry.
- Sort rows by `(status.rawValue, -statusChangedAt.timeIntervalSinceReferenceDate, panelId.uuidString)` — the uuid tail makes ordering total/stable.
- `attach(tabManager:)` + live plumbing: add to `Workspace` a `@Published private(set) var agentLifecycleRevision: Int = 0`, incremented at the end of `setAgentLifecycle`, `clearAgentLifecycle` (when it returns true), `clearAgentLifecycleStates`, and `clearAllAgentLifecycleStates` (`Sources/Workspace.swift:4305-4350`). The model subscribes to `tabManager.$tabs` and, per workspace, to `$agentLifecycleRevision` merged with `$title`, coalesced with `.debounce(for: .milliseconds(40), scheduler: RunLoop.main)`, then rebuilds via `buildRows` and assigns only when the result differs (equality guard on `agentRows` / `workspaceRollups`).

**Steps:**

- [ ] **Step 1: Write failing tests** in `cmuxTests/AgentsSidebarModelTests.swift` (XCTest header pattern from `cmuxTests/SidebarWidthPolicyTests.swift`, incl. the `#if canImport(cmux_DEV)` block). Cover: (a) lifecycle→status mapping all four cases; (b) per-panel merge precedence: `["a": .idle, "b": .needsInput]` → blocked, `["a": .running, "b": .needsInput]` → working-then-mapped… careful: running>needsInput merge yields `.running` → `.working`; (c) rollup: workspace with working+blocked panels → blocked; (d) sort: blocked before working before idle; two working rows ordered by newer `statusChangedAt` first; (e) `statusChangedAt` preserved when status unchanged across rebuilds, reset when status flips; (f) `workspaceAgentCount` counts only agent panels; panel with empty dict yields no row; (g) `agentDisplayName`: `{"claude_code"}` → `claude`, `{"claude_code.2"}` → `claude`, `{"codex"}` → `codex`, `{}` → `agent`.
- [ ] **Step 2: Wire the test file into pbxproj** (4 entries, fresh IDs), run normalize + check scripts, then run the test target: expect FAIL (types don't exist).
- [ ] **Step 3: Implement** `Sources/Sidebar/AgentsSidebarModel.swift` (types above) and the `agentLifecycleRevision` counter in `Workspace.swift`. Note: `Sources/` files are folder-referenced? No — check whether `Sources/Sidebar/*.swift` need pbxproj wiring by looking at how `Sources/Sidebar/SidebarState.swift` is referenced; mirror exactly what existing `Sources/Sidebar` files do.
- [ ] **Step 4: Run the tests** (`-only-testing:cmuxTests/AgentsSidebarModelTests`): expect PASS. Also run the app build check.
- [ ] **Step 5: Commit** `feat: agent sidebar status projection model`.

---

### Task 2: `AgentStatusGlyph` + row views (`SpacesRowView`, `AgentRowView`)

**Files:**
- Create: `Sources/Sidebar/HerdrSidebarRows.swift` (glyph + both row views + shared style constants)
- Test: `cmuxTests/HerdrSidebarRowsTests.swift` (new; wire into pbxproj)

**Interfaces:**
- Consumes: `AgentSidebarStatus`, `AgentRowSnapshot` (Task 1); `cmuxAccentColor()` and `.cmuxFont(size:weight:design:)` (existing).
- Produces:

```swift
enum HerdrSidebarStyle {
    static func color(for status: AgentSidebarStatus) -> Color
    // blocked: Color(red: 0.94, green: 0.55, blue: 0.62)  (mock pink/red)
    // working: Color(red: 0.95, green: 0.85, blue: 0.55)  (mock yellow)
    // idle:    Color(red: 0.60, green: 0.80, blue: 0.55)  (mock green)
    // unknown: Color(nsColor: .tertiaryLabelColor)
    static func statusWord(for status: AgentSidebarStatus) -> String  // localized
    static let headerFont: Font   // .cmuxFont(size: 13, weight: .semibold, design: .monospaced)
    static let rowFont: Font      // .cmuxFont(size: 13, weight: .semibold, design: .monospaced)
    static let subFont: Font      // .cmuxFont(size: 12, weight: .regular, design: .monospaced)
}

struct AgentStatusGlyph: View { let status: AgentSidebarStatus; let size: CGFloat }
struct SpacesRowView: View, Equatable {
    let title: String
    let rollup: AgentSidebarStatus?   // nil = no agents → dim dot
    let isSelected: Bool
    let onSelect: () -> Void
    static func == (l: Self, r: Self) -> Bool  // title, rollup, isSelected only
}
struct AgentRowView: View, Equatable {
    let snapshot: AgentRowSnapshot
    let isSelected: Bool
    let onActivate: () -> Void
    static func == (l: Self, r: Self) -> Bool  // snapshot, isSelected only
}
```

**Details:**

- `statusWord` values: `String(localized: "herdr.status.blocked", defaultValue: "blocked")`, `…working…`, `…idle…`, `…unknown…` (lowercase everywhere, matching the mock).
- `AgentStatusGlyph` rendering: blocked = filled circle inside a stroked ring (`Circle().stroke` + inner `Circle().fill`); idle = `Image(systemName: "checkmark")`; unknown = `Circle().strokeBorder`; working = a 2×2 scatter of 4 small dots whose opacities shimmer. Animation: `TimelineView(.animation(minimumInterval: 0.15))` INSIDE `AgentStatusGlyph` only, opacity per dot = `0.35 + 0.65 * abs(sin(t * 1.7 + phase_i))` with distinct phases; wrap the working branch only, so blocked/idle/unknown render statically with zero timers.
- `SpacesRowView`: HStack of 6pt dot (`Circle().fill(color)`, dim `tertiaryLabelColor` when `rollup == nil` or `.unknown`) + `Text(title)` in `rowFont`, secondary color, brighter when selected; full-width `RoundedRectangle(cornerRadius: 5)` fill `Color.primary.opacity(0.08)` when selected; `.contentShape(Rectangle())`, `.onTapGesture(perform: onSelect)`. Height ~28pt, horizontal padding 8pt.
- `AgentRowView`: two-line VStack. Line 1: `AgentStatusGlyph(status:, size: 12)` + `Text(title)` (append `" · \(workspaceAgentCount)"` in secondary when count > 1) in `rowFont`. Line 2 (leading-aligned under the title, indented by glyph width + spacing): `Text(statusWord)` colored by status + `Text("·")` + `Text(agentName)` in `subFont`, `tertiaryLabelColor`. Same selection background as `SpacesRowView`. Accessibility: `.accessibilityLabel` combining title, status word, agent name.
- Both rows: pure value views, no store references (snapshot-boundary rule).

**Steps:**

- [ ] **Step 1: Write failing tests** in `cmuxTests/HerdrSidebarRowsTests.swift`: (a) `HerdrSidebarStyle.color(for:)` distinct per status and `unknown` uses tertiary; (b) `statusWord(for:)` returns non-empty lowercase for all four; (c) `SpacesRowView == ` ignores closures (two instances with different `onSelect` but equal data compare equal; differing `isSelected` compare unequal); same-shape test for `AgentRowView`.
- [ ] **Step 2: Wire test file into pbxproj** (fresh IDs), run guards, run tests: expect FAIL.
- [ ] **Step 3: Implement** `Sources/Sidebar/HerdrSidebarRows.swift`; add the four `herdr.status.*` keys to `Resources/Localizable.xcstrings` with en + ja (`blocked` → ブロック中, `working` → 作業中, `idle` → 待機中, `unknown` → 不明).
- [ ] **Step 4: Run tests** (`-only-testing:cmuxTests/HerdrSidebarRowsTests`): PASS; run app build check.
- [ ] **Step 5: Commit** `feat: herdr sidebar row views and status glyph`.

---

### Task 3: `HerdrSidebarView` — sections, sorting hookup, activation closures

**Files:**
- Create: `Sources/Sidebar/HerdrSidebarView.swift`
- Test: extend `cmuxTests/AgentsSidebarModelTests.swift` only if new pure logic is extracted; otherwise none (layout container).

**Interfaces:**
- Consumes: `AgentsSidebarModel` (`agentRows`, `workspaceRollups`), `SpacesRowView`, `AgentRowView`, `HerdrSidebarStyle`.
- Produces:

```swift
struct HerdrSidebarSpaceItem: Identifiable, Equatable {
    let id: UUID           // workspaceId
    let title: String
    let rollup: AgentSidebarStatus?
    let isSelected: Bool
}

struct HerdrSidebarView: View {
    let spaces: [HerdrSidebarSpaceItem]
    let agents: [AgentRowSnapshot]          // already sorted by the model
    let selectedPanelId: UUID?
    let onSelectSpace: (UUID) -> Void       // workspaceId
    let onActivateAgent: (UUID, UUID) -> Void  // (workspaceId, panelId)
    let onSpaceContextMenu: (UUID) -> AnyView  // context-menu content per workspace
}
```

**Details:**

- Layout: `VStack(spacing: 0)`. Upper region: header `Text("spaces")` (`String(localized: "herdr.section.spaces", defaultValue: "spaces")`, `headerFont`, secondary, 8pt padding) then `ScrollView { LazyVStack(spacing: 2) { ForEach(spaces) { SpacesRowView(...).equatable() .contextMenu { onSpaceContextMenu(item.id) } } } }`. Lower region pinned below: `Divider().opacity(0.4)`, header row `HStack { Text("agents"); Spacer(); Text("priority") }` (keys `herdr.section.agents` / `herdr.section.priority`, `headerFont`; `priority` in tertiary), then `ScrollView { LazyVStack(spacing: 2) { ForEach(agents) { AgentRowView(...).equatable() } } }`. Give the agents region `.frame(maxHeight: .infinity)` with the spaces scroll taking priority via `.layoutPriority(1)` on the upper region — spaces grow, agents get the remainder and scroll.
- Agent row `isSelected` = `snapshot.panelId == selectedPanelId`.
- `HerdrSidebarView` holds NO store references — all data in via values, all actions out via closures (the ForEach boundary starts here).
- Group headers/collapse from `WorkspaceGroup`: this pass renders spaces FLAT (plain workspace order from the caller). Grouping/collapse restyle is explicitly deferred; the spec's "groups keep collapse behavior" is satisfied at the data layer by the caller passing only non-collapsed workspaces (Task 4 uses `SidebarWorkspaceRenderItem.renderItems`, which already omits collapsed members).
- This task ships the view compiling + previewable; live wiring is Task 4.

**Steps:**

- [ ] **Step 1: Implement** `Sources/Sidebar/HerdrSidebarView.swift` per above, with a `#Preview` containing 3 spaces and 3 agent rows (one per status) so the layout is eyeballable in Xcode canvas.
- [ ] **Step 2: Add** the three `herdr.section.*` keys to `Resources/Localizable.xcstrings` (en: spaces/agents/priority; ja: スペース / エージェント / 優先度).
- [ ] **Step 3: Build check** (app scheme). Expected: compiles.
- [ ] **Step 4: Commit** `feat: herdr sidebar layout container`.

---

### Task 4: Wire into `VerticalTabsSidebar` as the built-in content

**Files:**
- Modify: `Sources/ContentView.swift` — `VerticalTabsSidebar.body` provider `Group` (~L10601-10660) and supporting members.
- Test: `cmuxTests/AgentsSidebarModelTests.swift` — add an integration-ish test for the spaces-item builder if extracted pure (see below).

**Interfaces:**
- Consumes: everything above; `SidebarWorkspaceRenderItem.renderItems(tabs:groupsById:)` (`Sources/SidebarWorkspaceRenderItem.swift`); `TabManager.selectWorkspace(_:)` (`Sources/TabManager.swift:2259`); `TabManager.focusPanel(workspaceId:panelId:)` + `triggerFocusFlash(workspaceId:panelId:)` (`Sources/TabManager+FocusHistoryHosting.swift:50,54`); existing context-menu machinery used by `TabItemView` (reuse the workspace context-menu builder the current row uses — find it inside `TabItemView`'s `.contextMenu` and extract/reuse the minimal subset: select, rename, pin, close).
- Produces: the built-in provider branch renders `HerdrSidebarView`.

**Details:**

- In `VerticalTabsSidebar`, add `@StateObject private var agentsModel = AgentsSidebarModel()`, call `agentsModel.attach(tabManager: tabManager)` in `.task`/`.onAppear` (idempotent guard inside `attach`).
- Extract a pure helper (unit-testable) `static func herdrSpaceItems(renderItems: [SidebarWorkspaceRenderItem], rollups: [UUID: AgentSidebarStatus], selectedWorkspaceId: UUID?) -> [HerdrSidebarSpaceItem]` — walks `renderItems`, keeps `.workspace` entries in order (group headers contribute their anchor workspace as a normal row), producing titles via the same title accessor `TabItemView` uses (`tab.title` / custom description precedence — copy exactly what the snapshot builder at ContentView.swift:14579 uses for the display title).
- Replace ONLY the `resolvesToDefaultSidebar` branch body: keep `SidebarFooter(updateViewModel:fileExplorerState:onSendFeedback:)` at the bottom, drop `SidebarFileExplorerPanel` and the old `workspaceScrollArea` from this branch; mount `HerdrSidebarView(spaces: …, agents: agentsModel.agentRows, selectedPanelId: …, onSelectSpace: { tabManager.selectWorkspace(id) via lookup }, onActivateAgent: { wsId, panelId in tabManager.selectWorkspace…; tabManager.focusPanel(workspaceId: wsId, panelId: panelId); tabManager.triggerFocusFlash(workspaceId: wsId, panelId: panelId) }, onSpaceContextMenu: …)`. `selectedPanelId` = `tabManager.selectedTab?.focusedPanelId` (verify the exact selected-workspace accessor name in TabManager and use it).
- `onSelectSpace` must resolve the `Workspace` by id from `tabManager.tabs` and call `selectWorkspace(_:)` (it takes a `Workspace`).
- Context menu: minimal viable set this pass — Rename, Pin/Unpin, Close — routed through the same dispatcher `TabItemView` uses (`WorkspaceActionDispatcher`); drag-to-reorder is NOT carried over this pass (removed affordance; note this deviation from the spec line "drag-to-reorder … survive" in the task report — the spec text and this plan conflict; the plan governs per Mike's clean-sweep answer, but FLAG it in the report for the reviewer).
- The extension (`extensionSidebarScrollArea`) and custom-sidebar branches remain byte-identical.
- Do not delete `TabItemView`, `workspaceRows`, snapshot builder, explorer split code — bypassed only.

**Steps:**

- [ ] **Step 1: Write failing test** for `herdrSpaceItems` (renderItems with a group header + members + plain workspace → flat ordered items; rollup lookup applied; selection flag set).
- [ ] **Step 2: Run it** — FAIL (helper missing).
- [ ] **Step 3: Implement** the wiring per Details.
- [ ] **Step 4: Run** the new test + full `AgentsSidebarModelTests` — PASS. Run the app build check.
- [ ] **Step 5: Build the tagged app**: `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag herdr-sidebar` and confirm it builds (do not launch).
- [ ] **Step 6: Commit** `feat: herdr layout replaces built-in sidebar content`.

---

### Task 5: Localization audit + polish sweep

**Files:**
- Modify: `Resources/Localizable.xcstrings` (fill any missing locales), touched Swift files for bare strings.

**Details / Steps:**

- [ ] **Step 1:** `rg` all files touched in Tasks 1-4 for bare user-facing string literals (`Text("`, `accessibilityLabel("`, tooltips); every user-facing string must use `String(localized:)`.
- [ ] **Step 2:** Parse `Resources/Localizable.xcstrings` and verify every `herdr.*` key has en + ja values (and that all supported locales at least fall back per existing repo convention — mirror what the 19-locale titlebar keys did: if sibling keys carry 19 locales, fill all 19 for `herdr.*` too, copying en where no translation is provided is NOT acceptable for ja).
- [ ] **Step 3:** Run all herdr test suites once (`AgentsSidebarModelTests`, `HerdrSidebarRowsTests`) + app build check.
- [ ] **Step 4: Commit** `chore: herdr sidebar localization audit`.

---

## Self-review notes

- Spec coverage: data projection (T1), spaces rows + removals (T2/T4), agents section + glyph animation + priority sort (T1/T2/T3), click-to-focus (T4), layout (T3), localization (T2/T3/T5), unit tests per spec §5 (T1/T2/T4). Deviation recorded in T4: drag-to-reorder and full context menu are pared down; group collapse handled via renderItems data, headers render as plain rows this pass.
- Type consistency: `AgentSidebarStatus`, `AgentRowSnapshot`, `AgentsSidebarModel.buildRows`, `HerdrSidebarSpaceItem`, `HerdrSidebarView` signatures repeated verbatim across tasks.
