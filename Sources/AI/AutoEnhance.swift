// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation
import CoreImage
import CoreGraphics

/// Apple's built-in automatic image enhancement (CIAutoEnhance).
/// No model download required — always available on macOS 10.15+.
enum AutoEnhance {
    static var isAvailable: Bool { return true }

    /// Apply CIAutoEnhance; returns nil when the filter produces nothing.
    static func enhance(_ cgImage: CGImage) -> CGImage? {
        let input = CIImage(cgImage: cgImage)
        let output = input.applyingFilter("CIAutoEnhance")
        let context = CIContext(options: [.cacheIntermediates: false])
        return context.createCGImage(output, from: output.extent)
    }
}
