// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation
import CoreML
import CoreVideo
import CoreGraphics

/// Real-ESRGAN x4 super-resolution via Core ML.
///
/// The model takes a fixed 512×512 BGRA input (`input`) and emits a 2048×2048
/// BGRA output (`activation_out`). Arbitrary image sizes are handled by tiling:
/// 512px tiles with a 64px overlap, ramp-weighted blending in the overlap zones.
/// Small images (≤512 on both sides) use a single pass with edge-replicated
/// padding so no black borders leak into the result.
final class RealESRGANEngine {
    static let shared = RealESRGANEngine()

    private let lock = NSLock()
    private var model: MLModel?

    /// Fixed model tile size (input → output).
    private let tileInput: Int = 512
    private let tileOutput: Int = 2048
    /// Overlap in input pixels (256 px in output space).
    private let overlap: Int = 64
    /// Band height in input rows for streaming the composite (bounds memory).
    private let bandInput: Int = 512

    var isAvailable: Bool {
        return PluginManager.shared.isEnabled(ModelPlugin.realesrgan)
    }

    // MARK: - Loading

    /// Compile (once, cached) and load the Core ML model. Safe to call repeatedly.
    func ensureLoaded() async throws {
        if isModelLoaded() {
            return
        }

        let plugin = ModelPlugin.realesrgan
        let mlpackageURL = plugin.localURL(forPath: "RealESRGAN_x4.mlpackage")
        guard FileManager.default.fileExists(atPath: mlpackageURL.path) else {
            throw PluginManager.PluginError.notDownloaded
        }

        // Compile to a persistent .mlmodelc cache (compileModel returns a temp path).
        let compiledURL = plugin.localDir.appendingPathComponent("RealESRGAN_x4.mlmodelc")
        if !FileManager.default.fileExists(atPath: compiledURL.path) {
            Logger.shared.log("RealESRGAN: compiling model (first run)...")
            let tmpCompiled = try await MLModel.compileModel(at: mlpackageURL)
            try FileManager.default.removeItem(at: compiledURL)
            try FileManager.default.moveItem(at: tmpCompiled, to: compiledURL)
            Logger.shared.log("RealESRGAN: compiled → \(compiledURL.path)")
        }

        let config = MLModelConfiguration()
        config.computeUnits = .all
        let loaded = try MLModel(contentsOf: compiledURL, configuration: config)

        storeModel(loaded)
        Logger.shared.log("RealESRGAN: model loaded")
    }

    private func isModelLoaded() -> Bool {
        lock.lock(); defer { lock.unlock() }
        return model != nil
    }

    private func storeModel(_ m: MLModel) {
        lock.lock(); defer { lock.unlock() }
        model = m
    }

    private func lockedModel() throws -> MLModel {
        lock.lock(); defer { lock.unlock() }
        guard let m = model else { throw PluginManager.PluginError.notDownloaded }
        return m
    }

    // MARK: - Upscale entry point

    /// Upscale `cgImage` by 4x. Synchronous; call off the main thread.
    /// `progress` (optional) receives 0.0...1.0 on the main thread.
    func upscale(_ cgImage: CGImage, progress: ((Double) -> Void)? = nil) throws -> CGImage {
        try ensureLoadedSync()
        let w = cgImage.width, h = cgImage.height
        guard w > 0, h > 0 else { throw PluginManager.PluginError.downloadFailed("empty image") }

        if w <= tileInput && h <= tileInput {
            // Single pass with edge-replicated padding.
            let padded = Self.padToSquare(cgImage, size: tileInput)
            let out = try inferTile(padded)
            guard let full = Self.bgraImage(bytes: out, width: tileOutput, height: tileOutput) else {
                throw PluginManager.PluginError.downloadFailed("tile image creation failed")
            }
            // padToSquare places the image at the bottom-left of the canvas in
            // CGImage coordinates; crop back to the 4x content region.
            let cropRect = CGRect(x: 0, y: CGFloat(tileOutput - h * 4),
                                  width: CGFloat(w * 4), height: CGFloat(h * 4))
            guard let result = full.cropping(to: cropRect) else {
                throw PluginManager.PluginError.downloadFailed("crop failed")
            }
            report(progress, 1.0)
            return result
        }

        return try upscaleTiled(cgImage, progress: progress)
    }

