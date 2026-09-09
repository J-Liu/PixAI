import Foundation

/// Unified image-decoding interface of the decode abstraction layer.
///
/// A decoder declares which `ImageFormat`s it can handle and turns raw file
/// data into a `DecodedImage`. Decoding is asynchronous: most decoders do
/// pure CPU work off the main actor, while the SVG WebKit fallback hops to
/// the main actor only for its offscreen render pass.
protocol ImageDecoder: AnyObject {
    /// Stable identifier (used for unregistration and logging).
    var name: String { get }

    /// The formats this decoder can handle.
    var supportedFormats: Set<ImageFormat> { get }

    /// Whether this decoder can handle `format`.
    func canDecode(_ format: ImageFormat) -> Bool

    /// Decode `data` as `format`.
    ///
    /// - Parameters:
    ///   - data: The full file content (always available).
    ///   - url: The source file URL when decoding from disk; some decoders
    ///     (Core Image RAW) prefer reading from the file system.
    ///   - format: The already-detected format of `data`.
    func decode(data: Data, url: URL?, format: ImageFormat) async throws -> DecodedImage
}
