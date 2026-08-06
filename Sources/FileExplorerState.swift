import AppKit
import SwiftUI

// MARK: - State (visibility toggle)

final class FileExplorerState: ObservableObject {
    /// Prefix for this instance's UserDefaults keys. The right sidebar uses the
    /// default ("fileExplorer"); the left-sidebar explorer passes a distinct
    /// prefix so the two instances never clobber each other's persisted state.
    let persistenceKeyPrefix: String
    private let legacyModeKey: String
    private static let customSidebarNameKey = "rightSidebar.customSidebarName"

    private func key(_ suffix: String) -> String { "\(persistenceKeyPrefix).\(suffix)" }

    @Published var isVisible: Bool {
        didSet { UserDefaults.standard.set(isVisible, forKey: key("isVisible")) }
    }
    @Published var width: CGFloat {
        didSet { UserDefaults.standard.set(Double(width), forKey: key("width")) }
    }

    /// Proportion of sidebar height allocated to the tab list (0.0-1.0).
    /// The file explorer gets the remaining space below.
    @Published var dividerPosition: CGFloat {
        didSet { UserDefaults.standard.set(Double(dividerPosition), forKey: key("dividerPosition")) }
    }

    /// Whether hidden files (dotfiles) are shown in the tree.
    @Published var showHiddenFiles: Bool {
        didSet { UserDefaults.standard.set(showHiddenFiles, forKey: key("showHidden")) }
    }

    @Published private var storedCustomSidebarName: String?

    var customSidebarName: String? {
        storedCustomSidebarName
    }

    init(persistenceKeyPrefix: String = "fileExplorer", defaultVisible: Bool = false) {
        self.persistenceKeyPrefix = persistenceKeyPrefix
        // The right sidebar used to persist a `RightSidebarMode` raw value here
        // (default instance under "rightSidebar.mode"). Files|Git replaced modes,
        // so the key is only read to be migrated away.
        self.legacyModeKey = persistenceKeyPrefix == "fileExplorer" ? "rightSidebar.mode" : "\(persistenceKeyPrefix).mode"
        let defaults = UserDefaults.standard
        self.isVisible = defaults.object(forKey: "\(persistenceKeyPrefix).isVisible") == nil
            ? defaultVisible
            : defaults.bool(forKey: "\(persistenceKeyPrefix).isVisible")
        let storedWidth = defaults.double(forKey: "\(persistenceKeyPrefix).width")
        self.width = storedWidth > 0 ? CGFloat(storedWidth) : 220
        let storedPosition = defaults.double(forKey: "\(persistenceKeyPrefix).dividerPosition")
        self.dividerPosition = storedPosition > 0 ? CGFloat(storedPosition) : 0.6
        let storedShowHidden = defaults.object(forKey: "\(persistenceKeyPrefix).showHidden")
        self.showHiddenFiles = storedShowHidden == nil ? true : defaults.bool(forKey: "\(persistenceKeyPrefix).showHidden")
        let customSidebarName = defaults.string(forKey: Self.customSidebarNameKey)?.nilIfEmpty
        self.storedCustomSidebarName = customSidebarName
        Self.migrateLegacyRightSidebarMode(legacyModeKey: self.legacyModeKey, defaults: defaults)
    }

    /// Folds the retired `RightSidebarMode` persistence into `FilesGitTab`.
    /// A stored `files` value keeps the Files tab; every other value (`find`,
    /// `sessions`, `feed`, `dock`, `custom-sidebar`, or anything unrecognized)
    /// is dead and falls back to Files silently. The legacy key is then dropped
    /// so a downgrade-then-upgrade cycle cannot revive a removed mode.
    static func migrateLegacyRightSidebarMode(
        legacyModeKey: String,
        defaults: UserDefaults = .standard
    ) {
        guard defaults.object(forKey: legacyModeKey) != nil else { return }
        defaults.removeObject(forKey: legacyModeKey)
        if FilesGitTab(rawValue: defaults.string(forKey: FilesGitTab.defaultsKey) ?? "") == nil {
            FilesGitTab.select(.files, defaults: defaults)
        }
    }

    func selectCustomSidebar(name rawName: String, defaults: UserDefaults = .standard) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        storedCustomSidebarName = name
        defaults.set(name, forKey: Self.customSidebarNameKey)
    }

    func toggle() {
        setVisible(!isVisible)
    }

    func setVisible(_ nextValue: Bool) {
        guard isVisible != nextValue else { return }

        // Suppress both SwiftUI transactions and AppKit/Core Animation implicit layout changes.
        NSAnimationContext.beginGrouping()
        CATransaction.begin()
        defer {
            CATransaction.commit()
            NSAnimationContext.endGrouping()
        }

        NSAnimationContext.current.duration = 0
        NSAnimationContext.current.allowsImplicitAnimation = false
        CATransaction.setDisableActions(true)

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isVisible = nextValue
        }
    }

}
