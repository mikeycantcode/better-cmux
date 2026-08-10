import AppKit
import CmuxFoundation
import UniformTypeIdentifiers

final class FileExplorerCellView: NSTableCellView {
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let loadingIndicator = NSProgressIndicator()
    /// `.vscode` only: replaces the outline view's stock disclosure triangle.
    private let chevronButton = NSButton()
    /// `.vscode` only: trailing "M"/"A"/"D"/"R"/"U" for files.
    private let badgeLabel = NSTextField(labelWithString: "")
    /// `.vscode` only: trailing filled dot for directories with dirty descendants.
    private let folderDotView = FileExplorerFolderDotView()
    private var trackingArea: NSTrackingArea?
    var onHover: ((Bool) -> Void)?
    /// Invoked when the custom chevron is clicked.
    var onToggleExpansion: (() -> Void)?
    private var nameLabelTrailingToLoadingConstraint: NSLayoutConstraint!
    private var nameLabelTrailingToContainerConstraint: NSLayoutConstraint!
    private var nameLabelTrailingToBadgeConstraint: NSLayoutConstraint!

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private var iconWidthConstraint: NSLayoutConstraint!
    private var iconHeightConstraint: NSLayoutConstraint!
    private var iconToTextConstraint: NSLayoutConstraint!
    private var loadingWidthConstraint: NSLayoutConstraint!
    private var chevronWidthConstraint: NSLayoutConstraint!
    private var badgeWidthConstraint: NSLayoutConstraint!

    /// Chevron column width for `.vscode`. Matches the 16pt glyph box.
    private static let chevronColumnWidth: CGFloat = 16
    private static let folderDotSize: CGFloat = 6

    /// Trailing status-letter column. The badge font is magnified, so the column it
    /// sits in must be too — a fixed 14pt truncated "M" at 150% magnification.
    static func statusLetterBadgeWidth(magnifiedBy scale: (CGFloat) -> CGFloat = GlobalFontMagnification.scaledSize) -> CGFloat {
        scale(14)
    }

    /// The two chevron glyphs, built once instead of per configure (i.e. per
    /// scroll-recycle). Fixed 16pt medium, independent of font magnification, so
    /// there is nothing to invalidate.
    private static let chevronImages: [Bool: NSImage] = {
        let config = NSImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        var images: [Bool: NSImage] = [:]
        for expanded in [false, true] {
            if let image = NSImage(
                systemSymbolName: FileExplorerStyle.chevronSymbolName(expanded: expanded),
                accessibilityDescription: nil
            )?.withSymbolConfiguration(config) {
                images[expanded] = image
            }
        }
        return images
    }()

    private func setupViews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1

        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .small
        loadingIndicator.isHidden = true
        loadingIndicator.setAccessibilityIdentifier("FileExplorerLoadingIndicator")

        chevronButton.translatesAutoresizingMaskIntoConstraints = false
        chevronButton.isBordered = false
        chevronButton.bezelStyle = .regularSquare
        chevronButton.imagePosition = .imageOnly
        chevronButton.contentTintColor = .secondaryLabelColor
        chevronButton.target = self
        chevronButton.action = #selector(chevronClicked)
        chevronButton.isHidden = true
        chevronButton.setAccessibilityLabel(
            String(localized: "fileExplorer.chevron.accessibility", defaultValue: "Toggle folder")
        )

        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.alignment = .center
        badgeLabel.isHidden = true

        folderDotView.translatesAutoresizingMaskIntoConstraints = false
        folderDotView.isHidden = true

        addSubview(chevronButton)
        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(badgeLabel)
        addSubview(folderDotView)
        addSubview(loadingIndicator)

