import AppKit
import UniformTypeIdentifiers

/// A semi-transparent toolbar that auto-hides (dims) when not hovered.
/// Layout: [◀] | [+] [−] [fit/100%] | [▶/⏸] | [↻] [↺] | [save] [delete] | [▶] —
/// the play/pause button sits in the middle, separated by thin vertical dividers:
/// the zoom group on its left, the rotate group and the save/delete group on
/// its right (the save+delete pair is one group with a divider to its left).
class AutoHideToolbar: NSView {
    let leftButton: NSButton
    let rightButton: NSButton
    let zoomInButton: NSButton
    let zoomOutButton: NSButton
    let fitToggleButton: NSButton
    let playPauseButton: NSButton
    let rotateClockwiseButton: NSButton
    let rotateCounterclockwiseButton: NSButton
    let saveButton: NSButton
    let deleteButton: NSButton
    private let leftDivider: NSView
    private let playDividerLeft: NSView
    private let playDividerRight: NSView
    private let saveGroupDivider: NSView
    private let rightDivider: NSView

    private var isHovered = false
    private let onLeftTap: () -> Void
    private let onRightTap: () -> Void
    private let onZoomInTap: () -> Void
    private let onZoomOutTap: () -> Void
    private let onFitToggleTap: () -> Void
    private let onPlayPauseTap: () -> Void
    private let onRotateClockwiseTap: () -> Void
    private let onRotateCounterclockwiseTap: () -> Void
    private let onSaveTap: () -> Void
    private let onDeleteTap: () -> Void

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
    /// SF Symbol shown while the slideshow is playing (next click pauses).
    static let pauseIconName = "pause.fill"
    /// SF Symbol shown while stopped or paused (next click plays/resumes).
    static let playIconName = "play.fill"

    init(onLeftTap: @escaping () -> Void,
         onRightTap: @escaping () -> Void,
         onZoomInTap: @escaping () -> Void,
         onZoomOutTap: @escaping () -> Void,
         onFitToggleTap: @escaping () -> Void,
         onPlayPauseTap: @escaping () -> Void,
         onRotateClockwiseTap: @escaping () -> Void,
         onRotateCounterclockwiseTap: @escaping () -> Void,
         onSaveTap: @escaping () -> Void,
         onDeleteTap: @escaping () -> Void) {
        self.onLeftTap = onLeftTap
        self.onRightTap = onRightTap
        self.onZoomInTap = onZoomInTap
        self.onZoomOutTap = onZoomOutTap
        self.onFitToggleTap = onFitToggleTap
        self.onPlayPauseTap = onPlayPauseTap
        self.onRotateClockwiseTap = onRotateClockwiseTap
        self.onRotateCounterclockwiseTap = onRotateCounterclockwiseTap
        self.onSaveTap = onSaveTap
        self.onDeleteTap = onDeleteTap
        leftButton = NSButton()
        rightButton = NSButton()
        zoomInButton = NSButton()
        zoomOutButton = NSButton()
        fitToggleButton = NSButton()
        playPauseButton = NSButton()
        rotateClockwiseButton = NSButton()
        rotateCounterclockwiseButton = NSButton()
        saveButton = NSButton()
        deleteButton = NSButton()
        // Thin vertical dividers (must be set before super.init, as they are
        // stored `let` properties).
        leftDivider = Self.makeDivider()
        playDividerLeft = Self.makeDivider()
        playDividerRight = Self.makeDivider()
        saveGroupDivider = Self.makeDivider()
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
        configureButton(playPauseButton, symbolName: Self.playIconName)
        configureButton(rotateClockwiseButton, symbolName: "arrow.clockwise")
        configureButton(rotateCounterclockwiseButton, symbolName: "arrow.counterclockwise")
        configureButton(saveButton, symbolName: "square.and.arrow.down")
        configureButton(deleteButton, symbolName: "trash")

        addSubview(leftButton)
        addSubview(leftDivider)
        addSubview(zoomInButton)
        addSubview(zoomOutButton)
        addSubview(fitToggleButton)
        addSubview(playDividerLeft)
        addSubview(playPauseButton)
        addSubview(playDividerRight)
        addSubview(rotateClockwiseButton)
        addSubview(rotateCounterclockwiseButton)
        addSubview(saveGroupDivider)
        addSubview(saveButton)
        addSubview(deleteButton)
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

    /// Switch the play/pause button's icon. `showsPause` == true means the
    /// slideshow is playing (the icon depicts pause, the next click pauses);
    /// false means it is stopped or paused (the icon depicts play).
    func setPlayPauseShowsPauseIcon(_ showsPause: Bool) {
        let name = showsPause ? Self.pauseIconName : Self.playIconName
        let config = NSImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            image.isTemplate = true
            playPauseButton.image = image
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

    /// Position all controls in a centered row:
    /// [◀] | [+] [−] [fit/100%] | [▶/⏸] | [↻] [↺] | [save] [delete] | [▶].
    override func layout() {
        super.layout()

        let buttonSize: CGFloat = 42
        let gap: CGFloat = 12
        let dividerW: CGFloat = 1
        let dividerH: CGFloat = 28
        let dividerPad: CGFloat = 14
        let zoomGroupWidth = buttonSize * 3 + gap * 2
        let rotateGroupWidth = buttonSize * 2 + gap
        let saveGroupWidth = buttonSize * 2 + gap
        let totalWidth = buttonSize
            + dividerPad + dividerW + dividerPad + zoomGroupWidth
            + dividerPad + dividerW + dividerPad + buttonSize
            + dividerPad + dividerW + dividerPad + rotateGroupWidth
            + dividerPad + dividerW + dividerPad + saveGroupWidth
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
        playDividerLeft.frame = NSRect(x: x, y: (bounds.height - dividerH) / 2, width: dividerW, height: dividerH)
        x += dividerW + dividerPad
        playPauseButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        x += buttonSize + dividerPad
        playDividerRight.frame = NSRect(x: x, y: (bounds.height - dividerH) / 2, width: dividerW, height: dividerH)
        x += dividerW + dividerPad
        rotateClockwiseButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        x += buttonSize + gap
        rotateCounterclockwiseButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        x += buttonSize + dividerPad
        saveGroupDivider.frame = NSRect(x: x, y: (bounds.height - dividerH) / 2, width: dividerW, height: dividerH)
        x += dividerW + dividerPad
        saveButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        x += buttonSize + gap
        deleteButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
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
        } else if sender == playPauseButton {
            onPlayPauseTap()
        } else if sender == rotateClockwiseButton {
            onRotateClockwiseTap()
        } else if sender == rotateCounterclockwiseButton {
            onRotateCounterclockwiseTap()
        } else if sender == saveButton {
            onSaveTap()
        } else if sender == deleteButton {
            onDeleteTap()
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
