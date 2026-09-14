import Foundation
import CoreGraphics
import CoreVideo
import Accelerate
import ExecuTorch

/// U2Net watermark detection (ExecuTorch, Core ML delegate) + removal.
///
/// The model expects a 320×320 RGB input with ImageNet normalization and emits
/// a 320×320 saliency mask in [0,1]. The mask is min-max normalized, resized to
/// the original image size, thresholded at 0.5, and the masked pixels are
/// removed with an onion-peel (multi-source BFS) inpaint that propagates color
/// from the surrounding non-masked region, followed by a light local blur.
final class U2NetEngine {
    static let shared = U2NetEngine()

    private let lock = NSLock()
    private var module: Module?

    /// Saliency threshold (after min-max normalization) for "is watermark".
    private let maskThreshold: Float = 0.5
    /// Masked area below this fraction of the image → treat as "no watermark".
    private let minMaskFraction: Double = 0.001

    /// ImageNet normalization constants.
    private let mean: [Float] = [0.485, 0.456, 0.406]
    private let std: [Float] = [0.229, 0.224, 0.225]

    var isAvailable: Bool {
        return PluginManager.shared.isEnabled(ModelPlugin.u2net)
    }

    // MARK: - Loading

    func ensureLoaded() throws {
        lock.lock()
        if module != nil {
            lock.unlock()
            return
        }
        lock.unlock()

        let pteURL = ModelPlugin.u2net.localURL(forPath: "u2net_coreml_all.pte")
        guard FileManager.default.fileExists(atPath: pteURL.path) else {
            throw PluginManager.PluginError.notDownloaded
        }

        let m = Module(filePath: pteURL.path)
        try m.load()

        lock.lock()
        module = m
        lock.unlock()
        Logger.shared.log("U2Net: module loaded (Core ML delegate)")
    }

    // MARK: - Watermark removal

    /// Detect and remove a watermark. Returns the cleaned image and the fraction
    /// of pixels that were masked (0 when nothing was detected).
    func removeWatermark(from cgImage: CGImage) throws -> (image: CGImage, removedFraction: Double) {
        try ensureLoaded()
        let w = cgImage.width, h = cgImage.height
        guard w > 8, h > 8 else {
            throw PluginManager.PluginError.downloadFailed("image too small")
        }

        // 1) Saliency mask at 320×320.
        let maskSmall = try predictMask(cgImage)

        // 2) Min-max normalize (the model output range is often narrow).
        var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
        for v in maskSmall {
            if v < lo { lo = v }
            if v > hi { hi = v }
        }
        let range = max(hi - lo, 1e-6)
        let normSmall = maskSmall.map { ($0 - lo) / range }

        // 3) Resize the mask to full resolution (bilinear via CGContext).
        let maskFull = Self.resizeMask(normSmall, from: 320, to: w, h: h)

        // 4) Threshold + dilate.
        var target = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) where maskFull[i] > maskThreshold {
            target[i] = true
        }
        Self.dilate(&target, width: w, height: h, radius: 2)

        let maskedCount = target.filter { $0 }.count
        let fraction = Double(maskedCount) / Double(w * h)
        if fraction < minMaskFraction {
            Logger.shared.log("U2Net: no significant watermark detected (mask \(fraction))")
            return (cgImage, 0)
        }

        // 5) Onion-peel inpaint + local smoothing.
        var pixels = Self.rgbaPixels(of: cgImage)
        Self.inpaint(&pixels, target: target, width: w, height: h)
        Self.smoothMaskedRegion(&pixels, target: target, width: w, height: h)

