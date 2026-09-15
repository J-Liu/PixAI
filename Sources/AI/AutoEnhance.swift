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

    /// Apply auto-enhancement with subtle, natural adjustments.
    static func enhance(_ cgImage: CGImage) -> CGImage? {
        let input = CIImage(cgImage: cgImage)
        var current = input
        
        // 1. Slight vibrance boost - very subtle color enhancement
        if let vibrance = CIFilter(name: "CIVibrance") {
            vibrance.setValue(current, forKey: kCIInputImageKey)
            vibrance.setValue(0.15, forKey: kCIInputAmountKey)
            if let output = vibrance.outputImage {
                current = output
            }
        }
        
        // 2. Slight contrast boost - improves overall tonality
        if let contrast = CIFilter(name: "CIColorControls") {
            contrast.setValue(current, forKey: kCIInputImageKey)
            contrast.setValue(1.05, forKey: kCIInputContrastKey) // 1.0 = no change
            if let output = contrast.outputImage {
                current = output
            }
        }
        
        // 3. Subtle sharpening - improve clarity without over-sharpening
        if let sharpen = CIFilter(name: "CISharpenLuminance") {
            sharpen.setValue(current, forKey: kCIInputImageKey)
            sharpen.setValue(0.1, forKey: kCIInputSharpnessKey)
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
