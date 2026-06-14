# Manual-mode Monaco diff Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When a Claude file-edit (`Edit`/`Write`/`MultiEdit`) is pending in manual approval mode, pop a read-only Monaco two-pane diff in a split directly above the agent's pane; Accept/Reject resolves the edit through cmux's existing permission path and closes the pane.

**Architecture:** A pure `CmuxEditPreview` package turns the hook's `tool_input` + the file's current on-disk text into an `EditDiff` (original vs proposed). The existing Monaco WKWebView gains a read-only diff editor. A new `EditReviewPanel` (a `Panel`) hosts that diff plus an Accept/Reject toolbar wired to the **existing** `feed.permission.reply`. A coordinator hook in `FeedCoordinator` opens the panel above the agent when a file-edit permission arrives (gated by a new setting) and closes it on resolution/timeout. No new control path — the permission decision plumbing (`feed.push` blocking → `deliverReply`) is reused verbatim.

**Tech Stack:** Swift 6 / SwiftUI / AppKit, WKWebView + Monaco 0.55.1 (`createDiffEditor`), Swift Package (SPM) for the pure core, Swift Testing for unit tests, bonsplit layout.

**Spec:** `docs/superpowers/specs/2026-06-13-manual-edit-diff-design.md`

**Branch:** `manual-edit-diff` (already created off `origin/main`).

---

## Key verified seams (from codebase exploration — real, not placeholders)

- Monaco controller: `Sources/Monaco/MonacoWebController.swift` — `load(text:language:theme:)`, `jsonArgs(_:)` (JSON-encodes args into a JS array literal), `isReady`/`pendingLoad`/`applyPendingLoad()`, ready via `MonacoBridgeMessage.ready`.
- Monaco HTML: `Resources/monaco/monaco.html` — single `var editor = monaco.editor.create(document.getElementById("container"), …)`; `window.cmuxMonaco = { setContent, applyExternalChange, setTheme, focus, currentValue, flushSave }`. Themes: `"vs"` (light) / `"vs-dark"` (dark).
- Language map: `Sources/Monaco/MonacoLanguageMap.swift` — `enum MonacoLanguageMap { static func languageId(forPath:) -> String }` (app-internal; **not** in a package). The app computes language at render time; the pure package carries only `filePath`.
- Permission flow: `Sources/Feed/FeedCoordinator.swift` — `ingestBlocking(event:waitTimeout:) -> IngestBlockingResult`, `deliverReply(requestId:decision:)`, `PendingWaiter`; the item payload is `WorkstreamPayload.permissionRequest(requestId:toolName:toolInputJSON:pattern:)`; item has `workstreamId` (e.g. `claude-<sessionId>`).
- Decision enums (`Packages/CMUXWorkstream`): `WorkstreamPermissionMode { once, always, all, bypass, deny }`, `WorkstreamDecision.permission(WorkstreamPermissionMode)`.
- Reply UI: `Sources/Feed/FeedPanelView.swift` `PermissionActionArea` → `onApprove(.once|.deny|.always)`; `FeedRowActions.approvePermission(itemId, mode)` → `FeedCoordinator.shared.deliverReply(requestId:decision:.permission(mode))`.
- Anchor resolution: `FeedJumpResolver.parse(_ workstreamId) -> (agent, sessionId)?`, `FeedJumpResolver.lookup(agent:sessionId:) -> Target?` where `struct Target { let workspaceId: String; let surfaceId: String }` (reads `~/.cmuxterm/<agent>-hook-sessions.json`). Focus handler posts `.feedRequestFocus` with `{workspaceId, surfaceId}`.
- Surface→pane: `Workspace.panelIdFromSurfaceId(_ surfaceId: TabID) -> UUID?`, `Workspace.paneId(forPanelId: UUID) -> PaneID?`, `AppDelegate.locateSurface(surfaceId: UUID) -> (windowId, workspaceId, tabManager)?`.
- Split-above + host panel (the pattern to mirror): `Workspace.splitPaneWithFilePreview(targetPane:orientation:insertFirst:filePath:) -> FilePreviewPanel?` (uses `bonsplitController.splitPane(_:orientation:withTab:insertFirst:)`; `.vertical` + `insertFirst: true` = new pane on top). Close: `Workspace.closePanel(_ panelId: UUID, force: Bool) -> Bool`.
- Panel model: `Sources/Panels/Panel.swift` — `enum PanelType { terminal, browser, markdown, filePreview, rightSidebarTool, project, extensionBrowser }`; `protocol Panel: AnyObject, Identifiable, ObservableObject where ID == UUID { … close(); focus(); … }`. `FilePreviewPanel` (`Sources/Panels/FilePreviewPanel.swift`) is the reference conformance to mirror.
- Setting pattern to mirror: `automation.agentCapabilityBrief` / `automation.suppressSubagentNotifications` across `Packages/CmuxSettings/Sources/CmuxSettings/Keys/AutomationCatalogSection.swift`, `Packages/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/AutomationSection.swift`, `Sources/CommandPalette/CommandPaletteSettingsToggle.swift`, `web/data/cmux.schema.json`, `skills/cmux-settings/references/all-keys.md`, `Resources/Localizable.xcstrings`.
- Package wiring to mirror: `Packages/CmuxLayoutPolicy/` + its entries in `cmux.xcodeproj/project.pbxproj` (one `XCLocalSwiftPackageReference`, `XCSwiftPackageProductDependency` linked into **both** `cmux` and `cmux-unit`, and a `PBXBuildFile` in each target's Frameworks phase). Guards: `scripts/normalize-pbxproj.py`, `scripts/check-pbxproj.sh`, `scripts/lint-pbxproj-test-wiring.sh`.

**Build/test policy (from CLAUDE.md):** never run app/E2E/socket tests locally. A standalone `swift test` on the pure SPM package does **not** launch the app and is the same gate used for `CmuxLayoutPolicy` — allowed. For app compilation use a tagged derivedDataPath: `xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-medit build`. For the test target use `-scheme cmux-unit`.

---

## File structure

**Create:**
- `Packages/CmuxEditPreview/Package.swift`
- `Packages/CmuxEditPreview/Sources/CmuxEditPreview/ProposedEdit.swift` — value model of a parsed Claude edit.
- `Packages/CmuxEditPreview/Sources/CmuxEditPreview/SingleEdit.swift` — one `old→new` replacement (used by `Edit`/`MultiEdit`).
- `Packages/CmuxEditPreview/Sources/CmuxEditPreview/EditDiff.swift` — `{ filePath, originalText, modifiedText, isNewFile }`.
- `Packages/CmuxEditPreview/Sources/CmuxEditPreview/EditPreviewComputer.swift` — `compute(_:originalText:) -> EditDiff?` (nil when not applicable).
- `Packages/CmuxEditPreview/Tests/CmuxEditPreviewTests/ProposedEditParsingTests.swift`
- `Packages/CmuxEditPreview/Tests/CmuxEditPreviewTests/EditPreviewComputerTests.swift`
- `Sources/Monaco/MonacoDiffView.swift` — NSViewRepresentable for the read-only diff.
- `Sources/Panels/EditReviewPanel.swift` — the `Panel` hosting the diff + Accept/Reject toolbar.
- `Sources/Panels/EditReviewPanelView.swift` — its SwiftUI body.
- `Sources/Feed/EditReviewCoordinator.swift` — opens/closes the review panel for a pending file-edit permission.

**Modify:**
- `Resources/monaco/monaco.html` — add `setDiff(...)` to `window.cmuxMonaco`.
- `Sources/Monaco/MonacoWebController.swift` — add `loadDiff(original:modified:language:theme:)`.
- `Sources/Workspace.swift` — add `splitPaneWithEditReview(...)` mirroring `splitPaneWithFilePreview(...)`.
- `Sources/Feed/FeedCoordinator.swift` — call the coordinator on file-edit ingest + on reply/timeout.
- `Packages/CmuxSettings/Sources/CmuxSettings/Keys/AutomationCatalogSection.swift`, `Packages/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/AutomationSection.swift`, `Sources/CommandPalette/CommandPaletteSettingsToggle.swift`, `web/data/cmux.schema.json`, `skills/cmux-settings/references/all-keys.md`, `Resources/Localizable.xcstrings` — the setting.
- `cmux.xcodeproj/project.pbxproj` — wire `CmuxEditPreview` + new app source files.

---

## Task 1: `CmuxEditPreview` pure package (parse + compute the diff)

**Files:**
- Create: `Packages/CmuxEditPreview/Package.swift`
- Create: `Packages/CmuxEditPreview/Sources/CmuxEditPreview/{ProposedEdit,SingleEdit,EditDiff,EditPreviewComputer}.swift`
- Test: `Packages/CmuxEditPreview/Tests/CmuxEditPreviewTests/{ProposedEditParsingTests,EditPreviewComputerTests}.swift`

- [ ] **Step 1: Create the package manifest**

`Packages/CmuxEditPreview/Package.swift`:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CmuxEditPreview",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CmuxEditPreview", targets: ["CmuxEditPreview"])],
    targets: [
        .target(
            name: "CmuxEditPreview",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
                .enableUpcomingFeature("InternalImportsByDefault"),
            ]
        ),
        .testTarget(name: "CmuxEditPreviewTests", dependencies: ["CmuxEditPreview"]),
    ]
)
```

- [ ] **Step 2: Write the value types (no test yet — they are data the tests reference)**

`Packages/CmuxEditPreview/Sources/CmuxEditPreview/SingleEdit.swift`:
```swift
/// One `old_string` → `new_string` replacement, as proposed by a Claude `Edit`/`MultiEdit` tool call.
public struct SingleEdit: Equatable, Sendable {
    /// The text to find in the file.
    public let oldString: String
    /// The text to replace it with.
    public let newString: String
    /// Whether every occurrence is replaced (Claude's `replace_all`); when `false`, only the first.
    public let replaceAll: Bool

