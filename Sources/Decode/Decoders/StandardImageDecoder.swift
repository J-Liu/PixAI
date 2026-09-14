// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import Foundation
import ImageIO

/// Decodes the formats ImageIO/NSImage handle natively: JPEG, PNG, GIF, BMP,
/// TIFF and HEIC (HEIF). `NSImage(data:)` is tried first (fastest path, keeps
/// all representations), with a direct CGImageSource decode as fallback.
final class StandardImageDecoder: ImageDecoder {
    let name = "standard"
    let supportedFormats: Set<ImageFormat> = [.jpeg, .png, .gif, .bmp, .tiff, .heic]

    func canDecode(_ format: ImageFormat) -> Bool {
        return supportedFormats.contains(format)
    }

    func decode(data: Data, url: URL?, format: ImageFormat) async throws -> DecodedImage {
        if let image = NSImage(data: data) {
            return DecodedImage(image: image, format: format,
                                pixelSize: image.decodedPixelSize, companionVideoURL: nil)
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw DecodeError.decodeFailed("StandardImageDecoder: ImageIO could not decode \(format.displayName)")
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return DecodedImage(image: image, format: format,
                            pixelSize: image.decodedPixelSize, companionVideoURL: nil)
    }
}
