// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// A small helper window listing every keyboard shortcut (Help ▸ Shortcuts,
/// or the `?` key). Rebuilt on each `show()` so it always reflects the active
/// UI language (`L10n`).
final class ShortcutsHelpWindow {
    static let shared = ShortcutsHelpWindow()

    private var window: NSWindow?

    private init() {}

    /// Rows of (shortcut, description) shown in the help window.
    private static func rows() -> [(String, String)] {
        let t = L10n.shared.t
        return [
            ("←/↑/W/A/H/J", t("Previous image")),
            ("→/↓/S/D/L/K", t("Next image")),
            ("R", t("Rotate 90° clockwise")),
            ("⌘R", t("Rotate 90° counterclockwise")),
            ("Space", t("Play / Pause slideshow")),
            ("P", t("Start / Stop slideshow")),
            ("F", t("Toggle full screen")),
            ("Esc / Enter", t("Exit slideshow / full screen")),
            ("⌘S", t("Save (overwrite)")),
            ("⌘⇧S", t("Save As...")),
            ("⌘⌫", t("Delete (move to Trash)")),
            ("?", t("Show this help")),
            ("Double-click", t("Fit / 100% (double-click image)")),
            ("Wheel / Pinch", t("Zoom (mouse wheel / trackpad pinch)")),
        ]
    }

    func show() {
        buildWindow()
        guard let window = window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        // Make the content view first responder so it can handle ESC key
        window.makeFirstResponder(window.contentView)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildWindow() {
        window?.orderOut(nil)

        let t = L10n.shared.t
        let rows = Self.rows()

        let margin: CGFloat = 24
        let rowHeight: CGFloat = 30
        let keyColumnWidth: CGFloat = 150
        let contentWidth: CGFloat = 460
        let titleBlockHeight: CGFloat = 56
        let contentHeight: CGFloat = titleBlockHeight + CGFloat(rows.count) * rowHeight + margin

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = t("Keyboard Shortcuts")
        win.isReleasedWhenClosed = false

        // Flipped container so rows lay out top-to-bottom.
        let root = FlippedContainer(frame: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight))
        win.contentView = root

        let title = NSTextField(labelWithString: t("Keyboard Shortcuts"))
        title.font = NSFont.systemFont(ofSize: 18, weight: .semibold)
        title.frame = NSRect(x: margin, y: 16, width: contentWidth - margin * 2, height: 28)
        root.addSubview(title)

        var y = titleBlockHeight
        for (key, description) in rows {
            let keyLabel = NSTextField(labelWithString: key)
            keyLabel.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .medium)
            keyLabel.textColor = AutoHideToolbar.buttonColor
            keyLabel.frame = NSRect(x: margin, y: y, width: keyColumnWidth, height: rowHeight - 6)
            root.addSubview(keyLabel)

            let descLabel = NSTextField(labelWithString: description)
            descLabel.font = NSFont.systemFont(ofSize: 13)
            descLabel.frame = NSRect(x: margin + keyColumnWidth, y: y, width: contentWidth - margin * 2 - keyColumnWidth, height: rowHeight - 6)
            root.addSubview(descLabel)

            y += rowHeight
        }

        self.window = win
    }
}

/// Simple flipped container so the help rows can be placed top-to-bottom.
private final class FlippedContainer: NSView {
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        // ESC key closes the window
        if event.keyCode == 53 {
            self.window?.close()
        } else {
            super.keyDown(with: event)
        }
    }
}