    /// Creates a single replacement.
    public init(oldString: String, newString: String, replaceAll: Bool) {
        self.oldString = oldString
        self.newString = newString
        self.replaceAll = replaceAll
    }
}
```

`Packages/CmuxEditPreview/Sources/CmuxEditPreview/ProposedEdit.swift`:
```swift
import Foundation

/// A parsed, file-targeted edit proposed by a Claude tool call (`Write`/`Edit`/`MultiEdit`).
///
/// Build one with ``ProposedEdit/from(toolName:toolInputJSON:)``; feed it to
/// ``EditPreviewComputer`` together with the file's current contents to get an ``EditDiff``.
public struct ProposedEdit: Equatable, Sendable {
    /// What kind of mutation the tool proposes.
    public enum Kind: Equatable, Sendable {
        /// `Write`: replace the whole file (or create it) with `content`.
        case write(content: String)
        /// `Edit`: a single `old→new` replacement.
        case edit(SingleEdit)
        /// `MultiEdit`: apply replacements in order.
        case multiEdit([SingleEdit])
    }

    /// Absolute path of the file the tool will write.
    public let filePath: String
    /// The proposed mutation.
    public let kind: Kind

    /// Creates a proposed edit from already-parsed parts.
    public init(filePath: String, kind: Kind) {
        self.filePath = filePath
        self.kind = kind
    }

    /// Parses Claude's `tool_input` JSON for a supported file-edit tool.
    ///
    /// - Parameters:
    ///   - toolName: The tool name (`"Write"`, `"Edit"`, or `"MultiEdit"`; case-insensitive).
    ///   - toolInputJSON: The raw `tool_input` JSON object string from the hook payload.
    /// - Returns: A ``ProposedEdit``, or `nil` if the tool is unsupported or the JSON is malformed
    ///   / missing required fields.
    public static func from(toolName: String, toolInputJSON: String) -> ProposedEdit? {
        guard let data = toolInputJSON.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let filePath = obj["file_path"] as? String, !filePath.isEmpty
        else { return nil }

        switch toolName.lowercased() {
        case "write":
            guard let content = obj["content"] as? String else { return nil }
            return ProposedEdit(filePath: filePath, kind: .write(content: content))
        case "edit":
            guard let edit = Self.singleEdit(from: obj) else { return nil }
            return ProposedEdit(filePath: filePath, kind: .edit(edit))
        case "multiedit":
            guard let rawEdits = obj["edits"] as? [[String: Any]], !rawEdits.isEmpty else { return nil }
            var edits: [SingleEdit] = []
            for raw in rawEdits {
                guard let edit = Self.singleEdit(from: raw) else { return nil }
                edits.append(edit)
            }
            return ProposedEdit(filePath: filePath, kind: .multiEdit(edits))
        default:
            return nil
        }
    }

    /// Reads `old_string` / `new_string` / `replace_all` out of one JSON object.
    private static func singleEdit(from obj: [String: Any]) -> SingleEdit? {
        guard let oldString = obj["old_string"] as? String,
              let newString = obj["new_string"] as? String
        else { return nil }
        let replaceAll = (obj["replace_all"] as? Bool) ?? false
        return SingleEdit(oldString: oldString, newString: newString, replaceAll: replaceAll)
    }
}
```

`Packages/CmuxEditPreview/Sources/CmuxEditPreview/EditDiff.swift`:
```swift
/// The original-vs-proposed text pair to render in a two-pane diff.
///
/// `languageId` is intentionally absent: the app maps `filePath` to a Monaco language at render
/// time via its existing `MonacoLanguageMap`, keeping this package free of presentation concerns.
public struct EditDiff: Equatable, Sendable {
    /// Absolute path of the edited file (used by the app for the title and language id).
    public let filePath: String
    /// The file's current on-disk text (empty when creating a new file).
    public let originalText: String
    /// The text the file would have after the edit is applied.
    public let modifiedText: String
    /// Whether the file does not yet exist (the original side is empty).
    public let isNewFile: Bool

