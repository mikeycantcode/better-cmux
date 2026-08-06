import CmuxFoundation
import AppKit
import Combine
import Foundation
import QuartzCore
import SwiftUI

// MARK: - Explorer Visual Style

enum FileExplorerStyle: Int, CaseIterable {
    case liquidGlass = 0
    case highDensity = 1
    case terminalStealth = 2
    case proStudio = 3
    case finder = 4
    case vscodeIcons = 5
    case codika = 6

    var label: String {
        switch self {
        case .liquidGlass: return "Liquid Glass"
        case .highDensity: return "High-Density IDE"
        case .terminalStealth: return "Terminal Stealth"
        case .proStudio: return "Pro Studio"
        case .finder: return "Finder"
        case .vscodeIcons: return "VS Code Icons"
        case .codika: return "Codika"
        }
    }

    var rowHeight: CGFloat {
        let baseHeight: CGFloat
        switch self {
        case .liquidGlass: baseHeight = 28
        case .highDensity: baseHeight = 20
        case .terminalStealth: baseHeight = 24
        case .proStudio: baseHeight = 32
        case .finder: baseHeight = 26
        case .vscodeIcons: baseHeight = 24
        case .codika: baseHeight = 34
        }
        return GlobalFontMagnification.scaledSize(baseHeight)
    }

    var indentation: CGFloat {
        switch self {
        case .liquidGlass: return 16
        case .highDensity: return 12
        case .terminalStealth: return 14
        case .proStudio: return 20
        case .finder: return 18
        case .vscodeIcons: return 16
        case .codika: return 16
        }
    }

    var iconSize: CGFloat {
        switch self {
        case .liquidGlass: return 16
        case .highDensity: return 14
        case .terminalStealth: return 12
        case .proStudio: return 18
        case .finder: return 18
        case .vscodeIcons: return 16
        case .codika: return 16
        }
    }

    var iconWeight: NSFont.Weight {
        switch self {
        case .liquidGlass: return .regular
        case .highDensity: return .regular
        case .terminalStealth: return .light
        case .proStudio: return .regular
        case .finder: return .medium
        case .vscodeIcons: return .regular
        case .codika: return .regular
        }
    }

    var nameFont: NSFont {
        switch self {
        case .liquidGlass: return GlobalFontMagnification.systemFont(ofSize: 13, weight: .medium)
        case .highDensity: return GlobalFontMagnification.systemFont(ofSize: 11, weight: .regular)
        case .terminalStealth: return GlobalFontMagnification.monospacedSystemFont(ofSize: 12, weight: .regular)
        case .proStudio: return GlobalFontMagnification.systemFont(ofSize: 14, weight: .semibold)
        case .finder: return GlobalFontMagnification.systemFont(ofSize: 13, weight: .regular)
        case .vscodeIcons: return GlobalFontMagnification.systemFont(ofSize: 12, weight: .regular)
        case .codika: return GlobalFontMagnification.systemFont(ofSize: 13, weight: .regular)
        }
    }

    var iconToTextSpacing: CGFloat {
        switch self {
        case .liquidGlass: return 8
        case .highDensity: return 4
        case .terminalStealth: return 6
        case .proStudio: return 12
        case .finder: return 6
        case .vscodeIcons: return 6
        case .codika: return 8
        }
    }

    var selectionInset: CGFloat {
        switch self {
        case .liquidGlass: return 8
        case .highDensity: return 0
        case .terminalStealth: return 0
        case .proStudio: return 4
        case .finder: return 4
        case .vscodeIcons: return 4
        case .codika: return 6
        }
    }

    var selectionRadius: CGFloat {
        switch self {
        case .liquidGlass: return 6
        case .highDensity: return 0
        case .terminalStealth: return 0
        case .proStudio: return 8
        case .finder: return 5
        case .vscodeIcons: return 5
        case .codika: return 6
        }
    }

    var selectionColor: NSColor {
        switch self {
        case .liquidGlass: return .controlAccentColor.withAlphaComponent(0.15)
        case .highDensity: return .selectedContentBackgroundColor
        case .terminalStealth: return .controlAccentColor
        case .proStudio: return .controlAccentColor
        case .finder: return .controlAccentColor.withAlphaComponent(0.15)
        case .vscodeIcons: return .controlAccentColor.withAlphaComponent(0.15)
        case .codika: return .controlAccentColor.withAlphaComponent(0.15)
        }
    }

