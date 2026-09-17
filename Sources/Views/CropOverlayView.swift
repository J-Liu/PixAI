// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Interactive crop-rectangle overlay drawn exactly on top of the image view.
///
/// The crop rectangle is stored in IMAGE PIXEL coordinates using CGImage
/// conventions (origin at the TOP-left, y grows downward) so it can be passed
/// straight to `CGImage.cropping(to:)`. Conversion between pixel space and
/// this view's (non-flipped, y-up) coordinate space is done through two
/// closures provided by the host (`toViewRect` / `toPixelPoint`), which keep
/// the overlay decoupled from the zoom/pan state of the image view.
///
/// The user can drag the eight edge/corner handles to resize the rectangle,
/// or drag inside it to move it. The rectangle is clamped to the image bounds
/// with a minimum size.
final class CropOverlayView: NSView {
    // MARK: - State

    /// Current crop rectangle in CG image-pixel coordinates (y from top).
    private(set) var cropRectPixels: CGRect
    /// Full pixel size of the displayed image (CGImage conventions).
    let imagePixelSize: NSSize
    /// Minimum crop edge length in image pixels.
    static let minCropPixels: CGFloat = 16
    /// Whether we start with full image or drag to select
    var startWithFullImage: Bool = true

    // MARK: - Coordinate conversion (provided by the host)

    /// Convert an image-pixel rect (CG coords, y from top) to this view's coords.
    var toViewRect: ((CGRect) -> NSRect)?
    /// Convert a point in this view's coords to an image-pixel point (CG coords).
    var toPixelPoint: ((NSPoint) -> CGPoint)?

    // MARK: - Callbacks

    /// Called after every resize/move with the updated pixel rect.
    var onCropChanged: ((CGRect) -> Void)?

    // MARK: - Handles