    /// Synchronous load used by the synchronous upscale path (the async
    /// ensureLoaded has already been awaited by callers before this runs).
    private func ensureLoadedSync() throws {
        lock.lock()
        let m = model
        lock.unlock()
        if m == nil { throw PluginManager.PluginError.notDownloaded }
    }

    // MARK: - Tiled upscale

    private func tileOrigins(_ extent: Int) -> [Int] {
        guard extent > tileInput else { return [0] }
        let stride = tileInput - overlap
        var origins: [Int] = []
        var x = 0
        while x < extent - tileInput {
            origins.append(x)
            x += stride
        }
        origins.append(extent - tileInput)
        return origins
    }

    /// Ramp weight for a position d (0..<512) inside a tile; edges that touch
    /// the image border (no neighbor tile) stay at full weight.
    private func ramp(_ d: Int, edgeFull: Bool) -> Float {
        if edgeFull { return 1 }
        if d < overlap { return Float(d) / Float(overlap) }
        if d > tileInput - overlap { return Float(tileInput - d) / Float(overlap) }
        return 1
    }

    private func upscaleTiled(_ cgImage: CGImage, progress: ((Double) -> Void)?) throws -> CGImage {
        let w = cgImage.width, h = cgImage.height
        let W = w * 4, H = h * 4

        let xs = tileOrigins(w)
        let ys = tileOrigins(h)
        let bandCount = (h + bandInput - 1) / bandInput

        // Total inference work: each tile is inferred once per band it touches.
        var totalWork = 0
        for ty in ys {
            let firstBand = ty / bandInput
            let lastBand = (ty + tileInput - 1) / bandInput
            totalWork += xs.count * (lastBand - firstBand + 1)
        }
        var doneWork = 0

        // Final canvas: W×H RGBA8.
        guard let canvas = CGContext(
            data: nil, width: W, height: H,
            bitsPerComponent: 8, bytesPerRow: W * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw PluginManager.PluginError.downloadFailed("canvas alloc failed") }

        // Cache of tile outputs (BGRA bytes) still needed by the next band.
        var tileCache: [Int: [UInt8]] = [:]   // key: ty*1000 + txIndex

        for band in 0..<bandCount {
            let by = band * bandInput
            let bh = min(bandInput, h - by)
            let outH = bh * 4

            var accum = [Float](repeating: 0, count: W * outH * 4)
            var weight = [Float](repeating: 0, count: W * outH)

            let activeYs = ys.enumerated().filter { (_, ty) in ty + tileInput > by && ty < by + bh }

            for (yi, ty) in activeYs {
                for (xi, tx) in xs.enumerated() {
                    let key = yi * 1000 + xi
                    var out: [UInt8]? = tileCache[key]
                    if out == nil {
                        let tileRect = CGRect(x: tx, y: ty, width: tileInput, height: tileInput)
                        guard let tileCG = cgImage.cropping(to: tileRect) else {
                            throw PluginManager.PluginError.downloadFailed("tile crop failed")
                        }
                        out = try inferTile(tileCG)
                        doneWork += 1
                        report(progress, Double(doneWork) / Double(totalWork))
                    }
                    guard let tileOut = out else { continue }

                    // Output rows of this tile that fall inside the current band.
                    let rowStart = max(by * 4, ty * 4)
                    let rowEnd = min((by + bh) * 4, (ty + tileInput) * 4)

                    for r in rowStart..<rowEnd {
                        let ir = r / 4 - ty                       // row inside tile (input space)
                        let topEdge = yi == 0 && ir < overlap
                        let bottomEdge = yi == ys.count - 1 && ir > tileInput - overlap
                        let wy = ramp(ir, edgeFull: topEdge || bottomEdge)
                        let bandRow = r - by * 4
                        for c in (tx * 4)..<(tx * 4 + tileOutput) {
                            let ic = c / 4 - tx                   // col inside tile (input space)
                            let leftEdge = xi == 0 && ic < overlap
                            let rightEdge = xi == xs.count - 1 && ic > tileInput - overlap
                            let wx = ramp(ic, edgeFull: leftEdge || rightEdge)
                            let wt = wx * wy
                            if wt <= 0 { continue }
                            let srcIdx = (r - ty * 4) * tileOutput * 4 + c * 4
                            let dstIdx = bandRow * W * 4 + c * 4
                            accum[dstIdx] += Float(tileOut[srcIdx]) * wt       // B
                            accum[dstIdx + 1] += Float(tileOut[srcIdx + 1]) * wt // G
                            accum[dstIdx + 2] += Float(tileOut[srcIdx + 2]) * wt // R
                            weight[bandRow * W + c] += wt
                        }
                    }
                }
            }

            // Normalize and write the band into the canvas (BGRA → RGBA).
            let canvasBase = canvas.data!.assumingMemoryBound(to: UInt8.self)
            for r in 0..<outH {
                let canvasRow = (by * 4 + r) * W * 4
                for c in 0..<W {
                    let wt = weight[r * W + c]
                    let s = r * W * 4 + c * 4
                    if wt > 0 {
                        canvasBase[canvasRow + c * 4] = UInt8(min(255, max(0, (accum[s + 2] / wt).rounded())))     // R
                        canvasBase[canvasRow + c * 4 + 1] = UInt8(min(255, max(0, (accum[s + 1] / wt).rounded()))) // G
                        canvasBase[canvasRow + c * 4 + 2] = UInt8(min(255, max(0, (accum[s] / wt).rounded())))     // B
                    } else {
                        canvasBase[canvasRow + c * 4] = 0
                        canvasBase[canvasRow + c * 4 + 1] = 0
                        canvasBase[canvasRow + c * 4 + 2] = 0
                    }
                    canvasBase[canvasRow + c * 4 + 3] = 255
                }
            }

            // Evict cached tiles that no longer touch the next band.
            let nextBandTop = (band + 1) * bandInput
            tileCache = tileCache.filter { key, _ in
                let yi = key / 1000
                let ty = ys[yi]
                return ty + tileInput > nextBandTop
            }
        }

        report(progress, 1.0)
        guard let result = canvas.makeImage() else {
            throw PluginManager.PluginError.downloadFailed("canvas makeImage failed")
        }
        return result
    }

