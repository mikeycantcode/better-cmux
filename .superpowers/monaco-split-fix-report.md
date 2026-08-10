# Monaco panel renders black after a pane split — root cause and fix

## Symptom

The Monaco code-editor panel (`FilePreviewPanel` text mode, `EditReviewPanelView` diff)
renders completely black/blank after a bonsplit split of the workspace. Terminal panes are
unaffected. Pre-existing, not caused by the transparent-background commit `ed0b6361`.

## Root cause

cmux re-parents panes by `removeFromSuperview` → `addSubview` when the bonsplit layout
changes. While a `WKWebView` is out of a window, WebKit suspends painting and can reclaim
its WebContent process; when the view is re-added, nothing drives the in-window lifecycle
back on, so the layer stays blank. Monaco's web view is a plain `WKWebView`
(`Sources/Monaco/MonacoWebController.swift:55`, pre-fix) with no `viewDidMoveToWindow`
handling — and because `wv.setValue(false, forKey: "drawsBackground")` is set
(`MonacoWebController.swift:57`), the unpainted view shows through as pure black rather
than white. The controller correctly survives SwiftUI wrapper churn (it owns the web view
and hands the same instance back from `makeWebView()`), so no reload is ever triggered:
`isReady` stays `true`, `lastAppliedContent` matches, and `load(text:language:theme:)`
short-circuits at `MonacoWebController.swift:89`. The result is a permanently blank editor
with no user-facing recovery path.

## What the other WebKit panels do differently

This exact bug was already found and fixed for the Markdown panel, which is why Markdown
survives splits and Monaco does not:

- `Sources/Panels/MarkdownWebSupport.swift:22` — `MarkdownWebView: WKWebView` overrides
  `viewDidMoveToWindow`. On detach (`window == nil`) it calls the private
  `viewDidHide` / `_exitInWindow` selectors; on re-entry it calls
  `viewDidUnhide` / `_enterInWindow` / `_endDeferringViewInWindowChangesSync`
  and forces `needsLayout` / `needsDisplay` / `layoutSubtreeIfNeeded` /
  `displayIfNeeded` (`MarkdownWebSupport.swift:44-76`). All private selectors are
  `responds(to:)`-guarded.
- `Sources/Panels/MarkdownWebRenderer.swift:779-802` — coordinator-side recovery.
  `handleViewLeftWindow` records whether the document was healthy at detach;
  `handleViewReenteredWindow` reloads the shell only if it was healthy and is now dead,
  so a genuine crash loop is not granted a fresh recovery budget on every re-parent.
- `Sources/Panels/MarkdownWebRenderer.swift:33-35` — the reuse path in `makeNSView`
  detaches the retained web view (`removeFromSuperview()`) before returning it to a freshly
  created SwiftUI host.
- `Sources/Panels/BrowserPanelView.swift` hosts its `WKWebView` in an AppKit portal and
  re-pins/re-lays it out on every re-host (`pinHostedWebView`, `BrowserPanelView.swift:6029`)
  with `viewDidMoveToWindow` hooks at `BrowserPanelView.swift:6364`, i.e. the same class of
  handling by a different route.

Monaco had none of the three.

## Fix

All changes are in the single shared hosting path, `Sources/Monaco/MonacoWebController.swift`,
so both mount sites (`Sources/Panels/FilePreviewPanel.swift:1652` and
`Sources/Panels/EditReviewPanelView.swift:21`) are covered without per-site patches.
`MonacoEditorView.swift` / `MonacoDiffView.swift` are untouched.

1. New `MonacoWebView: WKWebView` (same file, to avoid an unwired pbxproj entry) with the
   `viewDidMoveToWindow` detach/re-entry rendering reattach, ported from `MarkdownWebView`
   including the `responds(to:)` guards.
2. `makeWebView()` now instantiates `MonacoWebView` and wires `onLeaveWindow` /
   `onReenterWindow` through `bindWindowLifecycle`. Leave records
   `shellWasHealthyWhenDetached = isReady`; re-entry no-ops when `isReady` (the repaint nudge
   is enough) and otherwise seeds `pendingLoad` from `lastAppliedContent` and reloads the
   shell, so content replays on the `ready` bridge message. `pendingDiff` is retained across
   `load(request:)` and replays the same way, so the diff panel recovers too.
3. `makeWebView()`'s reuse path now calls `removeFromSuperview()` when the retained web view
   still has a stale superview, matching `MarkdownWebRenderer.makeNSView`.
4. `dismantle()` clears both closures.

No new user-facing strings, so no localization work is required; no typing-latency-sensitive
path (`WindowTerminalHostView.hitTest`, `TabItemView`, `TerminalSurface.forceRefresh`) is
touched.

## Verification

`CMUX_SKIP_ZIG_BUILD=1 xcodebuild -project cmux.xcodeproj -scheme cmux -configuration Debug
-destination 'platform=macOS' -derivedDataPath /tmp/cmux-herdr build` → **BUILD SUCCEEDED**.
Tagged Debug app rebuilt with `./scripts/reload.sh --tag herdr-sidebar` (build only).

## What could not be verified without a live GUI

- No unit test was added. This is a WebKit/AppKit view-lifecycle mechanism: it requires a
  real window, a real WebContent process, and an actual bonsplit re-parent to exercise. A
  test that asserts "`viewDidMoveToWindow` sets a flag" would assert the implementation, not
  the bug, so writing one would be theater. Stating this explicitly rather than adding a fake
  test.
- Not empirically confirmed: that the black frame is specifically the suspended-paint state
  vs. a terminated WebContent process. The fix covers both (repaint nudge + healthy-at-detach
  reload), so the distinction does not change the change set.
- Needs Mike's manual check: open a file in the Monaco editor, split the pane, and confirm the
  editor repaints with its buffer, cursor, and undo history intact; repeat with the diff
  (Edit Review) panel; and confirm a drag of the pane between splits and a workspace switch
  behave the same.