    /// Creates a diff pair.
    public init(filePath: String, originalText: String, modifiedText: String, isNewFile: Bool) {
        self.filePath = filePath
        self.originalText = originalText
        self.modifiedText = modifiedText
        self.isNewFile = isNewFile
    }
}
```

- [ ] **Step 3: Write the failing parsing tests**

`Packages/CmuxEditPreview/Tests/CmuxEditPreviewTests/ProposedEditParsingTests.swift`:
```swift
import Testing
@testable import CmuxEditPreview

@Suite struct ProposedEditParsingTests {
    @Test func parsesWrite() {
        let json = #"{"file_path":"/a/b.swift","content":"hello"}"#
        let edit = ProposedEdit.from(toolName: "Write", toolInputJSON: json)
        #expect(edit == ProposedEdit(filePath: "/a/b.swift", kind: .write(content: "hello")))
    }

    @Test func parsesEditWithReplaceAllDefaultFalse() {
        let json = #"{"file_path":"/a/b.swift","old_string":"foo","new_string":"bar"}"#
        let edit = ProposedEdit.from(toolName: "Edit", toolInputJSON: json)
        #expect(edit == ProposedEdit(filePath: "/a/b.swift",
                                     kind: .edit(SingleEdit(oldString: "foo", newString: "bar", replaceAll: false))))
    }

    @Test func parsesMultiEditInOrder() {
        let json = #"{"file_path":"/a/b.swift","edits":[{"old_string":"a","new_string":"b"},{"old_string":"c","new_string":"d","replace_all":true}]}"#
        let edit = ProposedEdit.from(toolName: "MultiEdit", toolInputJSON: json)
        #expect(edit == ProposedEdit(filePath: "/a/b.swift", kind: .multiEdit([
            SingleEdit(oldString: "a", newString: "b", replaceAll: false),
            SingleEdit(oldString: "c", newString: "d", replaceAll: true),
        ])))
    }

    @Test func rejectsUnsupportedTool() {
        let json = #"{"file_path":"/a/b.swift","content":"x"}"#
        #expect(ProposedEdit.from(toolName: "Bash", toolInputJSON: json) == nil)
    }

    @Test func rejectsMalformedJSON() {
        #expect(ProposedEdit.from(toolName: "Write", toolInputJSON: "not json") == nil)
    }
}
```

- [ ] **Step 4: Run parsing tests to verify they pass**

Run: `cd Packages/CmuxEditPreview && swift test`
Expected: PASS — the parsing value types (`ProposedEdit`/`SingleEdit`) exist from Step 2, so `ProposedEditParsingTests` builds and passes. (The computer and its tests come next; this confirms the parser is correct in isolation first.)

- [ ] **Step 5: Write the failing computer tests**

`Packages/CmuxEditPreview/Tests/CmuxEditPreviewTests/EditPreviewComputerTests.swift`:
```swift
import Testing
@testable import CmuxEditPreview

@Suite struct EditPreviewComputerTests {
    let computer = EditPreviewComputer()

    @Test func writeOverwriteUsesDiskAsOriginal() {
        let edit = ProposedEdit(filePath: "/a.txt", kind: .write(content: "new"))
        let diff = computer.compute(edit, originalText: "old")
        #expect(diff == EditDiff(filePath: "/a.txt", originalText: "old", modifiedText: "new", isNewFile: false))
    }

    @Test func writeNewFileHasEmptyOriginalAndFlag() {
        let edit = ProposedEdit(filePath: "/a.txt", kind: .write(content: "new"))
        let diff = computer.compute(edit, originalText: nil)
        #expect(diff == EditDiff(filePath: "/a.txt", originalText: "", modifiedText: "new", isNewFile: true))
    }

    @Test func editReplacesFirstOccurrence() {
        let edit = ProposedEdit(filePath: "/a.txt",
                                kind: .edit(SingleEdit(oldString: "x", newString: "y", replaceAll: false)))
        let diff = computer.compute(edit, originalText: "x and x")
        #expect(diff?.modifiedText == "y and x")
    }

    @Test func editReplaceAllReplacesEvery() {
        let edit = ProposedEdit(filePath: "/a.txt",
                                kind: .edit(SingleEdit(oldString: "x", newString: "y", replaceAll: true)))
        let diff = computer.compute(edit, originalText: "x and x")
        #expect(diff?.modifiedText == "y and y")
    }

    @Test func multiEditAppliesSequentially() {
        let edit = ProposedEdit(filePath: "/a.txt", kind: .multiEdit([
            SingleEdit(oldString: "1", newString: "2", replaceAll: false),
            SingleEdit(oldString: "2", newString: "3", replaceAll: false),
        ]))
        // "1" -> "2" makes "2 2"; next replaces first "2" -> "3" => "3 2".
        let diff = computer.compute(edit, originalText: "1 2")
        #expect(diff?.modifiedText == "3 2")
    }

    @Test func nonApplicableWhenOldStringMissing() {
        let edit = ProposedEdit(filePath: "/a.txt",
                                kind: .edit(SingleEdit(oldString: "zzz", newString: "y", replaceAll: false)))
        #expect(computer.compute(edit, originalText: "abc") == nil)
    }

    @Test func editOnMissingFileIsNonApplicable() {
        let edit = ProposedEdit(filePath: "/a.txt",
                                kind: .edit(SingleEdit(oldString: "x", newString: "y", replaceAll: false)))
        #expect(computer.compute(edit, originalText: nil) == nil)
    }
}
```

Then run `cd Packages/CmuxEditPreview && swift test` — Expected: FAIL to build, error names `EditPreviewComputer` (referenced by the new suite, not yet defined). That is the red state.

- [ ] **Step 6: Implement `EditPreviewComputer`**

`Packages/CmuxEditPreview/Sources/CmuxEditPreview/EditPreviewComputer.swift`:
```swift
import Foundation

/// Turns a ``ProposedEdit`` plus the file's current text into an ``EditDiff``.
///
/// Returns `nil` ("not applicable") when the edit cannot be represented as a clean before/after —
/// e.g. an `Edit`/`MultiEdit` whose `old_string` is absent from the original, or an `Edit` on a
/// file that does not exist. Callers fall back to the raw permission UI in that case.
///
/// ```swift
/// let computer = EditPreviewComputer()
/// if let diff = computer.compute(edit, originalText: onDiskText) {
///     // render diff.originalText vs diff.modifiedText
/// }
/// ```
public struct EditPreviewComputer: Sendable {
    /// Creates a computer. Stateless; cheap to make per call.
    public init() {}

