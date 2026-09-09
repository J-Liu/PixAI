import Foundation

/// Decoder manager: registry + dispatcher for the decode abstraction layer.
///
/// Responsibilities (per spec):
///   - **register** — add/remove `ImageDecoder`s (registration order = priority).
///   - **query** — `decoder(for:)` and `registeredDecoders`.
///   - **auto-select** — `decode(url:)` detects the format (magic numbers
///     first, extension fallback — Live Photo before HEIC) and dispatches to
///     the first registered decoder that can handle it.
final class DecoderManager {
    static let shared = DecoderManager()

    private var decoders: [ImageDecoder] = []
    private let lock = NSLock()

    // MARK: - Init (default registrations, priority order)

    private init() {
        register(LivePhotoImageDecoder())
        register(RAWImageDecoder())
        register(WebPImageDecoder())
        register(SVGImageDecoder())
        register(PDFImageDecoder())
        register(StandardImageDecoder())
    }

    // MARK: - Register / query

    /// Register a decoder. Later registrations have lower priority than
    /// earlier ones for the same format.
    func register(_ decoder: ImageDecoder) {
        lock.lock(); defer { lock.unlock() }
        decoders.append(decoder)
    }

    /// Remove all decoders with the given name.
    func unregister(name: String) {
        lock.lock(); defer { lock.unlock() }
        decoders.removeAll { $0.name == name }
    }

    /// All registered decoders, in priority order.
    var registeredDecoders: [ImageDecoder] {
        lock.lock(); defer { lock.unlock() }
        return decoders
    }

    /// The first registered decoder that can handle `format` (auto-select).
    func decoder(for format: ImageFormat) -> ImageDecoder? {
        lock.lock(); defer { lock.unlock() }
        return decoders.first { $0.canDecode(format) }
    }

    // MARK: - Format detection / lightweight support check

    /// Detect the format of a file on disk (reads only the header bytes).
    func detectFormat(of url: URL) -> ImageFormat {
        return MagicNumberDetector.detect(url: url)
    }

    /// Lightweight "is this a file we can display" check used by directory
    /// scans — magic/extension based, no full decode.
    func isSupportedImage(at url: URL) -> Bool {
        let format = detectFormat(of: url)
        guard format.isDisplayable else { return false }
        return decoder(for: format) != nil
    }

    // MARK: - Decode (auto-select entry points)

    /// Read `url`, detect its format, and decode it with the selected decoder.
    func decode(url: URL) async throws -> DecodedImage {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DecodeError.fileReadFailed(url, error.localizedDescription)
        }
        return try await decode(data: data, url: url)
    }

    /// Detect the format of `data` (using `url` for the extension fallback and
    /// Live Photo companion check) and dispatch to the first decoder that can
    /// handle it.
    func decode(data: Data, url: URL? = nil) async throws -> DecodedImage {
        let format = MagicNumberDetector.detect(data: data, url: url)
        guard format != .unknown else {
            throw DecodeError.unsupportedFormat(.unknown)
        }
        guard let decoder = decoder(for: format) else {
            throw DecodeError.noDecoderForFormat(format)
        }
        Logger.shared.log("DecoderManager: \(url?.lastPathComponent ?? "<data>") -> \(format.displayName) via \(decoder.name)")
        return try await decoder.decode(data: data, url: url, format: format)
    }
}
