// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation
import CoreGraphics
import CoreML
import Accelerate
import CoreImage
import Vision

/// LaMa inpainting model (Core ML).
///
/// Takes an image and a binary mask, outputs an inpainted image where masked
/// regions are filled with plausible content based on surrounding context.
final class LaMaEngine {
    static let shared = LaMaEngine()

    private let lock = NSLock()
    private var model: MLModel?

    /// Cancellation flag checked during inference.
    var isCancelled: Bool = false

    var isAvailable: Bool {
        return PluginManager.shared.isEnabled(ModelPlugin.lama)
    }

    // MARK: - Loading

    func ensureLoaded() throws {
        lock.lock()
        if model != nil {
            lock.unlock()
            return
        }
        lock.unlock()

        let modelURL = ModelPlugin.lama.localURL(forPath: "LaMa.mlpackage")
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw PluginManager.PluginError.notDownloaded
        }

        let compiledURL = try MLModel.compileModel(at: modelURL)
        let loadedModel = try MLModel(contentsOf: compiledURL)

        lock.lock()
        model = loadedModel
        lock.unlock()
        Logger.shared.log("LaMa: Core ML model loaded")
    }

    // MARK: - Inpainting

    /// Inpaint masked regions in the image.
    /// - Parameters:
    ///   - cgImage: Input image
    ///   - mask: Binary mask where true = pixels to inpaint
    /// - Returns: Inpainted image
    func inpaint(image cgImage: CGImage, mask: [Bool]) throws -> CGImage {
        isCancelled = false
        try ensureLoaded()
        guard !isCancelled else {
            throw CancellationError()
        }

        let w = cgImage.width, h = cgImage.height
        guard w > 8, h > 8 else {
            throw PluginManager.PluginError.downloadFailed("image too small")
        }

        // Apply feather to mask edges if configured
        // DISABLED: featherMask function is buggy - it expands from ALL non-mask pixels,
        // which causes the mask to cover the entire image when mask coverage is > 50%
        // TODO: Fix featherMask to only expand from mask boundary pixels
        let processedMask = mask

        // Debug: check mask before feathering
        let trueCountBefore = processedMask.filter { $0 }.count
        Logger.shared.log("LaMa: mask coverage = \(Double(trueCountBefore) / Double(w * h) * 100)%")

        // Get model input size (LaMa uses 800x800)
        let modelSize = 800

        // Prepare inputs: image and mask as CGImage
        guard let inputImage = prepareImageInput(cgImage, size: modelSize),
              let inputMask = prepareMaskInput(processedMask, width: w, height: h, size: modelSize) else {
            throw PluginManager.PluginError.downloadFailed("input preparation failed")
        }

        guard !isCancelled else {
            throw CancellationError()
        }

        // Run inference
        let output = try runInference(image: inputImage, mask: inputMask, modelSize: modelSize)

        guard !isCancelled else {
            throw CancellationError()
        }

        // Post-process: resize output back to original size
        guard let result = postprocessOutput(output, originalWidth: w, originalHeight: h) else {
            throw PluginManager.PluginError.downloadFailed("output processing failed")
        }

        // Blend result with original image using the original mask
        return blendResult(result, original: cgImage, mask: processedMask, width: w, height: h)
    }

    // MARK: - Input preparation

    private func prepareImageInput(_ cgImage: CGImage, size: Int) -> CGImage? {
        Logger.shared.log("LaMa: preparing image input, original size = \(cgImage.width) x \(cgImage.height)")

        // Resize image to model size using CGContext
        guard let ctx = CGContext(
            data: nil, width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Logger.shared.log("LaMa: failed to create CGContext for resize")
            return nil
        }

        ctx.interpolationQuality = .high
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

        guard let resizedImage = ctx.makeImage() else {
            Logger.shared.log("LaMa: failed to create resized CGImage")
            return nil
        }

        return resizedImage
    }

    private func prepareMaskInput(_ mask: [Bool], width: Int, height: Int, size: Int) -> CGImage? {
        // Create grayscale mask image resized to model size
        // Map from dest (size) to src (original dimensions)
        let scaleX = Float(width) / Float(size)
        let scaleY = Float(height) / Float(size)

        var pixels = [UInt8](repeating: 0, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                // Map dest coord to src coord
                let srcX = min(Int(Float(x) * scaleX), width - 1)
                let srcY = min(Int(Float(y) * scaleY), height - 1)
                let srcIdx = srcY * width + srcX
                let val: UInt8 = (srcIdx < mask.count && mask[srcIdx]) ? 255 : 0
                pixels[y * size + x] = val
            }
        }

        // Create CGImage from grayscale pixels
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else {
            return nil
        }

        let cgImage = CGImage(
            width: size, height: size,
            bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: size,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )

        Logger.shared.log("LaMa: mask input prepared, size = \(size) x \(size)")
        return cgImage
    }

    // Create CVPixelBuffer from CGImage
    private func createPixelBuffer(from cgImage: CGImage) -> CVPixelBuffer? {
        let width = cgImage.width
        let height = cgImage.height

        // Create CVPixelBuffer with 32BGRA format (most compatible)
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let pb = pixelBuffer else {
            Logger.shared.log("LaMa: failed to create BGRA pixel buffer")
            return nil
        }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let basePtr = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)

        // Create CGContext with BGRA format
        guard let ctx = CGContext(
            data: basePtr, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        ) else {
            Logger.shared.log("LaMa: failed to create CGContext")
            return nil
        }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Debug: log input pixel values
        let ptr = basePtr.assumingMemoryBound(to: UInt8.self)
        Logger.shared.log("LaMa: INPUT PIXEL BUFFER (BGRA):")
        var row0 = ""
        for x in 0..<4 {
            let idx = x * 4
            row0 += "[B=\(ptr[idx]),G=\(ptr[idx+1]),R=\(ptr[idx+2]),A=\(ptr[idx+3])] "
        }
        Logger.shared.log("LaMa: input row 0: \(row0)")

        return pb
    }

    // Create grayscale CVPixelBuffer from CGImage
    private func createGrayscalePixelBuffer(from cgImage: CGImage) -> CVPixelBuffer? {
        let width = cgImage.width
        let height = cgImage.height

        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_OneComponent8,
            attrs as CFDictionary,
            &pixelBuffer
        )

        guard status == kCVReturnSuccess, let pb = pixelBuffer else {
            Logger.shared.log("LaMa: failed to create grayscale pixel buffer")
            return nil
        }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let basePtr = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)

        // Create grayscale context
        guard let ctx = CGContext(
            data: basePtr, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        ) else {
            return nil
        }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        Logger.shared.log("LaMa: created grayscale pixelBuffer size=\(width)x\(height)")
        return pb
    }

    // MARK: - Inference

    private func runInference(image: CGImage, mask: CGImage, modelSize: Int) throws -> CVPixelBuffer {
        lock.lock()
        guard let mlModel = model else {
            lock.unlock()
            throw PluginManager.PluginError.notDownloaded
        }
        lock.unlock()

        // Get model description
        let modelDescription = mlModel.modelDescription
        let inputNames = modelDescription.inputDescriptionsByName.keys.sorted()

        // Prepare MLMultiArray inputs
        var inputs: [String: Any] = [:]
        for name in inputNames {
            if name.lowercased().contains("image") || name.lowercased().contains("img") {
                if let array = createImageMultiArray(from: image) {
                    inputs[name] = array
                }
            } else if name.lowercased().contains("mask") {
                if let array = createMaskMultiArray(from: mask) {
                    inputs[name] = array
                }
            }
        }

        // Create feature provider and run prediction
        guard let inputProvider = try? MLDictionaryFeatureProvider(dictionary: inputs) else {
            throw PluginManager.PluginError.downloadFailed("failed to create input provider")
        }

        let prediction = try mlModel.prediction(from: inputProvider)

        // Get output
        guard let outputName = prediction.featureNames.first,
              let outputValue = prediction.featureValue(for: outputName) else {
            throw PluginManager.PluginError.downloadFailed("invalid model output")
        }

        // Convert output to CVPixelBuffer
        let outputBuffer: CVPixelBuffer
        if outputValue.type == .multiArray, let array = outputValue.multiArrayValue {
            guard let buffer = multiArrayToPixelBuffer(array) else {
                throw PluginManager.PluginError.downloadFailed("failed to convert output to pixel buffer")
            }
            outputBuffer = buffer
        } else if let buffer = outputValue.imageBufferValue {
            outputBuffer = buffer
        } else {
            throw PluginManager.PluginError.downloadFailed("unsupported output type")
        }

        return outputBuffer
    }

    // Create MLMultiArray from CGImage for image input (NCHW format)
    private func createImageMultiArray(from cgImage: CGImage) -> MLMultiArray? {
        let width = cgImage.width
        let height = cgImage.height

        // Shape: [1, 3, H, W] (batch, channels, height, width)
        let shape: [NSNumber] = [1, 3, height as NSNumber, width as NSNumber]
        guard let array = try? MLMultiArray(shape: shape, dataType: .float32) else {
            Logger.shared.log("LaMa: failed to create MLMultiArray")
            return nil
        }

        // Get RGBA pixels
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let ctx = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            Logger.shared.log("LaMa: failed to create CGContext for image array")
            return nil
        }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Fill array in NCHW format with normalized values (0-1)
        // Use CGContext coordinates directly (y=0 is bottom)
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: 3 * height * width)
        let hw = height * width

        for y in 0..<height {
            for x in 0..<width {
                let srcIdx = (y * width + x) * 4
                let r = Float(pixels[srcIdx]) / 255.0
                let g = Float(pixels[srcIdx + 1]) / 255.0
                let b = Float(pixels[srcIdx + 2]) / 255.0

                let dstIdx = y * width + x
                ptr[dstIdx] = r           // R channel
                ptr[hw + dstIdx] = g      // G channel
                ptr[2 * hw + dstIdx] = b  // B channel
            }
        }

        return array
    }

    // Create MLMultiArray from CGImage for mask input
    private func createMaskMultiArray(from cgImage: CGImage) -> MLMultiArray? {
        let width = cgImage.width
        let height = cgImage.height

        // Shape: [1, 1, H, W]
        let shape: [NSNumber] = [1, 1, height as NSNumber, width as NSNumber]
        guard let array = try? MLMultiArray(shape: shape, dataType: .float32) else {
            Logger.shared.log("LaMa: failed to create mask MLMultiArray")
            return nil
        }

        // Get grayscale pixels
        var pixels = [UInt8](repeating: 0, count: width * height)
        guard let ctx = CGContext(
            data: &pixels, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        ) else { return nil }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Fill array using CGContext coordinates directly (y=0 is bottom)
        let ptr = array.dataPointer.bindMemory(to: Float.self, capacity: height * width)
        for i in 0..<(width * height) {
            ptr[i] = Float(pixels[i]) / 255.0
        }

        return array
    }

    // Convert MLMultiArray output to CVPixelBuffer
    private func multiArrayToPixelBuffer(_ array: MLMultiArray) -> CVPixelBuffer? {
        let shape = array.shape.map { $0.intValue }

        // Expected: [1, 3, H, W] or [1, H, W, 3]
        let height: Int, width: Int
        var isNCHW = true

        if shape.count == 4 {
            if shape[1] == 3 {
                // NCHW: [1, 3, H, W]
                height = shape[2]
                width = shape[3]
                isNCHW = true
            } else if shape[3] == 3 {
                // NHWC: [1, H, W, 3]
                height = shape[1]
                width = shape[2]
                isNCHW = false
            } else {
                return nil
            }
        } else {
            return nil
        }

        // Create CVPixelBuffer
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferMetalCompatibilityKey: true
        ]
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pb = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }

        guard let basePtr = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let dstPtr = basePtr.assumingMemoryBound(to: UInt8.self)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pb)

        let srcPtr = array.dataPointer.bindMemory(to: Float.self, capacity: height * width * 3)
        let hw = height * width

        for y in 0..<height {
            for x in 0..<width {
                let dstIdx = y * bytesPerRow + x * 4
                var r: Float, g: Float, b: Float

                if isNCHW {
                    let srcIdx = y * width + x
                    r = srcPtr[srcIdx]
                    g = srcPtr[hw + srcIdx]
                    b = srcPtr[2 * hw + srcIdx]
                } else {
                    let srcIdx = (y * width + x) * 3
                    r = srcPtr[srcIdx]
                    g = srcPtr[srcIdx + 1]
                    b = srcPtr[srcIdx + 2]
                }

                // Model outputs 0-255 range, convert directly to UInt8
                dstPtr[dstIdx] = UInt8(min(max(b, 0), 255))     // B
                dstPtr[dstIdx + 1] = UInt8(min(max(g, 0), 255)) // G
                dstPtr[dstIdx + 2] = UInt8(min(max(r, 0), 255)) // R
                dstPtr[dstIdx + 3] = 255                          // A
            }
        }

        return pb
    }

    // MARK: - Output processing

    private func postprocessOutput(_ pixelBuffer: CVPixelBuffer, originalWidth: Int, originalHeight: Int) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        let ctx = CIContext()

        guard let cgImage = ctx.createCGImage(ciImage, from: ciImage.extent) else {
            Logger.shared.log("LaMa: failed to create CGImage from CIImage")
            return nil
        }

        // Resize to original dimensions
        guard let resizeCtx = CGContext(
            data: nil, width: originalWidth, height: originalHeight,
            bitsPerComponent: 8, bytesPerRow: originalWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        resizeCtx.interpolationQuality = .high
        resizeCtx.draw(cgImage, in: CGRect(x: 0, y: 0, width: originalWidth, height: originalHeight))
        return resizeCtx.makeImage()
    }

    private func blendResult(_ result: CGImage, original: CGImage, mask: [Bool], width: Int, height: Int) -> CGImage {
        var resultPixels = Self.rgbaPixels(of: result)
        let originalPixels = Self.rgbaPixels(of: original)

        // Blend: use inpainted result for masked areas, original for others
        // Alpha blend at edges for smoother transition
        for i in 0..<(width * height) {
            if mask[i] {
                // Check if this pixel is near the edge of the mask
                let x = i % width
                let y = i / width
                var neighborCount = 0
                var nonMaskNeighbors = 0

                // Check 4-connected neighbors
                if x > 0 { neighborCount += 1; if !mask[i - 1] { nonMaskNeighbors += 1 } }
                if x < width - 1 { neighborCount += 1; if !mask[i + 1] { nonMaskNeighbors += 1 } }
                if y > 0 { neighborCount += 1; if !mask[i - width] { nonMaskNeighbors += 1 } }
                if y < height - 1 { neighborCount += 1; if !mask[i + width] { nonMaskNeighbors += 1 } }

                // If near edge, blend with original for smoother transition
                if nonMaskNeighbors > 0 {
                    let alpha = 0.7 // Use 70% inpainted, 30% original at edges
                    resultPixels[i * 4] = UInt8(min(255, max(0, (Double(resultPixels[i * 4]) * alpha + Double(originalPixels[i * 4]) * (1 - alpha)).rounded())))
                    resultPixels[i * 4 + 1] = UInt8(min(255, max(0, (Double(resultPixels[i * 4 + 1]) * alpha + Double(originalPixels[i * 4 + 1]) * (1 - alpha)).rounded())))
                    resultPixels[i * 4 + 2] = UInt8(min(255, max(0, (Double(resultPixels[i * 4 + 2]) * alpha + Double(originalPixels[i * 4 + 2]) * (1 - alpha)).rounded())))
                    resultPixels[i * 4 + 3] = originalPixels[i * 4 + 3]
                }
                // Otherwise keep inpainted result
            } else {
                // Use original
                resultPixels[i * 4] = originalPixels[i * 4]
                resultPixels[i * 4 + 1] = originalPixels[i * 4 + 1]
                resultPixels[i * 4 + 2] = originalPixels[i * 4 + 2]
                resultPixels[i * 4 + 3] = originalPixels[i * 4 + 3]
            }
        }

        return Self.cgImage(fromRGBA: resultPixels, width: width, height: height)!
    }

    // MARK: - Mask feathering

    static func featherMask(_ mask: inout [Bool], width: Int, height: Int, radius: Int) {
        // Apply Gaussian-like feathering at mask edges
        var distances = [Int](repeating: Int.max, count: width * height)

        // First pass: find distances from non-masked pixels
        for i in 0..<(width * height) {
            if !mask[i] {
                distances[i] = 0
            }
        }

        // Simple distance transform approximation
        for _ in 0..<radius {
            var newDistances = distances
            for y in 0..<height {
                for x in 0..<width {
                    let i = y * width + x
                    if distances[i] == Int.max {
                        let neighbors = [
                            x > 0 ? distances[i - 1] : Int.max,
                            x < width - 1 ? distances[i + 1] : Int.max,
                            y > 0 ? distances[i - width] : Int.max,
                            y < height - 1 ? distances[i + width] : Int.max
                        ]
                        if let minNeighbor = neighbors.filter({ $0 != Int.max }).min() {
                            newDistances[i] = minNeighbor + 1
                        }
                    }
                }
            }
            distances = newDistances
        }

        // Expand mask based on distance
        for i in 0..<(width * height) {
            if distances[i] <= radius {
                mask[i] = true
            }
        }
    }

    // MARK: - Pixel helpers

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
        // Note: CGContext y=0 is bottom, so pixels[0] is bottom-left pixel
        return pixels
    }

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
