import AppKit

/// A thread-safe NSCache of decoded NSImages keyed by file URL, shared by all
/// viewer windows. The maximum entry count is read live from AppConfig
/// (`imageCacheCount`, 1...20, default 3), so a change in Preferences takes
/// effect immediately without restarting anything.
///
/// Per Apple's documentation NSCache is thread-safe and evicts entries beyond
/// `countLimit` automatically; the cache is cleared on system memory warnings
/// (see MemoryPressureMonitor) and when all viewer windows close.
final class ImageCache {
    static let shared = ImageCache()

    /// NSCache caps the number of stored images via `countLimit`.
    private let cache = NSCache<NSURL, NSImage>()
    /// URLs whose cached entry is a downscaled thumbnail of a huge image.
    private var scaledKeys: Set<NSURL> = []
    /// Guards `scaledKeys` (NSCache manages its own locking).
    private let lock = NSLock()
    private var configObserver: NSObjectProtocol?

    private init() {
        cache.countLimit = AppConfig.shared.imageCacheCount
        // Keep countLimit in sync with the "Cached images" setting (1–20).
        configObserver = NotificationCenter.default.addObserver(
            forName: AppConfig.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.cache.countLimit = AppConfig.shared.imageCacheCount
        }
    }

    /// Returns the cached image for `url`, or nil.
    func image(for url: URL) -> NSImage? {
        return cache.object(forKey: url as NSURL)
    }

    /// Insert (or refresh) a decoded image; NSCache evicts entries beyond
    /// `countLimit` automatically.
    func insert(_ image: NSImage, for url: URL, scaled: Bool = false) {
        let key = url as NSURL
        cache.setObject(image, forKey: key)
        lock.lock()
        if scaled {
            scaledKeys.insert(key)
        } else {
            scaledKeys.remove(key)
        }
        lock.unlock()
    }

    /// Whether a decoded image for `url` is already cached.
    func contains(_ url: URL) -> Bool {
        return cache.object(forKey: url as NSURL) != nil
    }

    /// Whether the cached entry for `url` (if any) is a huge-image thumbnail.
    func isScaled(_ url: URL) -> Bool {
        let key = url as NSURL
        lock.lock()
        let scaled = scaledKeys.contains(key)
        lock.unlock()
        return scaled && cache.object(forKey: key) != nil
    }

    /// Release every cached image (memory warning / all windows closed).
    func removeAll() {
        cache.removeAllObjects()
        lock.lock()
        scaledKeys.removeAll()
        lock.unlock()
    }
}
