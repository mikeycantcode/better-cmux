# Agent Layout Control Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let coding agents in cmux terminals open files beside themselves, see the current layout, and reorganize tabs/panes when the developer asks — discovered automatically with zero developer setup.

**Architecture:** A pure `CmuxLayoutPolicy` package (Codable snapshot models + placement/target-resolution decisions, unit-tested) is consumed by the bundled `cmux` CLI. The CLI fetches a new read-only `workspace.snapshot` socket command, runs the policy, and issues existing socket primitives (`pane.create`, `file.open`, `surface.move`, `surface.reorder`, `pane.swap`). The `claude` wrapper auto-injects a capability brief so agents know these exist.

**Tech Stack:** Swift 6 (pure package + CLI Swift), the cmux v2 socket protocol, the existing `Resources/bin/claude` bash wrapper, Xcode project (`cmux`, `cmux-cli`, `cmux-unit` targets), Swift Testing, `CmuxSettings`/`CmuxSettingsUI`.

**Spec:** `docs/superpowers/specs/2026-06-12-agent-layout-control-design.md`

**Binding conventions (CLAUDE.md):**
- Build only with `./scripts/reload.sh --tag agentlayout` (env `CMUX_SKIP_ZIG_BUILD=1` — local zig is 0.16, build pins 0.15.2). Compile-check the CLI/test target with `CMUX_SKIP_ZIG_BUILD=1 xcodebuild -scheme cmux-unit -derivedDataPath /tmp/cmux-agentlayout build`.
- Never run app/E2E tests locally; an isolated package's `swift test` is fine (no app launch).
- New package links into the targets that import it (here: `cmux-cli`, and `cmux-unit` so tests can reach it). Run `scripts/normalize-pbxproj.py` then `scripts/check-pbxproj.sh`.
- Swift-6 concurrency only; pure package types are `Sendable` value types.
- New `public` package symbols get DocC `///`. One major type per file.
- All new user-facing strings localized en + ja. Socket commands follow the off-main vs main-actor policy: `workspace.snapshot` is read-only ⇒ off-main, no focus side effects.
- Two-commit red/green for the policy tests.

---

### Task 0: Spike — confirm snapshot source shape + env-injection site (no production code)

**Files:** none. Record findings for later tasks.

- [ ] **Step 1: Inspect the bonsplit tree snapshot shape**

```bash
rg -n "func treeSnapshot|struct .*TreeNode|ExternalTreeNode|orientation|dividerPosition|selectedTabId" vendor/bonsplit/Sources/Bonsplit/Public/Types/LayoutSnapshot.swift
rg -n "treeSnapshot\(\)" Sources/ | head
```
Record the exact node struct(s): split node fields (`orientation`, `dividerPosition`, `children`), pane node fields (`id`/`frame`/`tabs`/`selectedTabId`), and how a tab is represented (`{id,title}`). Task 2 maps these into the snapshot JSON.

- [ ] **Step 2: Confirm per-surface metadata accessors (off-main safe?)**

```bash
rg -n "func panelType|var panelType|case filePreview|browser.*url|var currentURL|reportedShellState|cwd|var title" Sources/Panels/Panel.swift Sources/TerminalController.swift | head -40
```
Record how to get, per `Panel`: type, title, file path (filePreview), URL (browser), cwd/command (terminal). Note which require main-actor; per spec, omit fields not cheaply available off-main rather than block.

- [ ] **Step 3: Confirm the env-injection site + claude flag**

```bash
rg -n "CMUX_SURFACE_ID|setManagedEnvironmentValue|managedEnvironment|CMUX_SOCKET_PATH" Sources/TerminalStartupEnvironment.swift
sed -n '470,489p' Resources/bin/claude
```
Confirm: `TerminalStartupEnvironment` is where to add a `CMUX_AGENT_CAPABILITY_BRIEF` env var; the wrapper's exec line (currently `exec "$REAL_CLAUDE" [--session-id …] --settings "$HOOKS_JSON" "$@"`). Verify `claude --append-system-prompt <text>` is the correct real flag (it is, per Claude Code docs). No commit.

---

### Task 1: `CmuxLayoutPolicy` package — snapshot models + placement decision (RED → GREEN)

