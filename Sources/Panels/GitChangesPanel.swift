import AppKit
import Combine
import Foundation
import WebKit

/// One reviewable file in the Changes panel: the HEAD/worktree pair rendered as a
/// Monaco inline diff plus the metadata the native checklist rail shows.
///
/// A value snapshot on purpose — the checklist rail renders these below a
/// `ForEach` boundary and must never reach back into ``GitWorkingTreeModel``.
struct GitChangesFile: Identifiable, Hashable, Sendable {
    /// Repo-relative path (the post-rename path for renames).
    let path: String
    /// Porcelain status letter (`M`/`A`/`D`/`R`/`U`).
    let statusLetter: String
    /// Whether this path currently has staged content.
    let staged: Bool
    /// Monaco language id for syntax highlighting.
    let language: String
    /// Contents at HEAD (empty for added/untracked).
    let original: String
    /// Contents in the working tree (empty for deleted).
    let modified: String
    let additions: Int
    let deletions: Int

    var id: String { path }

    /// Top-level directory used to group rows in the checklist rail; files at the
    /// repo root group under an empty name.
    var groupName: String {
        let components = path.split(separator: "/")
        return components.count > 1 ? String(components[0]) : ""
    }

    var fileName: String { (path as NSString).lastPathComponent }
}

/// Messages the `changes.html` shell posts back over `cmuxGitChanges`.
enum GitChangesBridgeMessage: Equatable {
    case ready
    case stage(path: String)
    case unstage(path: String)
    case revert(path: String)
    case openFile(path: String)
    case loadError(message: String)

    /// Parses a `WKScriptMessage` body. Returns `nil` for anything unrecognized so
    /// a malformed post from the web view is ignored rather than trapped.
    init?(body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return nil }
        let path = dict["path"] as? String
        switch type {
        case "ready": self = .ready
        case "loadError": self = .loadError(message: dict["message"] as? String ?? "")
        case "stage": guard let path else { return nil }; self = .stage(path: path)
        case "unstage": guard let path else { return nil }; self = .unstage(path: path)
        case "revert": guard let path else { return nil }; self = .revert(path: path)
        case "openFile": guard let path else { return nil }; self = .openFile(path: path)
        default: return nil
        }
    }
}