    /// Computes the before/after pair, or `nil` when the edit is not cleanly applicable.
    ///
    /// - Parameters:
    ///   - edit: The parsed proposed edit.
    ///   - originalText: The file's current on-disk text, or `nil` if the file does not exist.
    /// - Returns: An ``EditDiff``, or `nil` when not applicable.
    public func compute(_ edit: ProposedEdit, originalText: String?) -> EditDiff? {
        switch edit.kind {
        case let .write(content):
            return EditDiff(filePath: edit.filePath,
                            originalText: originalText ?? "",
                            modifiedText: content,
                            isNewFile: originalText == nil)
        case let .edit(single):
            guard let original = originalText,
                  let modified = Self.apply([single], to: original) else { return nil }
            return EditDiff(filePath: edit.filePath, originalText: original,
                            modifiedText: modified, isNewFile: false)
        case let .multiEdit(edits):
            guard let original = originalText,
                  let modified = Self.apply(edits, to: original) else { return nil }
            return EditDiff(filePath: edit.filePath, originalText: original,
                            modifiedText: modified, isNewFile: false)
        }
    }

    /// Applies replacements in order; returns `nil` if any `old_string` is not found at its turn.
    private static func apply(_ edits: [SingleEdit], to original: String) -> String? {
        var text = original
        for edit in edits {
            guard text.contains(edit.oldString) else { return nil }
            if edit.replaceAll {
                text = text.replacingOccurrences(of: edit.oldString, with: edit.newString)
            } else if let range = text.range(of: edit.oldString) {
                text.replaceSubrange(range, with: edit.newString)
            } else {
                return nil
            }
        }
        return text
    }
}
```

- [ ] **Step 7: Run all package tests to verify they pass**

Run: `cd Packages/CmuxEditPreview && swift test`
Expected: PASS — all `ProposedEditParsingTests` and `EditPreviewComputerTests` green.

- [ ] **Step 8: Commit**

```bash
git add Packages/CmuxEditPreview
git commit -m "Add CmuxEditPreview package: parse + compute proposed-edit diffs"
```

---

## Task 2: Monaco read-only diff editor

**Files:**
- Modify: `Resources/monaco/monaco.html`
- Modify: `Sources/Monaco/MonacoWebController.swift`
- Create: `Sources/Monaco/MonacoDiffView.swift`

- [ ] **Step 1: Add `setDiff` to the Monaco HTML bridge**

In `Resources/monaco/monaco.html`, immediately after the `var editor = monaco.editor.create(...)` block, add a diff-editor holder:
```javascript
var diffEditor = null;
```

Then add a `setDiff` method inside the `window.cmuxMonaco = { ... }` object (e.g. right after `setContent`):
```javascript
  setDiff: function (original, modified, language, theme) {
    if (theme) monaco.editor.setTheme(theme);
    var originalModel = monaco.editor.createModel(original, language || "plaintext");
    var modifiedModel = monaco.editor.createModel(modified, language || "plaintext");
    if (!diffEditor) {
      // Hide the single editor's container child usage by reusing the same container;
      // the diff editor takes over the container element.
      diffEditor = monaco.editor.createDiffEditor(document.getElementById("container"), {
        automaticLayout: true,
        readOnly: true,
        originalEditable: false,
        renderSideBySide: true,
        minimap: { enabled: false },
        scrollBeyondLastLine: false
      });
    }
    diffEditor.setModel({ original: originalModel, modified: modifiedModel });
  },
```

Note: a panel uses **either** `setContent` **or** `setDiff`, never both, so the single `editor` and `diffEditor` do not need to coexist visually. The `EditReviewPanel` only calls `setDiff`.

- [ ] **Step 2: Add `loadDiff` to `MonacoWebController`**

In `Sources/Monaco/MonacoWebController.swift`, add a pending-diff field next to `pendingLoad`:
```swift
    private var pendingDiff: (original: String, modified: String, language: String, theme: String)?
```

In `userContentController(_:didReceive:)`, in the `.ready` case, after `applyPendingLoad()`, also apply a pending diff:
```swift
        case .ready:
            isReady = true
            applyPendingLoad()
            applyPendingDiff()
```

Add the method (mirroring `applyPendingLoad`'s `jsonArgs` + `evaluateJavaScript` shape):
```swift
    /// Loads a read-only two-pane diff (original vs modified) into the editor.
    ///
    /// If the web view is not ready yet, the diff is queued and applied on `ready`.
    /// A controller used for a diff shows only the diff editor; it does not also call ``load``.
    func loadDiff(original: String, modified: String, language: String, theme: String) {
        pendingDiff = (original, modified, language, theme)
        guard isReady else { return }
        applyPendingDiff()
    }

    private func applyPendingDiff() {
        guard let webView, let d = pendingDiff else { return }
        let args = jsonArgs(d.original, d.modified, d.language, d.theme)
        webView.evaluateJavaScript(
            "window.cmuxMonaco && window.cmuxMonaco.setDiff(\(args)[0], \(args)[1], \(args)[2], \(args)[3]);",
            completionHandler: nil
        )
    }
```

- [ ] **Step 3: Add the `MonacoDiffView` representable**

`Sources/Monaco/MonacoDiffView.swift`:
```swift
import AppKit
import SwiftUI
import WebKit

/// SwiftUI host for a read-only Monaco diff, driven by a panel-owned ``MonacoWebController``.
///
/// Mirrors ``MonacoEditorView`` but renders an original-vs-modified diff via
/// ``MonacoWebController/loadDiff(original:modified:language:theme:)``.
struct MonacoDiffView: NSViewRepresentable {
    /// The panel-owned controller that owns the web view and bridge.
    let controller: MonacoWebController
    /// The file's current text (left/original pane).
    let original: String
    /// The proposed text (right/modified pane).
    let modified: String
    /// The Monaco language id (see `MonacoLanguageMap`).
    let language: String
    /// Whether the cmux appearance is dark (selects the `vs-dark` theme).
    let isDark: Bool

    func makeNSView(context: Context) -> WKWebView {
        let webView = controller.makeWebView()
        applyAppearance(to: webView)
        controller.loadDiff(original: original, modified: modified, language: language, theme: theme)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        applyAppearance(to: nsView)
        controller.setTheme(theme)
    }

    private var theme: String { isDark ? "vs-dark" : "vs" }

