import AppKit
import UniformTypeIdentifiers

/// A semi-transparent toolbar that auto-hides (dims) when not hovered.
/// Layout: [◀] | [+] [−] [fit/100%] | [▶] — the three center zoom buttons are
/// separated from the navigation arrows by thin vertical dividers.
class AutoHideToolbar: NSView {
    let leftButton: NSButton
    let rightButton: NSButton
    let zoomInButton: NSButton
    let zoomOutButton: NSButton
    let fitToggleButton: NSButton
    private let leftDivider: NSView
    private let rightDivider: NSView

    private var isHovered = false
    private let onLeftTap: () -> Void
    private let onRightTap: () -> Void
    private let onZoomInTap: () -> Void
    private let onZoomOutTap: () -> Void
    private let onFitToggleTap: () -> Void

    /// The color for the toolbar buttons (bright orange).
    static let buttonColor = NSColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1.0) // Bright orange

    /// The background color of the toolbar (semi-transparent dark).
    static let toolbarColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.6)

    /// The height of the toolbar.
    static let toolbarHeight: CGFloat = 56

    /// SF Symbol shown while the next click will "fit to window".
    static let fitIconName = "arrow.down.left.and.arrow.up.right"
    /// SF Symbol shown while the next click will switch to 100% (1:1) size.
    static let hundredPercentIconName = "1.square"

    init(onLeftTap: @escaping () -> Void,
         onRightTap: @escaping () -> Void,
         onZoomInTap: @escaping () -> Void,
         onZoomOutTap: @escaping () -> Void,
         onFitToggleTap: @escaping () -> Void) {
        self.onLeftTap = onLeftTap
        self.onRightTap = onRightTap
        self.onZoomInTap = onZoomInTap
        self.onZoomOutTap = onZoomOutTap
        self.onFitToggleTap = onFitToggleTap
        leftButton = NSButton()
        rightButton = NSButton()
        zoomInButton = NSButton()
        zoomOutButton = NSButton()
        fitToggleButton = NSButton()
        // Thin vertical dividers flanking the center zoom group (must be set
        // before super.init, as they are stored `let` properties).
        leftDivider = Self.makeDivider()
        rightDivider = Self.makeDivider()
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = AutoHideToolbar.toolbarColor.cgColor
        layer?.cornerRadius = 14

        // Configure buttons with orange SF Symbols.
        configureButton(leftButton, symbolName: "chevron.left")
        configureButton(rightButton, symbolName: "chevron.right")
        configureButton(zoomInButton, symbolName: "plus.magnifyingglass")
        configureButton(zoomOutButton, symbolName: "minus.magnifyingglass")
        configureButton(fitToggleButton, symbolName: Self.fitIconName)

        addSubview(leftButton)
        addSubview(leftDivider)
        addSubview(zoomInButton)
        addSubview(zoomOutButton)
        addSubview(fitToggleButton)
        addSubview(rightDivider)
        addSubview(rightButton)

        // Start in the visible (hovered) state.
        self.alphaValue = 0.9
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func makeDivider() -> NSView {
        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(white: 1.0, alpha: 0.3).cgColor
        return divider
    }

    /// Switch the fit toggle button's icon. `showsFit` == true means the icon
    /// represents "fit to window" (the next click will fit); false means it
    /// represents 100% (the next click will switch to 1:1).
    func setFitToggleShowsFitIcon(_ showsFit: Bool) {
        let name = showsFit ? Self.fitIconName : Self.hundredPercentIconName
        let config = NSImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            image.isTemplate = true
            fitToggleButton.image = image
        }
    }

    private func configureButton(_ button: NSButton, symbolName: String) {
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.title = ""

        // Orange-tinted template SF Symbol.
        let config = NSImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            image.isTemplate = true
            button.image = image
        }
        button.contentTintColor = AutoHideToolbar.buttonColor

        // Set up the action.
        button.target = self
        button.action = #selector(buttonTapped(_:))
    }

    /// Position all controls in a centered row: [◀] | [+] [−] [fit/100%] | [▶].
    override func layout() {
        super.layout()

        let buttonSize: CGFloat = 42
        let gap: CGFloat = 12
        let dividerW: CGFloat = 1
        let dividerH: CGFloat = 28
        let dividerPad: CGFloat = 14
        let groupWidth = buttonSize * 3 + gap * 2
        let totalWidth = buttonSize
            + dividerPad + dividerW + dividerPad + groupWidth
            + dividerPad + dividerW + dividerPad + buttonSize

        var x = (bounds.width - totalWidth) / 2
        let y = (bounds.height - buttonSize) / 2

        leftButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        x += buttonSize + dividerPad
        leftDivider.frame = NSRect(x: x, y: (bounds.height - dividerH) / 2, width: dividerW, height: dividerH)
        x += dividerW + dividerPad
        zoomInButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        x += buttonSize + gap
        zoomOutButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        x += buttonSize + gap
        fitToggleButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        x += buttonSize + dividerPad
        rightDivider.frame = NSRect(x: x, y: (bounds.height - dividerH) / 2, width: dividerW, height: dividerH)
        x += dividerW + dividerPad
        rightButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
    }

    override func mouseDown(with event: NSEvent) {
        // Prevent the window from closing when clicking toolbar
        super.mouseDown(with: event)
    }

    @objc private func buttonTapped(_ sender: NSButton) {
        if sender == leftButton {
            onLeftTap()
        } else if sender == rightButton {
            onRightTap()
        } else if sender == zoomInButton {
            onZoomInTap()
        } else if sender == zoomOutButton {
            onZoomOutTap()
        } else if sender == fitToggleButton {
            onFitToggleTap()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshTrackingArea()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshTrackingArea()
    }

    private func refreshTrackingArea() {
        for area in self.trackingAreas {
            self.removeTrackingArea(area)
        }

        // Track mouse enter/exit over the whole visible rect.
        let trackingArea = NSTrackingArea(
            rect: self.bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        self.addTrackingArea(trackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().alphaValue = 0.9
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            self.animator().alphaValue = 0.3
        }
    }

    /// Show the toolbar with animation.
    func show() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.animator().alphaValue = 0.9
        }
    }

    /// Hide the toolbar with animation.
    func hide() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            self.animator().alphaValue = 0.3
        }
    }
}
