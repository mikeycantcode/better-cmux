import AppKit
import CmuxFoundation
import SwiftUI

/// The actions the explorer section header exposes. One bundle, wired identically
/// by every surface that mounts the header (right sidebar and left sidebar).
struct FileExplorerHeaderActions {
    var newFile: () -> Void
    var newFolder: () -> Void
    var refresh: () -> Void
    var collapseAll: () -> Void
    /// Toggles the section open/closed. `nil` renders a static (non-interactive) chevron.
    var toggleSection: (() -> Void)?

    init(
        newFile: @escaping () -> Void,
        newFolder: @escaping () -> Void,
        refresh: @escaping () -> Void,
        collapseAll: @escaping () -> Void,
        toggleSection: (() -> Void)? = nil
    ) {
        self.newFile = newFile
        self.newFolder = newFolder
        self.refresh = refresh
        self.collapseAll = collapseAll
        self.toggleSection = toggleSection
    }
}

/// VS Code-style explorer section header: leading chevron, uppercased root folder
/// name, and four trailing icon buttons that fade in while the header is hovered.
final class FileExplorerHeaderView: NSView {
    /// VS Code's explorer section header row height.
    static let rowHeight: CGFloat = 22

    private let chevronView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let newFileButton = NSButton()
    private let newFolderButton = NSButton()
    private let refreshButton = NSButton()
    private let collapseAllButton = NSButton()
    private var heightConstraint: NSLayoutConstraint?
    private var displayPath = ""
    private var quickSearchQuery: String?
    private var isSectionExpanded = true
    private var isHovering = false
    private var trackingArea: NSTrackingArea?
    /// Keeps the row height and label font tracking magnification changes on their
    /// own, so the header is correct wherever it is mounted (the right sidebar's
    /// container also drives `applyFonts()`; the call is idempotent).
    private var fontMagnificationObserver: GlobalFontMagnificationChangeObserver?

    /// Set by the mounting surface. Buttons no-op until this is assigned.
    var actions: FileExplorerHeaderActions?

    private var actionButtons: [NSButton] {
        [newFileButton, newFolderButton, refreshButton, collapseAllButton]
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        chevronView.translatesAutoresizingMaskIntoConstraints = false
        chevronView.contentTintColor = .secondaryLabelColor

        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        addSubview(chevronView)
        addSubview(titleLabel)

        configureActionButton(
            newFileButton,
            symbolName: "doc.badge.plus",
            tooltip: String(localized: "fileExplorer.header.newFile", defaultValue: "New File"),
            action: #selector(newFileClicked(_:))
        )
        configureActionButton(
            newFolderButton,
            symbolName: "folder.badge.plus",
            tooltip: String(localized: "fileExplorer.header.newFolder", defaultValue: "New Folder"),
            action: #selector(newFolderClicked(_:))
        )
        configureActionButton(
            refreshButton,
            symbolName: "arrow.clockwise",
            tooltip: String(localized: "fileExplorer.header.refresh", defaultValue: "Refresh Explorer"),
            action: #selector(refreshClicked(_:))
        )
        configureActionButton(
            collapseAllButton,
            symbolName: "rectangle.compress.vertical",
            tooltip: String(localized: "fileExplorer.header.collapseAll", defaultValue: "Collapse Folders in Explorer"),
            action: #selector(collapseAllClicked(_:))
        )

        let heightConstraint = heightAnchor.constraint(
            equalToConstant: GlobalFontMagnification.scaledSize(Self.rowHeight)
        )
        self.heightConstraint = heightConstraint

        var constraints: [NSLayoutConstraint] = [
            heightConstraint,

            chevronView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            chevronView.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronView.widthAnchor.constraint(equalToConstant: 12),
            chevronView.heightAnchor.constraint(equalToConstant: 12),

            titleLabel.leadingAnchor.constraint(equalTo: chevronView.trailingAnchor, constant: 4),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ]

        var previous: NSView?
        for button in actionButtons.reversed() {
            let trailing = previous.map { button.trailingAnchor.constraint(equalTo: $0.leadingAnchor, constant: -2) }
                ?? button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8)
            constraints += [
                trailing,
                button.centerYAnchor.constraint(equalTo: centerYAnchor),
                button.widthAnchor.constraint(equalToConstant: 20),
                button.heightAnchor.constraint(equalToConstant: 20),
            ]
            previous = button
        }
        if let leadingMostButton = previous {
            constraints.append(
                titleLabel.trailingAnchor.constraint(
                    lessThanOrEqualTo: leadingMostButton.leadingAnchor,
                    constant: -6
                )
            )
        }

