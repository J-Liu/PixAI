// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Edge navigation button with auto-hide on mouse leave and drag gesture support.
class NavigationButtonView: NSView {
    let button: NSButton
    private let isLeft: Bool
    private let onTap: () -> Void
    private let onDrag: ((CGFloat) -> Void)?

    /// Called continuously during drag with the current delta (for visual feedback).
    var onDragProgress: ((CGFloat) -> Void)?
    /// Called when drag ends (delta = 0 means cancelled/reset).
    var onDragEnd: ((CGFloat) -> Void)?

    /// Whether images are loaded (controls visibility).
    var hasImages: Bool = false {
        didSet {
            if !hasImages {
                // No images: always hide
                alphaValue = 0
                layer?.backgroundColor = NSColor(white: 0, alpha: 0).cgColor
            }
            // If hasImages is true, visibility is controlled by hover
        }
    }

    /// Whether toolbar is currently visible (higher priority).
    var toolbarIsVisible: Bool = false {
        didSet {
            if toolbarIsVisible {
                // Toolbar is visible: hide navigation buttons
                alphaValue = 0
                layer?.backgroundColor = NSColor(white: 0, alpha: 0).cgColor
            }
        }
    }

    /// When false, hover activation is disabled (for crop/watermark selection).
    var hoverEnabled: Bool = true {
        didSet {
            if !hoverEnabled && isHovered {
                // Force hide if currently hovered
                hide()
            }
        }
    }

    private var isHovered = false
    private var dragStartPoint: NSPoint?
    private var isDragging = false

    init(isLeft: Bool, onTap: @escaping () -> Void, onDrag: ((CGFloat) -> Void)? = nil) {
        self.isLeft = isLeft
        self.onTap = onTap
        self.onDrag = onDrag
        button = NSButton()

        super.init(frame: .zero)

        wantsLayer = true
        // Transparent by default, only show on hover
        layer?.backgroundColor = NSColor(white: 0, alpha: 0).cgColor

        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.title = ""

        let symbolName = isLeft ? "chevron.left" : "chevron.right"
        let config = NSImage.SymbolConfiguration(pointSize: 90, weight: .bold)
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            image.isTemplate = true
            button.image = image
        }
        button.contentTintColor = NSColor(white: 1.0, alpha: 0.9)

        button.target = self
        button.action = #selector(buttonTapped)

        addSubview(button)

        // Make button fill entire view so whole area is clickable
        button.frame = bounds
        button.autoresizingMask = [.width, .height]

        // Start fully hidden
        alphaValue = 0
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        // Button fills entire view
        button.frame = bounds
    }

    @objc private func buttonTapped() {
        onTap()
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
        for area in trackingAreas {
            removeTrackingArea(area)
        }

        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
    }

    override func mouseEntered(with event: NSEvent) {
        guard hoverEnabled else { return }
        isHovered = true
        // Only show if images are loaded AND toolbar is not visible
        guard hasImages && !toolbarIsVisible else { return }
        // Show dark background and button on hover
        layer?.backgroundColor = NSColor(white: 0, alpha: 0.4).cgColor
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            animator().alphaValue = 1.0
        }
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        if !isDragging {
            hide()
        }
    }

    /// Show with animation.
    func show() {
        // Don't show unless hovered
    }

    /// Hide with animation.
    func hide() {
        layer?.backgroundColor = NSColor(white: 0, alpha: 0).cgColor
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            animator().alphaValue = 0
        }
    }

    // MARK: - Drag gesture support

    override func mouseDown(with event: NSEvent) {
        dragStartPoint = event.locationInWindow
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let startPoint = dragStartPoint else { return }
        let currentPoint = event.locationInWindow
        let deltaX = currentPoint.x - startPoint.x

        // Start drag after 5px threshold
        if abs(deltaX) > 5 {
            isDragging = true
            // Visual feedback - fade the button
            alphaValue = max(0.3, 0.8 - abs(deltaX) / 200.0)
            // Report drag progress for visual image movement
            onDragProgress?(deltaX)
        }
    }

    override func mouseUp(with event: NSEvent) {
        guard let startPoint = dragStartPoint else { return }
        let currentPoint = event.locationInWindow
        let deltaX = currentPoint.x - startPoint.x

        if isDragging {
            // Trigger navigation if dragged enough (> 50px)
            if abs(deltaX) > 50 {
                onDrag?(deltaX)
                onDragEnd?(deltaX)
            } else {
                // Reset if not dragged enough
                onDragEnd?(0)
            }
        }

        dragStartPoint = nil
        isDragging = false

        // Restore alpha
        if isHovered {
            show()
        } else {
            hide()
        }
    }
}