**Files:**
- Create: `Packages/CmuxLayoutPolicy/Package.swift`
- Create: `Packages/CmuxLayoutPolicy/Sources/CmuxLayoutPolicy/LayoutSnapshot.swift`
- Create: `Packages/CmuxLayoutPolicy/Sources/CmuxLayoutPolicy/Placement.swift`
- Create: `Packages/CmuxLayoutPolicy/Sources/CmuxLayoutPolicy/PlacementPolicy.swift`
- Create: `Packages/CmuxLayoutPolicy/Tests/CmuxLayoutPolicyTests/PlacementPolicyTests.swift`
- Modify: `cmux.xcodeproj/project.pbxproj` (link into `cmux-cli` + `cmux-unit`)

- [ ] **Step 1: `Package.swift`** (mirror `Packages/CmuxMathInline/Package.swift`)

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CmuxLayoutPolicy",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CmuxLayoutPolicy", targets: ["CmuxLayoutPolicy"])],
    targets: [
        .target(
            name: "CmuxLayoutPolicy",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(name: "CmuxLayoutPolicyTests", dependencies: ["CmuxLayoutPolicy"]),
    ]
)
```

- [ ] **Step 2: `LayoutSnapshot.swift` — Codable models matching `workspace.snapshot` JSON**

```swift
import Foundation

/// The decoded `workspace.snapshot` response: the workspace layout tree plus the calling
/// agent's anchor. Mirrors the JSON the app emits; the CLI decodes it to drive placement.
public struct LayoutSnapshot: Codable, Sendable, Equatable {
    public let workspaceId: String
    public let focusedPaneId: String?
    public let anchor: Anchor
    public let tree: LayoutNode

    public struct Anchor: Codable, Sendable, Equatable {
        public let surfaceId: String?
        public let paneId: String?
        public init(surfaceId: String?, paneId: String?) {
            self.surfaceId = surfaceId; self.paneId = paneId
        }
    }

    enum CodingKeys: String, CodingKey {
        case workspaceId = "workspace_id"
        case focusedPaneId = "focused_pane_id"
        case anchor, tree
    }

    public init(workspaceId: String, focusedPaneId: String?, anchor: Anchor, tree: LayoutNode) {
        self.workspaceId = workspaceId; self.focusedPaneId = focusedPaneId
        self.anchor = anchor; self.tree = tree
    }
}

/// A node in the split tree: either a split (with oriented children) or a leaf pane.
public indirect enum LayoutNode: Codable, Sendable, Equatable {
    case split(orientation: Orientation, dividerPosition: Double, children: [LayoutNode])
    case pane(Pane)

    /// Split arrangement. `horizontal` = side-by-side panes (a vertical divider); this is the
    /// "beside" orientation the placement policy prefers.
    public enum Orientation: String, Codable, Sendable { case horizontal, vertical }

    /// A leaf pane holding a list of surfaces (tabs).
    public struct Pane: Codable, Sendable, Equatable {
        public let paneId: String
        public let focused: Bool
        public let selectedSurfaceId: String?
        public let surfaces: [Surface]
        enum CodingKeys: String, CodingKey {
            case paneId = "pane_id"
            case focused
            case selectedSurfaceId = "selected_surface_id"
            case surfaces
        }
        public init(paneId: String, focused: Bool, selectedSurfaceId: String?, surfaces: [Surface]) {
            self.paneId = paneId; self.focused = focused
            self.selectedSurfaceId = selectedSurfaceId; self.surfaces = surfaces
        }
    }

    /// One tab/surface and what it shows.
    public struct Surface: Codable, Sendable, Equatable {
        public let id: String
        public let type: String          // terminal | browser | filePreview | markdown | …
        public let title: String?
        public let filePath: String?
        public let url: String?
        enum CodingKeys: String, CodingKey {
            case id, type, title
            case filePath = "file_path"
            case url
        }
        public init(id: String, type: String, title: String?, filePath: String?, url: String?) {
            self.id = id; self.type = type; self.title = title
            self.filePath = filePath; self.url = url
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, orientation, dividerPosition = "divider_position", children }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .kind) {
        case "split":
            self = .split(
                orientation: try c.decode(Orientation.self, forKey: .orientation),
                dividerPosition: try c.decodeIfPresent(Double.self, forKey: .dividerPosition) ?? 0.5,
                children: try c.decode([LayoutNode].self, forKey: .children))
        default:
            self = .pane(try Pane(from: decoder))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .split(orientation, divider, children):
            try c.encode("split", forKey: .kind)
            try c.encode(orientation, forKey: .orientation)
            try c.encode(divider, forKey: .dividerPosition)
            try c.encode(children, forKey: .children)
        case let .pane(pane):
            try c.encode("pane", forKey: .kind)
            try pane.encode(to: encoder)
        }
    }
}
```

- [ ] **Step 3: `Placement.swift` — the decision + overrides**

```swift
/// What the CLI should do to fulfill `cmux open` for a file.
public enum Placement: Sendable, Equatable {
    /// Create a new pane to the right of the anchor, then open the file there.
    case splitRight(fromSurfaceId: String)
    /// Open the file as a new tab in an existing pane.
    case newTab(inPaneId: String)
    /// The file is already open in this surface; just focus it.
    case reuse(surfaceId: String)
    /// Open as a new tab in the anchor's own pane (the `--here` / `--tab` override).
    case here(paneId: String)
}