    // MARK: - Single tile inference

    /// Run one 512×512 tile through the model; returns 2048×2048 BGRA bytes.
    private func inferTile(_ tileCG: CGImage) throws -> [UInt8] {
        let model = try lockedModel()

        // 512×512 BGRA input pixel buffer.
        var pb: CVPixelBuffer?
        let attrs = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: tileInput,
            kCVPixelBufferHeightKey as String: tileInput,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ] as CFDictionary
        guard CVPixelBufferCreate(kCFAllocatorDefault, tileInput, tileInput,
                                  kCVPixelFormatType_32BGRA, attrs, &pb) == kCVReturnSuccess,
              let pixelBuffer = pb else {
            throw PluginManager.PluginError.downloadFailed("input pixel buffer failed")
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw PluginManager.PluginError.downloadFailed("input base address failed")
        }
        let bpr = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let ctx = CGContext(
            data: base, width: tileInput, height: tileInput,
            bitsPerComponent: 8, bytesPerRow: bpr,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw PluginManager.PluginError.downloadFailed("input context failed") }
        ctx.interpolationQuality = .high
        ctx.draw(tileCG, in: CGRect(x: 0, y: 0, width: tileInput, height: tileInput))

        let provider = ESRGANInputProvider(pixelBuffer: pixelBuffer)
        let output = try model.prediction(from: provider)
        guard let outFeature = output.featureValue(for: "activation_out"),
              let outPB = outFeature.imageBufferValue else {
            throw PluginManager.PluginError.downloadFailed("missing 'activation_out' image feature")
        }

