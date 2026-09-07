import Foundation

/// Singleton that manages all image decoders.
class ImageDecoderManager {
    static let shared = ImageDecoderManager()
    private var decoders: [ImageDecoder] = []

    private init() {
        // Register the default ImageIODecoder
        registerDecoder(ImageIODecoder())
    }

    func registerDecoder(_ decoder: ImageDecoder) {
        if !decoders.contains(where: { type(of: $0) == type(of: decoder) }) {
            decoders.append(decoder)
        }
    }

    /// Decode image data using the first decoder that supports it.
    func decode(data: Data, options: DecodeOptions) throws -> DecodedImage {
        for decoder in decoders {
            if type(of: decoder).canDecode(data) {
                return try decoder.decode(data: data, options: options)
            }
        }
        throw ImageDecodeError.unsupported
    }

    /// Get all supported file extensions.
    func supportedExtensions() -> [String] {
        var exts = Set<String>()
        for decoder in decoders {
            exts.formUnion(type(of: decoder).supportedExtensions)
        }
        return Array(exts).sorted()
    }

    /// Extract metadata from image data.
    func metadata(from data: Data) throws -> ImageMetadata? {
        for decoder in decoders {
            if type(of: decoder).canDecode(data) {
                return try decoder.metadata(from: data)
            }
        }
        return nil
    }
}