/// Caller overrides for `cmux open`, from CLI flags.
public struct PlacementOverrides: Sendable, Equatable {
    public var forceHere: Bool          // --here / --tab
    public var forcedSplit: LayoutNode.Orientation?   // --split left/right/up/down → orientation
    public var allowReuse: Bool
    public init(forceHere: Bool = false, forcedSplit: LayoutNode.Orientation? = nil, allowReuse: Bool = true) {
        self.forceHere = forceHere; self.forcedSplit = forcedSplit; self.allowReuse = allowReuse
    }
}
```

- [ ] **Step 4: `PlacementPolicy.swift` — STUB returning a sentinel (for RED)**

```swift
/// Decides where `cmux open <file>` should place a file, given the current layout snapshot.
///
/// Beside-split by default; if the anchor pane is already in a horizontal (side-by-side) split,
/// open a new tab in the neighbor pane instead of adding a third column. See ``decide(filePath:in:anchorSurfaceId:overrides:)``.
public struct PlacementPolicy: Sendable {
    public init() {}

    /// Returns the placement for opening `filePath`.
    ///
    /// - Parameters:
    ///   - filePath: Absolute path of the file to open (for reuse detection).
    ///   - snapshot: The decoded workspace layout.
    ///   - anchorSurfaceId: The calling agent's surface id (`CMUX_SURFACE_ID`).
    ///   - overrides: CLI flag overrides.
    /// - Returns: the ``Placement`` the CLI should execute.
    public func decide(filePath: String, in snapshot: LayoutSnapshot,
                       anchorSurfaceId: String, overrides: PlacementOverrides) -> Placement {
        .here(paneId: "STUB")
    }
}
```

- [ ] **Step 5: Failing corpus `PlacementPolicyTests.swift`**

```swift
import Testing
@testable import CmuxLayoutPolicy

@Suite struct PlacementPolicyTests {
    let policy = PlacementPolicy()

    // Helpers to build snapshots.
    func surface(_ id: String, type: String = "terminal", file: String? = nil) -> LayoutNode.Surface {
        .init(id: id, type: type, title: nil, filePath: file, url: nil)
    }
    func pane(_ id: String, _ surfaces: [LayoutNode.Surface], focused: Bool = false) -> LayoutNode {
        .pane(.init(paneId: id, focused: focused, selectedSurfaceId: surfaces.first?.id, surfaces: surfaces))
    }
    func snap(_ tree: LayoutNode, anchorSurface: String, anchorPane: String) -> LayoutSnapshot {
        .init(workspaceId: "w", focusedPaneId: anchorPane,
              anchor: .init(surfaceId: anchorSurface, paneId: anchorPane), tree: tree)
    }

