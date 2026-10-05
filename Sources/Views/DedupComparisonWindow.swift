// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// A side-by-side duplicate-comparison window. Two images are shown left and
/// right; the user selects which to keep with the keyboard (←/↑/A/W/H/J = left,
/// →/↓/D/S/K/L = right) and confirms with Enter/Space. Esc CANCELS THE WHOLE
/// dedup operation and returns the app to browse mode.
final class DedupComparisonWindow: NSObject, NSWindowDelegate {
    private let panel: NSPanel
    private let leftView: ClickableImageView
    private let rightView: ClickableImageView
    private let leftBadge: NSTextField
    private let rightBadge: NSTextField
    private let statusBar: DedupStatusBar
    private let leftURL: URL
    private let rightURL: URL
    private var selection: Int = 0     // 0 = left, 1 = right
    private var onConfirm: ((Int) -> Void)?
    /// Called when the user presses Esc: cancel the entire dedup batch.
    private var onCancelAll: (() -> Void)?
    /// The currently active comparison window (singleton).
    static var active: DedupComparisonWindow?

    private init(panel: NSPanel, leftView: ClickableImageView, rightView: ClickableImageView,
                 leftBadge: NSTextField, rightBadge: NSTextField, statusBar: DedupStatusBar,
                 leftURL: URL, rightURL: URL) {
        self.panel = panel
        self.leftView = leftView
        self.rightView = rightView
        self.leftBadge = leftBadge
        self.rightBadge = rightBadge
        self.statusBar = statusBar
        self.leftURL = leftURL
        self.rightURL = rightURL
        super.init()
        panel.delegate = self
    }

    /// Present the comparison as a modal-ish key window over `parent`.
    /// onConfirm returns: 0 = keep left, 1 = keep right, 2 = keep both
    static func present(over parent: NSWindow,
                        leftURL: URL,
                        rightURL: URL,
                        initialSelection: Int = 0,
                        onConfirm: @escaping (Int) -> Void,
                        onCancelAll: @escaping () -> Void) {
        // Only one comparison at a time.
        active?.close()

        let size = NSSize(width: 1040, height: 730)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = L10n.shared.t("Choose which image to keep")
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.hidesOnDeactivate = false

        let root = DedupKeyCatcher(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor

        // Status bar at bottom
        let statusBarHeight: CGFloat = 28
        let statusBar = DedupStatusBar(frame: NSRect(x: 0, y: 0, width: size.width, height: statusBarHeight))
        root.addSubview(statusBar)

        func makePane(_ x: CGFloat, url: URL) -> (ClickableImageView, NSTextField) {
            let pad: CGFloat = 16
            let paneW = size.width / 2 - pad * 3
            let paneH = size.height - 150 - statusBarHeight
            let iv = ClickableImageView(frame: NSRect(x: x + pad, y: 104 + statusBarHeight, width: paneW, height: paneH))
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.wantsLayer = true
            iv.layer?.backgroundColor = NSColor(white: 0.18, alpha: 1).cgColor
            iv.layer?.cornerRadius = 10
            if let img = NSImage(contentsOf: url) { iv.image = img }

            let badge = NSTextField(labelWithString: "")
            badge.font = NSFont.systemFont(ofSize: 13, weight: .bold)
            badge.textColor = AutoHideToolbar.buttonColor
            badge.alignment = .center
            badge.frame = NSRect(x: x + pad, y: 70 + statusBarHeight, width: paneW, height: 24)
            root.addSubview(iv)
            root.addSubview(badge)
            return (iv, badge)
        }

        let (leftView, leftBadge) = makePane(0, url: leftURL)
        let (rightView, rightBadge) = makePane(size.width / 2, url: rightURL)

        // Keep Both button
        let t = L10n.shared.t
        let keepBothButton = NSButton(frame: NSRect(x: size.width / 2 - 80, y: 16 + 28, width: 160, height: 32))
        keepBothButton.title = t("Keep Both (B)")
        keepBothButton.bezelStyle = .rounded
        keepBothButton.contentTintColor = .white
        keepBothButton.target = nil
        keepBothButton.action = nil
        root.addSubview(keepBothButton)

        panel.contentView = root
        panel.center()
        // Offset slightly from the parent so both are visible.
        var f = panel.frame
        f.origin.x = parent.frame.midX - f.width / 2 + 40
        f.origin.y = parent.frame.midY - f.height / 2 + 20
        panel.setFrame(f, display: true)

        let win = DedupComparisonWindow(panel: panel, leftView: leftView, rightView: rightView,
                                        leftBadge: leftBadge, rightBadge: rightBadge, statusBar: statusBar,
                                        leftURL: leftURL, rightURL: rightURL)
        win.onConfirm = onConfirm
        win.onCancelAll = onCancelAll
        win.selection = (initialSelection == 1) ? 1 : 0
        win.applySelection()

        // Click handlers for image selection
        leftView.onClick = { [weak win] in win?.select(0) }
        rightView.onClick = { [weak win] in win?.select(1) }

        root.onSelectLeft = { [weak win] in win?.select(0) }
        root.onSelectRight = { [weak win] in win?.select(1) }
        root.onConfirmKey = { [weak win] in
            guard let win = win else { return }
            let pick = win.selection
            NSApp.stopModal()
            win.close()
            win.onConfirm?(pick)
        }
        root.onKeepBoth = { [weak win] in
            guard let win = win else { return }
            NSApp.stopModal()
            win.close()
            win.onConfirm?(2)
        }
        root.onCancelKey = { [weak win] in
            guard let win = win else { return }
            NSApp.stopModal()
            win.close()
            win.onCancelAll?()
        }

        keepBothButton.target = root
        keepBothButton.action = #selector(DedupKeyCatcher.keepBothAction(_:))

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(root)
        NSApp.activate(ignoringOtherApps: true)
        active = win

        // Run modal to keep focus in this window
        NSApp.runModal(for: panel)
    }

    private func select(_ which: Int) {
        selection = which
        applySelection()
    }

    private func applySelection() {
        let leftSelected = (selection == 0)
        leftView.layer?.borderWidth = leftSelected ? 4 : 0
        leftView.layer?.borderColor = AutoHideToolbar.buttonColor.cgColor
        rightView.layer?.borderWidth = !leftSelected ? 4 : 0
        rightView.layer?.borderColor = AutoHideToolbar.buttonColor.cgColor
        let t = L10n.shared.t
        leftBadge.stringValue = leftSelected ? t("← KEEP (Enter)") : ""
        rightBadge.stringValue = !leftSelected ? t("KEEP (Enter) →") : ""

        // Update status bar with selected image info
        let selectedURL = leftSelected ? leftURL : rightURL
        statusBar.update(with: selectedURL)
    }

    private func close() {
        panel.orderOut(nil)
        if Self.active === self { Self.active = nil }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Stop modal if still running
        NSApp.stopModal()
        // Cancel the dedup batch when window is closed via close button or Cmd+W
        onCancelAll?()
    }
}

/// Content view that captures the keyboard for the comparison window.
private final class DedupKeyCatcher: NSView {
    var onSelectLeft: (() -> Void)?
    var onSelectRight: (() -> Void)?
    var onConfirmKey: (() -> Void)?
    var onKeepBoth: (() -> Void)?
    var onCancelKey: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    @objc func keepBothAction(_ sender: Any?) {
        onKeepBoth?()
    }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Ignore modifier-key combos (let the system handle them).
        if mods.contains(.command) || mods.contains(.option) || mods.contains(.control) {
            super.keyDown(with: event)
            return
        }

