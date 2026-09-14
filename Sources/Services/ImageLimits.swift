// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Memory-management thresholds for image display (per spec).
enum ImageLimits {
    /// A single image file larger than this shows a warning dialog (50 MB).
    static let largeFileWarningBytes: Int64 = 50 * 1024 * 1024

    /// Any side at or above this many pixels: the image is shown as a
    /// downscaled thumbnail instead of the full bitmap (10 000 px).
    static let hugeImagePixelThreshold: CGFloat = 10_000

    /// Longest-side cap (px) for huge-image thumbnails.
    static let thumbnailMaxPixels: Int = 4_096
}
