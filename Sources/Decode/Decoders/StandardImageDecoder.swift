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
        // For GIF, extract all frames for animation
        if format == .gif, let source = CGImageSourceCreateWithData(data as CFData, nil) {
            let frameCount = CGImageSourceGetCount(source)
            var frames: [(cgImage: CGImage, delay: TimeInterval)] = []

            for i in 0..<frameCount {
                guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
                // Get delay from GIF properties
                let delay: TimeInterval
                if let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
                   let gifProps = props[kCGImagePropertyGIFDictionary as String] as? [String: Any],
                   let delayValue = gifProps[kCGImagePropertyGIFUnclampedDelayTime as String] as? Double ?? gifProps[kCGImagePropertyGIFDelayTime as String] as? Double {
                    delay = delayValue > 0 ? delayValue : 0.1
                } else {
                    delay = 0.1
                }
                frames.append((cgImage, delay))
            }

            // Create NSImage from first frame
            if let firstFrame = frames.first {
                let image = NSImage(cgImage: firstFrame.cgImage, size: NSSize(width: firstFrame.cgImage.width, height: firstFrame.cgImage.height))
                return DecodedImage(image: image, format: format,
                                    pixelSize: image.decodedPixelSize, companionVideoURL: nil,
                                    gifFrames: frames)
            }
        }

        // Non-GIF or fallback path
        if let image = NSImage(data: data) {
            return DecodedImage(image: image, format: format,
                                pixelSize: image.decodedPixelSize, companionVideoURL: nil,
                                gifFrames: [])
        }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw DecodeError.decodeFailed("StandardImageDecoder: ImageIO could not decode \(format.displayName)")
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return DecodedImage(image: image, format: format,
                            pixelSize: image.decodedPixelSize, companionVideoURL: nil,
                            gifFrames: [])
    }
}
