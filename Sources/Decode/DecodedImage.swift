import AppKit
import Foundation

/// The result of a successful decode: the displayable image plus the metadata
/// the viewer needs (format, pixel size, Live Photo companion video).
struct DecodedImage {
    let image: NSImage
    let format: ImageFormat
    /// Pixel dimensions when determinable (vector formats report their
    /// intrinsic point size).
    let pixelSize: NSSize?
    /// Companion .MOV for Apple Live Photo pairs; nil for every other format.
    let companionVideoURL: URL?
}

/// Errors surfaced by the decode abstraction layer.
enum DecodeError: LocalizedError {
    case fileReadFailed(URL, String)
    case unsupportedFormat(ImageFormat)
    case noDecoderForFormat(ImageFormat)
    case decodeFailed(String)

    var errorDescription: String? {
        switch self {
        case .fileReadFailed(let url, let reason):
            return "Cannot read \(url.lastPathComponent): \(reason)"
        case .unsupportedFormat(let format):
            return "Unrecognized image format (\(format.displayName))"
        case .noDecoderForFormat(let format):
            return "No decoder registered for \(format.displayName)"
        case .decodeFailed(let reason):
            return "Decode failed: \(reason)"
        }
    }
}

extension NSImage {
    /// Pixel dimensions from the first representation that reports real pixel
    /// counts, falling back to the image's point size (vector formats such as
    /// SVG report 0×0 pixels but a valid point size).
    var decodedPixelSize: NSSize? {
        for rep in representations where rep.pixelsWide > 0 && rep.pixelsHigh > 0 {
            return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        if size.width > 0, size.height > 0 {
            return size
        }
        return nil
    }
}