        NSLayoutConstraint.activate(constraints)
        fontMagnificationObserver = GlobalFontMagnificationChangeObserver { [weak self] in
            self?.applyFonts()
        }
        applyFonts()
        applyHoverState()
        applyHeaderState()
    }

    private func configureActionButton(
        _ button: NSButton,
        symbolName: String,
        tooltip: String,
        action: Selector
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
        button.contentTintColor = .secondaryLabelColor
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.setAccessibilityLabel(tooltip)
        addSubview(button)
    }

    // MARK: - Public API

    func applyFonts() {
        titleLabel.font = GlobalFontMagnification.systemFont(ofSize: 11, weight: .semibold)
        heightConstraint?.constant = GlobalFontMagnification.scaledSize(Self.rowHeight)
    }

    func update(displayPath: String) {
        guard self.displayPath != displayPath else { return }
        self.displayPath = displayPath
        applyHeaderState()
    }

    func updateQuickSearch(query: String?) {
        guard quickSearchQuery != query else { return }
        quickSearchQuery = query
        applyHeaderState()
    }

    /// Flips the leading chevron. Only meaningful when `actions.toggleSection` exists.
    func updateSectionExpanded(_ expanded: Bool) {
        guard isSectionExpanded != expanded else { return }
        isSectionExpanded = expanded
        applyHeaderState()
    }

    // MARK: - Rendering

    private func applyHeaderState() {
        assert(Thread.isMainThread, "AppKit image updates must run on the main thread")
        let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        if let quickSearchQuery {
            chevronView.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
                .withSymbolConfiguration(config)
            titleLabel.stringValue = "/" + quickSearchQuery
            titleLabel.toolTip = titleLabel.stringValue
        } else {
            chevronView.image = NSImage(
                systemSymbolName: FileExplorerStyle.chevronSymbolName(expanded: isSectionExpanded),
                accessibilityDescription: nil
            )?.withSymbolConfiguration(config)
            titleLabel.stringValue = Self.sectionTitle(forDisplayPath: displayPath)
            titleLabel.toolTip = displayPath.isEmpty ? nil : displayPath
        }
    }

    /// VS Code shows the workspace root's own folder name, uppercased.
    static func sectionTitle(forDisplayPath displayPath: String) -> String {
        let trimmed = displayPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (trimmed as NSString).lastPathComponent
        guard !name.isEmpty, name != "/" else {
            return String(localized: "sidebar.fileExplorer.title", defaultValue: "Explorer").uppercased()
        }
        return name.uppercased()
    }

    // MARK: - Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        applyHoverState()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        applyHoverState()
    }

    /// Reveal is purely visual: the buttons stay enabled so VoiceOver and
    /// full-keyboard-access users (who never generate `mouseEntered`) can still
    /// reach them, and a lagging tracking update can't swallow the first click.
    private func applyHoverState() {
        let alpha: CGFloat = isHovering ? 1 : 0
        for button in actionButtons {
            button.alphaValue = alpha
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard let toggleSection = actions?.toggleSection else {
            super.mouseDown(with: event)
            return
        }
        toggleSection()
    }

    // MARK: - Actions

    @objc private func newFileClicked(_ sender: Any?) { actions?.newFile() }
    @objc private func newFolderClicked(_ sender: Any?) { actions?.newFolder() }
    @objc private func refreshClicked(_ sender: Any?) { actions?.refresh() }
    @objc private func collapseAllClicked(_ sender: Any?) { actions?.collapseAll() }
}

// MARK: - SwiftUI host