    private enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, left, bottomLeft
    }

    private var activeHandle: Handle?
    private var isMoving = false
    private var isSelecting = false
    private var cropAtDragStart: CGRect = .zero
    private var selectStartPixel: CGPoint = .zero

    // MARK: - Init

    init(imagePixelSize: NSSize, startWithFull: Bool = true) {
        self.imagePixelSize = imagePixelSize
        self.startWithFullImage = startWithFull
        if startWithFull {
            self.cropRectPixels = CGRect(origin: .zero, size: imagePixelSize)
        } else {
            self.cropRectPixels = .zero
        }
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Geometry helpers

    private var fullRect: CGRect {
        return CGRect(x: 0, y: 0, width: imagePixelSize.width, height: imagePixelSize.height)
    }

    /// View-space rect of the current crop rectangle.
    private var cropViewRect: NSRect {
        guard let toViewRect else { return .zero }
        return toViewRect(cropRectPixels)
    }

    /// Handle anchor points in VIEW coordinates for the current crop rect.
    private func handlePoints() -> [Handle: NSPoint] {
        let r = cropViewRect
        var pts: [Handle: NSPoint] = [:]
        pts[.topLeft] = NSPoint(x: r.minX, y: r.maxY)
        pts[.top] = NSPoint(x: r.midX, y: r.maxY)
        pts[.topRight] = NSPoint(x: r.maxX, y: r.maxY)
        pts[.right] = NSPoint(x: r.maxX, y: r.midY)
        pts[.bottomRight] = NSPoint(x: r.maxX, y: r.minY)
        pts[.bottom] = NSPoint(x: r.midX, y: r.minY)
        pts[.left] = NSPoint(x: r.minX, y: r.midY)
        pts[.bottomLeft] = NSPoint(x: r.minX, y: r.minY)
        return pts
    }

    private func hitTestHandle(_ p: NSPoint, tolerance: CGFloat = 9) -> Handle? {
        for (handle, pt) in handlePoints() {
            if abs(p.x - pt.x) <= tolerance && abs(p.y - pt.y) <= tolerance {
                return handle
            }
        }
        return nil
    }

    private func cursor(for handle: Handle?) -> NSCursor {
        guard let handle else { return .arrow }
        switch handle {
        case .topLeft, .bottomRight: return .crosshair
        case .topRight, .bottomLeft: return .crosshair
        case .top, .bottom: return .resizeUpDown
        case .left, .right: return .resizeLeftRight
        }
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        // If in select mode with no rect yet, start selection
        if !startWithFullImage && cropRectPixels.isEmpty {
            isSelecting = true
            if let pixel = toPixelPoint?(p) {
                selectStartPixel = pixel
            }
            NSCursor.crosshair.set()
            return
        }

        if let handle = hitTestHandle(p) {
            activeHandle = handle
            cropAtDragStart = cropRectPixels
            NSCursor.crosshair.set()
        } else if cropViewRect.contains(p) {
            isMoving = true
            cropAtDragStart = cropRectPixels
            dragStartPixel = toPixelPoint?(p)
            NSCursor.openHand.set()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let toPixelPoint else { return }
        let p = convert(event.locationInWindow, from: nil)
        let pixel = toPixelPoint(p)

        if isSelecting {
            updateSelect(with: pixel)
        } else if isMoving {
            updateMove(with: pixel)
        } else if let handle = activeHandle {
            updateResize(handle: handle, with: pixel)
        }
    }

    private func updateSelect(with pixel: CGPoint) {
        let full = fullRect
        let minSide = Self.minCropPixels

        // Clamp pixel to image bounds
        let px = min(max(0, pixel.x), full.width)
        let py = min(max(0, pixel.y), full.height)
        let sx = min(max(0, selectStartPixel.x), full.width)
        let sy = min(max(0, selectStartPixel.y), full.height)

        // Calculate rect from start to current
        let x = min(sx, px)
        let y = min(sy, py)
        let w = abs(px - sx)
        let h = abs(py - sy)

        // Only update if above minimum size
        if w >= minSide && h >= minSide {
            setCrop(CGRect(x: x, y: y, width: w, height: h))
        }
    }

    private func updateMove(with pixel: CGPoint) {
        guard let start = dragStartPixel else { return }
        let full = fullRect
        let rect0 = cropAtDragStart
        let dx = pixel.x - start.x
        let dy = pixel.y - start.y
        let x = min(max(0, rect0.origin.x + dx), max(0, full.width - rect0.width))
        let y = min(max(0, rect0.origin.y + dy), max(0, full.height - rect0.height))
        setCrop(CGRect(x: x, y: y, width: rect0.width, height: rect0.height))
    }

    private var dragStartPixel: CGPoint?

    override func mouseUp(with event: NSEvent) {
        activeHandle = nil
        isMoving = false
        isSelecting = false
        dragStartPixel = nil
        selectStartPixel = .zero
        NSCursor.arrow.set()
    }

    private func updateResize(handle: Handle, with pixel: CGPoint) {
        let full = fullRect
        let minSide = Self.minCropPixels
        var x0 = cropAtDragStart.minX
        var y0 = cropAtDragStart.minY
        var x1 = cropAtDragStart.maxX
        var y1 = cropAtDragStart.maxY

        let px = min(max(0, pixel.x), full.width)
        let py = min(max(0, pixel.y), full.height)

        switch handle {
        case .left:      x0 = min(px, x1 - minSide)
        case .right:     x1 = max(px, x0 + minSide)
        case .top:       y0 = min(py, y1 - minSide)
        case .bottom:    y1 = max(py, y0 + minSide)
        case .topLeft:   x0 = min(px, x1 - minSide); y0 = min(py, y1 - minSide)
        case .topRight:  x1 = max(px, x0 + minSide); y0 = min(py, y1 - minSide)
        case .bottomLeft: x0 = min(px, x1 - minSide); y1 = max(py, y0 + minSide)
        case .bottomRight: x1 = max(px, x0 + minSide); y1 = max(py, y0 + minSide)
        }

        // Re-clamp against the image bounds (handles may be dragged outside).
        x0 = min(max(0, x0), full.width - minSide)
        y0 = min(max(0, y0), full.height - minSide)
        x1 = min(max(minSide, x1), full.width)
        y1 = min(max(minSide, y1), full.height)

        setCrop(CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0))
    }

    private func setCrop(_ rect: CGRect) {
        cropRectPixels = rect
        needsDisplay = true
        onCropChanged?(rect)
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        // If in select mode with no rect, show crosshair
        if !startWithFullImage && cropRectPixels.isEmpty {
            NSCursor.crosshair.set()
            return
        }

        if hitTestHandle(p) != nil {
            NSCursor.crosshair.set()
        } else if cropViewRect.contains(p) {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        // If in select mode with no rect, show instruction
        if !startWithFullImage && cropRectPixels.isEmpty {
            // Dim the entire image
            NSColor(white: 0, alpha: 0.3).setFill()
            bounds.fill()

            // Show instruction text
            let instruction = "Drag to select crop region" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.boldSystemFont(ofSize: 16),
                .foregroundColor: NSColor.white,
            ]
            let size = instruction.size(withAttributes: attrs)
            let textRect = CGRect(x: bounds.midX - size.width/2, y: bounds.midY - size.height/2, width: size.width, height: size.height)

            // Draw text background
            NSColor(calibratedRed: 0, green: 0, blue: 0, alpha: 0.7).setFill()
            let bgRect = textRect.insetBy(dx: -12, dy: -8)
            bgRect.fill()

            instruction.draw(in: textRect, withAttributes: attrs)
            return
        }

        let r = cropViewRect
        guard r.width > 0, r.height > 0 else {
            NSColor(white: 0, alpha: 0.45).setFill()
            bounds.fill()
            return
        }

        // Dim everything outside the crop rect.
        let dim = NSBezierPath()
        dim.appendRect(bounds)
        dim.appendRect(r)
        dim.windingRule = .evenOdd
        NSColor(white: 0, alpha: 0.45).setFill()
        dim.fill()

        // Rule-of-thirds grid inside the crop rect.
        NSColor(white: 1, alpha: 0.35).setStroke()
        let grid = NSBezierPath()
        for i in 1...2 {
            let gx = r.minX + r.width * CGFloat(i) / 3
            grid.move(to: NSPoint(x: gx, y: r.minY))
            grid.line(to: NSPoint(x: gx, y: r.maxY))
            let gy = r.minY + r.height * CGFloat(i) / 3
            grid.move(to: NSPoint(x: r.minX, y: gy))
            grid.line(to: NSPoint(x: r.maxX, y: gy))
        }
        grid.lineWidth = 1
        grid.stroke()

        // Crop border.
        NSColor.white.setStroke()
        let border = NSBezierPath(rect: r)
        border.lineWidth = 2
        border.stroke()

        // Handles.
        NSColor.white.setFill()
        for pt in handlePoints().values {
            let s: CGFloat = 10
            NSBezierPath(rect: NSRect(x: pt.x - s / 2, y: pt.y - s / 2, width: s, height: s)).fill()
        }

        // Size readout (image pixels) above the rectangle.
        let text = String(format: "%.0f × %.0f px", cropRectPixels.width, cropRectPixels.height)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white,
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        var tx = r.minX
        var ty = r.maxY + 6
        if ty + size.height > bounds.height { ty = r.minY - size.height - 6 }
        tx = min(max(0, tx), max(0, bounds.width - size.width))
        (text as NSString).draw(at: NSPoint(x: tx, y: ty), withAttributes: attrs)
    }
}
