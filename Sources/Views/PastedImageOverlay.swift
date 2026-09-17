// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// An overlay view for pasted images that can be selected, moved, scaled, and deleted.
class PastedImageOverlay: NSView {
    private let imageView: NSImageView
    private(set) var isSelected = false
    private let selectionBorder = NSView()

    // Resize handles
    private let handleSize: CGFloat = 10
    private var resizeHandles: [NSView] = []

    /// The image being displayed
    var image: NSImage? {
        get { imageView.image }
        set {
            imageView.image = newValue
            updateFrame()
        }
    }

    /// Original frame before transform (for undo)
    var originalFrame: CGRect = .zero

    /// Called when the overlay is deleted (Delete/Backspace key)
    var onDelete: (() -> Void)?
    /// Called when the overlay is selected
    var onSelect: (() -> Void)?
    /// Called when the overlay is moved/resized (for undo history)
    var onTransform: ((CGRect) -> Void)?

    init(image: NSImage) {
        self.imageView = NSImageView()
        self.imageView.image = image
        self.imageView.imageScaling = .scaleProportionallyUpOrDown

        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.bottomAnchor.constraint(equalTo: bottomAnchor),
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])

        // Selection border (initially hidden)
        selectionBorder.translatesAutoresizingMaskIntoConstraints = false
        selectionBorder.wantsLayer = true
        selectionBorder.layer?.borderColor = NSColor.systemBlue.cgColor
        selectionBorder.layer?.borderWidth = 2
        selectionBorder.layer?.backgroundColor = NSColor.clear.cgColor
        selectionBorder.isHidden = true
        addSubview(selectionBorder)
        NSLayoutConstraint.activate([
            selectionBorder.topAnchor.constraint(equalTo: topAnchor, constant: -2),
            selectionBorder.bottomAnchor.constraint(equalTo: bottomAnchor, constant: 2),
            selectionBorder.leadingAnchor.constraint(equalTo: leadingAnchor, constant: -2),
            selectionBorder.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 2)
        ])

        // Create resize handles
        for _ in 0..<4 {
            let handle = NSView(frame: NSRect(x: 0, y: 0, width: handleSize, height: handleSize))
            handle.wantsLayer = true
            handle.layer?.backgroundColor = NSColor.white.cgColor
            handle.layer?.borderColor = NSColor.systemBlue.cgColor
            handle.layer?.borderWidth = 1
            handle.isHidden = true
            addSubview(handle)
            resizeHandles.append(handle)
        }

        updateFrame()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func updateFrame() {
        guard let img = image else { return }
        let size = img.size
        frame = CGRect(x: frame.origin.x, y: frame.origin.y, width: size.width, height: size.height)
        originalFrame = frame
    }

    private func updateHandlePositionsInternal() {
        guard resizeHandles.count == 4 else { return }

        // Top-left
        resizeHandles[0].frame.origin = NSPoint(x: -handleSize/2, y: frame.height - handleSize/2)
        // Top-right
        resizeHandles[1].frame.origin = NSPoint(x: frame.width - handleSize/2, y: frame.height - handleSize/2)
        // Bottom-left
        resizeHandles[2].frame.origin = NSPoint(x: -handleSize/2, y: -handleSize/2)
        // Bottom-right
        resizeHandles[3].frame.origin = NSPoint(x: frame.width - handleSize/2, y: -handleSize/2)
    }

    func updateHandlePositions() {
        updateHandlePositionsInternal()
    }

    func select() {
        isSelected = true
        selectionBorder.isHidden = false
        resizeHandles.forEach { $0.isHidden = false }
        updateHandlePositionsInternal()
        onSelect?()
    }

    func deselect() {
        isSelected = false
        selectionBorder.isHidden = true
        resizeHandles.forEach { $0.isHidden = true }
    }

    // MARK: - Mouse Events

    private var isDragging = false
    private var isResizing = false
    private var activeHandle: NSView?
    private var dragStartPoint = NSPoint.zero
    private var dragStartFrame = CGRect.zero

    override func mouseDown(with event: NSEvent) {
        select()

        let point = convert(event.locationInWindow, from: nil)

        // Check if clicking on a resize handle
        for handle in resizeHandles {
            if handle.frame.contains(point) {
                isResizing = true
                activeHandle = handle
                dragStartPoint = event.locationInWindow
                dragStartFrame = frame
                return
            }
        }

        // Otherwise, start dragging
        isDragging = true
        dragStartPoint = event.locationInWindow
        dragStartFrame = frame
    }

    override func mouseDragged(with event: NSEvent) {
        let currentPoint = event.locationInWindow
        let deltaX = currentPoint.x - dragStartPoint.x
        let deltaY = currentPoint.y - dragStartPoint.y

        if isResizing, let handle = activeHandle {
            // Resize based on which handle
            // NSView coordinates: y=0 at bottom, origin is bottom-left corner
            // Window coordinates: same as NSView, so deltaY is already correct
            var newFrame = dragStartFrame

            // Top-left handle (index 0)
            if handle === resizeHandles[0] {
                newFrame.origin.x += deltaX
                newFrame.size.width -= deltaX
                newFrame.size.height += deltaY  // Drag up = taller
            }
            // Top-right handle (index 1)
            else if handle === resizeHandles[1] {
                newFrame.size.width += deltaX
                newFrame.size.height += deltaY  // Drag up = taller
            }
            // Bottom-left handle (index 2)
            else if handle === resizeHandles[2] {
                newFrame.origin.x += deltaX
                newFrame.origin.y += deltaY     // Move bottom edge
                newFrame.size.width -= deltaX
                newFrame.size.height -= deltaY  // Drag down = shorter
            }
            // Bottom-right handle (index 3)
            else if handle === resizeHandles[3] {
                newFrame.origin.y += deltaY     // Move bottom edge
                newFrame.size.width += deltaX
                newFrame.size.height -= deltaY  // Drag down = shorter
            }

            // Minimum size
            if newFrame.size.width >= 20 && newFrame.size.height >= 20 {
                frame = newFrame
                updateHandlePositionsInternal()
            }
        }
        else if isDragging {
            // Convert to superview coordinates
            if let superview = superview {
                let newOrigin = superview.convert(NSPoint(x: dragStartFrame.origin.x + deltaX, y: dragStartFrame.origin.y + deltaY), from: nil)
                frame.origin = newOrigin
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging || isResizing {
            // Record transform for undo
            if frame != dragStartFrame {
                onTransform?(dragStartFrame)
            }
        }
        isDragging = false
        isResizing = false
        activeHandle = nil
    }

    override func rightMouseDown(with event: NSEvent) {
        // Select on right-click so context menu can delete this overlay
        select()
        // Don't call super - we want to handle this ourselves
    }

    override func rightMouseUp(with event: NSEvent) {
        // Show context menu at the mouse location
        showOverlayMenu(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        // Return our own menu, not the parent's
        return createOverlayMenu()
    }

    private func showOverlayMenu(with event: NSEvent) {
        let menu = createOverlayMenu()
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func createOverlayMenu() -> NSMenu {
        let menu = NSMenu()

        let copyItem = NSMenuItem(title: "Copy", action: #selector(copyOverlay), keyEquivalent: "")
        copyItem.target = self
        menu.addItem(copyItem)

        let deleteItem = NSMenuItem(title: "Delete", action: #selector(deleteOverlay), keyEquivalent: "")
        deleteItem.target = self
        menu.addItem(deleteItem)

        return menu
    }

    @objc private func copyOverlay() {
        // Copy overlay image to clipboard
        if let image = image {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([image])
        }
    }

    @objc private func deleteOverlay() {
        onDelete?()
    }

    // MARK: - Keyboard Events

    override var acceptsFirstResponder: Bool { isSelected }

    override func keyDown(with event: NSEvent) {
        // Delete or Backspace
        if event.keyCode == 51 || event.keyCode == 117 {
            onDelete?()
            return
        }
        super.keyDown(with: event)
    }
}