    var hoverColor: NSColor {
        switch self {
        case .liquidGlass: return .labelColor.withAlphaComponent(0.05)
        case .highDensity: return .white.withAlphaComponent(0.05)
        case .terminalStealth: return .white.withAlphaComponent(0.03)
        case .proStudio: return .white.withAlphaComponent(0.1)
        case .finder: return .labelColor.withAlphaComponent(0.04)
        case .vscodeIcons: return .labelColor.withAlphaComponent(0.05)
        case .codika: return .labelColor.withAlphaComponent(0.05)
        }
    }

    var usesBorderSelection: Bool {
        self == .terminalStealth || self == .vscodeIcons
    }

    var fileIconTint: NSColor {
        switch self {
        case .liquidGlass: return .secondaryLabelColor
        case .highDensity: return .secondaryLabelColor
        case .terminalStealth: return .tertiaryLabelColor
        case .proStudio: return .secondaryLabelColor
        case .finder: return NSColor(white: 0.55, alpha: 1.0)
        case .vscodeIcons: return .secondaryLabelColor
        case .codika: return .secondaryLabelColor
        }
    }

    var folderIconTint: NSColor {
        switch self {
        case .liquidGlass: return .systemBlue
        case .highDensity: return .secondaryLabelColor
        case .terminalStealth: return .tertiaryLabelColor
        case .proStudio: return .systemBlue
        case .finder: return .systemBlue
        case .vscodeIcons: return .white
        case .codika: return .secondaryLabelColor
        }
    }

    func gitColor(for status: GitFileStatus) -> NSColor {
        switch self {
        case .liquidGlass:
            switch status {
            case .modified: return .systemOrange
            case .added: return .systemTeal
            case .deleted: return .systemRed
            case .renamed: return .systemPurple
            case .untracked: return .quaternaryLabelColor
            }
        case .highDensity:
            switch status {
            case .modified: return .systemYellow
            case .added: return .systemGreen
            case .deleted: return .systemRed
            case .renamed: return .systemBlue
            case .untracked: return .tertiaryLabelColor
            }
        case .terminalStealth:
            switch status {
            case .modified: return NSColor(red: 0.8, green: 0.7, blue: 0.4, alpha: 1.0)
            case .added: return NSColor(red: 0.5, green: 0.8, blue: 0.5, alpha: 1.0)
            case .deleted: return NSColor(red: 0.8, green: 0.4, blue: 0.4, alpha: 1.0)
            case .renamed: return NSColor(red: 0.5, green: 0.7, blue: 0.9, alpha: 1.0)
            case .untracked: return NSColor(white: 0.5, alpha: 1.0)
            }
        case .proStudio:
            switch status {
            case .modified: return .systemYellow
            case .added: return .systemGreen
            case .deleted: return .systemPink
            case .renamed: return .systemCyan
            case .untracked: return .systemGray
            }
        case .finder:
            switch status {
            case .modified: return .systemOrange
            case .added: return .systemGreen
            case .deleted: return .systemRed
            case .renamed: return .systemBlue
            case .untracked: return .tertiaryLabelColor
            }
        case .vscodeIcons, .codika:
            switch status {
            case .modified: return .systemYellow
            case .added: return .systemGreen
            case .deleted: return .systemRed
            case .renamed: return .systemBlue
            case .untracked: return .tertiaryLabelColor
            }
        }
    }

    static var current: FileExplorerStyle {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "fileExplorer.style") == nil {
            return .codika
        }
        return FileExplorerStyle(rawValue: defaults.integer(forKey: "fileExplorer.style")) ?? .codika
    }
}

// MARK: - Models

struct FileExplorerEntry: Sendable {
    let name: String
    let path: String
    let isDirectory: Bool
}

final class FileExplorerNode: Identifiable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    var children: [FileExplorerNode]?
    var isLoading: Bool = false
    var error: String?

    init(name: String, path: String, isDirectory: Bool) {
        self.id = path
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
    }

    var isExpandable: Bool { isDirectory }

    var sortedChildren: [FileExplorerNode]? {
        children?.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }
}

