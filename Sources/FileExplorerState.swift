import AppKit
import SwiftUI

// MARK: - State (visibility toggle)

final class FileExplorerState: ObservableObject {
    /// Prefix for this instance's UserDefaults keys. The right sidebar uses the
    /// default ("fileExplorer"); the left-sidebar explorer passes a distinct
    /// prefix so the two instances never clobber each other's persisted state.
    let persistenceKeyPrefix: String
    private let modeKey: String
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

    @Published private var storedMode: RightSidebarMode
    @Published private var storedCustomSidebarName: String?

    /// Active mode for the right sidebar (file tree, search, sessions, or enabled beta modes).
    var mode: RightSidebarMode {
        get { storedMode }
        set { setMode(newValue) }
    }

    var customSidebarName: String? {
        storedCustomSidebarName
    }

    init(persistenceKeyPrefix: String = "fileExplorer", defaultVisible: Bool = false) {
        self.persistenceKeyPrefix = persistenceKeyPrefix
        // The mode key historically lives under "rightSidebar.mode" for the
        // default (right sidebar) instance; preserve it for back-compat and
        // give any other instance its own prefixed mode key.
        self.modeKey = persistenceKeyPrefix == "fileExplorer" ? "rightSidebar.mode" : "\(persistenceKeyPrefix).mode"
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
        let storedMode = RightSidebarMode(rawValue: defaults.string(forKey: self.modeKey) ?? "") ?? .files
        self.storedMode = Self.availableMode(storedMode, defaults: defaults)
        defaults.set(self.storedMode.rawValue, forKey: self.modeKey)
    }

    func refreshModeAvailability(defaults: UserDefaults = .standard) {
        setMode(storedMode, defaults: defaults)
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

    private func setMode(_ mode: RightSidebarMode, defaults: UserDefaults = .standard) {
        let nextMode = Self.availableMode(mode, defaults: defaults)
        guard storedMode != nextMode else {
            if defaults.string(forKey: modeKey) != nextMode.rawValue {
                defaults.set(nextMode.rawValue, forKey: modeKey)
            }
            return
        }
        storedMode = nextMode
        defaults.set(nextMode.rawValue, forKey: modeKey)
    }

    private static func availableMode(
        _ mode: RightSidebarMode,
        defaults: UserDefaults
    ) -> RightSidebarMode {
        if mode == .customSidebar {
            return .files
        }
        return mode.isAvailable(defaults: defaults) ? mode : .files
    }
}
