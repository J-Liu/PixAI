// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import Foundation
import ImageIO

/// Decodes Apple Live Photo pairs: the HEIF/HEIC still image plus a reference
/// to the companion .MOV (same base name, same directory).
///
/// Format detection classifies these files as `.livePhoto` BEFORE plain
/// `.heic` (see MagicNumberDetector), so this decoder is reached for every
/// Live Photo still. The UI's playback badge additionally verifies the MOV's
/// QuickTime metadata asynchronously (LivePhotoDetector).
final class LivePhotoImageDecoder: ImageDecoder {
    let name = "livephoto"
    let supportedFormats: Set<ImageFormat> = [.livePhoto]

    func canDecode(_ format: ImageFormat) -> Bool {
        return format == .livePhoto
    }

    func decode(data: Data, url: URL?, format: ImageFormat) async throws -> DecodedImage {
        // The still is a regular HEIF/JPEG image — decode it with ImageIO.
        var image: NSImage? = NSImage(data: data)
        if image == nil,
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        }
        guard let image = image else {
            throw DecodeError.decodeFailed("LivePhotoImageDecoder: could not decode the still image")
        }
        let companion = url.flatMap { MagicNumberDetector.livePhotoCompanion(for: $0) }
        return DecodedImage(image: image, format: .livePhoto,
                            pixelSize: image.decodedPixelSize,
                            companionVideoURL: companion)
    }
}