    @Test func singlePaneSplitsRight() {
        let s = snap(pane("P1", [surface("A")], focused: true), anchorSurface: "A", anchorPane: "P1")
        #expect(policy.decide(filePath: "/x.txt", in: s, anchorSurfaceId: "A", overrides: .init())
                == .splitRight(fromSurfaceId: "A"))
    }

    @Test func alreadyHorizontalSplitOpensTabInNeighbor() {
        let tree = LayoutNode.split(orientation: .horizontal, dividerPosition: 0.5, children: [
            pane("P1", [surface("A")], focused: true),
            pane("P2", [surface("B", type: "browser")]),
        ])
        let s = snap(tree, anchorSurface: "A", anchorPane: "P1")
        #expect(policy.decide(filePath: "/x.txt", in: s, anchorSurfaceId: "A", overrides: .init())
                == .newTab(inPaneId: "P2"))
    }

    @Test func verticalSplitStillSplitsRight() {
        // A vertical (stacked) split is NOT a horizontal neighbor → still prefer a beside split.
        let tree = LayoutNode.split(orientation: .vertical, dividerPosition: 0.5, children: [
            pane("P1", [surface("A")], focused: true),
            pane("P2", [surface("B")]),
        ])
        let s = snap(tree, anchorSurface: "A", anchorPane: "P1")
        #expect(policy.decide(filePath: "/x.txt", in: s, anchorSurfaceId: "A", overrides: .init())
                == .splitRight(fromSurfaceId: "A"))
    }

    @Test func reusesAlreadyOpenFile() {
        let tree = LayoutNode.split(orientation: .horizontal, dividerPosition: 0.5, children: [
            pane("P1", [surface("A")], focused: true),
            pane("P2", [surface("F", type: "filePreview", file: "/x.txt")]),
        ])
        let s = snap(tree, anchorSurface: "A", anchorPane: "P1")
        #expect(policy.decide(filePath: "/x.txt", in: s, anchorSurfaceId: "A", overrides: .init())
                == .reuse(surfaceId: "F"))
    }

    @Test func forceHereOpensInAnchorPane() {
        let s = snap(pane("P1", [surface("A")], focused: true), anchorSurface: "A", anchorPane: "P1")
        #expect(policy.decide(filePath: "/x.txt", in: s, anchorSurfaceId: "A",
                              overrides: .init(forceHere: true)) == .here(paneId: "P1"))
    }
}
```

- [ ] **Step 6: Verify RED**

Run: `cd Packages/CmuxLayoutPolicy && swift test 2>&1 | tail -20`
Expected: compiles; the 4 non-`here` tests FAIL (stub returns `.here("STUB")`).

- [ ] **Step 7: Commit RED**

```bash
git add Packages/CmuxLayoutPolicy
git commit -m "Add CmuxLayoutPolicy package: snapshot models + failing placement corpus (RED)"
```

- [ ] **Step 8: Implement `decide(...)` (GREEN)**

Replace the stub body. Algorithm: (1) if `overrides.forceHere`, return `.here(anchorPane)`. (2) if `allowReuse` and a `filePreview` surface anywhere has `filePath == filePath`, return `.reuse(thatSurfaceId)`. (3) find the anchor pane; if it has a horizontal-split neighbor pane, return `.newTab(neighborPaneId)`; else `.splitRight(anchorSurfaceId)`. Add private helpers `findAnchorPane`, `horizontalNeighbor` (walk the tree tracking parent splits; the neighbor is the sibling pane under the nearest enclosing `.horizontal` split, preferring the one to the right of the anchor). Include `forcedSplit` handling (force `.splitRight` when `.horizontal`, else map to a future stacked case — for v1 `.horizontal`/right is the only split target; `forcedSplit == .vertical` also yields `.splitRight` with a note, since the CLI passes the orientation to `pane.create`). Write full real code (no placeholders), e.g.:

```swift
public func decide(filePath: String, in snapshot: LayoutSnapshot,
                   anchorSurfaceId: String, overrides: PlacementOverrides) -> Placement {
    let panes = Self.allPanes(snapshot.tree)
    let anchorPaneId = snapshot.anchor.paneId
        ?? panes.first(where: { $0.surfaces.contains { $0.id == anchorSurfaceId } })?.paneId

    if overrides.forceHere, let anchorPaneId { return .here(paneId: anchorPaneId) }

    if overrides.allowReuse {
        for p in panes {
            if let s = p.surfaces.first(where: { $0.type == "filePreview" && $0.filePath == filePath }) {
                return .reuse(surfaceId: s.id)
            }
        }
    }

    if let anchorPaneId, let neighbor = Self.horizontalNeighbor(of: anchorPaneId, in: snapshot.tree) {
        return .newTab(inPaneId: neighbor)
    }
    return .splitRight(fromSurfaceId: anchorSurfaceId)
}
```

Plus `allPanes(_:) -> [LayoutNode.Pane]` (recursive collect) and `horizontalNeighbor(of:in:) -> String?` (recursive: at each `.horizontal` split, if a child subtree contains the anchor pane, return the pane-id of the adjacent sibling subtree — nearest right, else left). Write these fully.

- [ ] **Step 9: Verify GREEN** — `cd Packages/CmuxLayoutPolicy && swift test 2>&1 | tail -20` → all pass.

- [ ] **Step 10: Wire the package into `cmux-cli` + `cmux-unit` in pbxproj**

Mirror the `CmuxSocketControl` entries (it links into `cmux` + `cmux-cli`; here use `cmux-cli` + `cmux-unit`): one `XCLocalSwiftPackageReference`, one `XCSwiftPackageProductDependency` (shared), a `PBXBuildFile` per linking target's Frameworks phase, and the dep in each target's `packageProductDependencies`, plus the ref in the project `packageReferences`. Then:
```bash
python3 scripts/normalize-pbxproj.py cmux.xcodeproj/project.pbxproj && ./scripts/check-pbxproj.sh && plutil -lint cmux.xcodeproj/project.pbxproj
```

- [ ] **Step 11: Commit GREEN + wiring**

```bash
git add Packages/CmuxLayoutPolicy cmux.xcodeproj/project.pbxproj
git commit -m "Implement PlacementPolicy (GREEN) + wire CmuxLayoutPolicy into cmux-cli/cmux-unit"
```

---

### Task 2: `workspace.snapshot` socket command (app)

**Files:**
- Create: `Sources/WorkspaceSnapshotSocketSupport.swift` (the builder + handler)
- Modify: `Sources/TerminalController.swift` (register `workspace.snapshot` in the v2 dispatch switch ~line 1021–2298; add to `executionPolicy(forV2Method:)` as off-main/read-only)

- [ ] **Step 1: Implement `v2WorkspaceSnapshot(params:) -> V2CallResult`**

Build the JSON the CLI's `LayoutSnapshot` decodes: walk `workspace.bonsplitController.treeSnapshot()` into `{kind:"split"|"pane", …}` nodes; for each surface resolve `type` (Panel.panelType.rawValue), `title`, and best-effort `file_path` (filePreview), `url` (browser) per Task 0 Step 2; echo `anchor` from `params["surface_id"]` (or `CMUX_SURFACE_ID` the CLI passes) + its resolved pane via `workspace.paneId(forPanelId:)`; include `focused_pane_id`, `workspace_id`, and a static `actions` array (verbs from the spec). Use existing `v2Ref`, `v2MainSync`, `v2ResolveWorkspace` helpers. Read-only: never activate/raise/focus.

(Show the full function in implementation, mapping each `treeSnapshot` field captured in Task 0. The `actions` array is a literal list of `{verb, cli, desc}`.)

- [ ] **Step 2: Register + classify**

Add `case "workspace.snapshot": return v2Result(id: request.id, v2WorkspaceSnapshot(params: request.params))` in the dispatch switch, and add `workspace.snapshot` to the off-main/read-only set in `executionPolicy(forV2Method:)`.

- [ ] **Step 3: Compile-check**

```bash
CMUX_SKIP_ZIG_BUILD=1 xcodebuild -project cmux.xcodeproj -scheme cmux-unit -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-agentlayout build 2>&1 | tail -15
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Sources/WorkspaceSnapshotSocketSupport.swift Sources/TerminalController.swift
git commit -m "Add workspace.snapshot read-only socket command (layout tree + descriptors + actions)"
```

---

### Task 3: `cmux snapshot` CLI subcommand

**Files:**
- Modify: `CLI/cmux.swift` (add subcommand near the dispatch ~line 3090)

- [ ] **Step 1: Add the subcommand**

After the early-return command checks, add: if `command == "snapshot"`, build the socket client, call `try client.sendV2(method: "workspace.snapshot", params: anchorParams())` where `anchorParams()` includes `surface_id`/`workspace_id` from env when present, then print the JSON result to stdout (pretty when stdout is a TTY, compact otherwise). Reuse the existing socket-client construction used by other commands.

- [ ] **Step 2: Build the CLI + manual check**

```bash
CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag agentlayout 2>&1 | tail -8
CMUX_TAG=agentlayout scripts/cmux-debug-cli.sh snapshot --workspace workspace:1 2>&1 | head -40
```
Expected: prints the layout JSON with `tree`, per-surface descriptors, and `actions`.

- [ ] **Step 3: Commit**

```bash
git add CLI/cmux.swift
git commit -m "Add cmux snapshot CLI subcommand (prints workspace.snapshot JSON)"
```

---

### Task 4: Smart `cmux open` (placement policy wired to primitives)

**Files:**
- Modify: `CLI/cmux_open.swift` (`runOpenCommand` ~658–756, `parseOpenArguments` ~1077–1128)
- Modify: `CLI/cmux.swift` if a shared socket helper is needed

- [ ] **Step 1: Parse new flags** in `parseOpenArguments`: `--here`, `--tab` (→ `forceHere`), `--split <left|right|up|down>` (→ `forcedSplit`), `--no-focus` (→ focus=false), `--no-reuse`.

- [ ] **Step 2: Branch file-opens through the policy**

In `runOpenCommand`, for a FILE target (keep dirs/URLs as-is): if no explicit `--pane`/`--surface` destination and not `--here`, fetch `workspace.snapshot`, decode into `LayoutSnapshot` (import `CmuxLayoutPolicy`), run `PlacementPolicy().decide(filePath:in:anchorSurfaceId:overrides:)` with `anchorSurfaceId = CMUX_SURFACE_ID`, then execute:
  - `.reuse(id)` → `surface.focus` (respect `--no-focus`).
  - `.newTab(inPaneId)` → `file.open` with `pane_id`.
  - `.here(paneId)` → `file.open` with `pane_id` = anchor pane.
  - `.splitRight(fromSurfaceId)` → `pane.create` `{direction:"right"}` → take `pane_id` from result → `file.open` `{pane_id, paths, focus}`.
Explicit `--pane`/`--surface`/`--here`/`--split` short-circuit the snapshot fetch appropriately. Show the full Swift branch (no placeholders) using `sendV2`.

- [ ] **Step 3: Build + behavioral check (executed, not just typed)**

```bash
CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag agentlayout --launch 2>&1 | tail -8
# in a single-pane workspace: opening should create a right split with the file
CMUX_TAG=agentlayout scripts/cmux-debug-cli.sh open /etc/hosts --workspace workspace:1 --surface surface:1
CMUX_TAG=agentlayout scripts/cmux-debug-cli.sh snapshot --workspace workspace:1 | rg -i "filePreview|hosts|split|horizontal"
```
Expected: snapshot now shows a horizontal split with a `filePreview` surface for `/etc/hosts`. Re-running `open /etc/hosts` reuses it (no 2nd preview).

- [ ] **Step 4: Commit**

```bash
git add CLI/cmux_open.swift CLI/cmux.swift
git commit -m "cmux open: smart placement via PlacementPolicy (beside split / neighbor tab / reuse)"
```

---

### Task 5: Reorg verbs (`move-tab`, `reorder-tab`, `swap-panes`) + target resolution

**Files:**
- Create: `Packages/CmuxLayoutPolicy/Sources/CmuxLayoutPolicy/TargetResolver.swift` (pure resolution: human refs → ids)
- Create: `Packages/CmuxLayoutPolicy/Tests/CmuxLayoutPolicyTests/TargetResolverTests.swift`
- Modify: `CLI/cmux.swift` (three subcommands)

- [ ] **Step 1: `TargetResolver` (pure) + RED tests**

`resolvePane(_ ref: String, anchorPaneId:, in: LayoutSnapshot) -> String?` where `ref` ∈ {a pane id, `left`/`right`/`up`/`down` relative to anchor, or `focused`}; and `resolveSurface(_ ref:, in:) -> String?` where `ref` ∈ {surface id, or a title/filename substring match}. Write failing tests first (e.g. `right` → neighbor pane id; `"eval.mp4"` → matching surface id; ambiguous match → nil). Commit RED, then implement, commit GREEN (two commits).

- [ ] **Step 2: CLI subcommands** in `cmux.swift`:
  - `move-tab <surfaceRef> --to-pane <paneRef>` → resolve via snapshot → `surface.move` `{surface_id, pane_id, focus}`.
  - `reorder-tab <surfaceRef> --index N | --before/--after <surfaceRef>` → `surface.reorder`.
  - `swap-panes <paneRefA> <paneRefB>` → `pane.swap` `{pane_id, target_pane_id}`.
Each fetches `workspace.snapshot`, resolves refs with `TargetResolver`, then issues the socket call. Show full Swift.

- [ ] **Step 3: Build + behavioral check**

```bash
CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag agentlayout --launch 2>&1 | tail -6
CMUX_TAG=agentlayout scripts/cmux-debug-cli.sh move-tab "hosts" --to-pane left --workspace workspace:1
CMUX_TAG=agentlayout scripts/cmux-debug-cli.sh snapshot --workspace workspace:1 | rg -i "hosts|pane_id"
```
Expected: the `hosts` preview tab moves to the left pane.

- [ ] **Step 4: Commit** (the GREEN target-resolver commit + CLI verbs commit)

```bash
git add Packages/CmuxLayoutPolicy CLI/cmux.swift
git commit -m "Add reorg verbs (move-tab/reorder-tab/swap-panes) + tested target resolution"
```

---

### Task 6: Auto-discovery — capability brief env var + claude wrapper injection

**Files:**
- Create: `Sources/AgentCapabilityBrief.swift` (the brief text constant + a builder reading the setting)
- Modify: `Sources/TerminalStartupEnvironment.swift` (set `CMUX_AGENT_CAPABILITY_BRIEF` when enabled)
- Modify: `Resources/bin/claude` (inject `--append-system-prompt` when the env var is non-empty)

- [ ] **Step 1: Brief constant**

`enum AgentCapabilityBrief { static let text = "…" }` — ≤6 lines, e.g.: "You're inside cmux. When the user asks to see/open/pull up a file, run `cmux open <FILE>` (cmux places it beside them). `cmux snapshot` returns the current layout as JSON. Rearrange with `cmux move-tab <tab> --to-pane <left|right|…>`, `cmux reorder-tab`, `cmux swap-panes`. Use these only when the user asks to view or arrange things."

- [ ] **Step 2: Set the env var (gated by setting)**

In `TerminalStartupEnvironment`, when `AutomationCatalogSection.agentCapabilityBrief` (Task 7) is true, `setManagedEnvironmentValue("CMUX_AGENT_CAPABILITY_BRIEF", AgentCapabilityBrief.text)`; otherwise leave unset. (Read the value the same way other catalog-backed booleans are read at this layer.)

- [ ] **Step 3: Wrapper injection**

In `Resources/bin/claude`, change the exec lines (~484–488) to conditionally add the flag:
```bash
EXTRA_ARGS=()
if [[ -n "$CMUX_AGENT_CAPABILITY_BRIEF" ]]; then
  EXTRA_ARGS+=(--append-system-prompt "$CMUX_AGENT_CAPABILITY_BRIEF")
