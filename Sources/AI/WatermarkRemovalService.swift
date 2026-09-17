// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation
import CoreGraphics

/// Coordinates U2Net (detection) and LaMa (inpainting) for watermark removal.
final class WatermarkRemovalService {
    static let shared = WatermarkRemovalService()

    var isAvailable: Bool {
        // Need at least U2Net for detection
        return U2NetEngine.shared.isAvailable
    }

    var hasInpainting: Bool {
        return LaMaEngine.shared.isAvailable
    }

    /// Remove watermark from image.
    /// - Parameters:
    ///   - cgImage: Input image
    ///   - mode: "auto" for automatic detection, "manual" for user-selected mask
    ///   - manualMask: User-provided mask (only used in manual mode)
    /// - Returns: Cleaned image and fraction of pixels modified
    func removeWatermark(from cgImage: CGImage, mode: String = "auto", manualMask: [Bool]? = nil) throws -> (image: CGImage, removedFraction: Double) {
        let w = cgImage.width, h = cgImage.height

        // Get mask based on mode
        let mask: [Bool]
        if mode == "manual", let userMask = manualMask {
            mask = userMask
        } else {
            // Auto mode: use U2Net to detect
            mask = try U2NetEngine.shared.detectWatermark(from: cgImage)
        }

        // Check if any watermark was detected
        let maskedCount = mask.filter { $0 }.count
        let fraction = Double(maskedCount) / Double(w * h)
        if fraction == 0 {
            return (cgImage, 0)
        }

        // Inpaint using LaMa if available, otherwise use simple inpainting
        if hasInpainting {
            let result = try LaMaEngine.shared.inpaint(image: cgImage, mask: mask)
            return (result, fraction)
        } else {
            // Fallback: simple onion-peel inpainting
            var pixels = rgbaPixels(of: cgImage)
            inpaint(&pixels, target: mask, width: w, height: h)
            smoothMaskedRegion(&pixels, target: mask, width: w, height: h)

            guard let result = Self.cgImage(fromRGBA: pixels, width: w, height: h) else {
                throw PluginManager.PluginError.downloadFailed("result image creation failed")
            }
            return (result, fraction)
        }
    }

    // MARK: - Simple inpainting fallback (from U2NetEngine)

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

    static func inpaint(_ pixels: inout [UInt8], target: [Bool], width: Int, height: Int) {
        let n = width * height
        var filled = [Bool](repeating: false, count: n)
        var queue: [Int] = []

        // Seed: masked pixels adjacent to a non-masked pixel
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

            let neighbors = [i - 1, i + 1, i - width, i + width].filter { j in
                j >= 0 && j < n && target[j] && !filled[j]
            }
            for j in neighbors where (x == 0 ? j != i - 1 : true) && (x == width - 1 ? j != i + 1 : true) {
                if target[j] && !filled[j] {
                    filled[j] = true
                    queue.append(j)
                }
            }
        }
    }

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

    // Instance methods for convenience
    private func rgbaPixels(of cgImage: CGImage) -> [UInt8] {
        Self.rgbaPixels(of: cgImage)
    }

    private func cgImage(fromRGBA pixels: [UInt8], width: Int, height: Int) -> CGImage? {
        Self.cgImage(fromRGBA: pixels, width: width, height: height)
    }

    private func inpaint(_ pixels: inout [UInt8], target: [Bool], width: Int, height: Int) {
        Self.inpaint(&pixels, target: target, width: width, height: height)
    }

    private func smoothMaskedRegion(_ pixels: inout [UInt8], target: [Bool], width: Int, height: Int) {
        Self.smoothMaskedRegion(&pixels, target: target, width: width, height: height)
    }
}