        // Check arrow keys by keyCode
        switch event.keyCode {
        case 123, 126: // Left arrow, Up arrow
            onSelectLeft?()
            return
        case 124, 125: // Right arrow, Down arrow
            onSelectRight?()
            return
        default:
            break
        }

        // Check character keys
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch key {
        case "a", "w", "h", "j":
            onSelectLeft?()
        case "d", "s", "k", "l":
            onSelectRight?()
        case "\r", "\n", " ":
            onConfirmKey?()
        case "b":
            onKeepBoth?()
        case "\u{1b}":
            onCancelKey?()
        default:
            super.keyDown(with: event)
        }
    }
}

/// Image view that handles mouse clicks for selection.
private final class ClickableImageView: NSImageView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}

/// Status bar for dedup comparison window showing selected image info.
private final class DedupStatusBar: NSView {
    private let filenameLabel: NSTextField
    private let fileSizeLabel: NSTextField
    private let resolutionLabel: NSTextField

    override init(frame frameRect: NSRect) {
        filenameLabel = Self.createLabel()
        fileSizeLabel = Self.createLabel()
        resolutionLabel = Self.createLabel()

        super.init(frame: frameRect)

        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.9).cgColor

        addSubview(filenameLabel)
        addSubview(fileSizeLabel)
        addSubview(resolutionLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func createLabel() -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = NSColor(white: 0.92, alpha: 1)
        label.alignment = .left
        label.lineBreakMode = .byTruncatingMiddle
        label.isEditable = false
        label.isBezeled = false
        label.isBordered = false
        return label
    }

    override func layout() {
        super.layout()

        let y = (bounds.height - 16) / 2
        let charWidth: CGFloat = 7
        let gap: CGFloat = 5 * charWidth
        var x: CGFloat = 12

        // Filename (flexible width)
        let filenameWidth = bounds.width - 40 * charWidth - gap * 2
        filenameLabel.frame = NSRect(x: x, y: y, width: filenameWidth, height: 16)
        x += filenameWidth + gap

        // File size (10 chars)
        let fileSizeWidth = 10 * charWidth
        fileSizeLabel.frame = NSRect(x: x, y: y, width: fileSizeWidth, height: 16)
        x += fileSizeWidth + gap

        // Resolution (18 chars)
        let resolutionWidth = 18 * charWidth
        resolutionLabel.frame = NSRect(x: x, y: y, width: resolutionWidth, height: 16)
    }

    func update(with url: URL) {
        // Filename with middle truncation
        let filename = url.lastPathComponent
        filenameLabel.stringValue = truncateFilenameMiddle(filename, maxChars: Int(bounds.width / 7 - 30))

        // File size
        var fileSizeStr = ""
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let fileSize = attrs[.size] as? Int64 {
            fileSizeStr = formatFileSize(fileSize)
        }
        fileSizeLabel.stringValue = fileSizeStr

        // Resolution
        var resolutionStr = ""
        if let image = NSImage(contentsOf: url),
           let rep = image.representations.first {
            resolutionStr = "\(rep.pixelsWide) × \(rep.pixelsHigh)"
        }
        resolutionLabel.stringValue = resolutionStr
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        let mb = kb / 1024
        if mb >= 1 {
            return String(format: "%.1f MB", mb)
        } else if kb >= 1 {
            return String(format: "%.0f KB", kb)
        } else {
            return "\(bytes) B"
        }
    }

    private func truncateFilenameMiddle(_ filename: String, maxChars: Int) -> String {
        if filename.count <= maxChars { return filename }
        let keep = (maxChars - 3) / 2
        let prefix = String(filename.prefix(keep))
        let suffix = String(filename.suffix(keep))
        return prefix + "~~~" + suffix
    }
}