    private func applyAppearance(to webView: WKWebView) {
        let appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
        if webView.appearance !== appearance {
            webView.appearance = appearance
        }
    }
}
```

- [ ] **Step 4: Wire `MonacoDiffView.swift` into the pbxproj**

`MonacoDiffView.swift` is a new app-target source. Add it to `cmux.xcodeproj/project.pbxproj` exactly like a sibling Monaco file (`MonacoEditorView.swift`): one `PBXFileReference`, one `PBXBuildFile`, an entry in the `Sources/Monaco` group, and an entry in the `cmux` target's `PBXSourcesBuildPhase`. Mirror `MonacoEditorView.swift`'s four entries; generate fresh unique 24-hex IDs. Then:
```bash
python3 scripts/normalize-pbxproj.py cmux.xcodeproj/project.pbxproj
./scripts/check-pbxproj.sh
```
Expected: both succeed (objectVersion pin + normalization OK).

- [ ] **Step 5: Verify the app compiles**

Run: `xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-medit build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **` (ignore any pre-existing zig/xcframework warnings).

- [ ] **Step 6: Commit**

```bash
git add Resources/monaco/monaco.html Sources/Monaco/MonacoWebController.swift Sources/Monaco/MonacoDiffView.swift cmux.xcodeproj/project.pbxproj
git commit -m "Monaco: add read-only createDiffEditor path (setDiff/loadDiff/MonacoDiffView)"
```

---

## Task 3: `automation.manualEditDiff` setting

**Files:**
- Modify: `Packages/CmuxSettings/Sources/CmuxSettings/Keys/AutomationCatalogSection.swift`
- Modify: `Packages/CmuxSettingsUI/Sources/CmuxSettingsUI/Sections/AutomationSection.swift`
- Modify: `Sources/CommandPalette/CommandPaletteSettingsToggle.swift`
- Modify: `web/data/cmux.schema.json`
- Modify: `skills/cmux-settings/references/all-keys.md`
- Modify: `Resources/Localizable.xcstrings`

- [ ] **Step 1: Add the catalog key**

Open `AutomationCatalogSection.swift`, find the existing `agentCapabilityBrief` (or `suppressSubagentNotifications`) `DefaultsKey<Bool>` declaration, and add a sibling **matching its exact structure**:
```swift
    public let manualEditDiff = DefaultsKey<Bool>(
        id: "automation.manualEditDiff",
        defaultValue: true,
        userDefaultsKey: "manualEditDiffEnabled"
    )
```
(Match the surrounding indentation/formatting; if siblings use a different `userDefaultsKey` convention, follow it — but keep `id: "automation.manualEditDiff"`.)

- [ ] **Step 2: Add the Settings UI row**

In `AutomationSection.swift`, mirror the `agentCapabilityBrief` card. Add, in the same four spots its sibling occupies:

State property (next to the sibling's `@State private var …Model`):
```swift
    @State private var manualEditDiffModel: DefaultsValueModel<Bool>
```
In `init`, next to the sibling's initializer line:
```swift
        _manualEditDiffModel = State(initialValue: DefaultsValueModel(store: defaultsStore, key: catalog.automation.manualEditDiff))
```
In `body`, next to the sibling's card reference:
```swift
            manualEditDiffCard
```
A `@ViewBuilder` card mirroring the sibling card's structure:
```swift
    @ViewBuilder
    private var manualEditDiffCard: some View {
        SettingsCard {
            SettingsCardRow(
                configurationReview: .json("automation.manualEditDiff"),
                String(localized: "settings.automation.manualEditDiff", defaultValue: "Manual Edit Diff"),
                subtitle: manualEditDiffModel.current
                    ? String(localized: "settings.automation.manualEditDiff.subtitleOn", defaultValue: "File edits show a Monaco diff in a split above the agent.")
                    : String(localized: "settings.automation.manualEditDiff.subtitleOff", defaultValue: "File edits use the Feed permission row.")
            ) {
                Toggle("", isOn: Binding(get: { manualEditDiffModel.current }, set: { manualEditDiffModel.set($0) }))
                    .labelsHidden()
                    .controlSize(.small)
                    .accessibilityIdentifier("SettingsManualEditDiffToggle")
            }
            SettingsCardDivider()
            SettingsCardNote(String(localized: "settings.automation.manualEditDiff.note", defaultValue: "When enabled, file-edit permissions in manual approval mode show a Monaco diff for review. When disabled, edits use the traditional Feed permission row."))
        }
    }
```
(If `SettingsCardRow`/`SettingsCardNote`/`configurationReview:` signatures differ from this in the actual sibling card, copy the sibling card verbatim and only change the keys, default text, identifier, and `manualEditDiffModel`.)

- [ ] **Step 3: Add the command-palette toggle**

In `CommandPaletteSettingsToggle.swift`, find the `agentCapabilityBrief` `CommandPaletteSettingToggleDescriptor` and add a sibling:
```swift
            CommandPaletteSettingToggleDescriptor(
                commandId: commandIdPrefix + "manualEditDiff",
                settingsKey: "automation.manualEditDiff",
                title: {
                    String(localized: "settings.automation.manualEditDiff", defaultValue: "Manual Edit Diff")
                },
                sectionTitle: automation,
                keywords: ["automation.manualEditDiff", "edit", "diff", "monaco", "approval", "permission", "manual"],
                defaultValue: true,
                defaultsKey: "manualEditDiffEnabled"
            ),
```
(Match the exact field names of the sibling descriptor; if it has no `defaultsKey`/`defaultValue` field, drop those to match.)

- [ ] **Step 4: Add the JSON schema + docs key**

In `web/data/cmux.schema.json`, inside the `automation` properties object, add (alphabetical position, matching sibling formatting):
```json
        "manualEditDiff": {
          "type": "boolean",
          "default": true,
          "description": "Show a Monaco diff for file edits in manual approval mode."
        },
```
In `skills/cmux-settings/references/all-keys.md`, add the row in alphabetical position among the `automation.*` keys (match the table's existing column format):
```markdown
| `automation.manualEditDiff` | boolean | `true` | Show a Monaco diff for file edits in manual approval mode. |
```

- [ ] **Step 5: Add the 4 localized strings (en + ja) via minimal textual splice**

`Resources/Localizable.xcstrings` is order/format-sensitive — **do not** reserialize it. Insert 4 new keys (`settings.automation.manualEditDiff`, `.subtitleOn`, `.subtitleOff`, `.note`) by textual splice next to an existing `settings.automation.*` key, mirroring its exact JSON structure. Each entry:
```json
    "settings.automation.manualEditDiff" : {
      "extractionState" : "manual",
      "localizations" : {
        "en" : { "stringUnit" : { "state" : "translated", "value" : "Manual Edit Diff" } },
        "ja" : { "stringUnit" : { "state" : "translated", "value" : "手動編集の差分" } }
      }
    },
