import AppKit

/// A small LRU cache of decoded NSImages keyed by file URL, shared by all
/// viewer windows. The maximum entry count is read live from AppConfig
/// (`imageCacheCount`, 1...20), so a change in Preferences takes effect at
/// the next insert/eviction without restarting anything.
final class ImageCache {
    static let shared = ImageCache()

    private var storage: [URL: NSImage] = [:]
    /// LRU order, oldest first.
    private var order: [URL] = []
    private let lock = NSLock()

    /// Returns the cached image for `url` (marking it most-recently-used), or nil.
    func image(for url: URL) -> NSImage? {
        lock.lock(); defer { lock.unlock() }
        guard let image = storage[url] else { return nil }
        touchLocked(url)
        return image
    }

    /// Insert (or refresh) a decoded image, evicting the least-recently-used
    /// entries beyond the configured cache count.
    func insert(_ image: NSImage, for url: URL) {
        lock.lock(); defer { lock.unlock() }
        if storage[url] == nil {
            order.append(url)
        } else {
            touchLocked(url)
        }
        storage[url] = image
        let limit = AppConfig.shared.imageCacheCount
        while order.count > limit, let oldest = order.first {
            order.removeFirst()
            storage[oldest] = nil
        }
    }

    /// Whether a decoded image for `url` is already cached.
    func contains(_ url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return storage[url] != nil
    }

    private func touchLocked(_ url: URL) {
        if let i = order.firstIndex(of: url) {
            order.remove(at: i)
            order.append(url)
        }
    }
}