/// Hosts the shared AppKit section header inside SwiftUI (left sidebar), so both
/// explorers render and wire the exact same header.
struct FileExplorerSectionHeader: NSViewRepresentable {
    @ObservedObject var store: FileExplorerStore
    let isExpanded: Bool
    let onToggle: () -> Void

    /// Holds the store the mounted view's action bundle is bound to, so the bundle
    /// is rebuilt only when the store instance changes rather than on every update.
    final class Coordinator {
        weak var actionsStore: FileExplorerStore?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> FileExplorerHeaderView {
        let view = FileExplorerHeaderView()
        apply(to: view, context: context)
        return view
    }

    func updateNSView(_ nsView: FileExplorerHeaderView, context: Context) {
        apply(to: nsView, context: context)
    }

    private func apply(to view: FileExplorerHeaderView, context: Context) {
        if context.coordinator.actionsStore !== store {
            context.coordinator.actionsStore = store
            view.actions = FileExplorerHeaderActionRunner.actions(for: store, toggleSection: onToggle)
        }
        view.update(displayPath: store.displayRootPath)
        view.updateSectionExpanded(isExpanded)
    }
}

// MARK: - Shared header action implementations

/// The one implementation of the header's create/refresh/collapse behavior, shared by
/// every surface that mounts ``FileExplorerHeaderView``.
@MainActor
enum FileExplorerHeaderActionRunner {
    static func actions(for store: FileExplorerStore, toggleSection: (() -> Void)? = nil)
        -> FileExplorerHeaderActions
    {
        FileExplorerHeaderActions(
            newFile: { [weak store] in guard let store else { return }; create(isDirectory: false, in: store) },
            newFolder: { [weak store] in guard let store else { return }; create(isDirectory: true, in: store) },
            refresh: { [weak store] in
                guard let store else { return }
                store.reload()
                store.refreshGitStatus()
            },
            collapseAll: { [weak store] in store?.requestCollapseAll() },
            toggleSection: toggleSection
        )
    }

    static func create(isDirectory: Bool, in store: FileExplorerStore) {
        guard let directory = store.createTargetDirectory() else { return }
        guard let name = promptForName(isDirectory: isDirectory, in: directory) else { return }
        let result = isDirectory
            ? store.createFolder(named: name, inDirectory: directory)
            : store.createFile(named: name, inDirectory: directory)
        switch result {
        case .success(let path):
            store.reload()
            store.revealAndSelect(path: path)
        case .failure(let error):
            presentError(error)
        }
    }

    private static func promptForName(isDirectory: Bool, in directory: String) -> String? {
        let alert = NSAlert()
        alert.messageText = isDirectory
            ? String(localized: "fileExplorer.create.folder.title", defaultValue: "New Folder")
            : String(localized: "fileExplorer.create.file.title", defaultValue: "New File")
        let folderName = (directory as NSString).lastPathComponent
        alert.informativeText = isDirectory
            ? String(
                localized: "fileExplorer.create.folder.message",
                defaultValue: "Enter a name for the new folder in “\(folderName)”."
            )
            : String(
                localized: "fileExplorer.create.file.message",
                defaultValue: "Enter a name for the new file in “\(folderName)”."
            )
        let input = NSTextField(string: "")
        input.placeholderString = isDirectory
            ? String(localized: "fileExplorer.create.folder.placeholder", defaultValue: "Folder name")
            : String(localized: "fileExplorer.create.file.placeholder", defaultValue: "File name")
        input.frame = NSRect(x: 0, y: 0, width: 240, height: 22)
        alert.accessoryView = input
        alert.addButton(withTitle: String(localized: "fileExplorer.create.confirm", defaultValue: "Create"))
        alert.addButton(withTitle: String(localized: "fileExplorer.create.cancel", defaultValue: "Cancel"))
        let alertWindow = alert.window
        alertWindow.initialFirstResponder = input
        DispatchQueue.main.async {
            alertWindow.makeFirstResponder(input)
            input.selectText(nil)
        }
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return input.stringValue
    }

    private static func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(
            localized: "fileExplorer.create.error.title",
            defaultValue: "Could not create item"
        )
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: String(localized: "fileExplorer.create.error.dismiss", defaultValue: "OK"))
        alert.runModal()
    }
}
