# Mermaid Diagram Viewer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `cmux open arch.mmd` opens a minimal, high-fidelity mermaid diagram surface — dot-grid canvas, drag-to-pan, pinch-to-zoom, live reload with a stationary camera, and parse errors reported back to the calling agent.

**Architecture:** This adds no new `PanelType`. `.mmd`/`.mermaid` files route to the existing `MarkdownPanel`, which gains a third `displayMode` case (`.diagram`). Raw `.mmd` content is wrapped in a ` ```mermaid ` fence before being pushed to the existing WebView shell, so the entire existing render path (`__cmuxRenderMarkdown` → `renderMermaidBlocks` → lazy-loaded `mermaid.min.js`) is reused unchanged. Diagram mode is a CSS/JS state in `shell.html` that suppresses document flow and installs a camera transform. Parse failures post back through the existing `cmuxLib` bridge; `v2FileOpen` awaits that callback using the existing `v2AwaitCallback` helper.

**Tech Stack:** Swift 6 / SwiftUI / AppKit, WKWebView, bundled `mermaid.min.js` (already vendored), Swift Testing (`@Test`/`#expect`), Xcode project (`cmux.xcodeproj`).

## Global Constraints

- **Build command:** always `CMUX_SKIP_ZIG_BUILD=1 ./scripts/reload.sh --tag mermaid-viewer`. Never bare `xcodebuild`, never `open` an untagged `cmux DEV.app`. The `CMUX_SKIP_ZIG_BUILD=1` prefix is **required** on this machine — the build pins zig 0.15.2 but the installed zig is 0.16.0, and without it the build fails with `error: zig 0.15.2 is required to build the Ghostty CLI helper`. A prebuilt GhosttyKit xcframework is already present, so skipping is safe.
- **Test scheme is `cmux-unit`, not `cmux`.** The `cmux` scheme cannot run `cmuxTests` at all — it reports "Executed 0 tests" regardless of wiring, which is indistinguishable from a missing-pbxproj failure. Use `cmux-unit` for every `CMUX_SKIP_ZIG_BUILD=1 xcodebuild test` invocation. Keep using `cmux` for compile-only `build` checks.
- **Compile-only check:** `CMUX_SKIP_ZIG_BUILD=1 xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/cmux-mermaid-viewer build`
- **Test command:** `CMUX_SKIP_ZIG_BUILD=1 xcodebuild test -project cmux.xcodeproj -scheme cmux-unit -destination 'platform=macOS' -derivedDataPath /tmp/cmux-mermaid-viewer -only-testing:cmuxTests/<TestClass>`
- **New test files MUST be wired into `cmux.xcodeproj/project.pbxproj`** with all four entries (PBXBuildFile, PBXFileReference, group child, PBXSourcesBuildPhase). An unwired test silently reports "Executed 0 tests". See Task 1 Step 5 for the exact pattern.
- **All user-facing strings** use `String(localized:defaultValue:)` and require entries in `Resources/Localizable.xcstrings` for **English and Japanese**. No bare English literals in UI code.
- **Regression test policy:** where a task fixes a bug, commit the failing test first, then the fix (two commits).
- **Never** add work to `TerminalSurface.forceRefresh()`, `TabItemView`, or `WindowTerminalHostView.hitTest()` — typing-latency paths, untouched by this plan.
- Diagram-mode file extensions, used verbatim everywhere: `mmd`, `mermaid`.
- The JS diagram-mode global namespace is `window.__cmuxDiagram*`. Swift→JS calls always guard: `window.__cmuxFoo && window.__cmuxFoo(...)`.

---

## File Structure

**Create:**
- `Sources/Panels/MermaidDiagramFileResolver.swift` — pure extension predicate + fence wrapping. No UI, no I/O.
- `Sources/Panels/MarkdownDiagramParseResult.swift` — the parse-result value type and the panel-side pending-callback registry.
- `cmuxTests/MermaidDiagramFileResolverTests.swift`
- `cmuxTests/MermaidDiagramRoutingTests.swift`
- `cmuxTests/MermaidDiagramModeTests.swift` — WKWebView integration, modeled on the existing `cmuxTests/MarkdownMermaidZoomTests.swift`.
- `cmuxTests/MermaidDiagramParseReportingTests.swift`

**Modify:**
- `Sources/Panels/MarkdownPanel.swift` — `.diagram` case, diagram-file detection, content wrapping, parse-result storage.
- `Sources/Panels/MarkdownPanelView.swift:152` — the exhaustive `switch` on `displayMode`.
- `Sources/Panels/FilePreviewWorkspaceOpenSupport.swift:27` — routing branch.
- `Sources/Panels/MarkdownWebRenderer.swift` — diagram-mode push, parse-message handling.
- `Resources/markdown-viewer/shell.html` — diagram CSS, camera, pan/zoom, parse reporting.
- `Sources/FileOpenSocketSupport.swift` — await parse result before responding.
- `Sources/WorkspaceSnapshotSocketSupport.swift:195` — advertise the verb.
- `Resources/Localizable.xcstrings` — new strings.
- `skills/cmux-markdown/SKILL.md` — document the `.mmd` pattern.

---

### Task 1: Diagram file detection and fence wrapping

Pure value logic, no dependencies. Everything downstream consumes it.

**Files:**
- Create: `Sources/Panels/MermaidDiagramFileResolver.swift`
- Test: `cmuxTests/MermaidDiagramFileResolverTests.swift`
- Modify: `cmux.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `enum MermaidDiagramFileResolver`
  - `static func isDiagramPathLike(_ rawPath: String) -> Bool`
  - `static func wrapAsMermaidFence(_ source: String) -> String`

- [ ] **Step 1: Write the failing test**

Create `cmuxTests/MermaidDiagramFileResolverTests.swift`:

```swift
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@Suite
struct MermaidDiagramFileResolverTests {
    @Test
    func recognizesDiagramExtensions() {
        #expect(MermaidDiagramFileResolver.isDiagramPathLike("arch.mmd"))
        #expect(MermaidDiagramFileResolver.isDiagramPathLike("/tmp/a/arch.mermaid"))
        #expect(MermaidDiagramFileResolver.isDiagramPathLike("docs/FLOW.MMD"))
    }

    @Test
    func rejectsNonDiagramPaths() {
        #expect(!MermaidDiagramFileResolver.isDiagramPathLike("notes.md"))
        #expect(!MermaidDiagramFileResolver.isDiagramPathLike("main.swift"))
        #expect(!MermaidDiagramFileResolver.isDiagramPathLike(""))
        #expect(!MermaidDiagramFileResolver.isDiagramPathLike("https://example.com/a.mmd"))
    }

    @Test
    func wrapsSourceInMermaidFence() {
        let wrapped = MermaidDiagramFileResolver.wrapAsMermaidFence("flowchart LR\n  a --> b")
        #expect(wrapped == "```mermaid\nflowchart LR\n  a --> b\n```")
    }

    @Test
    func wrappingTrimsTrailingNewlinesSoTheFenceStaysValid() {
        let wrapped = MermaidDiagramFileResolver.wrapAsMermaidFence("graph TD\n  a --> b\n\n\n")
        #expect(wrapped == "```mermaid\ngraph TD\n  a --> b\n```")
    }

