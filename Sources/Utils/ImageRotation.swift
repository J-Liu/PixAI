import AppKit
import CoreGraphics

extension NSImage {
    /// The CGImage backing the first representation, or a rasterized fallback at
    /// the image's point size (for representations that expose no CGImage).
    var sourceCGImage: CGImage? {
        if let rep = representations.first {
            var rect = NSRect.zero
            if let cg = rep.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
                return cg
            }
        }
        guard size.width > 0, size.height > 0 else { return nil }
        let w = max(1, Int(size.width.rounded()))
        let h = max(1, Int(size.height.rounded()))
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsCtx
        draw(in: NSRect(x: 0, y: 0, width: w, height: h))
        NSGraphicsContext.restoreGraphicsState()
        return ctx.makeImage()
    }

    /// A copy of this image rotated by `degrees` clockwise (as seen on screen).
    /// Only multiples of 90 are meaningful; any value is normalized to one.
    /// Returns self unchanged for 0°. The rotation is an exact pixel rearrangement
    /// (no interpolation), so quality is never degraded.
    func rotatedClockwise(by degrees: Int) -> NSImage? {
        let normalized = ((degrees % 360) + 360) % 360
        guard normalized != 0 else { return self }
        guard let src = sourceCGImage else { return nil }

        let w = src.width
        let h = src.height
        let swap = (normalized == 90 || normalized == 270)
        let outW = swap ? h : w
        let outH = swap ? w : h

        guard let ctx = CGContext(
            data: nil, width: outW, height: outH,
            bitsPerComponent: src.bitsPerComponent, bytesPerRow: 0,
            space: src.colorSpace ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.interpolationQuality = .none
        // Screen-space clockwise == negative angle in CG's y-up coordinate space.
        ctx.translateBy(x: CGFloat(outW) / 2, y: CGFloat(outH) / 2)
        ctx.rotate(by: -CGFloat(normalized) * .pi / 180.0)
        ctx.draw(src, in: CGRect(x: -CGFloat(w) / 2, y: -CGFloat(h) / 2, width: CGFloat(w), height: CGFloat(h)))

        guard let result = ctx.makeImage() else { return nil }
        return NSImage(cgImage: result, size: NSSize(width: outW, height: outH))
    }
}
