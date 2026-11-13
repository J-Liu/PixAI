// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import UniformTypeIdentifiers

/// A semi-transparent toolbar that auto-hides (dims) when not hovered.
/// Layout (left → right):
/// [◀] | [save] [crop] | [⇅] [⇆] [↻] [↺] | [▶/⏸] | [enhance] [dewatermark] [upscale] [dedup] | [delete] [exit] | [▶]
class AutoHideToolbar: NSView {
    let leftButton: NSButton
    let rightButton: NSButton
    let zoomInButton: NSButton
    let zoomOutButton: NSButton
    let fitToggleButton: NSButton
    let cropButton: NSButton
    let aiEnhanceQualityButton: NSButton
    let aiDewatermarkButton: NSButton
    let aiUpscaleButton: NSButton
    let aiDedupButton: NSButton
    let playPauseButton: NSButton
    let rotateClockwiseButton: NSButton
    let rotateCounterclockwiseButton: NSButton
    let flipHorizontalButton: NSButton
    let flipVerticalButton: NSButton
    let saveButton: NSButton
    let deleteButton: NSButton
    let exitButton: NSButton
    private let leftDivider: NSView
    private let flipGroupDivider: NSView
    private let rotateGroupDivider: NSView
    private let zoomGroupDivider: NSView
    private let aiGroupLeftDivider: NSView
    private let saveGroupDivider: NSView
    private let exitGroupDivider: NSView

    private var isHovered = false
    /// Whether images are loaded (affects default visibility)
    private var hasImages = false
    /// Force toolbar to stay visible (for unsupported format case)
    private var forceVisible = false
    private let onLeftTap: () -> Void
    private let onRightTap: () -> Void
    private let onZoomInTap: () -> Void
    private let onZoomOutTap: () -> Void
    private let onFitToggleTap: () -> Void
    private let onCropTap: () -> Void
    private let onAIEnhanceQualityTap: () -> Void
    private let onAIDewatermarkTap: () -> Void
    private let onAIUpscaleTap: () -> Void
    private let onAIDedupTap: () -> Void
    private let onPlayPauseTap: () -> Void
    private let onRotateClockwiseTap: () -> Void
    private let onRotateCounterclockwiseTap: () -> Void
    private let onFlipHorizontalTap: () -> Void
    private let onFlipVerticalTap: () -> Void
    private let onSaveTap: () -> Void
    private let onDeleteTap: () -> Void
    private let onExitTap: () -> Void
    private var l10nObserver: NSObjectProtocol?

    /// Called when toolbar visibility changes due to hover (true = visible, false = hidden).
    var onVisibilityChange: ((Bool) -> Void)?