```
with values:
- `.subtitleOn` → en `"File edits show a Monaco diff in a split above the agent."`, ja `"ファイル編集はエージェントの上の分割にMonaco差分を表示します。"`
- `.subtitleOff` → en `"File edits use the Feed permission row."`, ja `"ファイル編集はFeedの許可行を使用します。"`
- `.note` → en `"When enabled, file-edit permissions in manual approval mode show a Monaco diff for review. When disabled, edits use the traditional Feed permission row."`, ja `"有効にすると、手動承認モードのファイル編集許可がレビュー用のMonaco差分を表示します。無効にすると、従来のFeedの許可行を使用します。"`

Match the exact indentation/quote-spacing of the neighboring key (xcstrings uses `" : "` spacing). Verify the file still parses:
```bash
python3 -c "import json,sys; json.load(open('Resources/Localizable.xcstrings')); print('ok')"
```
Expected: `ok`.

- [ ] **Step 6: Verify Settings packages still build**

Run: `cd Packages/CmuxSettings && swift build && cd ../CmuxSettingsUI && swift build`
Expected: both build (the catalog key + UI row compile). If `CmuxSettingsUI` can't build standalone (missing app deps), instead build the app: `xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-medit build 2>&1 | tail -5` → `** BUILD SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add Packages/CmuxSettings Packages/CmuxSettingsUI Sources/CommandPalette/CommandPaletteSettingsToggle.swift web/data/cmux.schema.json skills/cmux-settings/references/all-keys.md Resources/Localizable.xcstrings
git commit -m "Add automation.manualEditDiff setting (catalog, UI, palette, schema, docs, l10n)"
```

---

## Task 4: `EditReviewPanel` (hosts the diff + Accept/Reject toolbar) + package wiring

**Files:**
- Modify: `cmux.xcodeproj/project.pbxproj` (wire `CmuxEditPreview` into `cmux` and `cmux-unit`; add the two new source files)
- Create: `Sources/Panels/EditReviewPanel.swift`
- Create: `Sources/Panels/EditReviewPanelView.swift`

- [ ] **Step 1: Wire `CmuxEditPreview` into the Xcode project**

Mirror every `CmuxLayoutPolicy` entry in `cmux.xcodeproj/project.pbxproj` for `CmuxEditPreview` (do **not** copy any IDs from notes — grep the live file and generate fresh unique 24-hex IDs):
```bash
grep -n "CmuxLayoutPolicy" cmux.xcodeproj/project.pbxproj
```
For `CmuxEditPreview` add: one `XCLocalSwiftPackageReference` (relativePath `Packages/CmuxEditPreview`) in the project's `packageReferences`; one `XCSwiftPackageProductDependency` (productName `CmuxEditPreview`); and a `PBXBuildFile` in the **Frameworks** build phase of **both** the `cmux` target and the `cmux-unit` target (CmuxLayoutPolicy links into both — match that exactly). Then:
```bash
python3 scripts/normalize-pbxproj.py cmux.xcodeproj/project.pbxproj
./scripts/check-pbxproj.sh
```
Expected: both succeed.

- [ ] **Step 2: Create the `EditReviewPanel`**

`Sources/Panels/EditReviewPanel.swift` — a `Panel` that holds the diff + request id, mirroring `FilePreviewPanel`'s `Panel` conformance boilerplate (focus-intent methods, `triggerFlash`, etc. — copy them from `FilePreviewPanel` and forward/no-op as that file does for a non-terminal panel). The meaningful, non-boilerplate parts are below; everything else is mirrored from `FilePreviewPanel`:

```swift
import AppKit
import CmuxEditPreview
import SwiftUI

/// A non-terminal panel that reviews one pending Claude file edit as a read-only Monaco diff.
///
/// Created above the agent's pane by ``EditReviewCoordinator`` when a file-edit permission is
/// pending. Its Accept / Reject / Always-allow buttons resolve the permission via the existing
/// `feed.permission.reply` path (`FeedCoordinator.deliverReply`), after which the coordinator
/// closes the panel.
@MainActor
final class EditReviewPanel: ObservableObject, Panel {
    let id = UUID()
    let workspaceId: UUID
    /// The permission request this panel reviews; used to resolve the decision.
    let requestId: String
    /// The computed diff to display.
    let diff: EditDiff
    /// Owns the Monaco web view across SwiftUI churn (same pattern as FilePreviewPanel).
    let monacoController = MonacoWebController()

    /// Invoked when the user picks a decision; the coordinator routes it to `deliverReply`.
    var onDecision: ((WorkstreamPermissionMode) -> Void)?

    var panelType: PanelType { .filePreview } // reuse the closest existing kind; see Step 4 note.
    var displayTitle: String { (diff.filePath as NSString).lastPathComponent }
    var displayIcon: String? { "plus.forwardslash.minus" }
    var isDirty: Bool { false }

    init(workspaceId: UUID, requestId: String, diff: EditDiff) {
        self.workspaceId = workspaceId
        self.requestId = requestId
        self.diff = diff
    }

    func close() { /* mirror FilePreviewPanel.close(): tear down monacoController/web view */ }
    func focus() { monacoController.focus() }
    func unfocus() {}

    // Mirror the remaining `Panel` protocol methods (triggerFlash, captureFocusIntent,
    // preferredFocusIntentForActivation, prepareFocusIntentForActivation, restoreFocusIntent,
    // ownedFocusIntent, yieldFocusIntent) from FilePreviewPanel — same no-op/forwarding bodies a
    // non-terminal panel uses there.
}
```

Important: `PanelType` has no `editReview` case. Reusing `.filePreview` avoids a schema/case change; it only affects how the surface is tagged. If `FilePreviewPanel`-specific behavior keys off `panelType == .filePreview` in a way that misbehaves for this panel, add a dedicated `case editReview = "editreview"` to `PanelType` in `Sources/Panels/Panel.swift` instead and handle it wherever `PanelType` is switched. Default to reusing `.filePreview` unless a concrete conflict appears during the build.

- [ ] **Step 3: Create the SwiftUI body with the diff + toolbar**

`Sources/Panels/EditReviewPanelView.swift`:
```swift
import CmuxEditPreview
import SwiftUI

/// The body for an ``EditReviewPanel``: a header, the Monaco diff, and the decision toolbar.
struct EditReviewPanelView: View {
    @ObservedObject var panel: EditReviewPanel
    let isDark: Bool

    private var language: String { MonacoLanguageMap.languageId(forPath: panel.diff.filePath) }

