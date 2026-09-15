// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation
import CoreImage
import CoreGraphics

/// Automatic image enhancement using Core Image filters.
/// Applies subtle vibrance, contrast, and sharpening.
/// No model download required — always available.
enum AutoEnhance {
    static var isAvailable: Bool { return true }

    /// Apply auto-enhancement with configurable adjustments from AppConfig.
    static func enhance(_ cgImage: CGImage) -> CGImage? {
        let cfg = AppConfig.shared
        let vibrance = cfg.enhanceVibrance
        let contrast = cfg.enhanceContrast
        let sharpness = cfg.enhanceSharpness

        let input = CIImage(cgImage: cgImage)
        var current = input

        // 1. Vibrance boost
        if vibrance > 0, let vibranceFilter = CIFilter(name: "CIVibrance") {
            vibranceFilter.setValue(current, forKey: kCIInputImageKey)
            vibranceFilter.setValue(vibrance, forKey: kCIInputAmountKey)
            if let output = vibranceFilter.outputImage {
                current = output
            }
        }

        // 2. Contrast adjustment
        if abs(contrast - 1.0) > 0.001, let contrastFilter = CIFilter(name: "CIColorControls") {
            contrastFilter.setValue(current, forKey: kCIInputImageKey)
            contrastFilter.setValue(contrast, forKey: kCIInputContrastKey)
            if let output = contrastFilter.outputImage {
                current = output
            }
        }

        // 3. Sharpening
        if sharpness > 0, let sharpen = CIFilter(name: "CISharpenLuminance") {
            sharpen.setValue(current, forKey: kCIInputImageKey)
            sharpen.setValue(sharpness, forKey: kCIInputSharpnessKey)
            if let output = sharpen.outputImage {
                current = output
            }
        }

        let context = CIContext(options: nil)
        let extent = current.extent
        let renderRect = extent.isInfinite ? CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height) : extent

        return context.createCGImage(current, from: renderRect)
    }
}
