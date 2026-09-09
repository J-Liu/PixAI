import Foundation

/// Persistent application settings stored as JSON at `~/.pixai/config.json`.
///
/// - Values are read live by every feature (delete confirmation, image cache
///   budget, slideshow interval, quit-on-last-window-closed, logging).
/// - Every mutation is written back to disk immediately (atomic write) and
///   posts `AppConfig.didChangeNotification` on the main thread, so changes
///   made in the Preferences window take effect at once and are persisted.
///
/// NOTE: `init()` must never touch `Logger.shared` (its first access may be
/// triggered from inside this very init, which would deadlock the static).
final class AppConfig {
    static let shared = AppConfig()

    /// Posted on the main thread after any setting value changes.
    static let didChangeNotification = Notification.Name("AppConfig.didChange")

    enum Defaults {
        static let deleteConfirmationEnabled = true
        static let imageCacheCount = 3
        static let slideshowInterval: Double = 3.0
        static let quitOnLastWindowClosed = false
        static let logEnabled = false
        /// `~/.pixai/PixAI.log`, expanded to an absolute path at use time.
        static func logPath() -> String {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".pixai/PixAI.log").path
        }
    }

    /// Allowed range for the image cache count.
    static let cacheCountRange = 1...20
    /// Allowed range for the slideshow interval (seconds).
    static let intervalRange: ClosedRange<Double> = 1.0...600.0

    private struct Payload: Codable {
        var deleteConfirmationEnabled: Bool?
        var imageCacheCount: Int?
        var slideshowInterval: Double?
        var quitOnLastWindowClosed: Bool?
        var logEnabled: Bool?
        var logPath: String?
    }

    private let fileURL: URL
    private let lock = NSLock()

    // Backing storage (underscore-prefixed to avoid clashing with the public
    // computed accessors below).
    private var _deleteConfirmationEnabled: Bool = Defaults.deleteConfirmationEnabled
    private var _imageCacheCount: Int = Defaults.imageCacheCount
    private var _slideshowInterval: Double = Defaults.slideshowInterval
    private var _quitOnLastWindowClosed: Bool = Defaults.quitOnLastWindowClosed
    private var _logEnabled: Bool = Defaults.logEnabled
    private var _logPath: String = Defaults.logPath()

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        fileURL = home.appendingPathComponent(".pixai/config.json")
        load()
    }

    /// Log the loaded settings once at startup (call after Logger is up).
    func logLoadedState() {
        lock.lock()
        let msg = "Config state: deleteConfirm=\(_deleteConfirmationEnabled), cacheCount=\(_imageCacheCount), interval=\(_slideshowInterval)s, quitOnLastClose=\(_quitOnLastWindowClosed), logEnabled=\(_logEnabled), logPath=\(_logPath)"
        lock.unlock()
        Logger.shared.log(msg)
    }

    // MARK: - Settings accessors

    /// Whether deleting a file shows a confirmation dialog (default: true).
    var deleteConfirmationEnabled: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _deleteConfirmationEnabled
        }
        set {
            lock.lock()
            let changed = _deleteConfirmationEnabled != newValue
            if changed { _deleteConfirmationEnabled = newValue }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Number of decoded images kept in the LRU cache (default 3, range 1...20).
    var imageCacheCount: Int {
        get {
            lock.lock(); defer { lock.unlock() }
            return _imageCacheCount
        }
        set {
            let clamped = Self.clampCacheCount(newValue)
            lock.lock()
            let changed = _imageCacheCount != clamped
            if changed { _imageCacheCount = clamped }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Seconds shown per slideshow slide (default 3, range 1...600).
    var slideshowInterval: Double {
        get {
            lock.lock(); defer { lock.unlock() }
            return _slideshowInterval
        }
        set {
            let clamped = Self.clampInterval(newValue)
            lock.lock()
            let changed = _slideshowInterval != clamped
            if changed { _slideshowInterval = clamped }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Whether closing the last window quits the app (default: false).
    var quitOnLastWindowClosed: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _quitOnLastWindowClosed
        }
        set {
            lock.lock()
            let changed = _quitOnLastWindowClosed != newValue
            if changed { _quitOnLastWindowClosed = newValue }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Whether file logging is enabled (default: false).
    var logEnabled: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _logEnabled
        }
        set {
            lock.lock()
            let changed = _logEnabled != newValue
            if changed { _logEnabled = newValue }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Absolute path of the log file (default: `~/.pixai/PixAI.log`).
    /// A leading `~` is expanded to the user's home directory.
    var logPath: String {
        get {
            lock.lock(); defer { lock.unlock() }
            return _logPath
        }
        set {
            let expanded = (newValue as NSString).expandingTildeInPath
            lock.lock()
            let changed = _logPath != expanded
            if changed { _logPath = expanded }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Reset every setting to its default value (and persist).
    func resetToDefaults() {
        lock.lock()
        var changed = false
        if _deleteConfirmationEnabled != Defaults.deleteConfirmationEnabled {
            _deleteConfirmationEnabled = Defaults.deleteConfirmationEnabled
            changed = true
        }
        if _imageCacheCount != Defaults.imageCacheCount {
            _imageCacheCount = Defaults.imageCacheCount
            changed = true
        }
        if _slideshowInterval != Defaults.slideshowInterval {
            _slideshowInterval = Defaults.slideshowInterval
            changed = true
        }
        if _quitOnLastWindowClosed != Defaults.quitOnLastWindowClosed {
            _quitOnLastWindowClosed = Defaults.quitOnLastWindowClosed
            changed = true
        }
        if _logEnabled != Defaults.logEnabled {
            _logEnabled = Defaults.logEnabled
            changed = true
        }
        let defaultLogPath = Defaults.logPath()
        if _logPath != defaultLogPath {
            _logPath = defaultLogPath
            changed = true
        }
        lock.unlock()
        if changed { save(); notifyChange() }
    }

    // MARK: - Clamping

    static func clampCacheCount(_ value: Int) -> Int {
        return min(max(value, cacheCountRange.lowerBound), cacheCountRange.upperBound)
    }

    static func clampInterval(_ value: Double) -> Double {
        return min(max(value, intervalRange.lowerBound), intervalRange.upperBound)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return
        }
        lock.lock()
        if let v = payload.deleteConfirmationEnabled { _deleteConfirmationEnabled = v }
        if let v = payload.imageCacheCount { _imageCacheCount = Self.clampCacheCount(v) }
        if let v = payload.slideshowInterval { _slideshowInterval = Self.clampInterval(v) }
        if let v = payload.quitOnLastWindowClosed { _quitOnLastWindowClosed = v }
        if let v = payload.logEnabled { _logEnabled = v }
        if let v = payload.logPath, !v.isEmpty { _logPath = (v as NSString).expandingTildeInPath }
        lock.unlock()
    }

    private func save() {
        lock.lock()
        let payload = Payload(
            deleteConfirmationEnabled: _deleteConfirmationEnabled,
            imageCacheCount: _imageCacheCount,
            slideshowInterval: _slideshowInterval,
            quitOnLastWindowClosed: _quitOnLastWindowClosed,
            logEnabled: _logEnabled,
            logPath: _logPath
        )
        lock.unlock()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(payload)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Logging is not available here (Logger depends on AppConfig);
            // surface the failure on stderr instead.
            FileHandle.standardError.write(Data("PixAI: failed to save config to \(fileURL.path): \(error)\n".utf8))
        }
    }

    private func notifyChange() {
        let post = {
            NotificationCenter.default.post(name: AppConfig.didChangeNotification, object: self)
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }
}