// MARK: - Root Resolver

enum FileExplorerRootResolver {
    static func displayPath(for fullPath: String, homePath: String?) -> String {
        guard let home = homePath, !home.isEmpty else { return fullPath }
        let normalizedHome = home.hasSuffix("/") ? String(home.dropLast()) : home
        let normalizedPath = fullPath.hasSuffix("/") ? String(fullPath.dropLast()) : fullPath
        if normalizedPath == normalizedHome {
            return "~"
        }
        let homePrefix = normalizedHome + "/"
        if normalizedPath.hasPrefix(homePrefix) {
            return "~/" + normalizedPath.dropFirst(homePrefix.count)
        }
        return fullPath
    }
}

// MARK: - Provider Protocol

protocol FileExplorerProvider: AnyObject {
    func listDirectory(path: String, showHidden: Bool) async throws -> [FileExplorerEntry]
    var homePath: String { get }
    var isAvailable: Bool { get }
}

enum FileExplorerWorkspaceRoot: Equatable {
    case none
    case local(workspaceId: UUID, path: String)
}

// MARK: - Local Provider

final class LocalFileExplorerProvider: FileExplorerProvider {
    var homePath: String { NSHomeDirectory() }
    var isAvailable: Bool { true }

    func listDirectory(path: String, showHidden: Bool) async throws -> [FileExplorerEntry] {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(atPath: path)
        return contents.compactMap { name in
            guard showHidden || !name.hasPrefix(".") else { return nil }
            let fullPath = (path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { return nil }
            return FileExplorerEntry(name: name, path: fullPath, isDirectory: isDir.boolValue)
        }
    }
}

enum FileExplorerError: LocalizedError {
    case providerUnavailable

    var errorDescription: String? {
        switch self {
        case .providerUnavailable:
            return String(localized: "fileExplorer.error.unavailable", defaultValue: "File explorer is not available")
        }
    }
}

// MARK: - Selection Restoration

enum FileExplorerSelectionRestoration {
    static func scrollRow(anchorRow: Int?, exactRows: IndexSet) -> Int? {
        if let anchorRow, exactRows.contains(anchorRow) {
            return anchorRow
        }
        return exactRows.first
    }
}

// MARK: - Store

/// All access must happen on the main thread. Properties are not marked @MainActor
/// because NSOutlineView data source/delegate methods are called on the main thread
/// but are not annotated @MainActor.
final class FileExplorerStore: ObservableObject {
    @Published var rootPath: String = ""
    @Published var rootNodes: [FileExplorerNode] = []
    @Published private(set) var isRootLoading: Bool = false
    @Published private(set) var gitStatusByPath: [String: GitFileStatus] = [:]
    /// Absolute paths that git reports as ignored. Populated lazily as directories load.
    @Published private(set) var ignoredPaths: Set<String> = []
    @Published private(set) var contentRevision = 0
    @Published private(set) var rootStatusMessage: String?
    /// In-tree filter text. When non-empty the outline shows only matching entries
    /// (and the ancestors that lead to them).
    @Published var filterText: String = "" {
        didSet {
            guard oldValue != filterText else { return }
            scheduleFilterRecompute()
        }
    }
    /// Bumped whenever the filter result set changes so the outline can do a full reload.
    @Published private(set) var filterRevision = 0
    /// path -> whether the node (or any loaded descendant) matches `filterText`.
    private var filterSubtreeMatch: [String: Bool] = [:]
    /// Coalesces keystrokes: one recompute + outline reload per typing burst.
    private var filterRecomputeWorkItem: DispatchWorkItem?
    static let filterRecomputeDebounceSeconds: TimeInterval = 0.15
    private(set) var workspaceRootIdentity: UUID?

    var provider: FileExplorerProvider?

    /// Whether hidden files are shown. Set from FileExplorerState externally.
    var showHiddenFiles: Bool = false

    /// Watches the root directory for filesystem changes (local only).
    private var directoryWatcher: FileWatcher?
    private var directoryWatchTask: Task<Void, Never>?
    private var directoryWatchPath: String?

