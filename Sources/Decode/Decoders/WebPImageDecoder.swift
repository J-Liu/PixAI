// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import Foundation
import ImageIO

/// Decodes WebP images.
///
/// ImageIO ships a native WebP decoder (type identifier `org.webmproject.webp`),
/// so WebP goes through the same NSImage/CGImageSource path as other formats.
/// On a system build lacking the plugin the decode fails with a clear error
/// instead of a silent nil.
final class WebPImageDecoder: ImageDecoder {
    let name = "webp"
    let supportedFormats: Set<ImageFormat> = [.webp]

    func canDecode(_ format: ImageFormat) -> Bool {
        return format == .webp
    }

    func decode(data: Data, url: URL?, format: ImageFormat) async throws -> DecodedImage {
        // Try to detect animated WebP first
        if let source = CGImageSourceCreateWithData(data as CFData, nil) {
            let frameCount = CGImageSourceGetCount(source)
            // Animated WebP has multiple frames
            if frameCount > 1 {
                var frames: [(cgImage: CGImage, delay: TimeInterval)] = []
                for i in 0..<frameCount {
                    guard let cgImage = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
                    // Get delay from WebP properties
                    let delay: TimeInterval
                    if let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [String: Any],
                       let webpProps = props[kCGImagePropertyWebPDictionary as String] as? [String: Any] {
                        // Try unclamped delay first, then regular delay
                        if let delayValue = webpProps[kCGImagePropertyWebPUnclampedDelayTime as String] as? Double {
                            delay = delayValue > 0 ? delayValue : 0.1
                        } else if let delayValue = webpProps[kCGImagePropertyWebPDelayTime as String] as? Double {
                            delay = delayValue > 0 ? delayValue : 0.1
                        } else {
                            delay = 0.1
                        }
                    } else {
                        delay = 0.1
                    }
                    frames.append((cgImage, delay))
                }
                if let firstFrame = frames.first {
                    let image = NSImage(cgImage: firstFrame.cgImage, size: NSSize(width: firstFrame.cgImage.width, height: firstFrame.cgImage.height))
                    return DecodedImage(image: image, format: .webp,
                                        pixelSize: image.decodedPixelSize, companionVideoURL: nil,
                                        gifFrames: frames)
                }
            }
            // Static WebP
            if let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
                return DecodedImage(image: image, format: .webp,
                                    pixelSize: image.decodedPixelSize, companionVideoURL: nil,
                                    gifFrames: [])
            }
        }
        // Fallback
        if let image = NSImage(data: data) {
            return DecodedImage(image: image, format: .webp,
                                pixelSize: image.decodedPixelSize, companionVideoURL: nil,
                                gifFrames: [])
        }
        throw DecodeError.decodeFailed("WebPImageDecoder: no native WebP decoder available on this system")
    }
}
