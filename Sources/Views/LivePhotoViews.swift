// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import AVFoundation

/// Click-through container that hosts the AVPlayerLayer for a Live Photo's
/// companion video. Its frame is kept in sync with the drawn image rect by
/// ZoomableImageView, so the video follows zoom/pan exactly like the still.
final class LivePhotoOverlayView: NSView {
    private let playerLayer = AVPlayerLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // The Live Photo video is framed to match the still image, so filling
        // the drawn image rect (cropping any sub-pixel mismatch) keeps the two
        // perfectly aligned.
        playerLayer.videoGravity = .resizeAspectFill
        playerLayer.frame = bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    /// Mouse events pass through to the image view below, so zoom/pan keep
    /// working even while the video is playing on top of the still.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }
}

/// The semi-transparent Live Photo badge drawn at the bottom-left corner of the
/// image (the glyph Apple's Photos app uses). A single click plays the Live
/// Photo; clicking again while it plays stops it.
final class LivePhotoBadgeView: NSView {
    var onTap: (() -> Void)?

    /// "camera.livephoto" SF Symbol tinted white (nil if the symbol is
    /// unavailable on this OS; a concentric-rings glyph is drawn instead).
    private let symbolImage: NSImage?

    override init(frame frameRect: NSRect) {
        let config = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let raw = NSImage(systemSymbolName: "camera.livephoto", accessibilityDescription: "Live Photo")?
            .withSymbolConfiguration(config)
        symbolImage = raw.map { Self.tinted($0, with: NSColor.white.withAlphaComponent(0.95)) }
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Let a click in the badge act even when it activates the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        // Semi-transparent rounded background for visibility on any photo.
        let background = NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7)
        NSColor.black.withAlphaComponent(0.35).setFill()
        background.fill()

        // Glyph centered in the badge.
        let side: CGFloat = 16
        let rect = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        if let symbolImage {
            symbolImage.draw(in: rect)
        } else {
            // Fallback: two concentric rings (the classic Live Photo glyph).
            NSColor.white.withAlphaComponent(0.95).setStroke()
            let outer = NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1))
            outer.lineWidth = 1.5
            outer.stroke()
            let inner = NSBezierPath(ovalIn: rect.insetBy(dx: 6, dy: 6))
            inner.lineWidth = 1.5
            inner.stroke()
        }
    }

    /// Swallow the mouse-down so the image view does not start panning.
    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.contains(point), event.clickCount == 1 else { return }
        onTap?()
    }

    /// Render `image` tinted with `color` (offscreen, so the semi-transparent
    /// badge background is never affected).
    private static func tinted(_ image: NSImage, with color: NSColor) -> NSImage {
        let size = image.size
        let out = NSImage(size: size)
        out.lockFocus()
        color.set()
        let rect = NSRect(origin: .zero, size: size)
        image.draw(in: rect)
        rect.fill(using: .sourceAtop)
        out.unlockFocus()
        return out
    }
}