    /// Paths that are logically expanded (persisted across provider changes)
    private(set) var expandedPaths: Set<String> = []

    /// Stable navigation selection. The outline view mirrors this path after reloads.
    private(set) var selectedPath: String?

    /// Stable multi-selection. `selectedPath` remains the keyboard/navigation anchor.
    private(set) var selectedPaths: Set<String> = []

    /// Folder path whose first child should be selected once its async load completes.
    private var pendingDescendIntoFirstChildPath: String?

    /// Paths currently being loaded
    private(set) var loadingPaths: Set<String> = []

    /// In-flight load tasks keyed by path
    private var loadTasks: [String: Task<Void, Never>] = [:]

    /// Cache of path -> node for quick lookup
    private var nodesByPath: [String: FileExplorerNode] = [:]

    /// Prefetch debounce: path -> work item
    private var prefetchWorkItems: [String: DispatchWorkItem] = [:]

    var displayRootPath: String {
        FileExplorerRootResolver.displayPath(for: rootPath, homePath: provider?.homePath)
    }

    // MARK: - Public API

    func applyWorkspaceRoot(_ request: FileExplorerWorkspaceRoot) {
        switch request {
        case .none:
            setRootStatusMessage(nil); setWorkspaceRootIdentity(nil)
            if provider != nil { setProvider(nil, reloadIfAvailable: false) }
            setRootPath("")
        case .local(let workspaceId, let path):
            setRootStatusMessage(nil); setWorkspaceRootIdentity(workspaceId)
            if !(provider is LocalFileExplorerProvider) {
                setRootPath("")
                setProvider(LocalFileExplorerProvider(), reloadIfAvailable: false)
            }
            setRootPath(path)
        }
    }
    private func setWorkspaceRootIdentity(_ identity: UUID?) { guard workspaceRootIdentity != identity else { return }; objectWillChange.send(); workspaceRootIdentity = identity }

    func setRootPath(_ path: String) {
        guard path != rootPath else {
            #if DEBUG
            NSLog("[FileExplorer] setRootPath skipped (same path): \(path)")
            #endif
            return
        }
        #if DEBUG
        NSLog("[FileExplorer] setRootPath: \(rootPath) -> \(path)")
        #endif
        if let selectedPath, !Self.path(selectedPath, isContainedIn: path) {
            self.selectedPath = nil
            selectedPaths = []
            pendingDescendIntoFirstChildPath = nil
        }
        rootPath = path
        ignoredPaths = []
        reload()
        refreshGitStatus()
        updateDirectoryWatcher()
    }

    func isIgnored(_ path: String) -> Bool { ignoredPaths.contains(path) }

    // MARK: - Filter

    /// True when `name` fuzzily matches `filter` (case-insensitive subsequence).
    static func nameMatchesFilter(_ name: String, filter: String) -> Bool {
        guard !filter.isEmpty else { return true }
        var remainder = filter.lowercased()[...]
        for ch in name.lowercased() {
            if let first = remainder.first, first == ch { remainder = remainder.dropFirst() }
            if remainder.isEmpty { return true }
        }
        return remainder.isEmpty
    }