        // Copy the 2048×2048 BGRA output into a tight [UInt8] buffer.
        let ow = CVPixelBufferGetWidth(outPB)
        let oh = CVPixelBufferGetHeight(outPB)
        let obpr = CVPixelBufferGetBytesPerRow(outPB)
        var bytes = [UInt8](repeating: 0, count: ow * oh * 4)
        CVPixelBufferLockBaseAddress(outPB, [])
        defer { CVPixelBufferUnlockBaseAddress(outPB, []) }
        guard let srcBase = CVPixelBufferGetBaseAddress(outPB) else {
            throw PluginManager.PluginError.downloadFailed("output base address failed")
        }
        let srcPtr = srcBase.assumingMemoryBound(to: UInt8.self)
        for row in 0..<oh {
            let srcRow = UnsafeRawPointer(srcPtr + row * obpr)
            bytes.withUnsafeMutableBytes { dst in
                dst.baseAddress!.advanced(by: row * ow * 4).copyMemory(from: srcRow, byteCount: ow * 4)
            }
        }
        return bytes
    }

    // MARK: - Helpers

    /// Pad a small image into a `size`×`size` canvas using edge-replicated
    /// borders (the image sits at the bottom-left in context coordinates, i.e.
    /// top-left in CGImage coordinates).
    private static func padToSquare(_ image: CGImage, size: Int) -> CGImage {
        let w = image.width, h = image.height
        guard w < size || h < size else { return image }
        let space = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        // Image at bottom-left of the canvas (context origin is bottom-left;
        // makeImage rows run top-down, so it also sits at the CGImage bottom).
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

        // Edge-replicate the uncovered strips (context coordinates).
        if w < size {
            if let rightCol = image.cropping(to: CGRect(x: w - 1, y: 0, width: 1, height: h)) {
                ctx.draw(rightCol, in: CGRect(x: w, y: 0, width: size - w, height: h))
            }
        }
        if h < size {
            if let topRow = image.cropping(to: CGRect(x: 0, y: 0, width: w, height: 1)) {
                ctx.draw(topRow, in: CGRect(x: 0, y: h, width: w, height: size - h))
            }
        }
        if w < size && h < size {
            if let corner = image.cropping(to: CGRect(x: w - 1, y: 0, width: 1, height: 1)) {
                ctx.draw(corner, in: CGRect(x: w, y: h, width: size - w, height: size - h))
            }
        }

        return ctx.makeImage() ?? image
    }

    /// Build a CGImage from a tight BGRA8 buffer (row 0 = top).
    private static func bgraImage(bytes: [UInt8], width: Int, height: Int) -> CGImage? {
        guard !bytes.isEmpty else { return nil }
        // premultipliedLast + 32Little ⇒ memory byte order B,G,R,A (BGRA).
        let provider = CGDataProvider(data: Data(bytes) as CFData)
        guard let p = provider else { return nil }
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Little.rawValue),
            provider: p, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    private func report(_ progress: ((Double) -> Void)?, _ value: Double) {
        guard let progress = progress else { return }
        DispatchQueue.main.async { progress(value) }
    }
}

/// MLFeatureProvider wrapping a 512×512 BGRA pixel buffer for the `input` feature.
final class ESRGANInputProvider: NSObject, MLFeatureProvider {
    let featureNames: Set<String> = ["input"]
    private let pixelBuffer: CVPixelBuffer

    init(pixelBuffer: CVPixelBuffer) {
        self.pixelBuffer = pixelBuffer
    }

    func featureValue(for key: String) -> MLFeatureValue? {
        guard key == "input" else { return nil }
        return MLFeatureValue(pixelBuffer: pixelBuffer)
    }
}