/// Drives the Changes panel's single `WKWebView`: loads the bundled shell from the
/// Monaco asset origin, queues payloads until the page reports `ready`, and
/// forwards bridge messages to the owning panel.
///
/// Owned by the panel (not the SwiftUI wrapper) so the web view survives SwiftUI
/// recreating its representable during split/workspace churn — the same ownership
/// model ``MonacoWebController`` uses.
@MainActor
final class GitChangesWebController: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    static let messageHandlerName = "cmuxGitChanges"

    private(set) var webView: WKWebView?
    private var isReady = false
    private var pendingPayloadJSON: String?
    private var pendingTheme: String?
    // Last values actually evaluated into the page. `flushPending` clears the
    // pending fields, so without these a web-content-process crash would reload
    // the shell with nothing to replay and leave a blank panel at the default
    // theme until the next `$status` change.
    private var lastPayloadJSON: String?
    private var lastTheme: String?

    /// Called on the main actor for every parsed bridge message.
    var onMessage: ((GitChangesBridgeMessage) -> Void)?

    func makeWebView() -> WKWebView {
        if let webView { return webView }
        let config = WKWebViewConfiguration()
        config.setURLSchemeHandler(
            MonacoAssetURLSchemeHandler(),
            forURLScheme: MonacoAssetURLSchemeHandler.scheme
        )
        // Weak trampoline: `userContentController` retains its handler, so a direct
        // `add(self, ...)` would leak this controller and its web content process
        // on any teardown path where `dismantle()` never runs.
        config.userContentController.add(
            WeakMonacoScriptMessageHandler(self),
            name: Self.messageHandlerName
        )
        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        wv.setValue(false, forKey: "drawsBackground")
        wv.allowsBackForwardNavigationGestures = false
        wv.allowsLinkPreview = false
#if DEBUG
        if #available(macOS 13.3, *) { wv.isInspectable = true }
#endif
        webView = wv
        load()
        return wv
    }

    private func shellRequest() -> URLRequest {
        URLRequest(
            url: URL(string: "\(MonacoAssetURLSchemeHandler.scheme)://app/git-changes/changes.html")!
        )
    }

    /// Loads (or reloads) the shell. Re-seeds the pending payload/theme from the
    /// last applied values so a recovery reload repaints the panel on `ready`
    /// instead of coming back empty.
    private func load() {
        isReady = false
        pendingPayloadJSON = pendingPayloadJSON ?? lastPayloadJSON
        pendingTheme = pendingTheme ?? lastTheme
        webView?.load(shellRequest())
    }

    /// Pushes a rendered payload, queueing it if the shell is not ready yet.
    func render(payloadJSON: String) {
        pendingPayloadJSON = payloadJSON
        guard isReady else { return }
        flushPending()
    }

    func setTheme(_ theme: String) {
        pendingTheme = theme
        guard isReady else { return }
        flushPending()
    }

    /// Scrolls the card for `path` into view. No-op when the path is not rendered.
    func scrollToFile(_ path: String) {
        guard isReady, let webView else { return }
        webView.evaluateJavaScript(
            "window.cmuxScrollToFile && window.cmuxScrollToFile(\(Self.jsStringLiteral(path)));",
            completionHandler: nil
        )
    }

    private func flushPending() {
        guard let webView else { return }
        if let theme = pendingTheme {
            pendingTheme = nil
            lastTheme = theme
            webView.evaluateJavaScript(
                "window.cmuxSetTheme && window.cmuxSetTheme(\(Self.jsStringLiteral(theme)));",
                completionHandler: nil
            )
        }
        if let payload = pendingPayloadJSON {
            pendingPayloadJSON = nil
            lastPayloadJSON = payload
            webView.evaluateJavaScript(
                "window.cmuxRenderChanges && window.cmuxRenderChanges(\(Self.jsStringLiteral(payload)));",
                completionHandler: nil
            )
        }
    }

    /// JSON-encodes `value` as a JS string literal so arbitrary text is escaped.
    private static func jsStringLiteral(_ value: String) -> String {
        (try? JSONSerialization.data(withJSONObject: [value]))
            .flatMap { String(data: $0, encoding: .utf8) }
            .map { String($0.dropFirst().dropLast()) } ?? "\"\""
    }

    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == Self.messageHandlerName,
              let parsed = GitChangesBridgeMessage(body: message.body) else { return }
        if case .ready = parsed {
            isReady = true
            flushPending()
        }
        onMessage?(parsed)
    }

    func dismantle() {
        webView?.stopLoading()
        webView?.configuration.userContentController
            .removeScriptMessageHandler(forName: Self.messageHandlerName)
        webView?.navigationDelegate = nil
        webView = nil
        isReady = false
        pendingPayloadJSON = nil
        pendingTheme = nil
        lastPayloadJSON = nil
        lastTheme = nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard let current = self.webView, current === webView else { return }
        // `load()` re-seeds pending from the last applied payload/theme, so the
        // recovered page repaints on its `ready` without waiting for new status.
        load()
    }
}

/// Main-area diff review surface: stacked Monaco inline-diff cards in one web view
/// plus a native staging checklist rail.
///
/// The panel does not own git state — it reads ``GitWorkingTreeModel`` (shared with
/// the Git sidebar tab) and re-renders whenever that model's status changes, so
/// staging from either surface converges on one model.
@MainActor
final class GitChangesPanel: Panel, ObservableObject {
    let id: UUID
    let panelType: PanelType = .gitChanges
    var displayTitle: String {
        String(localized: "gitChanges.title", defaultValue: "Changes")
    }
    var displayIcon: String? { "plusminus" }

    /// Files currently rendered, in web-view card order.
    @Published private(set) var files: [GitChangesFile] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var focusFlashToken: Int = 0
    /// Set when the user hits Revert on a card; the view presents the confirm.
    @Published var pendingRevertPath: String?

    let model: GitWorkingTreeModel
    let webController = GitChangesWebController()

    private weak var workspace: Workspace?
    private var statusCancellable: AnyCancellable?
    private var reloadTask: Task<Void, Never>?
    private var isClosed = false

    /// Upper bound on cards rendered in one pass. A 5000-file working tree would
    /// otherwise spawn 5000 `git show` processes and mount 5000 diff editors.
    static let maxRenderedFiles = 200
    /// Files larger than this are rendered with empty content (the rail still shows
    /// their counts) rather than pushing megabytes through the JS bridge.
    static let maxFileByteCount = 1_000_000