        guard let result = Self.cgImage(fromRGBA: pixels, width: w, height: h) else {
            throw PluginManager.PluginError.downloadFailed("result image creation failed")
        }
        Logger.shared.log("U2Net: removed watermark covering \(String(format: "%.2f%%", fraction * 100)) of the image")
        return (result, fraction)
    }

    // MARK: - Inference

    /// Run the model; returns the 320×320 saliency mask as [Float] (row-major).
    private func predictMask(_ cgImage: CGImage) throws -> [Float] {
        lock.lock()
        let m = module
        lock.unlock()
        guard let m = m else { throw PluginManager.PluginError.notDownloaded }

        // Preprocess: resize to 320x320 and normalize with ImageNet stats.
        let inputTensor = try preprocessImage(cgImage, targetSize: 320)

        // Run inference.
        let outputs = try m.forward([inputTensor])

        guard let outValue = outputs.first, let maskTensor = outValue.tensor else {
            throw PluginManager.PluginError.downloadFailed("missing tensor output")
        }

        // Extract float data from tensor.
        var maskData: [Float] = []
        maskTensor.bytes { pointer, count, dataType in
            guard dataType == .float else { return }
            let floatPtr = pointer.assumingMemoryBound(to: Float.self)
            maskData = Array(UnsafeBufferPointer(start: floatPtr, count: min(count, 320 * 320)))
        }

        guard maskData.count >= 320 * 320 else {
            throw PluginManager.PluginError.downloadFailed("unexpected mask size \(maskData.count)")
        }
        return maskData
    }

    // MARK: - Preprocessing

    /// Resize image to targetSize×targetSize and normalize with ImageNet stats.
    /// Returns a Tensor with shape [1, 3, targetSize, targetSize] (NCHW).
    private func preprocessImage(_ cgImage: CGImage, targetSize: Int) throws -> Tensor {
        // Resize to targetSize×targetSize.
        guard let ctx = CGContext(
            data: nil, width: targetSize, height: targetSize,
            bitsPerComponent: 8, bytesPerRow: targetSize * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PluginManager.PluginError.downloadFailed("context failed")
        }
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))

        guard let resizedCGImage = ctx.makeImage() else {
            throw PluginManager.PluginError.downloadFailed("resize failed")
        }

        // Get RGBA pixels.
        var rgba = [UInt8](repeating: 0, count: targetSize * targetSize * 4)
        guard let ctx2 = CGContext(
            data: &rgba, width: targetSize, height: targetSize,
            bitsPerComponent: 8, bytesPerRow: targetSize * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw PluginManager.PluginError.downloadFailed("context2 failed")
        }
        ctx2.draw(resizedCGImage, in: CGRect(x: 0, y: 0, width: targetSize, height: targetSize))

        // Convert to NCHW float tensor with ImageNet normalization.
        let n = targetSize * targetSize
        var floatData = [Float](repeating: 0, count: n * 3)

        for i in 0..<n {
            let r = Float(rgba[i * 4])
            let g = Float(rgba[i * 4 + 1])
            let b = Float(rgba[i * 4 + 2])

            // Normalize: (pixel / 255 - mean) / std
            let y = i / targetSize
            let x = i % targetSize
            let idx = y * targetSize + x

            floatData[idx] = (r / 255.0 - mean[0]) / std[0]
            floatData[n + idx] = (g / 255.0 - mean[1]) / std[1]
            floatData[2 * n + idx] = (b / 255.0 - mean[2]) / std[2]
        }

        // Create tensor with shape [1, 3, targetSize, targetSize].
        let shape: [NSNumber] = [1, 3, NSNumber(value: targetSize), NSNumber(value: targetSize)]
        return Tensor(bytes: floatData, shape: shape, dataType: .float)
    }

    // MARK: - Mask / pixel helpers (static, testable)

    /// Bilinear-resize a 320×320 [Float] mask to w×h.
    static func resizeMask(_ small: [Float], from s: Int, to w: Int, h: Int) -> [Float] {
        if w == s && h == s { return small }
        var out = [Float](repeating: 0, count: w * h)
        let sx = Float(s) / Float(w)
        let sy = Float(s) / Float(h)
        for y in 0..<h {
            let fy = (Float(y) + 0.5) * sy - 0.5
            let y0 = max(0, min(s - 1, Int(fy)))
            let y1 = max(0, min(s - 1, y0 + 1))
            let ty = max(0, min(1, fy - Float(y0)))
            for x in 0..<w {
                let fx = (Float(x) + 0.5) * sx - 0.5
                let x0 = max(0, min(s - 1, Int(fx)))
                let x1 = max(0, min(s - 1, x0 + 1))
                let tx = max(0, min(1, fx - Float(x0)))
                let v00 = small[y0 * s + x0], v01 = small[y0 * s + x1]
                let v10 = small[y1 * s + x0], v11 = small[y1 * s + x1]
                out[y * w + x] = (v00 * (1 - tx) + v01 * tx) * (1 - ty) + (v10 * (1 - tx) + v11 * tx) * ty
            }
        }
        return out
    }

    /// Binary dilation of the mask by `radius` pixels (box).
    static func dilate(_ mask: inout [Bool], width: Int, height: Int, radius: Int) {
        guard radius > 0 else { return }
        let n = width * height
        let src = mask
        for dy in -radius...radius {
            for dx in -radius...radius {
                for y in 0..<height {
                    let sy = y + dy
                    guard sy >= 0, sy < height else { continue }
                    for x in 0..<width {
                        let sx = x + dx
                        guard sx >= 0, sx < width else { continue }
                        if src[sy * width + sx] {
                            mask[y * width + x] = true
                        }
                    }
                }
            }
        }
        _ = n
    }

    /// Decode a CGImage into a tight RGBA8 [UInt8] buffer (top-left origin).
    static func rgbaPixels(of cgImage: CGImage) -> [UInt8] {
        let w = cgImage.width, h = cgImage.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return pixels }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        return pixels
    }

    /// Onion-peel inpaint: multi-source BFS from the boundary of the masked
    /// region; each filled pixel takes the average color of its already-known
    /// (non-masked or already-filled) neighbors.
    static func inpaint(_ pixels: inout [UInt8], target: [Bool], width: Int, height: Int) {
        let n = width * height
        var filled = [Bool](repeating: false, count: n)   // true once a pixel has a final color
        var queue: [Int] = []

        // Seed: masked pixels adjacent to a non-masked pixel.
        for i in 0..<n where target[i] {
            let x = i % width, y = i / width
            var isBoundary = false
            if x > 0, !target[i - 1] { isBoundary = true }
            else if x < width - 1, !target[i + 1] { isBoundary = true }
            else if y > 0, !target[i - width] { isBoundary = true }
            else if y < height - 1, !target[i + width] { isBoundary = true }
            if isBoundary {
                queue.append(i)
                filled[i] = true
            }
        }

        var head = 0
        while head < queue.count {
            let i = queue[head]
            head += 1
            let x = i % width, y = i / width
            var rSum: Double = 0, gSum: Double = 0, bSum: Double = 0, cnt: Double = 0

            // Gather from known neighbors (4-neighborhood).
            if x > 0 {
                let j = i - 1
                if !target[j] || filled[j] {
                    rSum += Double(pixels[j * 4]); gSum += Double(pixels[j * 4 + 1]); bSum += Double(pixels[j * 4 + 2]); cnt += 1
                }
            }
            if x < width - 1 {
                let j = i + 1
                if !target[j] || filled[j] {
                    rSum += Double(pixels[j * 4]); gSum += Double(pixels[j * 4 + 1]); bSum += Double(pixels[j * 4 + 2]); cnt += 1
                }
            }
            if y > 0 {
                let j = i - width
                if !target[j] || filled[j] {
                    rSum += Double(pixels[j * 4]); gSum += Double(pixels[j * 4 + 1]); bSum += Double(pixels[j * 4 + 2]); cnt += 1
                }
            }
            if y < height - 1 {
                let j = i + width
                if !target[j] || filled[j] {
                    rSum += Double(pixels[j * 4]); gSum += Double(pixels[j * 4 + 1]); bSum += Double(pixels[j * 4 + 2]); cnt += 1
                }
            }

            if cnt > 0 {
                pixels[i * 4] = UInt8(min(255, max(0, (rSum / cnt).rounded())))
                pixels[i * 4 + 1] = UInt8(min(255, max(0, (gSum / cnt).rounded())))
                pixels[i * 4 + 2] = UInt8(min(255, max(0, (bSum / cnt).rounded())))
            }

            // Enqueue masked neighbors not yet filled.
            let neighbors = [i - 1, i + 1, i - width, i + width].filter { j in
                j >= 0 && j < n && target[j] && !filled[j]
            }
            // Keep horizontal moves valid (no row wrap).
            for j in neighbors where (x == 0 ? j != i - 1 : true) && (x == width - 1 ? j != i + 1 : true) {
                if target[j] && !filled[j] {
                    filled[j] = true
                    queue.append(j)
                }
            }
        }

        // Fallback: any still-unfilled masked pixel (disconnected components
        // with no boundary, e.g. a full-frame mask) keeps its original color.
    }

    /// 3×3 box blur applied only to masked pixels (smooths inpaint seams).
    static func smoothMaskedRegion(_ pixels: inout [UInt8], target: [Bool], width: Int, height: Int) {
        let n = width * height
        var updated = pixels
        for i in 0..<n where target[i] {
            let x = i % width, y = i / width
            var rSum: Double = 0, gSum: Double = 0, bSum: Double = 0, cnt: Double = 0
            for dy in -1...1 {
                let ny = y + dy
                guard ny >= 0, ny < height else { continue }
                for dx in -1...1 {
                    let nx = x + dx
                    guard nx >= 0, nx < width else { continue }
                    let j = ny * width + nx
                    rSum += Double(pixels[j * 4]); gSum += Double(pixels[j * 4 + 1]); bSum += Double(pixels[j * 4 + 2]); cnt += 1
                }
            }
            updated[i * 4] = UInt8(min(255, max(0, (rSum / cnt).rounded())))
            updated[i * 4 + 1] = UInt8(min(255, max(0, (gSum / cnt).rounded())))
            updated[i * 4 + 2] = UInt8(min(255, max(0, (bSum / cnt).rounded())))
        }
        pixels = updated
    }

    /// Rebuild a CGImage from a tight RGBA8 buffer.
    static func cgImage(fromRGBA pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        let space = CGColorSpaceCreateDeviceRGB()
        guard !pixels.isEmpty else { return nil }
        let provider = CGDataProvider(data: Data(pixels) as CFData)
        guard let p = provider else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: space,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: p, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}