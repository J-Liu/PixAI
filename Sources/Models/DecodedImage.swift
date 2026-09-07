import CoreGraphics

struct DecodedImage {
    let cgImage: CGImage
    let orientation: UInt32?  // CGImagePropertyOrientation value (1-8)
    let metadata: ImageMetadata?
}
