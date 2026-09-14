// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import CoreImage
import Foundation

/// Decodes camera RAW files (CR2/CR3, NEF/NRW, ARW/SR2, DNG, RW2, SRW, ORF,
/// RAF, X3F, …) through Core Image.
///
/// `CIImage(contentsOf:)` ships built-in decoders for the common camera RAW
/// formats (unlike ImageIO, which has no RAW pixel decoder), applying the
/// embedded color profile and orientation. A single shared `CIContext` is
/// reused — creating one is expensive (GPU allocation).
final class RAWImageDecoder: ImageDecoder {
    let name = "raw-coreimage"
    let supportedFormats: Set<ImageFormat> = [.raw]

    /// Shared rendering context (expensive to create, safe to reuse).
    private static let context = CIContext()

    func canDecode(_ format: ImageFormat) -> Bool {
        return format == .raw
    }

    func decode(data: Data, url: URL?, format: ImageFormat) async throws -> DecodedImage {
        var options: [CIImageOption: Any] = [:]
        options[.applyOrientationProperty] = true

        // Prefer the file URL (Core Image reads RAWs most reliably from disk);
        // fall back to in-memory data when no URL is available.
        let ciImage: CIImage?
        if let url = url {
            ciImage = CIImage(contentsOf: url, options: options)
        } else {
            ciImage = CIImage(data: data, options: options)
        }
        guard let ciImage = ciImage else {
            throw DecodeError.decodeFailed("RAWImageDecoder: Core Image could not open RAW file")
        }

        let extent = ciImage.extent
        guard extent.width > 0, extent.height > 0,
              let cgImage = Self.context.createCGImage(ciImage, from: extent) else {
            throw DecodeError.decodeFailed("RAWImageDecoder: Core Image produced no pixels")
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return DecodedImage(image: image, format: .raw,
                            pixelSize: NSSize(width: cgImage.width, height: cgImage.height),
                            companionVideoURL: nil)
    }
}
