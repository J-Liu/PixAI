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
        if let image = NSImage(data: data) {
            return DecodedImage(image: image, format: .webp,
                                pixelSize: image.decodedPixelSize, companionVideoURL: nil)
        }
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            return DecodedImage(image: image, format: .webp,
                                pixelSize: image.decodedPixelSize, companionVideoURL: nil)
        }
        throw DecodeError.decodeFailed("WebPImageDecoder: no native WebP decoder available on this system")
    }
}
