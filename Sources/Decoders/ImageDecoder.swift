import Foundation
import CoreGraphics

struct DecodeOptions {
    var maxSize: CGSize?
    var thumbnail: Bool
    var quality: CGFloat
}

protocol ImageDecoder {
    static var supportedExtensions: [String] { get }
    static func canDecode(_ data: Data) -> Bool
    func decode(data: Data, options: DecodeOptions) throws -> DecodedImage
    func metadata(from data: Data) throws -> ImageMetadata?
}