    /// When false, hover activation is disabled (for crop/watermark selection).
    var hoverEnabled: Bool = true {
        didSet {
            if !hoverEnabled && isHovered {
                // Force hide if currently hovered
                isHovered = false
                onVisibilityChange?(false)
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.15
                    self.animator().alphaValue = AppConfig.shared.toolbarHiddenAlpha
                }
            }
        }
    }

    /// The color for the toolbar buttons (bright orange).
    static let buttonColor = NSColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1.0) // Bright orange

    /// The background color of the toolbar (semi-transparent dark).
    static let toolbarColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.6)

    /// The height of the toolbar.
    static let toolbarHeight: CGFloat = 72

    /// SF Symbol shown while the next click will "fit to window".
    static let fitIconName = "arrow.down.left.and.arrow.up.right"
    /// SF Symbol shown while the next click will switch to 100% (1:1) size.
    static let hundredPercentIconName = "1.square"
    /// SF Symbol shown while the slideshow is playing (next click pauses).
    static let pauseIconName = "pause.fill"
    /// SF Symbol shown while stopped or paused (next click plays/resumes).
    static let playIconName = "play.fill"

    // AI button icons: each pair is (action icon, restore icon); the icon always
    // depicts what the NEXT click will do.
    static let aiEnhanceQualityIconName = "sparkles"
    static let aiRestoreIconName = "arrow.uturn.backward"
    static let aiDewatermarkIconName = "eraser.fill"
    static let aiUpscaleIconName = "arrow.up.left.and.arrow.down.right"
    static let aiDeUpscaleIconName = "arrow.down.right.and.arrow.up.left"
    static let aiDedupIconName = "rectangle.stack.badge.minus"

    init(onLeftTap: @escaping () -> Void,
         onRightTap: @escaping () -> Void,
         onZoomInTap: @escaping () -> Void,
         onZoomOutTap: @escaping () -> Void,
         onFitToggleTap: @escaping () -> Void,
         onCropTap: @escaping () -> Void,
         onAIEnhanceQualityTap: @escaping () -> Void,
         onAIDewatermarkTap: @escaping () -> Void,
         onAIUpscaleTap: @escaping () -> Void,
         onAIDedupTap: @escaping () -> Void,
         onPlayPauseTap: @escaping () -> Void,
         onRotateClockwiseTap: @escaping () -> Void,
         onRotateCounterclockwiseTap: @escaping () -> Void,
         onFlipHorizontalTap: @escaping () -> Void,
         onFlipVerticalTap: @escaping () -> Void,
         onSaveTap: @escaping () -> Void,
         onDeleteTap: @escaping () -> Void,
         onExitTap: @escaping () -> Void) {
        self.onLeftTap = onLeftTap
        self.onRightTap = onRightTap
        self.onZoomInTap = onZoomInTap
        self.onZoomOutTap = onZoomOutTap
        self.onFitToggleTap = onFitToggleTap
        self.onCropTap = onCropTap
        self.onAIEnhanceQualityTap = onAIEnhanceQualityTap
        self.onAIDewatermarkTap = onAIDewatermarkTap
        self.onAIUpscaleTap = onAIUpscaleTap
        self.onAIDedupTap = onAIDedupTap
        self.onPlayPauseTap = onPlayPauseTap
        self.onRotateClockwiseTap = onRotateClockwiseTap
        self.onRotateCounterclockwiseTap = onRotateCounterclockwiseTap
        self.onFlipHorizontalTap = onFlipHorizontalTap
        self.onFlipVerticalTap = onFlipVerticalTap
        self.onSaveTap = onSaveTap
        self.onDeleteTap = onDeleteTap
        self.onExitTap = onExitTap
        leftButton = NSButton()
        rightButton = NSButton()
        zoomInButton = NSButton()
        zoomOutButton = NSButton()
        fitToggleButton = NSButton()
        cropButton = NSButton()
        aiEnhanceQualityButton = NSButton()
        aiDewatermarkButton = NSButton()
        aiUpscaleButton = NSButton()
        aiDedupButton = NSButton()
        playPauseButton = NSButton()
        rotateClockwiseButton = NSButton()
        rotateCounterclockwiseButton = NSButton()
        flipHorizontalButton = NSButton()
        flipVerticalButton = NSButton()
        saveButton = NSButton()
        deleteButton = NSButton()
        exitButton = NSButton()
        // Thin vertical dividers (must be set before super.init, as they are
        // stored `let` properties).
        leftDivider = Self.makeDivider()
        flipGroupDivider = Self.makeDivider()
        rotateGroupDivider = Self.makeDivider()
        zoomGroupDivider = Self.makeDivider()
        aiGroupLeftDivider = Self.makeDivider()
        saveGroupDivider = Self.makeDivider()
        exitGroupDivider = Self.makeDivider()
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
        configureButton(cropButton, symbolName: "crop")
        configureButton(aiEnhanceQualityButton, symbolName: Self.aiEnhanceQualityIconName)
        configureButton(aiDewatermarkButton, symbolName: Self.aiDewatermarkIconName)
        configureButton(aiUpscaleButton, symbolName: Self.aiUpscaleIconName)
        configureButton(aiDedupButton, symbolName: Self.aiDedupIconName)
        configureButton(playPauseButton, symbolName: Self.playIconName)
        configureButton(rotateClockwiseButton, symbolName: "arrow.clockwise")
        configureButton(rotateCounterclockwiseButton, symbolName: "arrow.counterclockwise")
        configureButton(flipHorizontalButton, symbolName: "arrow.left.arrow.right")
        configureButton(flipVerticalButton, symbolName: "arrow.up.arrow.down")
        configureButton(saveButton, symbolName: "square.and.arrow.down")
        configureButton(deleteButton, symbolName: "trash")
        configureButton(exitButton, symbolName: "power")

        addSubview(leftButton)
        addSubview(leftDivider)
        addSubview(saveButton)
        addSubview(cropButton)
        addSubview(flipGroupDivider)
        addSubview(flipVerticalButton)
        addSubview(flipHorizontalButton)
        addSubview(rotateClockwiseButton)
        addSubview(rotateCounterclockwiseButton)
        addSubview(rotateGroupDivider)
        addSubview(playPauseButton)
        addSubview(zoomGroupDivider)
        addSubview(aiEnhanceQualityButton)
        addSubview(aiDewatermarkButton)
        addSubview(aiUpscaleButton)
        addSubview(aiDedupButton)
        addSubview(aiGroupLeftDivider)
        addSubview(deleteButton)
        addSubview(exitButton)
        addSubview(saveGroupDivider)
        addSubview(rightButton)

        refreshTooltips()

        // Keep tooltips in sync with the active UI language.
        self.l10nObserver = NotificationCenter.default.addObserver(
            forName: L10n.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshTooltips()
        }

        // Start hidden by default (no images loaded yet)
        self.alphaValue = 0.9
    }

    deinit {
        if let observer = l10nObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Localized hover tooltips for every button (English keys → L10n).
    func refreshTooltips() {
        let t = L10n.shared.t
        leftButton.toolTip = t("Previous image")
        rightButton.toolTip = t("Next image")
        flipVerticalButton.toolTip = t("Flip vertical")
        flipHorizontalButton.toolTip = t("Flip horizontal")
        rotateClockwiseButton.toolTip = t("Rotate clockwise (R)")
        rotateCounterclockwiseButton.toolTip = t("Rotate counterclockwise (Cmd+R)")
        zoomInButton.toolTip = t("Zoom in")
        zoomOutButton.toolTip = t("Zoom out")
        fitToggleButton.toolTip = t("Fit to window / 100%")
        cropButton.toolTip = t("Crop")
        playPauseButton.toolTip = t("Play/Pause (Space)")
        aiEnhanceQualityButton.toolTip = t("AI quality enhance")
        aiDewatermarkButton.toolTip = t("AI dewatermark")
        aiUpscaleButton.toolTip = t("AI super-resolution")
        aiDedupButton.toolTip = t("AI dedup")
        saveButton.toolTip = t("Save (overwrite)")
        deleteButton.toolTip = t("Delete (move to Trash)")
        exitButton.toolTip = t("Exit")
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
        applySymbol(name, to: fitToggleButton)
    }

    /// Switch the play/pause button's icon. `showsPause` == true means the
    /// slideshow is playing (the icon depicts pause, the next click pauses);
    /// false means it is stopped or paused (the icon depicts play).
    func setPlayPauseShowsPauseIcon(_ showsPause: Bool) {
        let name = showsPause ? Self.pauseIconName : Self.playIconName
        applySymbol(name, to: playPauseButton)
    }

    // MARK: - AI button state

    /// `applied` == true → the transform is on; show the "restore" icon (what
    /// the next click will do). false → show the action icon.
    func setAIEnhanceQualityApplied(_ applied: Bool) {
        applySymbol(applied ? Self.aiRestoreIconName : Self.aiEnhanceQualityIconName, to: aiEnhanceQualityButton)
    }

    func setAIDewatermarkApplied(_ applied: Bool) {
        applySymbol(applied ? Self.aiRestoreIconName : Self.aiDewatermarkIconName, to: aiDewatermarkButton)
    }

    func setAIUpscaleApplied(_ applied: Bool) {
        applySymbol(applied ? Self.aiDeUpscaleIconName : Self.aiUpscaleIconName, to: aiUpscaleButton)
    }

    /// Enable/disable the model-backed AI buttons (disabled when the model
    /// plugin is not downloaded/enabled). The one-click button stays enabled;
    /// it reports missing models itself.
    func setAIModelButtonsEnabled(upscaleAvailable: Bool, dewatermarkAvailable: Bool) {
        aiUpscaleButton.isEnabled = upscaleAvailable
        aiDewatermarkButton.isEnabled = dewatermarkAvailable
    }

    /// Enable/disable all AI buttons (e.g., for GIF format).
    func setAllAIButtonsEnabled(_ enabled: Bool) {
        aiEnhanceQualityButton.isEnabled = enabled
        aiDedupButton.isEnabled = enabled
        // These will be overridden by setAIModelButtonsEnabled for model-backed buttons
        aiUpscaleButton.isEnabled = enabled
        aiDewatermarkButton.isEnabled = enabled
    }

    private func applySymbol(_ name: String, to button: NSButton) {
        let config = NSImage.SymbolConfiguration(pointSize: 32, weight: .semibold)
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            image.isTemplate = true
            button.image = image
        }
    }

    private func configureButton(_ button: NSButton, symbolName: String) {
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.title = ""

        // Orange-tinted template SF Symbol.
        let config = NSImage.SymbolConfiguration(pointSize: 32, weight: .semibold)
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
    /// [◀] | [save] [crop] | [⇅] [⇆] [↻] [↺] | [▶/⏸] | [enhance] [dewatermark] [upscale] [dedup] | [delete] [exit] | [▶]
    override func layout() {
        super.layout()

        let buttonSize: CGFloat = 53
        let gap: CGFloat = 13
        let dividerW: CGFloat = 1
        let dividerH: CGFloat = 30
        let dividerPad: CGFloat = 12
        let saveCropGroupWidth = buttonSize * 2 + gap
        let flipRotateGroupWidth = buttonSize * 4 + gap * 3
        let aiGroupWidth = buttonSize * 4 + gap * 3
        let deleteExitGroupWidth = buttonSize * 2 + gap
        let totalWidth = buttonSize
            + dividerPad + dividerW + dividerPad + saveCropGroupWidth
            + dividerPad + dividerW + dividerPad + flipRotateGroupWidth
            + dividerPad + dividerW + dividerPad + buttonSize
            + dividerPad + dividerW + dividerPad + aiGroupWidth
            + dividerPad + dividerW + dividerPad + deleteExitGroupWidth
            + dividerPad + dividerW + dividerPad + buttonSize

        var x = (bounds.width - totalWidth) / 2
        let y = (bounds.height - buttonSize) / 2

        // [◀]
        leftButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        x += buttonSize + dividerPad
        leftDivider.frame = NSRect(x: x, y: (bounds.height - dividerH) / 2, width: dividerW, height: dividerH)
        x += dividerW + dividerPad

        // [save] [crop]
        saveButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        x += buttonSize + gap
        cropButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        x += buttonSize + dividerPad
        flipGroupDivider.frame = NSRect(x: x, y: (bounds.height - dividerH) / 2, width: dividerW, height: dividerH)
        x += dividerW + dividerPad

        // [⇅] [⇆] [↻] [↺]
        flipVerticalButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        x += buttonSize + gap
        flipHorizontalButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        x += buttonSize + gap
        rotateClockwiseButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        x += buttonSize + gap
        rotateCounterclockwiseButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        x += buttonSize + dividerPad
        rotateGroupDivider.frame = NSRect(x: x, y: (bounds.height - dividerH) / 2, width: dividerW, height: dividerH)
        x += dividerW + dividerPad

        // [▶/⏸]
        playPauseButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        x += buttonSize + dividerPad
        zoomGroupDivider.frame = NSRect(x: x, y: (bounds.height - dividerH) / 2, width: dividerW, height: dividerH)
        x += dividerW + dividerPad

        // [enhance] [dewatermark] [upscale] [dedup]
        aiEnhanceQualityButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        x += buttonSize + gap
        aiDewatermarkButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        x += buttonSize + gap
        aiUpscaleButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        x += buttonSize + gap
        aiDedupButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        x += buttonSize + dividerPad
        aiGroupLeftDivider.frame = NSRect(x: x, y: (bounds.height - dividerH) / 2, width: dividerW, height: dividerH)
        x += dividerW + dividerPad

        // [delete] [exit]
        deleteButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        x += buttonSize + gap
        exitButton.frame = NSRect(x: x, y: y, width: buttonSize, height: buttonSize)
        x += buttonSize + dividerPad
        saveGroupDivider.frame = NSRect(x: x, y: (bounds.height - dividerH) / 2, width: dividerW, height: dividerH)
        x += dividerW + dividerPad

        // [▶]
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
        } else if sender == cropButton {
            onCropTap()
        } else if sender == aiEnhanceQualityButton {
            guard sender.isEnabled else { return }
            onAIEnhanceQualityTap()
        } else if sender == aiDewatermarkButton {
            guard sender.isEnabled else { return }
            onAIDewatermarkTap()
        } else if sender == aiUpscaleButton {
            guard sender.isEnabled else { return }
            onAIUpscaleTap()
        } else if sender == aiDedupButton {
            onAIDedupTap()
        } else if sender == playPauseButton {
            onPlayPauseTap()
        } else if sender == rotateClockwiseButton {
            onRotateClockwiseTap()
        } else if sender == rotateCounterclockwiseButton {
            onRotateCounterclockwiseTap()
        } else if sender == flipHorizontalButton {
            onFlipHorizontalTap()
        } else if sender == flipVerticalButton {
            onFlipVerticalTap()
        } else if sender == saveButton {
            onSaveTap()
        } else if sender == deleteButton {
            onDeleteTap()
        } else if sender == exitButton {
            onExitTap()
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
        guard hoverEnabled else { return }
        // Don't change visibility when force visible
        guard !forceVisible else { return }
        // Only trigger hover behavior when images are loaded
        guard hasImages else { return }
        isHovered = true
        onVisibilityChange?(true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().alphaValue = 0.9
        }
    }

    override func mouseExited(with event: NSEvent) {
        // Don't change visibility when force visible
        guard !forceVisible else { return }
        // Only trigger auto-hide when images are loaded
        guard hasImages else { return }
        isHovered = false
        onVisibilityChange?(false)
        let hiddenAlpha = AppConfig.shared.toolbarHiddenAlpha
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            self.animator().alphaValue = hiddenAlpha
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
        let hiddenAlpha = AppConfig.shared.toolbarHiddenAlpha
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            self.animator().alphaValue = hiddenAlpha
        }
    }

    /// Set the default visibility based on whether images are loaded.
    /// - When no images: toolbar is visible by default
    /// - When images loaded: toolbar is hidden by default, appears on hover
    func setHasImages(_ hasImages: Bool) {
        self.hasImages = hasImages
        // Only update if not currently hovered and not forced visible
        guard !isHovered && !forceVisible else { return }
        let hiddenAlpha = AppConfig.shared.toolbarHiddenAlpha
        if hasImages {
            // Images loaded: start hidden
            self.alphaValue = hiddenAlpha
        } else {
            // No images: start visible
            self.alphaValue = 0.9
        }
    }

    /// Force toolbar to stay visible (for unsupported format case).
    /// When true, hover events are ignored and toolbar stays at 0.9 alpha.
    func setForceVisible(_ force: Bool) {
        self.forceVisible = force
        if force {
            // Force visible: set to full opacity
            self.alphaValue = 0.9
        } else {
            // Resume normal behavior
            let hiddenAlpha = AppConfig.shared.toolbarHiddenAlpha
            if hasImages && !isHovered {
                self.alphaValue = hiddenAlpha
            }
        }
    }
}