    init(workspace: Workspace, model: GitWorkingTreeModel) {
        self.id = UUID()
        self.workspace = workspace
        self.model = model
        webController.onMessage = { [weak self] message in
            self?.handleBridgeMessage(message)
        }
        // Status changes (from either surface's staging actions, or the watcher)
        // are the single trigger for re-rendering. `reload()` deliberately does not
        // call `model.refresh()`, which would make this a feedback loop.
        statusCancellable = model.$status
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.scheduleReload()
            }
        Task { [weak model] in await model?.refresh() }
    }

    // MARK: - Reload

    func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { [weak self] in
            await self?.reload()
        }
    }

    /// Recomputes the diff payload from the model's current status and pushes it
    /// to the web view. Never mutates git state.
    func reload() async {
        guard !isClosed else { return }
        let root = model.repoPath
        let status = model.status
        guard !root.isEmpty else {
            files = []
            pushPayload()
            return
        }

        isLoading = true
        defer { isLoading = false }

        let stagedPaths = Set(status.staged.map(\.path))
        var seen = Set<String>()
        var entries: [GitStatusEntry] = []
        for entry in status.staged + status.modified + status.untracked
        where seen.insert(entry.path).inserted {
            entries.append(entry)
        }
        entries = Array(entries.prefix(Self.maxRenderedFiles))

        let counts = await Self.loadDiffCounts(root: root)
        var built: [GitChangesFile] = []
        for entry in entries {
            if Task.isCancelled { return }
            let original = await Self.headContents(for: entry, root: root)
            let modified = await Self.workingTreeContents(for: entry, root: root)
            let count = counts[entry.path]
            built.append(
                GitChangesFile(
                    path: entry.path,
                    statusLetter: String(entry.status.rawValue),
                    staged: stagedPaths.contains(entry.path),
                    language: MonacoLanguageMap.languageId(forPath: entry.path),
                    original: original,
                    modified: modified,
                    additions: count?.additions
                        ?? (entry.status == .untracked ? Self.lineCount(modified) : 0),
                    deletions: count?.deletions ?? 0
                )
            )
        }

        guard !Task.isCancelled, !isClosed else { return }
        files = built
        pushPayload()
    }

    private func pushPayload() {
        guard let json = Self.payloadJSON(files: files) else { return }
        webController.render(payloadJSON: json)
    }

    /// Encodes the Swift→JS payload. All UI chrome text the shell renders is
    /// localized here; `changes.html` never hardcodes English.
    static func payloadJSON(files: [GitChangesFile]) -> String? {
        let fileObjects: [[String: Any]] = files.map { file in
            [
                "path": file.path,
                "status": file.statusLetter,
                "staged": file.staged,
                "original": file.original,
                "modified": file.modified,
                "language": file.language,
            ]
        }
        let payload: [String: Any] = [
            "files": fileObjects,
            "strings": [
                "stage": String(localized: "gitChanges.stage", defaultValue: "Stage"),
                "unstage": String(localized: "gitChanges.unstage", defaultValue: "Unstage"),
                "revert": String(localized: "gitChanges.revert", defaultValue: "Revert"),
                "open": String(localized: "gitChanges.open", defaultValue: "Open"),
                "newBadge": String(localized: "gitChanges.new", defaultValue: "New"),
                "empty": String(localized: "gitChanges.empty", defaultValue: "No changes"),
            ],
        ]
        return (try? JSONSerialization.data(withJSONObject: payload))
            .flatMap { String(data: $0, encoding: .utf8) }
    }

    // MARK: - Git reads

    /// `git show HEAD:<path>` for tracked, non-added paths. Renames read the
    /// pre-rename path, which is the only name that exists at HEAD.
    private static func headContents(for entry: GitStatusEntry, root: String) async -> String {
        guard entry.status != .untracked, entry.status != .added else { return "" }
        let headPath = entry.originalPath ?? entry.path
        switch await GitWorkingTreeModel.runGit(["show", "HEAD:\(headPath)"], in: root) {
        // Oversized blobs take the same "too large" path as the working-tree
        // side: empty contents, so the card renders the placeholder instead of
        // shipping megabytes into Monaco.
        case .success(let output):
            return output.utf8.count <= maxFileByteCount ? output : ""
        // A path with no HEAD blob (e.g. added-then-modified) diffs against empty.
        case .failure: return ""
        }
    }

    private static func workingTreeContents(for entry: GitStatusEntry, root: String) async -> String {
        guard entry.status != .deleted else { return "" }
        let absolute = GitPanelView.absolutePath(root: root, relative: entry.path)
        return await Task.detached(priority: .userInitiated) { () -> String in
            guard let data = FileManager.default.contents(atPath: absolute),
                  data.count <= maxFileByteCount,
                  let text = String(data: data, encoding: .utf8) else { return "" }
            return text
        }.value
    }

    /// `git diff --numstat HEAD` → per-path added/deleted line counts. Untracked
    /// files are absent from this output and fall back to a line count.
    private static func loadDiffCounts(root: String) async -> [String: (additions: Int, deletions: Int)] {
        guard case .success(let output) = await GitWorkingTreeModel.runGit(
            ["diff", "--numstat", "HEAD"],
            in: root
        ) else { return [:] }
        return parseNumstat(output)
    }

    /// Parses `--numstat` lines. Binary files report `-` and are skipped; rename
    /// lines carry `old => new` and are keyed by the new path.
    static func parseNumstat(_ output: String) -> [String: (additions: Int, deletions: Int)] {
        var result: [String: (additions: Int, deletions: Int)] = [:]
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard fields.count == 3,
                  let additions = Int(fields[0]),
                  let deletions = Int(fields[1]) else { continue }
            var path = String(fields[2])
            if let arrow = path.range(of: " => ") {
                path = String(path[arrow.upperBound...])
            }
            result[path] = (additions, deletions)
        }
        return result
    }

    static func lineCount(_ text: String) -> Int {
        text.isEmpty ? 0 : text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    // MARK: - Bridge actions
    //
    // Card buttons and rail checkboxes route through these single action paths, so
    // the two surfaces cannot drift.

    private func handleBridgeMessage(_ message: GitChangesBridgeMessage) {
        switch message {
        case .ready:
            // The controller replays its queued payload on `ready`; pushing again
            // here would tear down and rebuild every diff editor on first load.
            break
        case .stage(let path):
            Task { await model.stageFile(path) }
        case .unstage(let path):
            Task { await model.unstageFile(path) }
        case .revert(let path):
            pendingRevertPath = path
        case .openFile(let path):
            openInEditor(path)
        case .loadError:
            break
        }
    }

    /// Toggles staging for `path`. Shared by the rail checkbox and the card button.
    func toggleStaged(path: String, isStaged: Bool) {
        Task {
            if isStaged {
                await model.unstageFile(path)
            } else {
                await model.stageFile(path)
            }
        }
    }

    /// Discards working-tree changes for `path` through the model's single discard
    /// path (`clean` for untracked, `checkout` otherwise).
    func confirmRevert(path: String) {
        let entry = entryForRevert(path: path)
        pendingRevertPath = nil
        guard let entry else { return }
        Task { await model.discardFile(entry) }
    }

    private func entryForRevert(path: String) -> GitStatusEntry? {
        let status = model.status
        return (status.modified + status.untracked + status.staged).first { $0.path == path }
    }

    /// Opens the file in a normal editor surface next to the Changes panel.
    func openInEditor(_ relativePath: String) {
        guard let workspace,
              let paneId = workspace.bonsplitController.focusedPaneId
                ?? workspace.bonsplitController.allPaneIds.first else { return }
        let absolute = GitPanelView.absolutePath(root: model.repoPath, relative: relativePath)
        _ = workspace.openFileSurfaces(
            inPane: paneId,
            filePaths: [absolute],
            focus: true,
            reuseExisting: true
        )
    }

    /// Focuses the card for `path` (used when a Git-tab row is clicked while the
    /// Changes panel is open).
    func revealFile(path: String) {
        webController.scrollToFile(path)
    }

    // MARK: - Panel

    func close() {
        isClosed = true
        reloadTask?.cancel()
        reloadTask = nil
        statusCancellable = nil
        webController.onMessage = nil
        webController.dismantle()
    }

    func focus() {
        webController.webView?.window?.makeFirstResponder(webController.webView)
    }

    func unfocus() {}

    func triggerFlash(reason: WorkspaceAttentionFlashReason) {
        _ = reason
        guard NotificationPaneFlashSettings.isEnabled() else { return }
        focusFlashToken += 1
    }
}
