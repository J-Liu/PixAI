// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Empty-state view: big icon + hint text, centered in the image area.
/// Clicking anywhere on it opens the file selection panel; it also accepts dropped files.
class PlaceholderView: NSView {
    /// Size of the placeholder group. Area is 3x the original 420x280 (117600 -> 352800).
    static let preferredSize = NSSize(width: 720, height: 490)

    private let onOpen: () -> Void
    private let onDrop: ([URL]) -> Void
    private let iconView: NSImageView
    private let titleLabel: NSTextField
    private let subtitleLabel: NSTextField

    private var l10nObserver: NSObjectProtocol?

    init(onOpen: @escaping () -> Void, onDrop: @escaping ([URL]) -> Void) {
        self.onOpen = onOpen
        self.onDrop = onDrop

        iconView = NSImageView()
        titleLabel = NSTextField(labelWithString: L10n.shared.t("Open Images"))
        subtitleLabel = NSTextField(labelWithString: L10n.shared.t("Drag images here, or click here to open"))

        super.init(frame: .zero)

        wantsLayer = true
        registerForDraggedTypes(DragDropHelper.draggedTypes)

        // Big SF Symbol icon.
        let config = NSImage.SymbolConfiguration(pointSize: 165, weight: .light)
        if let symbol = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            symbol.isTemplate = true
            iconView.image = symbol
        }
        iconView.contentTintColor = NSColor(white: 0.55, alpha: 1)
        iconView.imageScaling = .scaleProportionallyUpOrDown
        addSubview(iconView)

        titleLabel.font = NSFont.systemFont(ofSize: 34, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        addSubview(titleLabel)

        subtitleLabel.font = NSFont.systemFont(ofSize: 18)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        addSubview(subtitleLabel)
        // Keep the labels in sync with the active UI language.
        self.l10nObserver = NotificationCenter.default.addObserver(
            forName: L10n.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            self.titleLabel.stringValue = L10n.shared.t("Open Images")
            self.subtitleLabel.stringValue = L10n.shared.t("Drag images here, or click here to open")
        }
    }

    deinit {
        if let observer = l10nObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Re-layout the internal content whenever this view is resized.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    /// Center icon + title + subtitle as a vertical group inside the view.
    /// AppKit default coordinate system: origin at bottom-left, y up (non-flipped).
    override func layout() {
        super.layout()

        let b = bounds.size
        guard b.width > 0, b.height > 0 else { return }

        // Measure the three pieces.
        let iconSize: CGFloat = 210
        titleLabel.sizeToFit()
        let titleH = titleLabel.frame.height
        subtitleLabel.sizeToFit()
        let subH = subtitleLabel.frame.height

        let gapIconTitle: CGFloat = 36
        let gapTitleSub: CGFloat = 14
        let groupHeight = iconSize + gapIconTitle + titleH + gapTitleSub + subH
        var y = (b.height - groupHeight) / 2  // bottom of the centered group

        // Bottom to top in non-flipped coordinates.
        subtitleLabel.frame = NSRect(
            x: (b.width - subtitleLabel.frame.width) / 2,
            y: y,
            width: subtitleLabel.frame.width,
            height: subH
        )
        y += subH + gapTitleSub

        titleLabel.frame = NSRect(
            x: (b.width - titleLabel.frame.width) / 2,
            y: y,
            width: titleLabel.frame.width,
            height: titleH
        )
        y += titleH + gapIconTitle

        iconView.frame = NSRect(
            x: (b.width - iconSize) / 2,
            y: y,
            width: iconSize,
            height: iconSize
        )
    }

    override func mouseDown(with event: NSEvent) {
        onOpen()
    }

    // MARK: - Drag and drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = DragDropHelper.extractURLs(from: sender.draggingPasteboard)
        if !urls.isEmpty {
            onDrop(urls)
            return true
        }
        return false
    }
}