    /// Debounces the (potentially tree-wide) recompute so a burst of keystrokes triggers
    /// one cache rebuild and one outline reload instead of one per character.
    private func scheduleFilterRecompute() {
        filterRecomputeWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.filterRecomputeWorkItem = nil
            self.applyFilterRecompute()
        }
        filterRecomputeWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.filterRecomputeDebounceSeconds,
            execute: workItem
        )
    }

    private func applyFilterRecompute() {
        recomputeFilterMatches()
        filterRevision &+= 1
    }

    /// Applies any pending debounced filter recompute immediately.
    func flushPendingFilterRecompute() {
        guard let workItem = filterRecomputeWorkItem else { return }
        workItem.cancel()
        filterRecomputeWorkItem = nil
        applyFilterRecompute()
    }

    /// Recomputes the per-path match cache for the currently loaded tree.
    /// Never call from a view body or an outline data-source callback.
    private func recomputeFilterMatches() {
        filterSubtreeMatch = [:]
        guard !filterText.isEmpty else { return }
        for node in rootNodes { _ = computeFilterMatch(node) }
    }

    @discardableResult
    private func computeFilterMatch(_ node: FileExplorerNode) -> Bool {
        var matches = Self.nameMatchesFilter(node.name, filter: filterText)
        if let children = node.children {
            for child in children where computeFilterMatch(child) { matches = true }
        }
        filterSubtreeMatch[node.path] = matches
        return matches
    }

    /// A directory whose children were never loaded can't be searched, so it stays visible
    /// while filtering — otherwise the filter would delete the only path to its own matches.
    private static func isUnexploredDirectory(_ node: FileExplorerNode) -> Bool {
        node.isDirectory && node.children == nil
    }

    /// Children of `node` (or the roots when nil) that survive the current filter.
    func visibleChildren(of node: FileExplorerNode?) -> [FileExplorerNode] {
        let children: [FileExplorerNode]
        if let node {
            children = node.sortedChildren ?? []
        } else {
            children = rootNodes
        }
        guard !filterText.isEmpty else { return children }
        return children.filter { filterSubtreeMatch[$0.path] == true || Self.isUnexploredDirectory($0) }
    }

    /// True when a filter is active and `node`'s subtree contains a match (so it should auto-expand).
    func subtreeContainsFilterMatch(_ node: FileExplorerNode) -> Bool {
        guard !filterText.isEmpty, node.isDirectory else { return false }
        return filterSubtreeMatch[node.path] == true
    }

    func refreshGitStatus() {
        guard !rootPath.isEmpty else {
            gitStatusByPath = [:]
            ignoredPaths = []
            return
        }
        let path = rootPath
        DispatchQueue.global(qos: .utility).async {
            let status = GitStatusProvider.fetchStatus(directory: path)
            DispatchQueue.main.async { [weak self] in
                self?.gitStatusByPath = status
            }
        }
    }

    /// Serializes `git check-ignore` batches: directory loads (especially expanded-state
    /// restore) can fan out to many directories at once, and each batch blocks its thread
    /// on a subprocess. One queue means at most one git process at a time.
    private static let ignoreCheckQueue = DispatchQueue(
        label: "com.cmux.file-explorer.check-ignore",
        qos: .utility
    )

    /// Batches a `git check-ignore` query for freshly loaded children and folds the
    /// ignored subset into `ignoredPaths` on the main thread.
    private func refreshIgnoredStatus(forChildPaths paths: [String]) {
        guard provider is LocalFileExplorerProvider, !paths.isEmpty, !rootPath.isEmpty else { return }
        let root = rootPath
        Self.ignoreCheckQueue.async {
            let ignored = Self.checkIgnored(paths: paths, repoRoot: root)
            guard !ignored.isEmpty else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.rootPath == root else { return }
                self.ignoredPaths.formUnion(ignored)
            }
        }
    }

    /// Feeds paths to `git check-ignore --stdin -z`; returns the subset git reports ignored.
    ///
    /// Paths are sent relative to the symlink-resolved repo root. git resolves its worktree
    /// through symlinks, so an absolute path under an unresolved root (e.g. `/tmp/...` when
    /// the worktree resolves to `/private/tmp/...`) is rejected as "outside repository"
    /// (exit 128) and every entry would silently read as not-ignored.
    private static func checkIgnored(paths: [String], repoRoot: String) -> Set<String> {
        let resolvedRoot = URL(fileURLWithPath: repoRoot).resolvingSymlinksInPath().path
        // relative path -> the original absolute path the caller asked about
        var byRelative: [String: String] = [:]
        for path in paths {
            guard let relative = relativePath(for: path, root: repoRoot, resolvedRoot: resolvedRoot) else { continue }
            byRelative[relative] = path
        }
        guard !byRelative.isEmpty else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.currentDirectoryURL = URL(fileURLWithPath: resolvedRoot)
        process.arguments = ["check-ignore", "--stdin", "-z"]
        let stdin = Pipe(), stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return [] }
        let payload = byRelative.keys.joined(separator: "\0") + "\0"
        stdin.fileHandleForWriting.write(payload.data(using: .utf8) ?? Data())
        try? stdin.fileHandleForWriting.close()
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        // exit 0 = some ignored, 1 = none ignored, anything else = failure
        guard process.terminationStatus == 0 else {
            #if DEBUG
            if process.terminationStatus > 1 {
                NSLog("[FileExplorer] git check-ignore failed (exit \(process.terminationStatus)) in \(resolvedRoot)")
            }
            #endif
            return []
        }
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\0").compactMap { byRelative[String($0)] })
    }

    /// Path relative to the repo root, matching against both the raw and the
    /// symlink-resolved root so either spelling of the path works.
    private static func relativePath(for path: String, root: String, resolvedRoot: String) -> String? {
        for base in [root, resolvedRoot] where !base.isEmpty {
            let prefix = base.hasSuffix("/") ? base : base + "/"
            if path.hasPrefix(prefix) {
                let relative = String(path.dropFirst(prefix.count))
                if !relative.isEmpty { return relative }
            }
        }
        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        guard resolvedPath != path else { return nil }
        return relativePath(for: resolvedPath, root: root, resolvedRoot: resolvedRoot)
    }

    private func updateDirectoryWatcher() {
        if provider is LocalFileExplorerProvider, !rootPath.isEmpty {
            guard directoryWatchPath != rootPath || directoryWatcher == nil else { return }
            stopDirectoryWatcher()
            // Preserve the previous 0.3s coalescing as a leading-edge throttle.
            let watcher = FileWatcher(path: rootPath, throttle: .milliseconds(300))
            directoryWatcher = watcher
            directoryWatchPath = rootPath
            let events = watcher.events
            directoryWatchTask = Task { @MainActor [weak self] in
                for await _ in events {
                    guard let self else { break }
                    self.reload()
                    self.refreshGitStatus()
                }
            }
        } else {
            stopDirectoryWatcher()
        }
    }

    /// Cancels the directory-watch consumer and drops the watcher; the watcher's
    /// deinit cancels its `DispatchSource`s synchronously.
    private func stopDirectoryWatcher() {
        directoryWatchTask?.cancel()
        directoryWatchTask = nil
        directoryWatcher = nil
        directoryWatchPath = nil
    }

    private func setProvider(_ newProvider: FileExplorerProvider?, reloadIfAvailable: Bool = true) {
        #if DEBUG
        NSLog("[FileExplorer] setProvider: \(type(of: newProvider).self) available=\(newProvider?.isAvailable ?? false)")
        #endif
        provider = newProvider
        // Re-expand previously expanded nodes if provider becomes available
        if reloadIfAvailable, newProvider?.isAvailable == true {
            reload()
        }
    }

    #if DEBUG
    func setProviderForTesting(_ newProvider: FileExplorerProvider?, reloadIfAvailable: Bool = true) {
        setProvider(newProvider, reloadIfAvailable: reloadIfAvailable)
    }
    #endif

    func reload() {
        #if DEBUG
        NSLog("[FileExplorer] reload() path=\(rootPath) provider=\(type(of: provider).self)")
        #endif
        contentRevision &+= 1
        cancelAllLoads()
        rootNodes = []
        nodesByPath = [:]
        guard !rootPath.isEmpty, provider != nil else { return }
        isRootLoading = true
        let path = rootPath
        let task = Task { [weak self] in
            guard let self else { return }
            await self.loadChildren(for: nil, at: path)
        }
        loadTasks[rootPath] = task
    }

    func expand(node: FileExplorerNode) {
        guard node.isDirectory else { return }
        expandedPaths.insert(node.path)
        if node.children == nil, loadTasks[node.path] == nil, !loadingPaths.contains(node.path) {
            node.isLoading = true
            node.error = nil
            objectWillChange.send()
            let nodePath = node.path
            let task = Task { [weak self] in
                guard let self else { return }
                await self.loadChildren(for: node, at: nodePath)
            }
            loadTasks[node.path] = task
        }
    }

    func collapse(node: FileExplorerNode) {
        expandedPaths.remove(node.path)
        if pendingDescendIntoFirstChildPath == node.path {
            pendingDescendIntoFirstChildPath = nil
        }
        objectWillChange.send()
    }

    func isExpanded(_ node: FileExplorerNode) -> Bool {
        expandedPaths.contains(node.path)
    }

    func select(node: FileExplorerNode?) {
        let path = node?.path
        let paths = path.map { Set([$0]) } ?? []
        guard selectedPath != path || selectedPaths != paths else { return }
        selectedPath = path
        selectedPaths = paths
        if path != pendingDescendIntoFirstChildPath {
            pendingDescendIntoFirstChildPath = nil
        }
    }

    func select(nodes: [FileExplorerNode], anchor: FileExplorerNode?) {
        let paths = Set(nodes.map(\.path))
        let path = anchor?.path ?? nodes.first?.path
        guard selectedPath != path || selectedPaths != paths else { return }
        selectedPath = path
        selectedPaths = paths
        if path != pendingDescendIntoFirstChildPath {
            pendingDescendIntoFirstChildPath = nil
        }
    }

    func requestDescendIntoFirstChild(of node: FileExplorerNode) {
        guard node.isDirectory else { return }
        selectedPath = node.path
        selectedPaths = [node.path]
        pendingDescendIntoFirstChildPath = node.path
        expand(node: node)
    }

    func prefetchChildren(for node: FileExplorerNode) {
        guard node.isDirectory, node.children == nil, !loadingPaths.contains(node.path) else { return }
        // Debounce: only prefetch if hover persists for 200ms
        let path = node.path
        prefetchWorkItems[path]?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, node.children == nil, !self.loadingPaths.contains(path) else { return }
                // Silent prefetch: don't show loading indicator
                await self.loadChildren(for: node, at: path, silent: true)
            }
        }
        prefetchWorkItems[path] = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    func cancelPrefetch(for node: FileExplorerNode) {
        prefetchWorkItems[node.path]?.cancel()
        prefetchWorkItems.removeValue(forKey: node.path)
    }

    /// Re-hydrates expanded nodes that were waiting for the provider to become available.
    func hydrateExpandedNodes() {
        guard let provider, provider.isAvailable, !expandedPaths.isEmpty else { return }
        #if DEBUG
        NSLog("[FileExplorer] hydrateExpandedNodes: \(expandedPaths.count) paths to hydrate")
        #endif
        reload()
    }

    // MARK: - Private

    @MainActor
    private func loadChildren(for parentNode: FileExplorerNode?, at path: String, silent: Bool = false) async {
        guard let provider else { return }

        if !silent {
            loadingPaths.insert(path)
            parentNode?.error = nil
            objectWillChange.send()
        }

        do {
            let entries = try await provider.listDirectory(path: path, showHidden: showHiddenFiles)
            try Task.checkCancellation()
            let children = entries.map { entry in
                let node = FileExplorerNode(name: entry.name, path: entry.path, isDirectory: entry.isDirectory)
                nodesByPath[entry.path] = node
                return node
            }.sorted { a, b in
                if a.isDirectory != b.isDirectory { return a.isDirectory }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }

            if let parentNode {
                parentNode.children = children
                parentNode.isLoading = false
                parentNode.error = nil
                if pendingDescendIntoFirstChildPath == parentNode.path {
                    let path = children.first?.path ?? parentNode.path
                    selectedPath = path
                    selectedPaths = [path]
                    pendingDescendIntoFirstChildPath = nil
                }
            } else {
                rootNodes = children
                isRootLoading = false
                setRootStatusMessage(nil)
                if selectedPath == nil {
                    selectedPath = children.first?.path
                    selectedPaths = selectedPath.map { Set([$0]) } ?? []
                }
            }
            loadingPaths.remove(path)
            loadTasks.removeValue(forKey: path)
            if !filterText.isEmpty {
                recomputeFilterMatches()
                filterRevision &+= 1
            }
            objectWillChange.send()

            refreshIgnoredStatus(forChildPaths: children.map(\.path))

            // Auto-expand children that were previously expanded
            for child in children where child.isDirectory && expandedPaths.contains(child.path) {
                child.isLoading = true
                objectWillChange.send()
                let childPath = child.path
                let childTask = Task { [weak self] in
                    guard let self else { return }
                    await self.loadChildren(for: child, at: childPath)
                }
                loadTasks[child.path] = childTask
            }
        } catch {
            if !Task.isCancelled {
                if let parentNode {
                    parentNode.isLoading = false
                    parentNode.error = error.localizedDescription
                } else {
                    isRootLoading = false
                    setRootStatusMessage(error.localizedDescription)
                }
                loadingPaths.remove(path)
                loadTasks.removeValue(forKey: path)
                objectWillChange.send()
            }
        }
    }

    private func cancelAllLoads() {
        for (_, task) in loadTasks {
            task.cancel()
        }
        loadTasks.removeAll()
        loadingPaths.removeAll()
        pendingDescendIntoFirstChildPath = nil
        for (_, item) in prefetchWorkItems {
            item.cancel()
        }
        prefetchWorkItems.removeAll()
        isRootLoading = false
    }

    private func setRootStatusMessage(_ message: String?) {
        guard rootStatusMessage != message else { return }
        rootStatusMessage = message
    }

    private static func path(_ candidate: String, isContainedIn root: String) -> Bool {
        guard !root.isEmpty else { return false }
        if root == "/" {
            return candidate.hasPrefix("/")
        }
        return candidate == root || candidate.hasPrefix(root + "/")
    }

    private static func normalizedRootPath(_ path: String?) -> String? {
        guard let path else { return nil }
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
    }

    deinit {
        directoryWatchTask?.cancel()
    }
}