        iconWidthConstraint = iconView.widthAnchor.constraint(equalToConstant: 16)
        iconHeightConstraint = iconView.heightAnchor.constraint(equalToConstant: 16)
        iconToTextConstraint = nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4)
        loadingWidthConstraint = loadingIndicator.widthAnchor.constraint(equalToConstant: 0)
        chevronWidthConstraint = chevronButton.widthAnchor.constraint(equalToConstant: 0)
        badgeWidthConstraint = badgeLabel.widthAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            chevronButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
            chevronButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            chevronWidthConstraint,
            chevronButton.heightAnchor.constraint(equalToConstant: Self.chevronColumnWidth),

            badgeWidthConstraint,
            badgeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            badgeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            folderDotView.widthAnchor.constraint(equalToConstant: Self.folderDotSize),
            folderDotView.heightAnchor.constraint(equalToConstant: Self.folderDotSize),
            folderDotView.centerXAnchor.constraint(equalTo: badgeLabel.centerXAnchor),
            folderDotView.centerYAnchor.constraint(equalTo: centerYAnchor),

            iconView.leadingAnchor.constraint(equalTo: chevronButton.trailingAnchor, constant: 0),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconWidthConstraint,
            iconHeightConstraint,

            iconToTextConstraint,
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            loadingIndicator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            loadingIndicator.centerYAnchor.constraint(equalTo: centerYAnchor),
            loadingWidthConstraint,
            loadingIndicator.heightAnchor.constraint(equalToConstant: 12),
        ])

        nameLabelTrailingToLoadingConstraint = nameLabel.trailingAnchor.constraint(
            equalTo: loadingIndicator.leadingAnchor,
            constant: -2
        )
        nameLabelTrailingToContainerConstraint = nameLabel.trailingAnchor.constraint(
            equalTo: trailingAnchor,
            constant: -2
        )
        nameLabelTrailingToBadgeConstraint = nameLabel.trailingAnchor.constraint(
            equalTo: badgeLabel.leadingAnchor,
            constant: -4
        )
        NSLayoutConstraint.activate([
            nameLabelTrailingToLoadingConstraint,
            nameLabelTrailingToContainerConstraint
        ])
        nameLabelTrailingToLoadingConstraint.isActive = false
        nameLabelTrailingToBadgeConstraint.isActive = false
    }

    @objc private func chevronClicked() {
        onToggleExpansion?()
    }

    func configure(
        with node: FileExplorerNode,
        decoration: FileRowDecoration = .plain,
        isExpanded: Bool = false
    ) {
        assert(Thread.isMainThread, "AppKit image updates must run on the main thread")
        let style = FileExplorerStyle.cachedCurrent
        nameLabel.stringValue = node.name
        nameLabel.font = style.nameFont
        iconWidthConstraint.constant = style.iconSize
        iconHeightConstraint.constant = style.iconSize
        iconToTextConstraint.constant = style.iconToTextSpacing

        configureChevron(style: style, node: node, isExpanded: isExpanded)

        if style == .vscodeIcons || style == .vscode {
            let iconSize = style.iconSize
            if node.isDirectory {
                // `.vscode` gets named folder variants (src/, test/, ...) and the
                // open/closed pair; `.vscodeIcons` keeps its plain folder icon.
                let image: NSImage = {
                    if style == .vscode {
                        return VSCodeFileIcon.folderIcon(
                            forFolderName: node.name, expanded: isExpanded, size: iconSize
                        ) ?? NSWorkspace.shared.icon(for: .folder)
                    }
                    return VSCodeFileIcon.folderIcon(size: iconSize)
                        ?? NSWorkspace.shared.icon(for: .folder)
                }()
                image.size = NSSize(width: iconSize, height: iconSize)
                iconView.image = image
                iconView.contentTintColor = nil
            } else {
                let image = VSCodeFileIcon.icon(forFileName: node.name, size: iconSize)
                    ?? NSImage(systemSymbolName: "doc", accessibilityDescription: nil)?
                        .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: iconSize, weight: style.iconWeight))
                iconView.image = image
                iconView.contentTintColor = nil
            }
        } else if style == .finder {
            if node.isDirectory {
                let folderIcon = NSWorkspace.shared.icon(for: .folder)
                folderIcon.size = NSSize(width: style.iconSize, height: style.iconSize)
                iconView.image = folderIcon
                iconView.contentTintColor = nil
            } else {
                let pathExtension = (node.name as NSString).pathExtension
                let fileIcon = NSWorkspace.shared.icon(for: UTType(filenameExtension: pathExtension) ?? .data)
                fileIcon.size = NSSize(width: style.iconSize, height: style.iconSize)
                iconView.image = fileIcon
                iconView.contentTintColor = nil
            }
        } else {
            let symbolConfig = NSImage.SymbolConfiguration(pointSize: style.iconSize, weight: style.iconWeight)
            if node.isDirectory {
                iconView.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)?
                    .withSymbolConfiguration(symbolConfig)
                iconView.contentTintColor = style.folderIconTint
            } else {
                iconView.image = NSImage(systemSymbolName: "doc", accessibilityDescription: nil)?
                    .withSymbolConfiguration(symbolConfig)
                iconView.contentTintColor = style.fileIconTint
            }
        }

        if node.isLoading {
            loadingWidthConstraint.constant = 12
            loadingIndicator.isHidden = false
            loadingIndicator.startAnimation(nil)
            nameLabelTrailingToLoadingConstraint.isActive = true
            nameLabelTrailingToContainerConstraint.isActive = false
        } else {
            loadingWidthConstraint.constant = 0
            loadingIndicator.isHidden = true
            loadingIndicator.stopAnimation(nil)
            nameLabelTrailingToLoadingConstraint.isActive = false
            nameLabelTrailingToContainerConstraint.isActive = true
        }

        if let error = node.error {
            nameLabel.textColor = .systemRed
            nameLabel.toolTip = error
        } else if let tint = decoration.tint {
            nameLabel.textColor = tint
            nameLabel.toolTip = node.path
        } else {
            nameLabel.textColor = .labelColor
            nameLabel.toolTip = node.path
        }

        configureBadge(decoration, isLoading: node.isLoading)

        iconView.alphaValue = decoration.alpha
        nameLabel.alphaValue = decoration.alpha
        badgeLabel.alphaValue = decoration.alpha
        folderDotView.alphaValue = decoration.alpha
    }

    /// The custom chevron exists only for `.vscode`; every other style keeps the
    /// outline view's stock disclosure triangle and a zero-width chevron column.
    private func configureChevron(style: FileExplorerStyle, node: FileExplorerNode, isExpanded: Bool) {
        guard style.usesCustomChevron, node.isDirectory else {
            chevronButton.isHidden = true
            chevronButton.image = nil
            chevronWidthConstraint.constant = style.usesCustomChevron ? Self.chevronColumnWidth : 0
            return
        }
        chevronWidthConstraint.constant = Self.chevronColumnWidth
        chevronButton.isHidden = false
        chevronButton.image = Self.chevronImages[isExpanded]
        chevronButton.contentTintColor = .secondaryLabelColor
    }

    private func configureBadge(_ decoration: FileRowDecoration, isLoading: Bool) {
        // The spinner and the badge share the trailing edge; the spinner wins.
        switch decoration.badge {
        case .none:
            hideBadge()
        case .statusLetter(let letter) where !isLoading:
            folderDotView.isHidden = true
            badgeLabel.isHidden = false
            badgeLabel.stringValue = letter
            badgeLabel.font = GlobalFontMagnification.systemFont(ofSize: 12, weight: .semibold)
            badgeLabel.textColor = decoration.tint ?? .secondaryLabelColor
            badgeLabel.setAccessibilityLabel(
                String(
                    localized: "fileExplorer.gitBadge.accessibility",
                    defaultValue: "Git status \(letter)"
                )
            )
            badgeWidthConstraint.constant = Self.statusLetterBadgeWidth()
            nameLabelTrailingToContainerConstraint.isActive = false
            nameLabelTrailingToBadgeConstraint.isActive = true
        case .folderDot where !isLoading:
            badgeLabel.isHidden = true
            badgeLabel.stringValue = ""
            folderDotView.isHidden = false
            folderDotView.fillColor = decoration.tint ?? .secondaryLabelColor
            folderDotView.setAccessibilityLabel(
                String(
                    localized: "fileExplorer.folderChangesBadge.accessibility",
                    defaultValue: "Contains changes"
                )
            )
            badgeWidthConstraint.constant = Self.folderDotSize
            nameLabelTrailingToContainerConstraint.isActive = false
            nameLabelTrailingToBadgeConstraint.isActive = true
        default:
            hideBadge()
        }
    }

    private func hideBadge() {
        badgeLabel.isHidden = true
        badgeLabel.stringValue = ""
        folderDotView.isHidden = true
        badgeWidthConstraint.constant = 0
        nameLabelTrailingToBadgeConstraint.isActive = false
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }
}

/// Filled 6pt dot VS Code shows on directories with dirty descendants.
final class FileExplorerFolderDotView: NSView {
    var fillColor: NSColor = .secondaryLabelColor {
        didSet {
            guard fillColor != oldValue else { return }
            needsDisplay = true
        }
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        fillColor.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }
}