    var body: some View {
        VStack(spacing: 0) {
            header
            MonacoDiffView(
                controller: panel.monacoController,
                original: panel.diff.originalText,
                modified: panel.diff.modifiedText,
                language: language,
                isDark: isDark
            )
            toolbar
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(panel.displayTitle).font(.system(.body, design: .monospaced)).lineLimit(1)
            if panel.diff.isNewFile {
                Text(String(localized: "editReview.newFile", defaultValue: "new file"))
                    .font(.caption).padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            Spacer()
            Button(String(localized: "editReview.reject", defaultValue: "Reject")) {
                panel.onDecision?(.deny)
            }
            .keyboardShortcut(.cancelAction)
            Button(String(localized: "editReview.always", defaultValue: "Always Allow Edits")) {
                panel.onDecision?(.always)
            }
            Button(String(localized: "editReview.accept", defaultValue: "Accept")) {
                panel.onDecision?(.once)
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }
}
```
Add the 4 new localization keys (`editReview.newFile`, `editReview.reject`, `editReview.always`, `editReview.accept`) to `Resources/Localizable.xcstrings` (en + ja) via the same minimal-splice method as Task 3 Step 5. ja values: `"新規ファイル"`, `"却下"`, `"常に編集を許可"`, `"承認"`.

Wire `EditReviewPanelView` to render wherever the workspace maps a panel to its view (find where `FilePreviewPanel` → `FilePreviewPanelView` is dispatched — typically a `switch` on the panel type/instance in the surface host — and add an `if let p = panel as? EditReviewPanel { EditReviewPanelView(panel: p, isDark: …) }` branch using the same `isDark` source the sibling uses).

- [ ] **Step 4: Add both new source files to the pbxproj**

Add `EditReviewPanel.swift` and `EditReviewPanelView.swift` to the `cmux` target (mirror a sibling in `Sources/Panels`, e.g. how `FilePreviewPanel.swift` is referenced): `PBXFileReference` + group entry + `PBXBuildFile` + `PBXSourcesBuildPhase` entry each, fresh unique IDs. Then `python3 scripts/normalize-pbxproj.py cmux.xcodeproj/project.pbxproj` and `./scripts/check-pbxproj.sh`.

- [ ] **Step 5: Verify the app compiles**

Run: `xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-medit build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add cmux.xcodeproj/project.pbxproj Sources/Panels/EditReviewPanel.swift Sources/Panels/EditReviewPanelView.swift Resources/Localizable.xcstrings
git commit -m "Add EditReviewPanel hosting the Monaco diff + decision toolbar; wire CmuxEditPreview"
```

---

## Task 5: `EditReviewCoordinator` — open above the agent, close on decision/timeout

**Files:**
- Modify: `Sources/Workspace.swift` (add `splitPaneWithEditReview(...)`)
- Create: `Sources/Feed/EditReviewCoordinator.swift`
- Modify: `Sources/Feed/FeedCoordinator.swift` (call the coordinator on ingest + reply/timeout)
- Modify: `cmux.xcodeproj/project.pbxproj` (add the new coordinator file)

- [ ] **Step 1: Read the existing focus-resolution seam (investigation step — no code yet)**

Read the `.feedRequestFocus` notification handler (search `Sources/` for `feedRequestFocus`) to learn exactly how the app turns `(workspaceId: String, surfaceId: String)` into a `Workspace` + the agent surface's pane. Note the precise calls it uses (`AppDelegate.locateSurface`, `Workspace.panelIdFromSurfaceId`, `Workspace.paneId(forPanelId:)`, or a workspace lookup by id). Reuse those exact calls in Step 3 so anchoring matches existing behavior. Record the call sequence in the commit message.

- [ ] **Step 2: Add `splitPaneWithEditReview` to `Workspace`**

In `Sources/Workspace.swift`, add a method mirroring `splitPaneWithFilePreview(targetPane:orientation:insertFirst:filePath:)` but hosting an `EditReviewPanel` instead of a `FilePreviewPanel`:
```swift
    /// Splits `paneId` and hosts an ``EditReviewPanel`` reviewing one pending file edit.
    ///
    /// Mirrors ``splitPaneWithFilePreview(targetPane:orientation:insertFirst:filePath:)``; use
    /// `orientation: .vertical, insertFirst: true` to place the review pane directly above.
    func splitPaneWithEditReview(
        targetPane paneId: PaneID,
        orientation: SplitOrientation,
        insertFirst: Bool,
        requestId: String,
        diff: EditDiff
    ) -> EditReviewPanel? {
        let panel = EditReviewPanel(workspaceId: id, requestId: requestId, diff: diff)
        panels[panel.id] = panel
        panelTitles[panel.id] = panel.displayTitle

        let newTab = Bonsplit.Tab(
            title: panel.displayTitle,
            icon: RenderableSystemSymbol.resolvedSurfaceTabIcon(panel.displayIcon),
            kind: SurfaceKind.filePreview,
            isDirty: false,
            isLoading: false,
            isPinned: false
        )
        surfaceIdToPanelId[newTab.id] = panel.id

        isProgrammaticSplit = true
        defer { isProgrammaticSplit = false }
        guard let newPaneId = bonsplitController.splitPane(paneId, orientation: orientation, withTab: newTab, insertFirst: insertFirst) else {
            panels.removeValue(forKey: panel.id)
            panelTitles.removeValue(forKey: panel.id)
            surfaceIdToPanelId.removeValue(forKey: newTab.id)
            return nil
        }
        publishCmuxSplitCreated(newPaneId, sourcePaneId: paneId, orientation: orientation, surfaceId: panel.id, kind: "edit_review", origin: "edit_review_split", focused: true)
        bonsplitController.selectTab(newTab.id)
        panel.focus()
        return panel
    }
```
(Match the surrounding helper names verbatim from `splitPaneWithFilePreview`; the only differences are the panel type, the `kind`/`origin` strings, and that there is no file-preview subscription to install.)

- [ ] **Step 3: Create the coordinator**

`Sources/Feed/EditReviewCoordinator.swift` — owns the request-id → open panel mapping and the open/close lifecycle. Constructor-injected, `@MainActor`, no singleton:
```swift
import AppKit
import CmuxEditPreview
import CMUXWorkstream
import Foundation

/// Opens a read-only edit-review diff above the agent for a pending file-edit permission, and
/// closes it when the permission resolves or times out.
///
/// State-free across requests except for the open-panel registry; constructed once at app startup
/// and handed the resolver/locator closures so it stays testable and free of global singletons.
@MainActor
final class EditReviewCoordinator {
    /// Resolves a workstream id to its (workspaceId, surfaceId) anchor; inject `FeedJumpResolver`.
    private let resolveAnchor: (_ workstreamId: String) -> (workspaceId: String, surfaceId: String)?
    /// Finds the `Workspace` and the agent surface's `PaneID` for an anchor; inject app navigation.
    private let resolvePane: (_ workspaceId: String, _ surfaceId: String) -> (Workspace, PaneID)?
    /// request_id → (workspace, opened panel id), so a reply can close the right pane.
    private var open: [String: (workspace: Workspace, panelId: UUID)] = [:]
    private let computer = EditPreviewComputer()

    init(
        resolveAnchor: @escaping (_ workstreamId: String) -> (workspaceId: String, surfaceId: String)?,
        resolvePane: @escaping (_ workspaceId: String, _ surfaceId: String) -> (Workspace, PaneID)?
    ) {
        self.resolveAnchor = resolveAnchor
        self.resolvePane = resolvePane
    }

    /// Whether the setting is enabled (read from UserDefaults; key mirrors the catalog).
    private var isEnabled: Bool {
        // `manualEditDiff` default is true; honor an explicit false only.
        (UserDefaults.standard.object(forKey: "manualEditDiffEnabled") as? Bool) ?? true
    }

    /// Called when a permission item is ingested. Opens a diff pane if this is an applicable
    /// file edit and the setting is on. `originalText` is read off-main by the caller.
    func handlePending(requestId: String, workstreamId: String, toolName: String,
                       toolInputJSON: String, originalText: String?,
                       onDecision: @escaping (String, WorkstreamPermissionMode) -> Void) {
        guard isEnabled,
              let edit = ProposedEdit.from(toolName: toolName, toolInputJSON: toolInputJSON),
              let diff = computer.compute(edit, originalText: originalText),
              let anchor = resolveAnchor(workstreamId),
              let (workspace, paneId) = resolvePane(anchor.workspaceId, anchor.surfaceId)
        else { return }

        guard let panel = workspace.splitPaneWithEditReview(
            targetPane: paneId, orientation: .vertical, insertFirst: true,
            requestId: requestId, diff: diff
        ) else { return }
        panel.onDecision = { mode in onDecision(requestId, mode) }
        open[requestId] = (workspace, panel.id)
    }

    /// Called when a permission resolves (any source) or times out: closes the diff pane if open.
    func handleResolved(requestId: String) {
        guard let entry = open.removeValue(forKey: requestId) else { return }
        _ = entry.workspace.closePanel(entry.panelId, force: true)
    }
}
```

- [ ] **Step 4: Construct and invoke the coordinator from `FeedCoordinator`**

In `Sources/Feed/FeedCoordinator.swift`:

(a) Construct one `EditReviewCoordinator` at the composition site where `FeedCoordinator`/the app store is assembled (mirror how the app already builds main-actor singletons there). Inject:
- `resolveAnchor`: `{ workstreamId in FeedJumpResolver.parse(workstreamId).flatMap { FeedJumpResolver.lookup(agent: $0.agent, sessionId: $0.sessionId) }.map { ($0.workspaceId, $0.surfaceId) } }`
- `resolvePane`: reuse the exact resolution found in Task 5 Step 1 (the `.feedRequestFocus` handler's path) — locate the `Workspace` by `workspaceId`, then `workspace.panelIdFromSurfaceId(<surfaceId as TabID>)` → `workspace.paneId(forPanelId:)`.

(b) In `ingestBlocking(...)`, when the event is a `.permissionRequest` whose `toolName` ∈ {Edit, Write, MultiEdit}: **before** parking on the semaphore and **off-main**, read the file at the edit's `file_path` (`try? String(contentsOfFile:encoding:.utf8)`, `nil` if absent), then hop to main (the method already hops to main to insert the item) and call:
```swift
editReviewCoordinator.handlePending(
    requestId: requestId,
    workstreamId: event.workstreamId,   // or the item's workstreamId
    toolName: toolName,
    toolInputJSON: toolInputJSON,
    originalText: originalText
) { rid, mode in
    FeedCoordinator.shared.deliverReply(requestId: rid, decision: .permission(mode))
}
```
Read `requestId`/`toolName`/`toolInputJSON` from the same payload fields the item is built from. Keep this additive — the existing insert + block path is unchanged.

(c) In `deliverReply(requestId:decision:)`, after the existing main-actor `markResolved`, also call `editReviewCoordinator.handleResolved(requestId: requestId)` so the pane closes whether the decision came from the diff toolbar **or** the Feed row.

(d) Where `ingestBlocking` returns `.timedOut`, call `editReviewCoordinator.handleResolved(requestId:)` (hop to main) so a timed-out edit closes its pane too.

Note (shared-behavior policy): the diff toolbar and the Feed row both end at `deliverReply(requestId:decision:.permission(mode))` — one decision path, one source of truth. Do not add a second reply route.

- [ ] **Step 5: Add the coordinator file to the pbxproj + build**

Add `Sources/Feed/EditReviewCoordinator.swift` to the `cmux` target (mirror a sibling in `Sources/Feed`), `normalize-pbxproj.py`, `check-pbxproj.sh`, then:
Run: `xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-medit build 2>&1 | tail -5`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Workspace.swift Sources/Feed/EditReviewCoordinator.swift Sources/Feed/FeedCoordinator.swift cmux.xcodeproj/project.pbxproj
git commit -m "Open Monaco edit-review diff above the agent for pending file-edit permissions"
```

---

## Task 6: Build the test target, localization audit, dogfood

**Files:** none new — verification only.

- [ ] **Step 1: Build the unit-test target (proves package + sources are wired for tests)**

Run: `xcodebuild -project cmux.xcodeproj -scheme cmux-unit -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-medit build-for-testing 2>&1 | tail -5`
Expected: `** TEST BUILD SUCCEEDED **`. (Confirms `CmuxEditPreview` links into `cmux-unit` and the new files compile in the test target.)

- [ ] **Step 2: Run the pure-package tests once more**

Run: `cd Packages/CmuxEditPreview && swift test 2>&1 | tail -5`
Expected: all tests pass.

- [ ] **Step 3: pbxproj + test-wiring guards**

Run:
```bash
./scripts/check-pbxproj.sh && ./scripts/lint-pbxproj-test-wiring.sh
```
Expected: both pass.

- [ ] **Step 4: Localization audit**

Enumerate every user-facing string added: the 4 `settings.automation.manualEditDiff*` keys, the 4 `editReview.*` keys, the schema `description`, and the `all-keys.md` row. Verify each `settings.*`/`editReview.*` key has **both** `en` and `ja` `stringUnit`s in `Resources/Localizable.xcstrings`:
```bash
python3 -c "
import json
d=json.load(open('Resources/Localizable.xcstrings'))['strings']
keys=['settings.automation.manualEditDiff','settings.automation.manualEditDiff.subtitleOn','settings.automation.manualEditDiff.subtitleOff','settings.automation.manualEditDiff.note','editReview.newFile','editReview.reject','editReview.always','editReview.accept']
for k in keys:
    locs=d.get(k,{}).get('localizations',{})
    assert 'en' in locs and 'ja' in locs, ('MISSING', k, list(locs))
print('l10n ok: all 8 keys have en+ja')
"
```
Expected: `l10n ok`. Then `rg` the changed Swift/TS/docs files for any bare English in `Text(...)`/`Button(...)` not wrapped in `String(localized:)`; fix any found. State the audit result in the final handoff.

- [ ] **Step 5: Dogfood the live behavior (tagged build)**

```bash
./scripts/reload.sh --tag medit
```
Open the printed `App path:`. In a terminal in the tagged app, run `claude` in **manual approval** mode and ask it to edit a file. Verify: a Monaco diff pane opens **above** the agent; **Accept** applies the edit and the pane closes; on a fresh edit, **Reject** skips it and the pane closes; toggling `automation.manualEditDiff` off falls back to the Feed JSON row. Surface the app link per CLAUDE.md.

- [ ] **Step 6: Final commit (if the audit changed anything)**

```bash
git add -A
git commit -m "Localization audit + verification for manual-mode edit diff"
```

---

## Notes for the executor

- **pbxproj IDs:** never reuse IDs from notes/snippets — grep the live `project.pbxproj`, copy a real sibling's entry shape, and generate fresh unique 24-hex IDs. Always run `normalize-pbxproj.py` then `check-pbxproj.sh` after editing.
- **Mirror, don't invent:** for `Panel` conformance (Task 4) and `splitPaneWithEditReview` (Task 5), copy the exact helper/method names from `FilePreviewPanel` / `splitPaneWithFilePreview`; this plan shows the deltas, not a from-scratch rewrite.
- **One decision path:** Accept/Reject in the diff and the Feed buttons must both terminate at `FeedCoordinator.deliverReply(requestId:decision:.permission(mode))`. Never add a parallel reply route (shared-behavior policy).
- **Off-main file read:** read the original file off-main in `ingestBlocking` before hopping to main to open the panel; never read files on the main actor in the permission hot path.
- **Concurrency:** new code uses `@MainActor`/`@Observable`-style patterns and the existing `MonacoWebController` bridge; no new locks, no `DispatchQueue.main.async` as a synchronization primitive.
```
