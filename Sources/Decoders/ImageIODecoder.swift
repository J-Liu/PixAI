import Foundation
import CoreGraphics
import ImageIO

/// Core Graphics / ImageIO based decoder.
class ImageIODecoder: ImageDecoder {
    static let supportedExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic"]

    static func canDecode(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return false
        }
        // Check if it's a valid image type
        return CGImageSourceGetType(source) != nil
    }

    func decode(data: Data, options: DecodeOptions) throws -> DecodedImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageDecodeError.unsupported
        }

        var cgImage: CGImage?
        let maxDimension = options.maxSize?.width ?? 0
        let imageOptions = [
            kCGImageSourceShouldCache: true as CFBoolean,
            kCGImageSourceCreateThumbnailFromImageAlways: true as CFBoolean
        ] as CFDictionary

        // Try to get a thumbnail if requested and max dimension is set
        if options.thumbnail, maxDimension > 0 {
            let optionsWithMaxSize = [
                kCGImageSourceShouldCache: true as CFBoolean,
                kCGImageSourceCreateThumbnailFromImageAlways: true as CFBoolean,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension as CFNumber
            ] as CFDictionary
            cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, optionsWithMaxSize)
        }

        // Fall back to full image if no thumbnail or thumbnail failed
        if cgImage == nil {
            cgImage = CGImageSourceCreateImageAtIndex(source, 0, imageOptions)
        }

        guard let image = cgImage else {
            throw ImageDecodeError.failedToDecode
        }

        // Extract orientation from metadata
        let orientation: UInt32?
        if let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let orientationValue = metadata[kCGImagePropertyOrientation] as? UInt32 {
            orientation = orientationValue
        } else {
            orientation = nil
        }

        // Extract metadata
        let meta = try extractMetadata(from: source)

        return DecodedImage(cgImage: image, orientation: orientation, metadata: meta)
    }

    func metadata(from data: Data) throws -> ImageMetadata? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw ImageDecodeError.unsupported
        }
        return try extractMetadata(from: source)
    }

    private func extractMetadata(from source: CGImageSource) throws -> ImageMetadata {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            throw ImageDecodeError.failedToDecode
        }

        let width = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties[kCGImagePropertyPixelHeight] as? Int ?? 0

        // Extract color space name from color model
        var colorSpaceName: String?
        if let colorModel = properties[kCGImagePropertyColorModel] as? String {
            colorSpaceName = colorModel
        }

        // Check for alpha
        let hasAlpha = (properties[kCGImagePropertyHasAlpha] as? Bool) ?? false

        // Determine format string from UTI (Uniform Type Identifier)
        let format: String
        if let uti = CGImageSourceGetType(source) as CFString? {
            // UTI is like "public.png", extract the extension part
            let nsString = uti as NSString
            let components = nsString.components(separatedBy: ".")
            if components.count > 1, let lastComponent = components.last {
                format = lastComponent.lowercased()
            } else {
                format = "unknown"
            }
        } else {
            // Fallback to color model or extension from filename
            if let colorModel = properties[kCGImagePropertyColorModel] as? String {
                format = colorModel.lowercased()
            } else {
                format = "unknown"
            }
        }

        return ImageMetadata(
            width: width,
            height: height,
            colorSpace: colorSpaceName,
            hasAlpha: hasAlpha,
            format: format
        )
    }
}

enum ImageDecodeError: Error {
    case unsupported
    case failedToDecode
}