    @Test
    func wrappingEmptySourceProducesAnEmptyFence() {
        #expect(MermaidDiagramFileResolver.wrapAsMermaidFence("   \n ") == "```mermaid\n\n```")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

First wire the test file into the project (Step 5 pattern applies now — do it before running), then:

Run: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild test -project cmux.xcodeproj -scheme cmux-unit -destination 'platform=macOS' -derivedDataPath /tmp/cmux-mermaid-viewer -only-testing:cmuxTests/MermaidDiagramFileResolverTests`

Expected: FAIL — `cannot find 'MermaidDiagramFileResolver' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/Panels/MermaidDiagramFileResolver.swift`:

```swift
import Foundation

/// Detects standalone mermaid diagram files and adapts their contents for the
/// shared markdown render pipeline.
///
/// A `.mmd` file is raw mermaid source with no fence. The markdown shell only
/// renders mermaid when it sees a ```` ```mermaid ```` fence, so we wrap the
/// source rather than teaching the shell a second input format. That keeps a
/// single render path for both `.md` fences and `.mmd` files.
enum MermaidDiagramFileResolver {
    /// Extensions that open directly as a diagram surface.
    private static let diagramExtensions: Set<String> = ["mmd", "mermaid"]

    static func isDiagramPathLike(_ rawPath: String) -> Bool {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        // Mirror MarkdownPanelFileLinkResolver: path-like only, never remote URLs.
        if let url = URL(string: trimmed), url.scheme != nil, url.scheme != "file" {
            return false
        }
        let ext = (trimmed as NSString).pathExtension.lowercased()
        return diagramExtensions.contains(ext)
    }

    /// Wraps raw mermaid source in a fence the markdown shell already knows how
    /// to render. Trailing blank lines are trimmed so the closing fence is not
    /// separated from the diagram body by empty lines.
    static func wrapAsMermaidFence(_ source: String) -> String {
        let body = source.trimmingCharacters(in: .whitespacesAndNewlines)
        return "```mermaid\n\(body)\n```"
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild test -project cmux.xcodeproj -scheme cmux-unit -destination 'platform=macOS' -derivedDataPath /tmp/cmux-mermaid-viewer -only-testing:cmuxTests/MermaidDiagramFileResolverTests`

Expected: PASS, 5 tests executed. **If it says "Executed 0 tests", the pbxproj wiring in Step 5 is wrong — fix it before continuing.**

- [ ] **Step 5: Wire both new files into the Xcode project**

`Sources/*.swift` and `cmuxTests/*.swift` both need pbxproj entries. Follow the existing `MarkdownMermaidZoomTests.swift` pattern, which uses a repeated-hex ID convention (`D6069001D6069001D6069001`). Pick fresh unique 24-hex IDs.

Verify the shape of the four required entries for a test file:

```bash
grep -n "MarkdownMermaidZoomTests" cmux.xcodeproj/project.pbxproj
```

Expected: exactly 4 lines — a `PBXBuildFile` (`... in Sources */ = {isa = PBXBuildFile; fileRef = ...`), a `PBXFileReference`, a group child entry, and a `PBXSourcesBuildPhase` entry.

Add the same 4 entries for `MermaidDiagramFileResolverTests.swift` (into the **cmuxTests** target) and for `MermaidDiagramFileResolver.swift` (into the **cmux** app target). Then confirm:

```bash
./scripts/lint-pbxproj-test-wiring.sh
```

Expected: passes with no output about missing wiring.

- [ ] **Step 6: Commit**

```bash
git add Sources/Panels/MermaidDiagramFileResolver.swift cmuxTests/MermaidDiagramFileResolverTests.swift cmux.xcodeproj/project.pbxproj
git commit -m "Add mermaid diagram file resolver

Detects .mmd/.mermaid paths and wraps raw source in a mermaid fence so
the existing markdown render path handles standalone diagram files."
```

---

### Task 2: `.diagram` display mode on MarkdownPanel

**Files:**
- Modify: `Sources/Panels/MarkdownPanel.swift:6-11` (enum), `:38-39` (property), `:101-119` (init), `:343-360` (`loadFileContent`)
- Modify: `Sources/Panels/MarkdownPanelView.swift:151-165` (exhaustive switch)
- Test: `cmuxTests/MermaidDiagramRoutingTests.swift`

**Interfaces:**
- Consumes: `MermaidDiagramFileResolver.isDiagramPathLike(_:)`, `.wrapAsMermaidFence(_:)` from Task 1.
- Produces:
  - `MarkdownPanelDisplayMode.diagram`
  - `MarkdownPanel.isDiagramFile: Bool` (read-only)
  - `MarkdownPanel.content` returns fence-wrapped source when `isDiagramFile`.

- [ ] **Step 1: Write the failing test**

Create `cmuxTests/MermaidDiagramRoutingTests.swift`:

```swift
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite
struct MermaidDiagramRoutingTests {
    private func writeTempFile(ext: String, contents: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-diagram-\(UUID().uuidString).\(ext)")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    @Test
    func diagramFileOpensInDiagramMode() throws {
        let path = try writeTempFile(ext: "mmd", contents: "flowchart LR\n  a --> b")
        let panel = MarkdownPanel(workspaceId: UUID(), filePath: path)
        #expect(panel.isDiagramFile)
        #expect(panel.displayMode == .diagram)
    }

    @Test
    func diagramContentIsFenceWrapped() throws {
        let path = try writeTempFile(ext: "mmd", contents: "flowchart LR\n  a --> b")
        let panel = MarkdownPanel(workspaceId: UUID(), filePath: path)
        #expect(panel.content == "```mermaid\nflowchart LR\n  a --> b\n```")
    }

    @Test
    func markdownFileIsUnaffected() throws {
        let path = try writeTempFile(ext: "md", contents: "# Title")
        let panel = MarkdownPanel(workspaceId: UUID(), filePath: path)
        #expect(!panel.isDiagramFile)
        #expect(panel.displayMode == .preview)
        #expect(panel.content == "# Title")
    }

    @Test
    func textModeOnADiagramFileExposesRawUnwrappedSource() throws {
        let path = try writeTempFile(ext: "mmd", contents: "flowchart LR\n  a --> b")
        let panel = MarkdownPanel(workspaceId: UUID(), filePath: path)
        panel.setDisplayMode(.text)
        // The editor must show the real file, not the synthesized fence.
        #expect(panel.textContent == "flowchart LR\n  a --> b")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Wire `MermaidDiagramRoutingTests.swift` into pbxproj (Task 1 Step 5 pattern), then:

Run: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild test -project cmux.xcodeproj -scheme cmux-unit -destination 'platform=macOS' -derivedDataPath /tmp/cmux-mermaid-viewer -only-testing:cmuxTests/MermaidDiagramRoutingTests`

Expected: FAIL — `value of type 'MarkdownPanel' has no member 'isDiagramFile'`.

- [ ] **Step 3: Add the enum case**

In `Sources/Panels/MarkdownPanel.swift`, replace lines 6-11:

```swift
enum MarkdownPanelDisplayMode: String, CaseIterable, Identifiable {
    case preview
    case text
    /// Single-diagram canvas for standalone `.mmd`/`.mermaid` files. Renders
    /// through the same WebView shell as `.preview`, but with document flow
    /// suppressed and a pan/zoom camera installed.
    case diagram

    var id: String { rawValue }
}
```

- [ ] **Step 4: Add diagram detection and default mode**

In `Sources/Panels/MarkdownPanel.swift`, replace lines 38-39:

```swift
    /// The current view mode for this markdown panel. Markdown files default to
    /// preview; standalone diagram files default to the diagram canvas.
    @Published private(set) var displayMode: MarkdownPanelDisplayMode = .preview

    /// True when this panel was opened on a standalone mermaid source file.
    /// Diagram files never enter `.preview` — their two modes are `.diagram`
    /// and `.text`.
    let isDiagramFile: Bool
```

In the init, replace line 107 (`self.filePath = filePath`) with:

```swift
        self.filePath = filePath
        self.isDiagramFile = MermaidDiagramFileResolver.isDiagramPathLike(filePath)
```

and immediately before `loadFileContent()` on line 116, insert:

```swift
        if self.isDiagramFile {
            self.displayMode = .diagram
        }
```

- [ ] **Step 5: Wrap content for diagram files**

`loadFileContent` funnels into `applyLoadedContent`, which sets both `content` (rendered) and `textContent` (raw editor buffer). Diagram files must diverge: `content` is fence-wrapped, `textContent` stays raw.

Find `applyLoadedContent` in `Sources/Panels/MarkdownPanel.swift` and locate the line assigning the rendered content (`content = newContent`). Replace that single assignment with:

```swift
        content = isDiagramFile
            ? MermaidDiagramFileResolver.wrapAsMermaidFence(newContent)
            : newContent
```

Leave every `textContent` / `originalTextContent` assignment untouched — the text editor and dirty-tracking must continue to see the real file bytes.

- [ ] **Step 6: Fix the exhaustive switch**

`Sources/Panels/MarkdownPanelView.swift:151-165` is the only exhaustive switch on `displayMode` and will now fail to compile. Replace `markdownModeButton` (lines 151-165) with:

```swift
    private var markdownModeButton: some View {
        switch panel.displayMode {
        case .preview:
            PanelHeaderIconButton(
                systemName: "doc.plaintext",
                label: String(localized: "markdown.mode.showTextEdit", defaultValue: "Show TextEdit"),
                action: { panel.setDisplayMode(.text) }
            )
        case .diagram:
            PanelHeaderIconButton(
                systemName: "doc.plaintext",
                label: String(localized: "markdown.mode.showDiagramSource", defaultValue: "Show Source"),
                action: { panel.setDisplayMode(.text) }
            )
        case .text:
            PanelHeaderIconButton(
                systemName: panel.isDiagramFile ? "point.topleft.down.curvedto.point.bottomright.up" : "eye",
                label: panel.isDiagramFile
                    ? String(localized: "markdown.mode.showDiagram", defaultValue: "Show Diagram")
                    : String(localized: "markdown.mode.showPreview", defaultValue: "Show Preview"),
                action: { panel.setDisplayMode(panel.isDiagramFile ? .diagram : .preview) }
            )
        }
    }
```

Then update the three preview-gated conditions so diagram mode also shows the WebView. In `Sources/Panels/MarkdownPanelView.swift`, replace lines 96-98:

```swift
            .opacity(panel.displayMode != .text ? 1 : 0)
            .allowsHitTesting(panel.displayMode != .text)
            .accessibilityHidden(panel.displayMode == .text)
```

Leave line 135 (`if panel.displayMode == .preview {`) exactly as it is — the typography controls stay preview-only. Diagram mode has no chrome by design, so it must not gain a font-size control.

- [ ] **Step 7: Add localized strings**

Add three keys to `Resources/Localizable.xcstrings`, each with `en` and `ja` localizations:

| Key | en | ja |
|---|---|---|
| `markdown.mode.showDiagramSource` | `Show Source` | `ソースを表示` |
| `markdown.mode.showDiagram` | `Show Diagram` | `図を表示` |

Verify both locales are present:

```bash
python3 -c "import json;d=json.load(open('Resources/Localizable.xcstrings'));[print(k, sorted(d['strings'][k].get('localizations',{}).keys())) for k in ['markdown.mode.showDiagramSource','markdown.mode.showDiagram']]"
```

Expected: `markdown.mode.showDiagramSource ['en', 'ja']` and `markdown.mode.showDiagram ['en', 'ja']`.

- [ ] **Step 8: Run tests to verify they pass**

Run: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild test -project cmux.xcodeproj -scheme cmux-unit -destination 'platform=macOS' -derivedDataPath /tmp/cmux-mermaid-viewer -only-testing:cmuxTests/MermaidDiagramRoutingTests -only-testing:cmuxTests/MarkdownPanelTests`

Expected: PASS. `MarkdownPanelTests` must still pass — it asserts `displayMode` behavior at `:233`, `:236`, `:290`.

- [ ] **Step 9: Commit**

```bash
git add Sources/Panels/MarkdownPanel.swift Sources/Panels/MarkdownPanelView.swift Resources/Localizable.xcstrings cmuxTests/MermaidDiagramRoutingTests.swift cmux.xcodeproj/project.pbxproj
git commit -m "Add diagram display mode to markdown panel

Standalone .mmd/.mermaid files open in a new .diagram mode with their
source fence-wrapped for the shared render path. Text mode still exposes
the raw file."
```

---

### Task 3: Route `.mmd` files through `openFileSurfaces`

**Files:**
- Modify: `Sources/Panels/FilePreviewWorkspaceOpenSupport.swift:27`
- Test: `cmuxTests/MermaidDiagramRoutingTests.swift` (extend)

**Interfaces:**
- Consumes: `MermaidDiagramFileResolver.isDiagramPathLike(_:)` (Task 1); `MarkdownPanel.isDiagramFile` (Task 2).
- Produces: `.mmd` paths yield a `MarkdownPanel` from `Workspace.openFileSurfaces`.

- [ ] **Step 1: Write the failing test**

Append to `cmuxTests/MermaidDiagramRoutingTests.swift`, inside the `MermaidDiagramRoutingTests` struct:

```swift
    @Test
    func openFileSurfacesRoutesDiagramFilesToMarkdownPanel() throws {
        let path = try writeTempFile(ext: "mmd", contents: "flowchart LR\n  a --> b")
        let workspace = Workspace(name: "diagram-routing-test")
        let paneId = try #require(workspace.bonsplitController.allPaneIds.first)

        let opened = workspace.openFileSurfaces(inPane: paneId, filePaths: [path], focus: false)

        let panel = try #require(opened.first as? MarkdownPanel)
        #expect(panel.isDiagramFile)
        #expect(panel.displayMode == .diagram)
        #expect(panel.panelType == .markdown)
    }
```

Note: if `Workspace(name:)` is not the available initializer in this codebase, construct it the same way `cmuxTests/MarkdownPanelTests.swift` does — copy that file's workspace setup helper verbatim rather than inventing one.

- [ ] **Step 2: Run test to verify it fails**

Run: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild test -project cmux.xcodeproj -scheme cmux-unit -destination 'platform=macOS' -derivedDataPath /tmp/cmux-mermaid-viewer -only-testing:cmuxTests/MermaidDiagramRoutingTests/openFileSurfacesRoutesDiagramFilesToMarkdownPanel`

Expected: FAIL — the panel comes back as a `FilePreviewPanel`, so `try #require(opened.first as? MarkdownPanel)` fails.

- [ ] **Step 3: Add the routing branch**

In `Sources/Panels/FilePreviewWorkspaceOpenSupport.swift`, replace line 27:

```swift
            } else if MarkdownPanelFileLinkResolver.isMarkdownPathLike(filePath)
                        || MermaidDiagramFileResolver.isDiagramPathLike(filePath) {
```

Both branches construct a `MarkdownPanel`; the panel itself decides diagram-vs-preview from its own path (Task 2), so no further change is needed here.

- [ ] **Step 4: Run test to verify it passes**

Run: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild test -project cmux.xcodeproj -scheme cmux-unit -destination 'platform=macOS' -derivedDataPath /tmp/cmux-mermaid-viewer -only-testing:cmuxTests/MermaidDiagramRoutingTests`

Expected: PASS, all 5 tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/Panels/FilePreviewWorkspaceOpenSupport.swift cmuxTests/MermaidDiagramRoutingTests.swift
git commit -m "Route .mmd/.mermaid files to the markdown panel

cmux open arch.mmd now lands on a diagram surface instead of the generic
file preview."
```

---

### Task 4: Diagram-mode canvas in the shell — dot grid and suppressed document flow

**Files:**
- Modify: `Resources/markdown-viewer/shell.html` (CSS block after line 151; new JS before line 1699)
- Modify: `Sources/Panels/MarkdownWebRenderer.swift` (add `setDiagramMode`, call it from `updateNSView`)
- Modify: `Sources/Panels/MarkdownPanelView.swift` (pass `displayMode` into the renderer)
- Test: `cmuxTests/MermaidDiagramModeTests.swift`

**Interfaces:**
- Consumes: `MarkdownPanelDisplayMode.diagram` (Task 2).
- Produces:
  - JS: `window.__cmuxSetDiagramMode(enabled)` — toggles `document.documentElement`'s `data-cmux-diagram` attribute.
  - Swift: `MarkdownWebRenderer.Coordinator.setDiagramMode(_ enabled: Bool)`.
  - `MarkdownWebRenderer` gains a `displayMode: MarkdownPanelDisplayMode` stored property.

- [ ] **Step 1: Write the failing test**

Create `cmuxTests/MermaidDiagramModeTests.swift`. Copy the WKWebView harness verbatim from `cmuxTests/MarkdownMermaidZoomTests.swift` (the `MarkdownMermaidStubHandler`, `MermaidZoomShellLoadDelegate`, `renderMarkdown`, and `waitForMermaidSnapshot` helpers) — rename the delegate/handler types with a `Diagram` prefix to avoid symbol collisions, and keep their bodies identical.

```swift
import AppKit
import Testing
import WebKit

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite
final class MermaidDiagramModeTests {
    @Test
    func diagramModeSuppressesDocumentPaddingAndShowsDotGrid() async throws {
        let harness = try await DiagramShellHarness.make()
        defer { harness.tearDown() }

        try await harness.render("```mermaid\nflowchart LR\n  a --> b\n```")

        let before = try await harness.evalString("getComputedStyle(document.body).padding")
        #expect(before != "0px")

        _ = try await harness.eval("window.__cmuxSetDiagramMode(true)")

        let attr = try await harness.evalString("document.documentElement.getAttribute('data-cmux-diagram')")
        #expect(attr == "1")

        let padding = try await harness.evalString("getComputedStyle(document.body).padding")
        #expect(padding == "0px")

        let overflow = try await harness.evalString("getComputedStyle(document.body).overflow")
        #expect(overflow == "hidden")

        // The dot grid is a repeating radial-gradient on the canvas layer.
        let bgImage = try await harness.evalString(
            "getComputedStyle(document.getElementById('cmux-diagram-canvas')).backgroundImage"
        )
        #expect(bgImage.contains("radial-gradient"))
    }

    @Test
    func disablingDiagramModeRestoresDocumentFlow() async throws {
        let harness = try await DiagramShellHarness.make()
        defer { harness.tearDown() }

        try await harness.render("```mermaid\nflowchart LR\n  a --> b\n```")
        _ = try await harness.eval("window.__cmuxSetDiagramMode(true)")
        _ = try await harness.eval("window.__cmuxSetDiagramMode(false)")

        let attr = try await harness.evalString("document.documentElement.getAttribute('data-cmux-diagram') || ''")
        #expect(attr == "")
        let padding = try await harness.evalString("getComputedStyle(document.body).padding")
        #expect(padding != "0px")
    }
}
```

Implement `DiagramShellHarness` in the same file as a small `@MainActor` helper wrapping the copied setup: it owns the `NSWindow`, `WKWebView`, `MarkdownWebRenderer.Coordinator`, and exposes `make()`, `tearDown()`, `render(_:)`, `eval(_:)`, and `evalString(_:)` (the latter returning `String` via `evaluateJavaScript` cast).

- [ ] **Step 2: Run test to verify it fails**

Wire the file into pbxproj (Task 1 Step 5), then:

Run: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild test -project cmux.xcodeproj -scheme cmux-unit -destination 'platform=macOS' -derivedDataPath /tmp/cmux-mermaid-viewer -only-testing:cmuxTests/MermaidDiagramModeTests`

Expected: FAIL — `window.__cmuxSetDiagramMode` is undefined, so the attribute read returns `null`.

- [ ] **Step 3: Add diagram-mode CSS to the shell**

In `Resources/markdown-viewer/shell.html`, immediately after line 151 (the `.cmux-mermaid .cmux-source` rule), insert:

```css
/* ---- Diagram mode -------------------------------------------------------
   Standalone .mmd files render as a single diagram on an infinite dotted
   canvas. Document flow is suppressed entirely: no padding, no scrolling,
   no reading column. The camera (translate+scale) lives on
   #cmux-diagram-canvas so the dot grid transforms with the diagram, which
   is what makes panning read as moving a surface rather than scrolling a
   page. ------------------------------------------------------------------ */
html[data-cmux-diagram="1"],
html[data-cmux-diagram="1"] body {
  width: 100%;
  height: 100%;
  overflow: hidden;
}
html[data-cmux-diagram="1"] body {
  padding: 0;
  /* The canvas is the drag surface; text selection would fight the pan. */
  -webkit-user-select: none;
  user-select: none;
}
html[data-cmux-diagram="1"] .markdown-body {
  max-width: none;
  margin: 0;
  font-size: inherit;
}
#cmux-diagram-canvas {
  display: none;
}
html[data-cmux-diagram="1"] #cmux-diagram-canvas {
  display: block;
  position: fixed;
  /* Oversized so the grid still covers the viewport at any pan offset. */
  left: -200vw;
  top: -200vh;
  width: 500vw;
  height: 500vh;
  z-index: 0;
  background-color: transparent;
  background-image: radial-gradient(
    circle at center,
    var(--cmux-diagram-dot, rgba(140, 140, 150, 0.28)) 1px,
    transparent 1px
  );
  background-size: var(--cmux-diagram-dot-spacing, 22px) var(--cmux-diagram-dot-spacing, 22px);
  transform-origin: 0 0;
  pointer-events: none;
}
html[data-cmux-diagram="1"] #content {
  position: fixed;
  left: 0;
  top: 0;
  z-index: 1;
  transform-origin: 0 0;
  will-change: transform;
}
html[data-cmux-diagram="1"] .cmux-mermaid {
  margin: 0;
}
html[data-cmux-diagram="1"] .cmux-mermaid svg {
  max-width: none;
}
```

- [ ] **Step 4: Add the canvas element and the mode toggle**

In `Resources/markdown-viewer/shell.html`, find the `<body>` element and insert the canvas div as the **first** child of `<body>`, before the `#content` element:

```html
<div id="cmux-diagram-canvas"></div>
```

Then, immediately before line 1699 (`var darkMql = window.matchMedia(...)`), insert:

```javascript
  // ---- Diagram mode -----------------------------------------------------
  var diagramModeEnabled = false;
  var diagramCanvasEl = document.getElementById('cmux-diagram-canvas');

  window.__cmuxSetDiagramMode = function(enabled) {
    var next = !!enabled;
    if (next === diagramModeEnabled) { return; }
    diagramModeEnabled = next;
    if (next) {
      document.documentElement.setAttribute('data-cmux-diagram', '1');
      if (!diagramCameraInitialized) { window.__cmuxDiagramFit(); }
      else { applyDiagramCamera(); }
    } else {
      document.documentElement.removeAttribute('data-cmux-diagram');
      if (contentEl) { contentEl.style.transform = ''; }
      if (diagramCanvasEl) { diagramCanvasEl.style.transform = ''; }
    }
  };

  window.__cmuxDiagramModeEnabled = function() { return diagramModeEnabled; };
```

`diagramCameraInitialized`, `window.__cmuxDiagramFit`, and `applyDiagramCamera` arrive in Task 5. To keep this task's build green on its own, also insert these three placeholders **above** the block you just added (Task 5 replaces them with real implementations):

```javascript
  var diagramCameraInitialized = false;
  function applyDiagramCamera() {}
  window.__cmuxDiagramFit = function() { diagramCameraInitialized = true; };
```

- [ ] **Step 5: Push the mode from Swift**

In `Sources/Panels/MarkdownWebRenderer.swift`, add a stored property to the representable alongside the existing `fontSize`/`theme` properties:

```swift
    let displayMode: MarkdownPanelDisplayMode
```

Add this method to `Coordinator` (place it next to `setFontSize`, near line 209):

```swift
        private var lastDiagramMode: Bool?

        func setDiagramMode(_ enabled: Bool) {
            guard lastDiagramMode != enabled else { return }
            lastDiagramMode = enabled
            guard isLoaded, let webView else { return }
            webView.evaluateJavaScript(
                "window.__cmuxSetDiagramMode && window.__cmuxSetDiagramMode(\(enabled));",
                completionHandler: nil
            )
        }
```

Because the mode must survive a shell reload, also re-apply it after load completes: find where `isLoaded` is set to `true` in the navigation delegate and append, immediately after that assignment:

```swift
            if let lastDiagramMode {
                webView?.evaluateJavaScript(
                    "window.__cmuxSetDiagramMode && window.__cmuxSetDiagramMode(\(lastDiagramMode));",
                    completionHandler: nil
                )
            }
```

In `updateNSView`, insert after line 105 (`context.coordinator.setMaxContentWidth(maxContentWidth)`):

```swift
        context.coordinator.setDiagramMode(displayMode == .diagram)
```

Do the same in `makeNSView` in both branches — after line 47 and after line 91.

- [ ] **Step 6: Pass the mode from the view**

In `Sources/Panels/MarkdownPanelView.swift`, find the `MarkdownWebRenderer(...)` construction and add the argument:

```swift
                displayMode: panel.displayMode,
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild test -project cmux.xcodeproj -scheme cmux-unit -destination 'platform=macOS' -derivedDataPath /tmp/cmux-mermaid-viewer -only-testing:cmuxTests/MermaidDiagramModeTests -only-testing:cmuxTests/MarkdownMermaidZoomTests`

Expected: PASS. The existing zoom test must stay green — diagram CSS is scoped entirely under `html[data-cmux-diagram="1"]`, so markdown rendering is untouched.

- [ ] **Step 8: Commit**

```bash
git add Resources/markdown-viewer/shell.html Sources/Panels/MarkdownWebRenderer.swift Sources/Panels/MarkdownPanelView.swift cmuxTests/MermaidDiagramModeTests.swift cmux.xcodeproj/project.pbxproj
git commit -m "Add diagram-mode canvas with dot grid to markdown shell

Suppresses document flow and renders the diagram on a fixed dotted
canvas. Scoped under a data attribute so markdown rendering is unchanged."
```

---

### Task 5: Pan and zoom camera

**Files:**
- Modify: `Resources/markdown-viewer/shell.html` (replace the Task 4 placeholders)
- Test: `cmuxTests/MermaidDiagramModeTests.swift` (extend)

**Interfaces:**
- Consumes: `window.__cmuxSetDiagramMode` (Task 4).
- Produces:
  - `window.__cmuxDiagramCamera()` → `{x, y, scale}`
  - `window.__cmuxDiagramSetCamera(x, y, scale)`
  - `window.__cmuxDiagramFit()` — centers and scales the diagram to the viewport.

- [ ] **Step 1: Write the failing test**

Append to `MermaidDiagramModeTests`:

```swift
    @Test
    func wheelWithoutModifierPansAndPinchZooms() async throws {
        let harness = try await DiagramShellHarness.make()
        defer { harness.tearDown() }

        try await harness.render("```mermaid\nflowchart LR\n  a --> b\n```")
        _ = try await harness.eval("window.__cmuxSetDiagramMode(true)")
        _ = try await harness.eval("window.__cmuxDiagramSetCamera(0, 0, 1)")

        // Plain wheel scroll pans; it must not scroll the document.
        _ = try await harness.eval("""
        document.getElementById('content').dispatchEvent(new WheelEvent('wheel', {
          deltaX: 30, deltaY: 40, bubbles: true, cancelable: true
        }));
        """)
        let panned = try await harness.evalString("JSON.stringify(window.__cmuxDiagramCamera())")
        #expect(panned.contains("\"x\":-30"))
        #expect(panned.contains("\"y\":-40"))

        // ctrl+wheel is the trackpad pinch gesture WebKit synthesizes.
        _ = try await harness.eval("window.__cmuxDiagramSetCamera(0, 0, 1)")
        _ = try await harness.eval("""
        document.getElementById('content').dispatchEvent(new WheelEvent('wheel', {
          deltaY: -10, ctrlKey: true, clientX: 0, clientY: 0, bubbles: true, cancelable: true
        }));
        """)
        let zoomed = try await harness.eval("window.__cmuxDiagramCamera().scale") as? Double
        #expect((zoomed ?? 0) > 1.0)
    }

    @Test
    func cameraScaleIsClamped() async throws {
        let harness = try await DiagramShellHarness.make()
        defer { harness.tearDown() }
        try await harness.render("```mermaid\nflowchart LR\n  a --> b\n```")
        _ = try await harness.eval("window.__cmuxSetDiagramMode(true)")

        _ = try await harness.eval("window.__cmuxDiagramSetCamera(0, 0, 500)")
        let high = try await harness.eval("window.__cmuxDiagramCamera().scale") as? Double
        #expect((high ?? 0) <= 8.0)

        _ = try await harness.eval("window.__cmuxDiagramSetCamera(0, 0, 0.0001)")
        let low = try await harness.eval("window.__cmuxDiagramCamera().scale") as? Double
        #expect((low ?? 0) >= 0.1)
    }

    @Test
    func dotGridTransformsWithTheCamera() async throws {
        let harness = try await DiagramShellHarness.make()
        defer { harness.tearDown() }
        try await harness.render("```mermaid\nflowchart LR\n  a --> b\n```")
        _ = try await harness.eval("window.__cmuxSetDiagramMode(true)")
        _ = try await harness.eval("window.__cmuxDiagramSetCamera(100, 50, 2)")

        let canvasTransform = try await harness.evalString(
            "document.getElementById('cmux-diagram-canvas').style.transform"
        )
        let contentTransform = try await harness.evalString(
            "document.getElementById('content').style.transform"
        )
        // Both layers share the camera, so dots track the diagram exactly.
        #expect(canvasTransform.contains("scale(2)"))
        #expect(contentTransform.contains("scale(2)"))
        #expect(contentTransform.contains("translate(100px, 50px)"))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild test -project cmux.xcodeproj -scheme cmux-unit -destination 'platform=macOS' -derivedDataPath /tmp/cmux-mermaid-viewer -only-testing:cmuxTests/MermaidDiagramModeTests`

Expected: FAIL — `__cmuxDiagramCamera` is not a function (Task 4 only stubbed `__cmuxDiagramFit`).

- [ ] **Step 3: Implement the camera**

In `Resources/markdown-viewer/shell.html`, replace the three placeholder lines added in Task 4 Step 4:

```javascript
  var diagramCameraInitialized = false;
  function applyDiagramCamera() {}
  window.__cmuxDiagramFit = function() { diagramCameraInitialized = true; };
```

with:

```javascript
  // Camera: content and dot-grid share one transform, so the dots translate
  // and scale with the diagram. transform-origin is 0 0 on both layers, and
  // the order is translate-then-scale, which makes zoom-about-a-point a
  // simple offset correction (see diagramZoomAt).
  var DIAGRAM_MIN_SCALE = 0.1;
  var DIAGRAM_MAX_SCALE = 8;
  var diagramCamera = { x: 0, y: 0, scale: 1 };
  var diagramCameraInitialized = false;

  function clampDiagramScale(value) {
    var scale = Number(value);
    if (!Number.isFinite(scale) || scale <= 0) { return 1; }
    return Math.max(DIAGRAM_MIN_SCALE, Math.min(scale, DIAGRAM_MAX_SCALE));
  }

  function applyDiagramCamera() {
    if (!diagramModeEnabled) { return; }
    var t = 'translate(' + diagramCamera.x + 'px, ' + diagramCamera.y + 'px) scale(' + diagramCamera.scale + ')';
    if (contentEl) { contentEl.style.transform = t; }
    if (diagramCanvasEl) { diagramCanvasEl.style.transform = t; }
  }

  window.__cmuxDiagramCamera = function() {
    return { x: diagramCamera.x, y: diagramCamera.y, scale: diagramCamera.scale };
  };

  window.__cmuxDiagramSetCamera = function(x, y, scale) {
    var nx = Number(x), ny = Number(y);
    diagramCamera.x = Number.isFinite(nx) ? nx : 0;
    diagramCamera.y = Number.isFinite(ny) ? ny : 0;
    diagramCamera.scale = clampDiagramScale(scale);
    diagramCameraInitialized = true;
    applyDiagramCamera();
  };

  function diagramSVG() {
    return contentEl ? contentEl.querySelector('.cmux-mermaid svg') : null;
  }

  // Zoom about a viewport point: keep the diagram-space point under the
  // cursor fixed while scale changes.
  function diagramZoomAt(factor, clientX, clientY) {
    var next = clampDiagramScale(diagramCamera.scale * factor);
    if (next === diagramCamera.scale) { return; }
    var ratio = next / diagramCamera.scale;
    diagramCamera.x = clientX - (clientX - diagramCamera.x) * ratio;
    diagramCamera.y = clientY - (clientY - diagramCamera.y) * ratio;
    diagramCamera.scale = next;
    applyDiagramCamera();
  }

  window.__cmuxDiagramFit = function() {
    diagramCameraInitialized = true;
    var svg = diagramSVG();
    if (!svg) {
      diagramCamera = { x: 0, y: 0, scale: 1 };
      applyDiagramCamera();
      return;
    }
    // Measure at identity so the reading is the diagram's intrinsic size.
    var prev = contentEl.style.transform;
    contentEl.style.transform = '';
    var rect = svg.getBoundingClientRect();
    contentEl.style.transform = prev;

    var vw = window.innerWidth, vh = window.innerHeight;
    if (!(rect.width > 0 && rect.height > 0 && vw > 0 && vh > 0)) {
      diagramCamera = { x: 0, y: 0, scale: 1 };
      applyDiagramCamera();
      return;
    }
    var margin = 48;
    var scale = clampDiagramScale(
      Math.min((vw - margin) / rect.width, (vh - margin) / rect.height, 1)
    );
    diagramCamera.scale = scale;
    diagramCamera.x = (vw - rect.width * scale) / 2;
    diagramCamera.y = (vh - rect.height * scale) / 2;
    applyDiagramCamera();
  };

  // ---- Input ------------------------------------------------------------
  var diagramDrag = null;

  document.addEventListener('mousedown', function(ev) {
    if (!diagramModeEnabled || ev.button !== 0) { return; }
    diagramDrag = { px: ev.clientX, py: ev.clientY };
    ev.preventDefault();
  });

  document.addEventListener('mousemove', function(ev) {
    if (!diagramModeEnabled || !diagramDrag) { return; }
    diagramCamera.x += ev.clientX - diagramDrag.px;
    diagramCamera.y += ev.clientY - diagramDrag.py;
    diagramDrag.px = ev.clientX;
    diagramDrag.py = ev.clientY;
    applyDiagramCamera();
  });

  document.addEventListener('mouseup', function() { diagramDrag = null; });
  document.addEventListener('mouseleave', function() { diagramDrag = null; });

  document.addEventListener('wheel', function(ev) {
    if (!diagramModeEnabled) { return; }
    ev.preventDefault();
    if (ev.ctrlKey) {
      // WebKit synthesizes ctrl+wheel for trackpad pinch.
      diagramZoomAt(Math.exp(-ev.deltaY * 0.01), ev.clientX, ev.clientY);
      return;
    }
    diagramCamera.x -= ev.deltaX;
    diagramCamera.y -= ev.deltaY;
    applyDiagramCamera();
  }, { passive: false });

  document.addEventListener('dblclick', function(ev) {
    if (!diagramModeEnabled) { return; }
    ev.preventDefault();
    window.__cmuxDiagramFit();
  });

  window.addEventListener('resize', function() {
    if (diagramModeEnabled) { applyDiagramCamera(); }
  });
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild test -project cmux.xcodeproj -scheme cmux-unit -destination 'platform=macOS' -derivedDataPath /tmp/cmux-mermaid-viewer -only-testing:cmuxTests/MermaidDiagramModeTests`

Expected: PASS, all 5 tests.

- [ ] **Step 5: Verify by hand in the real app**

```bash
printf 'flowchart LR\n  agent[Claude] --> panel[Diagram panel]\n  panel --> user[You]\n' > /tmp/demo.mmd
./scripts/reload.sh --tag mermaid-viewer --launch
```

Then in a terminal inside that tagged app: `cmux open /tmp/demo.mmd`

Expected: diagram centered on a dotted background, drag pans, pinch zooms, double-click re-fits, no scrollbars.

- [ ] **Step 6: Commit**

```bash
git add Resources/markdown-viewer/shell.html cmuxTests/MermaidDiagramModeTests.swift
git commit -m "Add pan/zoom camera to diagram mode

Content and dot grid share one transform so dots track the diagram.
Drag pans, ctrl+wheel (trackpad pinch) zooms about the cursor,
double-click fits."
```

---

### Task 6: Preserve camera across live reload

**Files:**
- Modify: `Resources/markdown-viewer/shell.html:1595-1618` (`__cmuxRenderMarkdown`)
- Test: `cmuxTests/MermaidDiagramModeTests.swift` (extend)

**Interfaces:**
- Consumes: `window.__cmuxDiagramCamera()`, `__cmuxDiagramSetCamera`, `__cmuxDiagramFit` (Task 5).
- Produces: no new API. Re-render preserves the camera when one is already established.

- [ ] **Step 1: Write the failing test**

Append to `MermaidDiagramModeTests`:

```swift
    @Test
    func rerenderPreservesCameraPosition() async throws {
        let harness = try await DiagramShellHarness.make()
        defer { harness.tearDown() }

        try await harness.render("```mermaid\nflowchart LR\n  a --> b\n```")
        _ = try await harness.eval("window.__cmuxSetDiagramMode(true)")
        _ = try await harness.eval("window.__cmuxDiagramSetCamera(137, 42, 1.75)")

        // Simulate the FileWatcher pushing an edited diagram.
        try await harness.render("```mermaid\nflowchart LR\n  a --> b\n  b --> c\n```")
        try await harness.waitForMermaidRender()

        let camera = try await harness.evalString("JSON.stringify(window.__cmuxDiagramCamera())")
        #expect(camera.contains("\"x\":137"))
        #expect(camera.contains("\"y\":42"))
        #expect(camera.contains("\"scale\":1.75"))
    }

    @Test
    func firstRenderFitsInsteadOfPreserving() async throws {
        let harness = try await DiagramShellHarness.make()
        defer { harness.tearDown() }

        _ = try await harness.eval("window.__cmuxSetDiagramMode(true)")
        try await harness.render("```mermaid\nflowchart LR\n  a --> b\n```")
        try await harness.waitForMermaidRender()

        // Fit centers the diagram, so the camera must have moved off origin.
        let camera = try await harness.evalString("JSON.stringify(window.__cmuxDiagramCamera())")
        #expect(camera != "{\"x\":0,\"y\":0,\"scale\":1}")
    }
```

Add `waitForMermaidRender()` to `DiagramShellHarness` — poll `document.querySelector('.cmux-mermaid svg') !== null` on a short interval up to ~5s, modeled on the existing `waitForMermaidSnapshot` in `MarkdownMermaidZoomTests.swift`.

- [ ] **Step 2: Run test to verify it fails**

Run: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild test -project cmux.xcodeproj -scheme cmux-unit -destination 'platform=macOS' -derivedDataPath /tmp/cmux-mermaid-viewer -only-testing:cmuxTests/MermaidDiagramModeTests/rerenderPreservesCameraPosition`

Expected: FAIL — the camera resets because `__cmuxRenderMarkdown` replaces `contentEl.innerHTML`, dropping the inline transform.

- [ ] **Step 3: Preserve the camera through re-render**

In `Resources/markdown-viewer/shell.html`, replace `window.__cmuxRenderMarkdown` (lines 1595-1618) with:

```javascript
  window.__cmuxRenderMarkdown = function(md) {
    try {
      headingSlugCounts = Object.create(null);
      var documentParts = extractFrontmatter(md || '');
      var html = renderFrontmatter(documentParts.frontmatter)
        + sanitizeRenderedHTML(marked.parse(documentParts.body || ''));
      var didReplaceContent = contentEl.innerHTML !== html;
      var scrollState = didReplaceContent ? captureMarkdownScrollState() : null;
      // In diagram mode the camera is the reading position. Replacing
      // innerHTML wipes the inline transform, so capture it here and
      // restore after the async mermaid render resolves — otherwise every
      // keystroke-triggered file write would yank the view back to fit.
      var hadCamera = diagramModeEnabled && diagramCameraInitialized;
      var savedCamera = hadCamera ? window.__cmuxDiagramCamera() : null;
      if (didReplaceContent) {
        contentEl.innerHTML = html;
      }
      rewriteLocalImageSources();
      rewriteRemoteImageSources();
      postProcessSpecialBlocks();
      if (didReplaceContent) {
        restoreMarkdownScrollState(scrollState);
      }
      if (diagramModeEnabled) {
        if (savedCamera) {
          window.__cmuxDiagramSetCamera(savedCamera.x, savedCamera.y, savedCamera.scale);
          diagramAfterRender(function() {
            window.__cmuxDiagramSetCamera(savedCamera.x, savedCamera.y, savedCamera.scale);
          });
        } else {
          diagramAfterRender(function() { window.__cmuxDiagramFit(); });
        }
      }
    } catch (e) {
      contentEl.innerHTML =
        '<div style="color:#f85149;font-family:ui-monospace,monospace;white-space:pre-wrap;padding:8px 12px;border:1px solid #f85149;border-radius:6px;margin-bottom:12px">'
        + 'markdown render error: ' + escapeHtml(String((e && e.message) || e))
        + '</div><pre><code>' + escapeHtml(md || '') + '</code></pre>';
    }
  };
```

Then add `diagramAfterRender` immediately above `window.__cmuxRenderMarkdown` — mermaid renders asynchronously, so the camera work must wait for the SVG to exist:

```javascript
  // mermaid.render() is async; poll briefly for the SVG so camera work
  // happens against real geometry. Bounded so a failed render can't spin.
  function diagramAfterRender(cb) {
    var attempts = 0;
    (function poll() {
      if (diagramSVG() || attempts >= 60) { cb(); return; }
      attempts += 1;
      requestAnimationFrame(poll);
    })();
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild test -project cmux.xcodeproj -scheme cmux-unit -destination 'platform=macOS' -derivedDataPath /tmp/cmux-mermaid-viewer -only-testing:cmuxTests/MermaidDiagramModeTests`

Expected: PASS, all 7 tests.

- [ ] **Step 5: Verify live reload by hand**

With the tagged app running and `/tmp/demo.mmd` open, pan and zoom somewhere off-center, then:

```bash
printf 'flowchart LR\n  agent[Claude] --> panel[Diagram panel]\n  panel --> user[You]\n  user --> agent\n' > /tmp/demo.mmd
```

Expected: the new edge appears; the camera does not move.

- [ ] **Step 6: Commit**

```bash
git add Resources/markdown-viewer/shell.html cmuxTests/MermaidDiagramModeTests.swift
git commit -m "Preserve diagram camera across live reload

Rewriting the .mmd file re-renders under a stationary camera instead of
snapping back to fit. First render still fits."
```

---

### Task 7: Theme mermaid to the cmux palette

**Files:**
- Modify: `Resources/markdown-viewer/shell.html:1291-1303` (`renderMermaidBlocks` init), `:1700-1709` (`__cmuxApplyTheme`)
- Modify: `Sources/Panels/MarkdownWebRenderer.swift:352-376` (`applyTheme`)
- Test: `cmuxTests/MermaidDiagramModeTests.swift` (extend)

**Interfaces:**
- Consumes: `MarkdownWebTheme` (existing).
- Produces: JS reads CSS custom properties `--cmux-diagram-dot` and mermaid `themeVariables` from the theme payload.

- [ ] **Step 1: Write the failing test**

Append to `MermaidDiagramModeTests`:

```swift
    @Test
    func mermaidUsesCmuxThemeVariables() async throws {
        let harness = try await DiagramShellHarness.make()
        defer { harness.tearDown() }
        _ = try await harness.eval("window.__cmuxSetDiagramMode(true)")

        _ = try await harness.eval("""
        document.documentElement.style.setProperty('--cmux-diagram-node-bg', 'rgb(30, 32, 38)');
        document.documentElement.style.setProperty('--cmux-diagram-line', 'rgb(120, 130, 150)');
        window.__cmuxApplyTheme();
        """)

        try await harness.render("```mermaid\nflowchart LR\n  a --> b\n```")
        try await harness.waitForMermaidRender()

        let vars = try await harness.evalString("JSON.stringify(window.__cmuxDiagramThemeVariables())")
        #expect(vars.contains("rgb(30, 32, 38)"))
        #expect(vars.contains("rgb(120, 130, 150)"))
    }
```

- [ ] **Step 2: Run test to verify it fails**

Run: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild test -project cmux.xcodeproj -scheme cmux-unit -destination 'platform=macOS' -derivedDataPath /tmp/cmux-mermaid-viewer -only-testing:cmuxTests/MermaidDiagramModeTests/mermaidUsesCmuxThemeVariables`

Expected: FAIL — `__cmuxDiagramThemeVariables` is not a function.

- [ ] **Step 3: Derive mermaid theme variables from CSS custom properties**

In `Resources/markdown-viewer/shell.html`, insert immediately above `function renderMermaidBlocks()` (line 1291):

```javascript
  // Mermaid's built-in palettes don't match cmux chrome, so we feed it
  // explicit themeVariables sourced from CSS custom properties that Swift
  // sets from the app palette (see MarkdownWebRenderer.applyTheme).
  function diagramCSSVar(name, fallback) {
    var value = getComputedStyle(document.documentElement).getPropertyValue(name);
    value = String(value || '').trim();
    return value || fallback;
  }

  window.__cmuxDiagramThemeVariables = function() {
    var isDark = darkMql.matches;
    var nodeBg = diagramCSSVar('--cmux-diagram-node-bg', isDark ? '#1f2228' : '#ffffff');
    var line = diagramCSSVar('--cmux-diagram-line', isDark ? '#8b949e' : '#57606a');
    var text = diagramCSSVar('--cmux-diagram-text', isDark ? '#e6edf3' : '#1f2328');
    var border = diagramCSSVar('--cmux-diagram-border', isDark ? '#3d444d' : '#d0d7de');
    return {
      background: 'transparent',
      primaryColor: nodeBg,
      primaryTextColor: text,
      primaryBorderColor: border,
      secondaryColor: nodeBg,
      tertiaryColor: nodeBg,
      lineColor: line,
      textColor: text,
      mainBkg: nodeBg,
      nodeBorder: border,
      clusterBkg: 'transparent',
      clusterBorder: border,
      edgeLabelBackground: 'transparent',
      fontFamily: 'ui-sans-serif, -apple-system, BlinkMacSystemFont, sans-serif'
    };
  };
```

Then replace the `mermaid.initialize` call (lines 1295-1300) with:

```javascript
          mermaid.initialize({
            startOnLoad: false,
            theme: 'base',
            themeVariables: window.__cmuxDiagramThemeVariables(),
            securityLevel: 'strict',
            fontFamily: 'ui-sans-serif, -apple-system, BlinkMacSystemFont, sans-serif'
          });
```

`theme: 'base'` is the mermaid theme that honors `themeVariables`; `'default'` and `'dark'` ignore most of them.

- [ ] **Step 4: Re-render diagrams on theme change**

`__cmuxApplyTheme` already resets `mermaidInitialized = false` (line 1708), but diagrams already marked `data-rendered` won't repaint. Replace `window.__cmuxApplyTheme` (lines 1700-1709) with:

```javascript
  window.__cmuxApplyTheme = function() {
    var isDark = darkMql.matches;
    if (lightSheet && darkSheet) {
      lightSheet.disabled = !!isDark;
      darkSheet.disabled  = !isDark;
    }
    // Mermaid caches its theme; force re-init so freshly added diagrams
    // pick up the new palette.
    mermaidInitialized = false;
    // Already-rendered diagrams keep their old colors unless we clear the
    // rendered marker and re-run. Only worth doing in diagram mode, where
    // the diagram is the entire surface.
    if (diagramModeEnabled && contentEl) {
      var rendered = contentEl.querySelectorAll('.cmux-mermaid[data-rendered]');
      if (rendered.length) {
        Array.prototype.forEach.call(rendered, function(el) {
          var src = el.getAttribute('data-cmux-source');
          if (src === null) { return; }
          el.removeAttribute('data-rendered');
          el.innerHTML = '<pre class="cmux-source"></pre>';
          el.querySelector('.cmux-source').textContent = src;
        });
        renderMermaidBlocks();
      }
    }
  };
```

For that to work, `renderMermaidBlocks` must stash the source before replacing innerHTML. In `renderMermaidBlocks` (line 1306-1310), insert after `var src = srcEl ? srcEl.textContent : el.textContent;`:

```javascript
        el.setAttribute('data-cmux-source', src);
```

- [ ] **Step 5: Push palette variables from Swift**

In `Sources/Panels/MarkdownWebRenderer.swift`, replace the `payload` dictionary in `applyTheme` (lines 354-361) with:

```swift
            let payload = [
                "--bgColor-default": theme.background,
                "--bgColor-muted": theme.mutedBackground,
                "--bgColor-neutral-muted": theme.neutralMutedBackground,
                "--borderColor-default": theme.border,
                "--borderColor-muted": theme.mutedBorder,
                "--borderColor-neutral-muted": theme.mutedBorder,
                // Diagram-mode palette. Set on :root (not #content) because
                // the dot grid and mermaid themeVariables read from there.
                "--cmux-diagram-node-bg": theme.mutedBackground,
                "--cmux-diagram-border": theme.border,
                "--cmux-diagram-line": theme.mutedBorder,
                "--cmux-diagram-text": theme.foreground
            ]
```

If `MarkdownWebTheme` has no `foreground` member, use the existing text-color member on that struct instead — check its declaration and use the real property name rather than adding one.

Then replace the JS in `applyTheme` (lines 364-374) with:

```swift
            let js = """
            (function(vars) {
              var content = document.getElementById('content');
              Object.keys(vars).forEach(function(name) {
                // Diagram vars live on :root so the fixed dot-grid layer,
                // which is not a child of #content, can read them.
                if (name.indexOf('--cmux-diagram-') === 0) {
                  document.documentElement.style.setProperty(name, vars[name]);
                } else if (content) {
                  content.style.setProperty(name, vars[name]);
                }
              });
              if (content) { content.style.background = 'transparent'; }
              if (window.__cmuxApplyTheme) { window.__cmuxApplyTheme(); }
            })(\(json));
            """
```

Finally, add a dot color derived from the border color. In `shell.html`, the CSS already falls back via `var(--cmux-diagram-dot, rgba(140,140,150,0.28))`; wire it by adding to the Swift payload:

```swift
                "--cmux-diagram-dot": theme.mutedBorder,
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild test -project cmux.xcodeproj -scheme cmux-unit -destination 'platform=macOS' -derivedDataPath /tmp/cmux-mermaid-viewer -only-testing:cmuxTests/MermaidDiagramModeTests -only-testing:cmuxTests/MarkdownMermaidZoomTests`

Expected: PASS.

- [ ] **Step 7: Verify both appearances by hand**

Relaunch the tagged app, open `/tmp/demo.mmd`, and toggle System Settings → Appearance between Light and Dark.

Expected: diagram, dots, and background all follow; no mermaid purple/pink anywhere.

- [ ] **Step 8: Commit**

```bash
git add Resources/markdown-viewer/shell.html Sources/Panels/MarkdownWebRenderer.swift cmuxTests/MermaidDiagramModeTests.swift
git commit -m "Theme mermaid diagrams to the cmux palette

Switches mermaid to the base theme driven by themeVariables sourced from
app-palette CSS variables, and repaints rendered diagrams on theme change."
```

---

### Task 8: Report parse errors from the shell to Swift

**Files:**
- Create: `Sources/Panels/MarkdownDiagramParseResult.swift`
- Modify: `Resources/markdown-viewer/shell.html` (`renderMermaidBlocks`, error CSS)
- Modify: `Sources/Panels/MarkdownWebRenderer.swift:435-463` (`userContentController`)
- Modify: `Sources/Panels/MarkdownPanel.swift`
- Test: `cmuxTests/MermaidDiagramParseReportingTests.swift`

**Interfaces:**
- Consumes: `MarkdownPanel` (Task 2), the `cmuxLib` bridge (existing).
- Produces:
  - `struct MarkdownDiagramParseResult: Equatable { let isValid: Bool; let message: String? }`
  - `MarkdownPanel.diagramParseResult: MarkdownDiagramParseResult?` (`@Published`, read-only)
  - `MarkdownPanel.awaitDiagramParseResult(timeout:completion:)`
  - `MarkdownWebRenderer.Coordinator` handles `action == "diagramParse"`.

- [ ] **Step 1: Write the failing test**

Create `cmuxTests/MermaidDiagramParseReportingTests.swift`:

```swift
import Foundation
import Testing

#if canImport(cmux_DEV)
@testable import cmux_DEV
#elseif canImport(cmux)
@testable import cmux
#endif

@MainActor
@Suite
struct MermaidDiagramParseReportingTests {
    private func makePanel(contents: String) throws -> MarkdownPanel {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-parse-\(UUID().uuidString).mmd")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return MarkdownPanel(workspaceId: UUID(), filePath: url.path)
    }

    @Test
    func recordingAFailureStoresTheMessage() throws {
        let panel = try makePanel(contents: "flowchart LR\n  a -->")
        panel.recordDiagramParseResult(
            MarkdownDiagramParseResult(isValid: false, message: "Parse error on line 2")
        )
        #expect(panel.diagramParseResult?.isValid == false)
        #expect(panel.diagramParseResult?.message == "Parse error on line 2")
    }

    @Test
    func awaitingResolvesImmediatelyWhenResultAlreadyPresent() throws {
        let panel = try makePanel(contents: "flowchart LR\n  a --> b")
        panel.recordDiagramParseResult(MarkdownDiagramParseResult(isValid: true, message: nil))

        var received: MarkdownDiagramParseResult?
        panel.awaitDiagramParseResult(timeout: 1.0) { received = $0 }
        #expect(received?.isValid == true)
    }

    @Test
    func awaitingResolvesWhenTheResultArrivesLater() throws {
        let panel = try makePanel(contents: "flowchart LR\n  a --> b")

        var received: MarkdownDiagramParseResult?
        panel.awaitDiagramParseResult(timeout: 1.0) { received = $0 }
        #expect(received == nil)

        panel.recordDiagramParseResult(
            MarkdownDiagramParseResult(isValid: false, message: "boom")
        )
        #expect(received?.isValid == false)
        #expect(received?.message == "boom")
    }

    @Test
    func reloadingContentClearsTheStaleResult() throws {
        let panel = try makePanel(contents: "flowchart LR\n  a --> b")
        panel.recordDiagramParseResult(MarkdownDiagramParseResult(isValid: false, message: "old"))
        panel.clearDiagramParseResult()
        #expect(panel.diagramParseResult == nil)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Wire the file into pbxproj (Task 1 Step 5), then:

Run: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild test -project cmux.xcodeproj -scheme cmux-unit -destination 'platform=macOS' -derivedDataPath /tmp/cmux-mermaid-viewer -only-testing:cmuxTests/MermaidDiagramParseReportingTests`

Expected: FAIL — `cannot find 'MarkdownDiagramParseResult' in scope`.

- [ ] **Step 3: Add the result type**

Create `Sources/Panels/MarkdownDiagramParseResult.swift`:

```swift
import Foundation

/// Outcome of a mermaid parse inside the diagram WebView.
///
/// Diagram sources are authored by agents as often as by people, so a failed
/// parse has to travel back out through `file.open` rather than living only
/// on screen. `message` carries mermaid's own text, which already names the
/// offending line.
struct MarkdownDiagramParseResult: Equatable {
    let isValid: Bool
    let message: String?
}
```

- [ ] **Step 4: Store and await the result on the panel**

In `Sources/Panels/MarkdownPanel.swift`, add near the other `@Published` properties:

```swift
    /// Most recent mermaid parse outcome for this panel, or nil if the
    /// diagram has not been rendered since the last content change.
    @Published private(set) var diagramParseResult: MarkdownDiagramParseResult?

    /// Callbacks waiting on the next parse outcome. Drained exactly once.
    private var diagramParseWaiters: [(MarkdownDiagramParseResult) -> Void] = []
```

and add these methods:

```swift
    func recordDiagramParseResult(_ result: MarkdownDiagramParseResult) {
        diagramParseResult = result
        let waiters = diagramParseWaiters
        diagramParseWaiters = []
        for waiter in waiters {
            waiter(result)
        }
    }

    func clearDiagramParseResult() {
        diagramParseResult = nil
    }

    /// Delivers the current parse result immediately if one exists, otherwise
    /// enqueues `completion` for the next one. `timeout` is enforced by the
    /// caller (see `v2FileOpen`); this method never blocks.
    func awaitDiagramParseResult(
        timeout: TimeInterval,
        completion: @escaping (MarkdownDiagramParseResult) -> Void
    ) {
        if let diagramParseResult {
            completion(diagramParseResult)
            return
        }
        diagramParseWaiters.append(completion)
    }
```

In `applyLoadedContent`, immediately after the `content = ...` assignment added in Task 2, insert:

```swift
        if isDiagramFile {
            // The prior verdict describes the old bytes.
            diagramParseResult = nil
        }
```

- [ ] **Step 5: Post the parse outcome from JS**

In `Resources/markdown-viewer/shell.html`, replace the body of the `blocks` loop inside `renderMermaidBlocks` (lines 1306-1324) with:

```javascript
      Array.prototype.forEach.call(blocks, function(el, i) {
        el.setAttribute('data-rendered', '1');
        var srcEl = el.querySelector('.cmux-source');
        var src = srcEl ? srcEl.textContent : el.textContent;
        el.setAttribute('data-cmux-source', src);
        var id = 'cmux-mermaid-' + Date.now() + '-' + i + '-' + Math.floor(Math.random() * 1e6);
        try {
          mermaid.render(id, src).then(function(res) {
            el.innerHTML = res.svg;
            applyMermaidZoom(el);
            if (res.bindFunctions) { try { res.bindFunctions(el); } catch (e) {} }
            reportDiagramParse(true, null);
          }).catch(function(err) {
            renderDiagramParseError(el, err);
          });
        } catch (err) {
          renderDiagramParseError(el, err);
        }
      });
```

Then insert above `function renderMermaidBlocks()`:

```javascript
  // Report the parse outcome to Swift so `cmux open` can fail loudly on a
  // broken diagram instead of silently showing an empty panel. Only diagram
  // mode reports — a bad fence inside a long markdown doc is not a reason
  // to fail the open.
  function reportDiagramParse(ok, message) {
    if (!diagramModeEnabled) { return; }
    try {
      window.webkit.messageHandlers.cmuxLib.postMessage({
        action: 'diagramParse',
        ok: !!ok,
        message: message == null ? '' : String(message)
      });
    } catch (e) { /* bridge unavailable; the on-screen card still shows */ }
  }

  function renderDiagramParseError(el, err) {
    var message = String((err && err.message) || err);
    if (diagramModeEnabled && el.getAttribute('data-cmux-last-svg')) {
      // Keep the last good diagram visible behind the error card so a typo
      // mid-edit doesn't blank the thing you were reading.
      el.innerHTML = el.getAttribute('data-cmux-last-svg')
        + '<div class="cmux-render-error cmux-diagram-error">Mermaid: ' + escapeHtml(message) + '</div>';
    } else {
      el.innerHTML = '<div class="cmux-render-error cmux-diagram-error">Mermaid: '
        + escapeHtml(message) + '</div>';
    }
    reportDiagramParse(false, message);
  }
```

To make "keep the last good render" work, stash the SVG on success. In the `.then` handler added above, insert immediately after `el.innerHTML = res.svg;`:

```javascript
            el.setAttribute('data-cmux-last-svg', res.svg);
```

Add the error-card CSS after the diagram CSS block from Task 4:

```css
html[data-cmux-diagram="1"] .cmux-diagram-error {
  position: fixed;
  left: 50%;
  bottom: 24px;
  transform: translateX(-50%);
  z-index: 2;
  max-width: min(680px, calc(100vw - 48px));
  padding: 10px 14px;
  border: 1px solid #f85149;
  border-radius: 8px;
  background: rgba(20, 20, 24, 0.92);
  color: #ff9492;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 12px;
  line-height: 1.5;
  white-space: pre-wrap;
  pointer-events: none;
}
```

Because the card is `position: fixed` it must not inherit the camera transform — it is a child of `#content`, which is transformed. Move it out at report time by appending to `body` instead. Replace the two `el.innerHTML = ... cmux-diagram-error ...` assignments in `renderDiagramParseError` with:

```javascript
    var existing = document.getElementById('cmux-diagram-error-card');
    if (existing) { existing.remove(); }
    if (diagramModeEnabled) {
      var last = el.getAttribute('data-cmux-last-svg');
      if (last) { el.innerHTML = last; }
      var card = document.createElement('div');
      card.id = 'cmux-diagram-error-card';
      card.className = 'cmux-render-error cmux-diagram-error';
      card.textContent = 'Mermaid: ' + message;
      document.body.appendChild(card);
    } else {
      el.innerHTML = '<div class="cmux-render-error">Mermaid: ' + escapeHtml(message) + '</div>';
    }
```

And clear any stale card on a successful render — in the `.then` handler, after `reportDiagramParse(true, null);`:

```javascript
            var stale = document.getElementById('cmux-diagram-error-card');
            if (stale) { stale.remove(); }
```

- [ ] **Step 6: Handle the message in Swift**

In `Sources/Panels/MarkdownWebRenderer.swift`, add a case to the `switch action` in `userContentController` (line 449-461), before `default:`:

```swift
                case "diagramParse":
                    let ok = (body["ok"] as? Bool) ?? false
                    let rawMessage = (body["message"] as? String) ?? ""
                    let message = rawMessage.isEmpty ? nil : rawMessage
                    onDiagramParseResult?(
                        MarkdownDiagramParseResult(isValid: ok, message: message)
                    )
```

Add the callback property to `Coordinator`:

```swift
        var onDiagramParseResult: ((MarkdownDiagramParseResult) -> Void)?
```

Add a matching closure property to the representable and wire it in `makeNSView`/`updateNSView`:

```swift
    let onDiagramParseResult: (MarkdownDiagramParseResult) -> Void
```

In both `makeNSView` branches and in `updateNSView`, alongside the existing coordinator setup calls:

```swift
        context.coordinator.onDiagramParseResult = onDiagramParseResult
```

In `Sources/Panels/MarkdownPanelView.swift`, pass it at the `MarkdownWebRenderer(...)` call site:

```swift
                onDiagramParseResult: { [weak panel] result in
                    panel?.recordDiagramParseResult(result)
                },
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild test -project cmux.xcodeproj -scheme cmux-unit -destination 'platform=macOS' -derivedDataPath /tmp/cmux-mermaid-viewer -only-testing:cmuxTests/MermaidDiagramParseReportingTests`

Expected: PASS, 4 tests.

- [ ] **Step 8: Verify the error card by hand**

```bash
printf 'flowchart LR\n  a --> b\n' > /tmp/demo.mmd
```

Open it in the tagged app, then break it:

```bash
printf 'flowchart LR\n  a -->\n  --> ???\n' > /tmp/demo.mmd
```

Expected: the previous diagram stays on screen; a red error card appears at the bottom naming the mermaid error. Fixing the file clears the card.

- [ ] **Step 9: Commit**

```bash
git add Sources/Panels/MarkdownDiagramParseResult.swift Sources/Panels/MarkdownPanel.swift Sources/Panels/MarkdownWebRenderer.swift Sources/Panels/MarkdownPanelView.swift Resources/markdown-viewer/shell.html cmuxTests/MermaidDiagramParseReportingTests.swift cmux.xcodeproj/project.pbxproj
git commit -m "Report mermaid parse outcomes from the shell to the panel

Failed parses surface an error card over the last good render and post
the outcome back through the cmuxLib bridge."
```

---

### Task 9: Fail `cmux open` on an invalid diagram

**Files:**
- Modify: `Sources/FileOpenSocketSupport.swift:136-173`
- Test: `cmuxTests/MermaidDiagramParseReportingTests.swift` (extend)

**Interfaces:**
- Consumes: `MarkdownPanel.awaitDiagramParseResult(timeout:completion:)` (Task 8); `v2AwaitCallback` (existing, `TerminalController.swift:5455`).
- Produces: `v2FileOpen` returns `.err(code: "render_failed", ...)` for an invalid diagram.

**Context the implementer needs:** `v2FileOpen` runs its whole body inside `v2MainSync`. `v2AwaitCallback` already handles the main-thread case by spinning a CFRunLoop with a timeout (`TerminalController.swift:5483-5510`) — this is the same mechanism `v2RunJavaScript` uses to await a WebView callback before responding. No new concurrency primitive is required. An `.err` return already produces stderr + exit 1 via `CLIError` (`CLI/cmux.swift:2585`, `:34366`); no CLI change is needed.

- [ ] **Step 1: Write the failing test**

Append to `MermaidDiagramParseReportingTests`:

```swift
    @Test
    func fileOpenReportsAnInvalidDiagramAsAnError() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-open-invalid-\(UUID().uuidString).mmd")
        try "flowchart LR\n  a -->\n".write(to: url, atomically: true, encoding: .utf8)

        let controller = try #require(TerminalController.shared)
        let result = controller.v2FileOpen(params: ["path": url.path, "focus": false])

        guard case let .err(code, message, _) = result else {
            Issue.record("Expected an error for an invalid diagram, got \(result)")
            return
        }
        #expect(code == "render_failed")
        #expect(message.lowercased().contains("mermaid"))
    }

    @Test
    func fileOpenSucceedsForAValidDiagram() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmux-open-valid-\(UUID().uuidString).mmd")
        try "flowchart LR\n  a --> b\n".write(to: url, atomically: true, encoding: .utf8)

        let controller = try #require(TerminalController.shared)
        let result = controller.v2FileOpen(params: ["path": url.path, "focus": false])

        guard case let .ok(payload) = result else {
            Issue.record("Expected success for a valid diagram, got \(result)")
            return
        }
        #expect(payload["display_mode"] as? String == "diagram")
    }
```

If `TerminalController.shared` is not the accessor used by existing socket tests, match whatever `cmuxTests` already uses to reach a controller — grep for `v2FileOpen(` in `cmuxTests/` and copy that setup.

- [ ] **Step 2: Run test to verify it fails**

Run: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild test -project cmux.xcodeproj -scheme cmux-unit -destination 'platform=macOS' -derivedDataPath /tmp/cmux-mermaid-viewer -only-testing:cmuxTests/MermaidDiagramParseReportingTests/fileOpenReportsAnInvalidDiagramAsAnError`

Expected: FAIL — `v2FileOpen` returns `.ok` because it never waits for a render.

- [ ] **Step 3: Await the parse result before responding**

In `Sources/FileOpenSocketSupport.swift`, insert immediately after the `guard !openedPanels.isEmpty else { ... }` block (after line 145) and before `let windowId = ...`:

```swift
              // Diagram files block the response on their first parse so a
              // broken .mmd fails the caller's `cmux open` instead of quietly
              // opening an empty panel. Bounded: a slow or wedged WebView
              // falls through to success rather than hanging the socket.
              if let diagramPanel = openedPanels.compactMap({ $0 as? MarkdownPanel })
                  .first(where: { $0.isDiagramFile }) {
                  let parse: MarkdownDiagramParseResult? = v2AwaitCallback(timeout: 4.0) { finish in
                      diagramPanel.awaitDiagramParseResult(timeout: 4.0) { finish($0) }
                  }
                  if let parse, !parse.isValid {
                      result = .err(
                          code: "render_failed",
                          message: parse.message.map { "Mermaid: \($0)" }
                              ?? "Mermaid: diagram failed to render",
                          data: ["path": diagramPanel.filePath]
                      )
                      return
                  }
              }
```

Note the `guard` at line 142 already returned early on an empty `openedPanels`, so `openedPanels` is non-empty here.

- [ ] **Step 4: Run tests to verify they pass**

Run: `CMUX_SKIP_ZIG_BUILD=1 xcodebuild test -project cmux.xcodeproj -scheme cmux-unit -destination 'platform=macOS' -derivedDataPath /tmp/cmux-mermaid-viewer -only-testing:cmuxTests/MermaidDiagramParseReportingTests`

Expected: PASS, 6 tests.

- [ ] **Step 5: Verify the CLI contract end-to-end**

```bash
./scripts/reload.sh --tag mermaid-viewer --launch
printf 'flowchart LR\n  a --> b\n' > /tmp/ok.mmd
printf 'flowchart LR\n  a -->\n  --> ???\n' > /tmp/bad.mmd
```

In a terminal inside the tagged app:

```bash
cmux open /tmp/ok.mmd; echo "exit=$?"
cmux open /tmp/bad.mmd; echo "exit=$?"
```

Expected: the first prints `OK files=1 ...` and `exit=0`. The second prints `Error: render_failed: Mermaid: ...` on **stderr** and `exit=1`.

Confirm stderr specifically:

```bash
cmux open /tmp/bad.mmd 2>/tmp/err.txt 1>/dev/null; echo "exit=$?"; cat /tmp/err.txt
```

Expected: `exit=1` and the mermaid message in `/tmp/err.txt`.

- [ ] **Step 6: Commit**

```bash
git add Sources/FileOpenSocketSupport.swift cmuxTests/MermaidDiagramParseReportingTests.swift
git commit -m "Fail cmux open on an invalid mermaid diagram

file.open now awaits the first parse for diagram files and returns
render_failed, so an agent finds out its own diagram is broken."
```

---

### Task 10: Advertise the verb and document the pattern

**Files:**
- Modify: `Sources/WorkspaceSnapshotSocketSupport.swift:195-208`
- Modify: `skills/cmux-markdown/SKILL.md`
- Modify: `Resources/Localizable.xcstrings` (audit only)

**Interfaces:**
- Consumes: everything above.
- Produces: no code API. Discoverability only.

- [ ] **Step 1: Advertise the diagram verb in the snapshot**

In `Sources/WorkspaceSnapshotSocketSupport.swift`, replace the `open` entry (lines 197-198) and add a diagram entry:

```swift
            ["verb": "open", "cli": "cmux open <file>",
             "desc": "Show a file beside you (smart placement). .md renders as markdown; .mmd/.mermaid render as a pan/zoom diagram."],
```

These strings are agent-facing socket payload, not UI chrome, and follow the existing English-only convention in this array — do not localize them.

- [ ] **Step 2: Document the pattern in the skill**

Append to `skills/cmux-markdown/SKILL.md`:

```markdown
## Diagrams

Standalone mermaid files (`.mmd`, `.mermaid`) open as a diagram canvas —
dot grid, drag to pan, pinch to zoom, double-click to fit. No toolbar and
no export: this is a surface for thinking with the user, not a publishing
tool.

The loop is the same as markdown — write the file, open it once, then keep
rewriting the file:

```bash
cat > /tmp/plan.mmd <<'EOF'
flowchart LR
  cli[cmux open] --> route{extension}
  route -->|.md| preview[Markdown preview]
  route -->|.mmd| diagram[Diagram canvas]
EOF
cmux open /tmp/plan.mmd
```

Rewriting `/tmp/plan.mmd` re-renders the panel in place. The user's pan and
zoom are preserved across the update, so iterating on a diagram they are
looking at does not move it under them.

`cmux open` **validates the diagram**: an invalid `.mmd` exits non-zero and
prints mermaid's parse error to stderr, while the panel keeps the last good
render visible behind an error card. Check the exit code — if it fails, fix
the source and re-open rather than leaving a stale diagram on screen.

Use this when explaining architecture, state machines, data flow, or any
decision with more than about three moving parts. A graph the user can look
at beats three paragraphs describing the same graph.
```

- [ ] **Step 3: Run the localization audit**

Per the repo policy, enumerate every user-facing surface this feature changed and confirm both locales.

User-facing strings added across the whole feature: `markdown.mode.showDiagramSource`, `markdown.mode.showDiagram` (Task 2). The error card text is mermaid's own parser output (not a cmux string) plus the literal prefix `Mermaid: `, which is a product name and is not localized.

```bash
python3 -c "
import json
d = json.load(open('Resources/Localizable.xcstrings'))['strings']
for k in ['markdown.mode.showDiagramSource','markdown.mode.showDiagram']:
    locs = sorted(d.get(k, {}).get('localizations', {}).keys())
    print(k, locs, 'OK' if locs == ['en','ja'] else 'MISSING')
"
```

Expected: both lines end in `OK`.

Then scan the diff for newly introduced bare English in Swift UI code:

```bash
git diff main --stat
git diff main -- 'Sources/**/*.swift' | grep -nE '^\+.*(Text\(|Button\(|label:|title:)\s*"' || echo "no bare strings"
```

Expected: `no bare strings`.

- [ ] **Step 4: Run the full affected test suite**

```bash
CMUX_SKIP_ZIG_BUILD=1 xcodebuild test -project cmux.xcodeproj -scheme cmux-unit -destination 'platform=macOS' -derivedDataPath /tmp/cmux-mermaid-viewer \
  -only-testing:cmuxTests/MermaidDiagramFileResolverTests \
  -only-testing:cmuxTests/MermaidDiagramRoutingTests \
  -only-testing:cmuxTests/MermaidDiagramModeTests \
  -only-testing:cmuxTests/MermaidDiagramParseReportingTests \
  -only-testing:cmuxTests/MarkdownPanelTests \
  -only-testing:cmuxTests/MarkdownMermaidZoomTests \
  -only-testing:cmuxTests/FilePreviewKindResolverTests
```

Expected: all pass, and the executed-test count is non-zero for every suite listed.

- [ ] **Step 5: Verify pbxproj integrity**

Parallel-branch merges can duplicate pbxproj IDs and silently drop files from the build.

```bash
./scripts/lint-pbxproj-test-wiring.sh
grep -oE '^\s+[A-F0-9]{24} ' cmux.xcodeproj/project.pbxproj | sort | uniq -d
```

Expected: the lint passes and the duplicate scan prints nothing.

- [ ] **Step 6: Commit**

```bash
git add Sources/WorkspaceSnapshotSocketSupport.swift skills/cmux-markdown/SKILL.md
git commit -m "Document and advertise the mermaid diagram surface

Snapshot actions mention diagram routing; the markdown skill documents the
write-file-then-open loop and the validating exit code."
```

---

## Verification Checklist

Run after all tasks, against a freshly built tagged app.

- [ ] `cmux open /tmp/demo.mmd` opens a dotted canvas with the diagram centered.
- [ ] Drag pans; pinch/scroll zooms; double-click re-fits; no scrollbars appear.
- [ ] Rewriting the file updates the diagram without moving the camera.
- [ ] `cmux open /tmp/bad.mmd` exits 1 with the mermaid error on stderr.
- [ ] A broken edit leaves the last good diagram visible behind the error card.
- [ ] Fixing the source clears the card.
- [ ] Light and dark appearance both theme the diagram, dots, and background.
- [ ] `cmux open notes.md` still renders markdown exactly as before.
- [ ] A `.md` file containing a mermaid fence still renders inline, scrolling normally.
- [ ] The header button toggles diagram ⇄ source on a `.mmd`, and preview ⇄ source on a `.md`.