fi
if [[ "$SKIP_SESSION_ID" == true ]]; then
  exec "$REAL_CLAUDE" --settings "$HOOKS_JSON" "${EXTRA_ARGS[@]}" "$@"
else
  SESSION_ID="$(uuidgen | tr '[:upper:]' '[:lower:]')"
  exec "$REAL_CLAUDE" --session-id "$SESSION_ID" --settings "$HOOKS_JSON" "${EXTRA_ARGS[@]}" "$@"
fi
```

- [ ] **Step 4: Build + verify the flag is passed**

```bash
CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag agentlayout --launch 2>&1 | tail -6
# In a terminal in the tagged app, the brief env var should be set:
CMUX_TAG=agentlayout scripts/cmux-debug-cli.sh send --workspace workspace:1 --surface surface:1 "$(printf 'printf %%s\\\\n \"$CMUX_AGENT_CAPABILITY_BRIEF\"\r')"
CMUX_TAG=agentlayout scripts/cmux-debug-cli.sh read-screen --workspace workspace:1 --surface surface:1 | tail -3
```
Expected: the brief text prints (env var is set). Wrapper-flag behavior is covered by Step-1 of Task 8.

- [ ] **Step 5: Commit**

```bash
git add Sources/AgentCapabilityBrief.swift Sources/TerminalStartupEnvironment.swift Resources/bin/claude
git commit -m "Auto-inject cmux capability brief into Claude Code via wrapper --append-system-prompt"
```

---

### Task 7: Setting `automation.agentCapabilityBrief` (catalog + UI + palette + schema + docs + l10n)

**Files:**
- Modify: `Packages/CmuxSettings/Sources/CmuxSettings/Keys/AutomationCatalogSection.swift`
- Modify: `Packages/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/<Automation section>.swift` (+ `CuratedSettingEntry+Default.swift`)
- Modify: `Sources/CommandPalette/CommandPaletteSettingsToggle.swift`
- Modify: `Resources/Localizable.xcstrings` (en + ja)
- Modify: `web/data/cmux.schema.json`, `skills/cmux-settings/references/all-keys.md`

- [ ] **Step 1: Catalog key**

```swift
public let agentCapabilityBrief = DefaultsKey<Bool>(
    id: "automation.agentCapabilityBrief",
    defaultValue: true,
    userDefaultsKey: "automation.agentCapabilityBrief"
)
```

- [ ] **Step 2–6:** Add the Settings-window row (mirror an existing Automation toggle: `@State` model + `Toggle` + `configurationReview: .json("automation.agentCapabilityBrief")` + a `CuratedSettingEntry`), a `CommandPaletteSettingToggleDescriptor` (commandId `…terminal… ` → use automation prefix; defaultsKey = catalog key), the `cmux.schema.json` property, the `all-keys.md` row, and en+ja strings for title (e.g. "Tell agents about cmux layout commands") + subtitles. Follow the exact pattern used by existing automation toggles.

- [ ] **Step 7: Build + localization audit**

```bash
CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag agentlayout 2>&1 | tail -6
python3 - <<'PY'
import json; d=json.load(open('Resources/Localizable.xcstrings'))['strings']
for k in ['settings.automation.agentCapabilityBrief']:
    print(k, sorted(d.get(k,{}).get('localizations',{})))
