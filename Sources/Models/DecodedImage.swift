import CoreGraphics

struct DecodedImage {
    let cgImage: CGImage
    let orientation: CGImagePropertyOrientation?
    let metadata: ImageMetadata?
}
