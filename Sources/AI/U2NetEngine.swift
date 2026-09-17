// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation
import CoreGraphics
import CoreML
import Accelerate

/// U2Net watermark detection (Core ML) + removal.
///
/// The model expects a 320×320 RGB input with ImageNet normalization and emits
/// a 320×320 saliency mask in [0,1]. The mask is min-max normalized, resized to
/// the original image size, thresholded at the configured threshold, and the masked
/// pixels are removed with LaMa inpainting (if available) or fallback onion-peel.
final class U2NetEngine {
    static let shared = U2NetEngine()

    private let lock = NSLock()
    private var model: MLModel?

    /// Cancellation flag checked during inference.
    var isCancelled: Bool = false

    var isAvailable: Bool {
        return PluginManager.shared.isEnabled(ModelPlugin.u2net)
    }

    /// ImageNet normalization constants.
    private let mean: [Float] = [0.485, 0.456, 0.406]
    private let std: [Float] = [0.229, 0.224, 0.225]

    // MARK: - Loading

    func ensureLoaded() throws {
        lock.lock()
        if model != nil {
            lock.unlock()
            return
        }
        lock.unlock()

        let modelURL = ModelPlugin.u2net.localURL(forPath: "U2NET.mlpackage")
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw PluginManager.PluginError.notDownloaded
        }

        let compiledURL = try MLModel.compileModel(at: modelURL)
        let loadedModel = try MLModel(contentsOf: compiledURL)

        lock.lock()
        model = loadedModel
        lock.unlock()
        Logger.shared.log("U2Net: Core ML model loaded")
    }

    // MARK: - Watermark detection

    /// Detect watermark region. Returns a binary mask (true = watermark).
    /// Throws `CancellationError` if `isCancelled` is set to true during execution.
    func detectWatermark(from cgImage: CGImage) throws -> [Bool] {
        isCancelled = false
        try ensureLoaded()
        guard !isCancelled else {
            throw CancellationError()
        }

        let w = cgImage.width, h = cgImage.height
        guard w > 8, h > 8 else {
            throw PluginManager.PluginError.downloadFailed("image too small")
        }

        // Get thresholds from config
        let maskThreshold = Float(AppConfig.shared.watermarkMaskThreshold)
        let minMaskFraction = AppConfig.shared.watermarkMinMaskFraction

        // 1) Predict saliency mask at 320×320
        let maskSmall = try predictMask(cgImage)

        guard !isCancelled else {
            throw CancellationError()
        }

        // 2) Min-max normalize
        var lo = Float.greatestFiniteMagnitude, hi = -Float.greatestFiniteMagnitude
        for v in maskSmall {
            if v < lo { lo = v }
            if v > hi { hi = v }
        }
        let range = max(hi - lo, 1e-6)
        let normSmall = maskSmall.map { ($0 - lo) / range }

        // 3) Resize mask to full resolution
        let maskFull = Self.resizeMask(normSmall, from: 320, to: w, h: h)

        // 4) Threshold only (no dilation to avoid expanding into non-watermark areas)
        var target = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) where maskFull[i] > maskThreshold {
            target[i] = true
        }
        // Removed dilation - it expands mask into unwanted areas like faces

        let maskedCount = target.filter { $0 }.count
        let fraction = Double(maskedCount) / Double(w * h)
        if fraction < minMaskFraction {
            Logger.shared.log("U2Net: no significant watermark detected (mask \(fraction), threshold \(minMaskFraction))")
            return [Bool](repeating: false, count: w * h)
        }

        Logger.shared.log("U2Net: detected watermark covering \(String(format: "%.2f%%", fraction * 100)) of the image")
        return target
    }

    /// Run the model; returns the 320×320 saliency mask as [Float] (row-major).
    private func predictMask(_ cgImage: CGImage) throws -> [Float] {
        lock.lock()
        guard let model = model else {
            lock.unlock()
            throw PluginManager.PluginError.notDownloaded
        }
        lock.unlock()

        // Resize to 320x320 and get pixel data
        guard let resized = resizeImage(cgImage, to: 320),
              let pixelData = getPixelData(from: resized) else {
            throw PluginManager.PluginError.downloadFailed("resize failed")
        }

        // Create input (MLMultiArray with shape [1, 3, 320, 320])
        let inputShape: [NSNumber] = [1, 3, 320, 320]
        guard let inputArray = try? MLMultiArray(shape: inputShape, dataType: .float32) else {
            throw PluginManager.PluginError.downloadFailed("input array creation failed")
        }

        // Fill input with normalized RGB data (NCHW format)
        let ptr = inputArray.dataPointer.bindMemory(to: Float.self, capacity: 3 * 320 * 320)
        for i in 0..<320*320 {
            let r = Float(pixelData[i * 4])     // Red
            let g = Float(pixelData[i * 4 + 1]) // Green
            let b = Float(pixelData[i * 4 + 2]) // Blue
            // Normalize with ImageNet stats
            ptr[i] = (r / 255.0 - mean[0]) / std[0]           // R channel
            ptr[320 * 320 + i] = (g / 255.0 - mean[1]) / std[1] // G channel
            ptr[2 * 320 * 320 + i] = (b / 255.0 - mean[2]) / std[2] // B channel
        }

        // Run prediction
        Logger.shared.log("U2Net: input array shape = \(inputArray.shape)")
        let provider = U2NetInputProvider(input: inputArray)
        Logger.shared.log("U2Net: provider featureNames = \(provider.featureNames)")
        let output = try model.prediction(from: provider)
        guard let saliency = output.featureValue(for: "saliency")?.multiArrayValue else {
            throw PluginManager.PluginError.downloadFailed("prediction failed")
        }

        // Extract saliency map
        let shape = saliency.shape.map { $0.intValue }
        Logger.shared.log("U2Net: output shape = \(shape)")

        var maskData = [Float](repeating: 0, count: 320 * 320)
        let outPtr = saliency.dataPointer.bindMemory(to: Float.self, capacity: 320 * 320)

        var lo: Float = Float.greatestFiniteMagnitude
        var hi: Float = -Float.greatestFiniteMagnitude
        for i in 0..<320*320 {
            let val = outPtr[i]
            maskData[i] = val
            if val < lo { lo = val }
            if val > hi { hi = val }
        }
        Logger.shared.log("U2Net: output range = [\(lo), \(hi)]")

        // Normalize to [0, 1] range
        let range = max(hi - lo, 1e-6)
        return maskData.map { ($0 - lo) / range }
    }

    /// Get RGBA pixel data from a CGImage
    private func getPixelData(from cgImage: CGImage) -> [UInt8]? {
        let w = cgImage.width, h = cgImage.height
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        guard let ctx = CGContext(
            data: &pixels, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        return pixels
    }

    // MARK: - Image helpers

    private func resizeImage(_ cgImage: CGImage, to size: Int) -> CGImage? {
        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
        return ctx.makeImage()
    }

    // MARK: - Mask helpers (static)

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
}

/// MLFeatureProvider wrapping an MLMultiArray for the "image" feature.
final class U2NetInputProvider: NSObject, MLFeatureProvider {
    let featureNames: Set<String> = ["image"]
    private let input: MLMultiArray

    init(input: MLMultiArray) {
        self.input = input
    }

    func featureValue(for key: String) -> MLFeatureValue? {
        guard key == "image" else { return nil }
        return MLFeatureValue(multiArray: input)
    }
}
