import AppKit

/// A side-by-side duplicate-comparison window. Two images are shown left and
/// right; the user selects which to keep with the keyboard (←/↑/A/W/H = left,
/// →/↓/D/S/J/K = right), confirms with Enter/Space, or cancels with Esc.
/// The selected side is highlighted with an orange border + "KEEP" badge.
final class DedupComparisonWindow {
    private let panel: NSPanel
    private let leftView: NSImageView
    private let rightView: NSImageView
    private let leftBadge: NSTextField
    private let rightBadge: NSTextField
    private var selection: Int = 0     // 0 = left, 1 = right
    private var onConfirm: ((Int) -> Void)?
    private var onCancel: (() -> Void)?
    private static var active: DedupComparisonWindow?

    private init(panel: NSPanel, leftView: NSImageView, rightView: NSImageView,
                 leftBadge: NSTextField, rightBadge: NSTextField) {
        self.panel = panel
        self.leftView = leftView
        self.rightView = rightView
        self.leftBadge = leftBadge
        self.rightBadge = rightBadge
    }

    /// Present the comparison as a modal-ish key window over `parent`.
    static func present(over parent: NSWindow,
                        leftURL: URL,
                        rightURL: URL,
                        initialSelection: Int = 0,
                        onConfirm: @escaping (Int) -> Void,
                        onCancel: @escaping () -> Void) {
        // Only one comparison at a time.
        active?.close()

        let size = NSSize(width: 1040, height: 620)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Choose which image to keep"
        panel.isReleasedWhenClosed = false

        let root = DedupKeyCatcher(frame: NSRect(origin: .zero, size: size))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor(white: 0.12, alpha: 1).cgColor

        func makePane(_ x: CGFloat, url: URL) -> (NSImageView, NSTextField) {
            let pad: CGFloat = 16
            let paneW = size.width / 2 - pad * 3
            let paneH = size.height - 90
            let iv = NSImageView(frame: NSRect(x: x + pad, y: 44, width: paneW, height: paneH))
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.wantsLayer = true
            iv.layer?.backgroundColor = NSColor(white: 0.18, alpha: 1).cgColor
            iv.layer?.cornerRadius = 10
            if let img = NSImage(contentsOf: url) { iv.image = img }

            let badge = NSTextField(labelWithString: "")
            badge.font = NSFont.systemFont(ofSize: 13, weight: .bold)
            badge.textColor = AutoHideToolbar.buttonColor
            badge.alignment = .center
            badge.frame = NSRect(x: x + pad, y: 10, width: paneW, height: 24)
            root.addSubview(iv)
            root.addSubview(badge)
            return (iv, badge)
        }

        let (leftView, leftBadge) = makePane(0, url: leftURL)
        let (rightView, rightBadge) = makePane(size.width / 2, url: rightURL)

        panel.contentView = root
        panel.center()
        // Offset slightly from the parent so both are visible.
        var f = panel.frame
        f.origin.x = parent.frame.midX - f.width / 2 + 40
        f.origin.y = parent.frame.midY - f.height / 2 + 20
        panel.setFrame(f, display: true)

        let win = DedupComparisonWindow(panel: panel, leftView: leftView, rightView: rightView,
                                        leftBadge: leftBadge, rightBadge: rightBadge)
        win.onConfirm = onConfirm
        win.onCancel = onCancel
        win.selection = (initialSelection == 1) ? 1 : 0
        win.applySelection()

        root.onSelectLeft = { [weak win] in win?.select(0) }
        root.onSelectRight = { [weak win] in win?.select(1) }
        root.onConfirmKey = { [weak win] in
            guard let win = win else { return }
            let pick = win.selection
            win.close()
            win.onConfirm?(pick)
        }
        root.onCancelKey = { [weak win] in
            guard let win = win else { return }
            win.close()
            win.onCancel?()
        }

        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(root)
        NSApp.activate(ignoringOtherApps: true)
        active = win
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
        leftBadge.stringValue = leftSelected ? "← KEEP (Enter)" : ""
        rightBadge.stringValue = !leftSelected ? "KEEP (Enter) →" : ""
    }

    private func close() {
        panel.orderOut(nil)
        if Self.active === self { Self.active = nil }
    }
}

/// Content view that captures the keyboard for the comparison window.
private final class DedupKeyCatcher: NSView {
    var onSelectLeft: (() -> Void)?
    var onSelectRight: (() -> Void)?
    var onConfirmKey: (() -> Void)?
    var onCancelKey: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Ignore modifier-key combos (let the system handle them).
        if mods.contains(.command) || mods.contains(.option) || mods.contains(.control) {
            super.keyDown(with: event)
            return
        }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        switch key {
        case "leftarrow", "a", "w", "h":
            onSelectLeft?()
        case "rightarrow", "d", "s", "j", "k":
            onSelectRight?()
        case "\r", "\n", " ":
            onConfirmKey?()
        case "\u{1b}":
            onCancelKey?()
        default:
            super.keyDown(with: event)
        }
    }
}