PY
```
Expected: build green; key present with `['en','ja']`.

- [ ] **Step 8: Commit**

```bash
git add Packages Sources Resources web skills
git commit -m "Add automation.agentCapabilityBrief setting (catalog, UI, palette, schema, docs, l10n)"
```

---

### Task 8: Integration pass + verification

- [ ] **Step 1: Full test-target compile**

```bash
CMUX_SKIP_ZIG_BUILD=1 xcodebuild -project cmux.xcodeproj -scheme cmux-unit -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-agentlayout build-for-testing 2>&1 | tail -15
./scripts/check-pbxproj.sh && ./scripts/lint-pbxproj-test-wiring.sh
```
Expected: `** TEST BUILD SUCCEEDED **`; guards pass.

- [ ] **Step 2: Policy tests green** — `cd Packages/CmuxLayoutPolicy && swift test 2>&1 | tail -5` → all pass.

- [ ] **Step 3: End-to-end manual matrix** (tagged app, executed commands via the debug CLI with `\r`):
  - single pane → `cmux open <file>` makes a right split with the file;
  - already side-by-side → `cmux open <file>` adds the file as a tab in the neighbor;
  - re-open same file → reuse;
  - `cmux snapshot` shows tree + descriptors + actions;
  - `cmux move-tab "<name>" --to-pane left` moves it; `swap-panes` swaps;
  - `$CMUX_AGENT_CAPABILITY_BRIEF` is set with the brief; toggling the setting off clears it.

- [ ] **Step 4: Handoff** — summarize built surface, the localization audit result, and which agent (Claude Code) gets auto-discovery; note Codex/OpenCode wrappers as the documented fast follow.
