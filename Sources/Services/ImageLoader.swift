import Foundation
import AppKit

/// Loads and caches images using NSCache.
class ImageLoader {
    private let cache: NSCache<NSString, NSImage>

    init() {
        self.cache = NSCache<NSString, NSImage>()
        // Set a reasonable memory limit (e.g., 512 MB)
        self.cache.countLimit = 20
        self.cache.totalCostLimit = 512 * 1024 * 1024
    }

    /// Load an image from a URL, using the cache.
    /// Returns nil if the image cannot be loaded.
    func load(url: URL) async -> NSImage? {
        // Check cache first
        let key = url.absoluteString as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        // Decode in background thread
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let data = try Data(contentsOf: url)

                    // Decode the image
                    let decoded = try ImageDecoderManager.shared.decode(
                        data: data,
                        options: DecodeOptions(thumbnail: false, quality: 1.0)
                    )

                    // Convert CGImage to NSImage
                    let nsImage = NSImage(cgImage: decoded.cgImage,
                                          size: CGSize(width: decoded.cgImage.width,
                                                       height: decoded.cgImage.height))

                    // Store in cache
                    self.cache.setObject(nsImage, forKey: key)

                    DispatchQueue.main.async {
                        continuation.resume(returning: nsImage)
                    }
                } catch {
                    print("Failed to load image \(url): \(error)")
                    DispatchQueue.main.async {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    /// Preload the previous and next images.
    func preload(url: URL) async {
        _ = await load(url: url)
    }
}