// MARK: - Git Status

enum GitFileStatus {
    case modified, added, deleted, renamed, untracked
}

/// Runs `git status --porcelain` and parses results into a path-to-status map.
enum GitStatusProvider {

    static func fetchStatus(directory: String) -> [String: GitFileStatus] {
        guard let repoRoot = gitRepoRoot(for: directory) else { return [:] }
        return parseGitStatus(
            output: runGit(in: repoRoot, arguments: ["status", "--porcelain"]),
            repoRoot: repoRoot,
            explorerRoot: directory
        )
    }

    private static func parseGitStatus(
        output: String?, repoRoot: String, explorerRoot: String
    ) -> [String: GitFileStatus] {
        guard let output, !output.isEmpty else { return [:] }
        var statusMap: [String: GitFileStatus] = [:]

        for line in output.components(separatedBy: "\n") where line.count >= 4 {
            let indexStatus = line[line.startIndex]
            let workTreeStatus = line[line.index(after: line.startIndex)]
            var path = String(line.dropFirst(3))
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: "\"", with: "")

            if path.contains(" -> ") {
                path = String(path.split(separator: " -> ").last ?? Substring(path))
            }

            guard let status = parseStatusChars(index: indexStatus, workTree: workTreeStatus) else { continue }

            let absolutePath = repoRoot.hasSuffix("/") ? repoRoot + path : repoRoot + "/" + path
            guard absolutePath.hasPrefix(explorerRoot) else { continue }

            statusMap[absolutePath] = status
            markParentDirectories(absolutePath: absolutePath, explorerRoot: explorerRoot, status: status, in: &statusMap)
        }
        return statusMap
    }

    private static func parseStatusChars(index: Character, workTree: Character) -> GitFileStatus? {
        if index == "?" && workTree == "?" { return .untracked }
        if index == "A" || workTree == "A" { return .added }
        if index == "D" || workTree == "D" { return .deleted }
        if index == "R" || workTree == "R" { return .renamed }
        if index == "M" || workTree == "M" { return .modified }
        return nil
    }

    private static func markParentDirectories(
        absolutePath: String, explorerRoot: String,
        status: GitFileStatus, in map: inout [String: GitFileStatus]
    ) {
        let dirStatus: GitFileStatus = (status == .untracked) ? .untracked : .modified
        var current = (absolutePath as NSString).deletingLastPathComponent
        while current.hasPrefix(explorerRoot) && current != explorerRoot {
            if map[current] == nil {
                map[current] = dirStatus
            }
            current = (current as NSString).deletingLastPathComponent
        }
    }

    private static func gitRepoRoot(for directory: String) -> String? {
        runGit(in: directory, arguments: ["rev-parse", "--show-toplevel"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func runGit(in directory: String, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: directory)
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFileOrEmpty()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }

}
