// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

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
        /// Live Photo companion videos play automatically when the still loads.
        static let livePhotoAutoPlay = true
        /// Live Photo playback is muted (the MOV carries an audio track).
        static let livePhotoMuted = true
        /// `~/.pixai/PixAI.log`, expanded to an absolute path at use time.
        static func logPath() -> String {
            return FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".pixai/PixAI.log").path
        }
        // ── AI defaults ──────────────────────────────────────────────
        static let aiAutoUpscaleEnabled = false
        static let aiAutoDewatermarkEnabled = false
        /// "both" | "dedupOnly" | "watermarkOnly"
        static let aiEnhanceMode = "both"
        static let dedupAskContinue = true
        /// Duplicate detection similarity threshold (0.70 - 0.99, default 0.85).
        /// Higher = stricter (fewer false positives, may miss similar images).
        static let dedupThreshold: Double = 0.85
        static let proxyEnabled = false
        /// "http" | "socks" (socks is accepted but downloads fall back to http).
        static let proxyType = "http"
        static let proxyHost = "127.0.0.1"
        static let proxyPort = 7890
        /// Images with longest side ≤ this are considered "small" for auto-upscaling.
        static let smallImageMaxSide = 1024
        /// UI language: "en" (default) or "zh".
        static let uiLanguage = "en"
        /// Image switch fade duration in seconds; 0 disables the animation.
        static let imageTransitionDuration: Double = 0.1
        /// Ask at startup whether to download missing/corrupted AI models.
        static let modelCheckPromptEnabled = true
        /// Confirm before cropping a Live Photo (the result is a still image).
        static let cropLivePhotoConfirm = true
        /// Open panel directory mode: "last" (remember last opened) or "custom" (fixed directory).
        static let openPanelDirectoryMode = "last"
        /// Custom directory for open panel (used when mode is "custom").
        static func customOpenDirectory() -> String { "" }
        // ── AI Enhancement defaults ─────────────────────────────────────
        /// Enhance vibrance amount (0.0 - 1.0, default 0.15)
        static let enhanceVibrance: Double = 0.15
        /// Enhance contrast multiplier (0.5 - 2.0, default 1.05, 1.0 = no change)
        static let enhanceContrast: Double = 1.05
        /// Enhance sharpness amount (0.0 - 1.0, default 0.1)
        static let enhanceSharpness: Double = 0.1
        // ── Watermark removal defaults ──────────────────────────────
        /// Saliency threshold for watermark detection (0.1 - 0.9, default 0.7, higher = more conservative)
        static let watermarkMaskThreshold: Double = 0.7
        /// Minimum mask fraction to treat as watermark (0.0001 - 0.1, default 0.001)
        static let watermarkMinMaskFraction: Double = 0.001
        /// Maximum mask fraction to treat as watermark (0.01 - 0.5, default 0.2).
        /// Masks covering more than this are likely false positives (faces, objects) and will be rejected.
        static let watermarkMaxMaskFraction: Double = 0.2
        /// Watermark removal mode: "auto" (U2Net detects, LaMa inpaints) or "manual" (user selects region, LaMa inpaints)
        static let watermarkMode: String = "auto"
        /// Feather radius for mask edges (0 - 10 pixels, default 3, for smoother blending)
        static let watermarkFeatherRadius: Int = 3
        // ── Crop mode defaults ─────────────────────────────────────
        /// Crop mode: "full" (start with full image) or "select" (drag to select region)
        static let cropMode: String = "full"
    }

    /// Allowed range for the image cache count.
    static let cacheCountRange = 1...20
    /// Allowed range for the slideshow interval (seconds).
    static let intervalRange: ClosedRange<Double> = 1.0...600.0
    /// Allowed range for the image transition duration (seconds); 0 disables it.
    static let transitionRange: ClosedRange<Double> = 0.0...2.0
    private struct Payload: Codable {
        var deleteConfirmationEnabled: Bool?
        var imageCacheCount: Int?
        var slideshowInterval: Double?
        var quitOnLastWindowClosed: Bool?
        var logEnabled: Bool?
        var logPath: String?
        var livePhotoAutoPlay: Bool?
        var livePhotoMuted: Bool?
        // AI
        var aiAutoUpscaleEnabled: Bool?
        var aiAutoDewatermarkEnabled: Bool?
        var aiEnhanceMode: String?
        var dedupAskContinue: Bool?
        var dedupThreshold: Double?
        var proxyEnabled: Bool?
        var proxyType: String?
        var proxyHost: String?
        var proxyPort: Int?
        var smallImageMaxSide: Int?
        // UX / i18n
        var uiLanguage: String?
        var imageTransitionDuration: Double?
        var modelCheckPromptEnabled: Bool?
        var cropLivePhotoConfirm: Bool?
        // Open panel directory
        var openPanelDirectoryMode: String?
        var customOpenDirectory: String?
        var lastOpenDirectory: String?
        // AI Enhancement
        var enhanceVibrance: Double?
        var enhanceContrast: Double?
        var enhanceSharpness: Double?
        // Watermark removal
        var watermarkMaskThreshold: Double?
        var watermarkMinMaskFraction: Double?
        var watermarkMaxMaskFraction: Double?
        var watermarkMode: String?
        var watermarkFeatherRadius: Int?
        // Crop mode
        var cropMode: String?
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
    private var _livePhotoAutoPlay: Bool = Defaults.livePhotoAutoPlay
    private var _livePhotoMuted: Bool = Defaults.livePhotoMuted
    // AI backing storage
    private var _aiAutoUpscaleEnabled: Bool = Defaults.aiAutoUpscaleEnabled
    private var _aiAutoDewatermarkEnabled: Bool = Defaults.aiAutoDewatermarkEnabled
    private var _aiEnhanceMode: String = Defaults.aiEnhanceMode
    private var _dedupAskContinue: Bool = Defaults.dedupAskContinue
    private var _dedupThreshold: Double = Defaults.dedupThreshold
    private var _proxyEnabled: Bool = Defaults.proxyEnabled
    private var _proxyType: String = Defaults.proxyType
    private var _proxyHost: String = Defaults.proxyHost
    private var _proxyPort: Int = Defaults.proxyPort
    private var _smallImageMaxSide: Int = Defaults.smallImageMaxSide
    // UX / i18n backing storage
    private var _uiLanguage: String = Defaults.uiLanguage
    private var _imageTransitionDuration: Double = Defaults.imageTransitionDuration
    private var _modelCheckPromptEnabled: Bool = Defaults.modelCheckPromptEnabled
    private var _cropLivePhotoConfirm: Bool = Defaults.cropLivePhotoConfirm
    // Open panel directory
    private var _openPanelDirectoryMode: String = Defaults.openPanelDirectoryMode
    private var _customOpenDirectory: String = Defaults.customOpenDirectory()
    private var _lastOpenDirectory: String = ""
    // AI Enhancement
    private var _enhanceVibrance: Double = Defaults.enhanceVibrance
    private var _enhanceContrast: Double = Defaults.enhanceContrast
    private var _enhanceSharpness: Double = Defaults.enhanceSharpness
    // Watermark removal
    private var _watermarkMaskThreshold: Double = Defaults.watermarkMaskThreshold
    private var _watermarkMinMaskFraction: Double = Defaults.watermarkMinMaskFraction
    private var _watermarkMaxMaskFraction: Double = Defaults.watermarkMaxMaskFraction
    private var _watermarkMode: String = Defaults.watermarkMode
    private var _watermarkFeatherRadius: Int = Defaults.watermarkFeatherRadius
    // Crop mode
    private var _cropMode: String = Defaults.cropMode
    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        fileURL = home.appendingPathComponent(".pixai/config.json")
        load()
    }

    /// Log the loaded settings once at startup (call after Logger is up).
    func logLoadedState() {
        lock.lock()
        let msg = "Config state: deleteConfirm=\(_deleteConfirmationEnabled), cacheCount=\(_imageCacheCount), interval=\(_slideshowInterval)s, quitOnLastClose=\(_quitOnLastWindowClosed), logEnabled=\(_logEnabled), logPath=\(_logPath), liveAutoPlay=\(_livePhotoAutoPlay), liveMuted=\(_livePhotoMuted)"
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

    /// Whether Live Photo companion videos play automatically when the still
    /// image loads (default: true).
    var livePhotoAutoPlay: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _livePhotoAutoPlay
        }
        set {
            lock.lock()
            let changed = _livePhotoAutoPlay != newValue
            if changed { _livePhotoAutoPlay = newValue }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Whether Live Photo playback is muted (default: true). Read live each
    /// time a Live Photo starts playing.
    var livePhotoMuted: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _livePhotoMuted
        }
        set {
            lock.lock()
            let changed = _livePhotoMuted != newValue
            if changed { _livePhotoMuted = newValue }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    // MARK: - AI settings

    /// Whether small images are automatically upscaled with Real-ESRGAN 4x
    /// when loaded (default: false).
    var aiAutoUpscaleEnabled: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _aiAutoUpscaleEnabled
        }
        set {
            lock.lock()
            let changed = _aiAutoUpscaleEnabled != newValue
            if changed { _aiAutoUpscaleEnabled = newValue }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Whether images are automatically de-watermarked with U2Net when loaded
    /// (default: false).
    var aiAutoDewatermarkEnabled: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _aiAutoDewatermarkEnabled
        }
        set {
            lock.lock()
            let changed = _aiAutoDewatermarkEnabled != newValue
            if changed { _aiAutoDewatermarkEnabled = newValue }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Which operations the "AI one-click enhance" batch runs:
    /// "both" | "dedupOnly" | "watermarkOnly" (default: "both").
    var aiEnhanceMode: String {
        get {
            lock.lock(); defer { lock.unlock() }
            return _aiEnhanceMode
        }
        set {
            let normalized = Self.normalizeEnhanceMode(newValue)
            lock.lock()
            let changed = _aiEnhanceMode != normalized
            if changed { _aiEnhanceMode = normalized }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Whether the duplicate-removal UI asks "continue?" between groups
    /// (default: true).
    var dedupAskContinue: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _dedupAskContinue
        }
        set {
            lock.lock()
            let changed = _dedupAskContinue != newValue
            if changed { _dedupAskContinue = newValue }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Duplicate detection similarity threshold (0.70 - 0.99, default 0.85).
    /// Higher = stricter (fewer false positives, may miss similar images).
    var dedupThreshold: Double {
        get {
            lock.lock(); defer { lock.unlock() }
            return _dedupThreshold
        }
        set {
            let clamped = min(max(newValue, 0.70), 0.99)
            lock.lock()
            let changed = _dedupThreshold != clamped
            if changed { _dedupThreshold = clamped }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Whether downloads route through the configured proxy (default: false).
    var proxyEnabled: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _proxyEnabled
        }
        set {
            lock.lock()
            let changed = _proxyEnabled != newValue
            if changed { _proxyEnabled = newValue }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Proxy type: "http" or "socks" (default: "http"). URLSession only
    /// supports http/https proxies; "socks" values are accepted for storage
    /// but downloads fall back to direct/http.
    var proxyType: String {
        get {
            lock.lock(); defer { lock.unlock() }
            return _proxyType
        }
        set {
            let normalized = (newValue == "socks") ? "socks" : "http"
            lock.lock()
            let changed = _proxyType != normalized
            if changed { _proxyType = normalized }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Proxy host (default: "127.0.0.1").
    var proxyHost: String {
        get {
            lock.lock(); defer { lock.unlock() }
            return _proxyHost
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            lock.lock()
            let changed = _proxyHost != trimmed
            if changed { _proxyHost = trimmed }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Proxy port (default: 7890, range 1...65535).
    var proxyPort: Int {
        get {
            lock.lock(); defer { lock.unlock() }
            return _proxyPort
        }
        set {
            let clamped = min(max(newValue, 1), 65535)
            lock.lock()
            let changed = _proxyPort != clamped
            if changed { _proxyPort = clamped }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Longest-side threshold (px) below which an image counts as "small"
    /// for the auto-upscale feature (default: 1024).
    var smallImageMaxSide: Int {
        get {
            lock.lock(); defer { lock.unlock() }
            return _smallImageMaxSide
        }
        set {
            let clamped = min(max(newValue, 64), 8192)
            lock.lock()
            let changed = _smallImageMaxSide != clamped
            if changed { _smallImageMaxSide = clamped }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    // MARK: - UX / i18n settings

    /// UI language: "en" (default) or "zh".
    var uiLanguage: String {
        get {
            lock.lock(); defer { lock.unlock() }
            return _uiLanguage
        }
        set {
            let normalized = Self.normalizeLanguage(newValue)
            lock.lock()
            let changed = _uiLanguage != normalized
            if changed { _uiLanguage = normalized }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Image switch fade duration in seconds (default 0.3, range 0...2;
    /// 0 disables the transition animation).
    var imageTransitionDuration: Double {
        get {
            lock.lock(); defer { lock.unlock() }
            return _imageTransitionDuration
        }
        set {
            let clamped = Self.clampTransitionDuration(newValue)
            lock.lock()
            let changed = _imageTransitionDuration != clamped
            if changed { _imageTransitionDuration = clamped }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Whether startup shows a dialog when AI models are missing/corrupted
    /// (default: true).
    var modelCheckPromptEnabled: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _modelCheckPromptEnabled
        }
        set {
            lock.lock()
            let changed = _modelCheckPromptEnabled != newValue
            if changed { _modelCheckPromptEnabled = newValue }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Whether cropping a Live Photo asks for confirmation first (default:
    /// true); the crop converts it into a regular still image.
    var cropLivePhotoConfirm: Bool {
        get {
            lock.lock(); defer { lock.unlock() }
            return _cropLivePhotoConfirm
        }
        set {
            lock.lock()
            let changed = _cropLivePhotoConfirm != newValue
            if changed { _cropLivePhotoConfirm = newValue }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    // MARK: - Open panel directory settings

    /// Open panel directory mode: "last" (remember last opened) or "custom" (fixed directory).
    var openPanelDirectoryMode: String {
        get {
            lock.lock(); defer { lock.unlock() }
            return _openPanelDirectoryMode
        }
        set {
            let normalized = (newValue == "custom") ? "custom" : "last"
            lock.lock()
            let changed = _openPanelDirectoryMode != normalized
            if changed { _openPanelDirectoryMode = normalized }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Custom directory for open panel (used when mode is "custom").
    var customOpenDirectory: String {
        get {
            lock.lock(); defer { lock.unlock() }
            return _customOpenDirectory
        }
        set {
            let expanded = (newValue as NSString).expandingTildeInPath
            lock.lock()
            let changed = _customOpenDirectory != expanded
            if changed { _customOpenDirectory = expanded }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Last opened directory (updated after each file open).
    var lastOpenDirectory: String {
        get {
            lock.lock(); defer { lock.unlock() }
            return _lastOpenDirectory
        }
        set {
            let expanded = (newValue as NSString).expandingTildeInPath
            lock.lock()
            let changed = _lastOpenDirectory != expanded
            if changed { _lastOpenDirectory = expanded }
            lock.unlock()
            if changed { save() }
        }
    }

    /// Get the directory URL to use for the open panel.
    func getOpenPanelDirectory() -> URL? {
        let mode = openPanelDirectoryMode
        if mode == "custom" {
            let custom = customOpenDirectory
            if !custom.isEmpty, FileManager.default.fileExists(atPath: custom) {
                return URL(fileURLWithPath: custom)
            }
        }
        let last = lastOpenDirectory
        if !last.isEmpty, FileManager.default.fileExists(atPath: last) {
            return URL(fileURLWithPath: last)
        }
        return nil
    }

    // MARK: - AI Enhancement settings

    /// Enhance vibrance amount (0.0 - 1.0, default 0.15)
    var enhanceVibrance: Double {
        get {
            lock.lock(); defer { lock.unlock() }
            return _enhanceVibrance
        }
        set {
            let clamped = min(max(newValue, 0), 1)
            lock.lock()
            let changed = _enhanceVibrance != clamped
            if changed { _enhanceVibrance = clamped }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Enhance contrast multiplier (0.5 - 2.0, default 1.05, 1.0 = no change)
    var enhanceContrast: Double {
        get {
            lock.lock(); defer { lock.unlock() }
            return _enhanceContrast
        }
        set {
            let clamped = min(max(newValue, 0.5), 2.0)
            lock.lock()
            let changed = _enhanceContrast != clamped
            if changed { _enhanceContrast = clamped }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Enhance sharpness amount (0.0 - 1.0, default 0.1)
    var enhanceSharpness: Double {
        get {
            lock.lock(); defer { lock.unlock() }
            return _enhanceSharpness
        }
        set {
            let clamped = min(max(newValue, 0), 1)
            lock.lock()
            let changed = _enhanceSharpness != clamped
            if changed { _enhanceSharpness = clamped }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    // MARK: - Watermark removal settings

    /// Saliency threshold for watermark detection (0.1 - 0.9, default 0.5).
    /// Lower values = more sensitive (detects fainter watermarks but more false positives).
    var watermarkMaskThreshold: Double {
        get {
            lock.lock(); defer { lock.unlock() }
            return _watermarkMaskThreshold
        }
        set {
            let clamped = min(max(newValue, 0.1), 0.9)
            lock.lock()
            let changed = _watermarkMaskThreshold != clamped
            if changed { _watermarkMaskThreshold = clamped }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Minimum fraction of image that must be masked to treat as watermark (0.0001 - 0.1, default 0.001).
    /// Lower values = detects smaller watermarks; higher = only large watermarks.
    var watermarkMinMaskFraction: Double {
        get {
            lock.lock(); defer { lock.unlock() }
            return _watermarkMinMaskFraction
        }
        set {
            let clamped = min(max(newValue, 0.0001), 0.1)
            lock.lock()
            let changed = _watermarkMinMaskFraction != clamped
            if changed { _watermarkMinMaskFraction = clamped }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Maximum fraction of image that can be masked to treat as watermark (0.01 - 0.5, default 0.2).
    /// Masks larger than this are likely false positives (faces, objects) and will be skipped.
    var watermarkMaxMaskFraction: Double {
        get {
            lock.lock(); defer { lock.unlock() }
            return _watermarkMaxMaskFraction
        }
        set {
            let clamped = min(max(newValue, 0.01), 0.5)
            lock.lock()
            let changed = _watermarkMaxMaskFraction != clamped
            if changed { _watermarkMaxMaskFraction = clamped }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Watermark removal mode: "auto" (U2Net detects, LaMa inpaints) or "manual" (user selects region, LaMa inpaints).
    var watermarkMode: String {
        get {
            lock.lock(); defer { lock.unlock() }
            return _watermarkMode
        }
        set {
            let normalized = Self.normalizeWatermarkMode(newValue)
            lock.lock()
            let changed = _watermarkMode != normalized
            if changed { _watermarkMode = normalized }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    /// Feather radius for mask edges (0 - 10 pixels, default 3, for smoother blending).
    var watermarkFeatherRadius: Int {
        get {
            lock.lock(); defer { lock.unlock() }
            return _watermarkFeatherRadius
        }
        set {
            let clamped = min(max(newValue, 0), 10)
            lock.lock()
            let changed = _watermarkFeatherRadius != clamped
            if changed { _watermarkFeatherRadius = clamped }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    // MARK: - Crop mode settings

    /// Crop mode: "full" (start with full image) or "select" (drag to select region).
    var cropMode: String {
        get {
            lock.lock(); defer { lock.unlock() }
            return _cropMode
        }
        set {
            let normalized = Self.normalizeCropMode(newValue)
            lock.lock()
            let changed = _cropMode != normalized
            if changed { _cropMode = normalized }
            lock.unlock()
            if changed { save(); notifyChange() }
        }
    }

    static func normalizeCropMode(_ value: String) -> String {
        switch value {
        case "select": return "select"
        default: return "full"
        }
    }

    static func normalizeWatermarkMode(_ value: String) -> String {
        switch value {
        case "manual": return "manual"
        default: return "auto"
        }
    }

    static func normalizeLanguage(_ value: String) -> String {
        switch value {
        case "zh": return "zh"
        case "zh-Hant": return "zh-Hant"
        default: return "en"
        }
    }

    static func normalizeEnhanceMode(_ value: String) -> String {
        switch value {
        case "dedupOnly": return "dedupOnly"
        case "watermarkOnly": return "watermarkOnly"
        default: return "both"
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
        if _livePhotoAutoPlay != Defaults.livePhotoAutoPlay {
            _livePhotoAutoPlay = Defaults.livePhotoAutoPlay
            changed = true
        }
        if _livePhotoMuted != Defaults.livePhotoMuted {
            _livePhotoMuted = Defaults.livePhotoMuted
            changed = true
        }
        if _aiAutoUpscaleEnabled != Defaults.aiAutoUpscaleEnabled {
            _aiAutoUpscaleEnabled = Defaults.aiAutoUpscaleEnabled
            changed = true
        }
        if _aiAutoDewatermarkEnabled != Defaults.aiAutoDewatermarkEnabled {
            _aiAutoDewatermarkEnabled = Defaults.aiAutoDewatermarkEnabled
            changed = true
        }
        if _aiEnhanceMode != Defaults.aiEnhanceMode {
            _aiEnhanceMode = Defaults.aiEnhanceMode
            changed = true
        }
        if _dedupAskContinue != Defaults.dedupAskContinue {
            _dedupAskContinue = Defaults.dedupAskContinue
            changed = true
        }
        if _proxyEnabled != Defaults.proxyEnabled {
            _proxyEnabled = Defaults.proxyEnabled
            changed = true
        }
        if _proxyType != Defaults.proxyType {
            _proxyType = Defaults.proxyType
            changed = true
        }
        if _proxyHost != Defaults.proxyHost {
            _proxyHost = Defaults.proxyHost
            changed = true
        }
        if _proxyPort != Defaults.proxyPort {
            _proxyPort = Defaults.proxyPort
            changed = true
        }
        if _smallImageMaxSide != Defaults.smallImageMaxSide {
            _smallImageMaxSide = Defaults.smallImageMaxSide
            changed = true
        }
        if _uiLanguage != Defaults.uiLanguage {
            _uiLanguage = Defaults.uiLanguage
            changed = true
        }
        if _imageTransitionDuration != Defaults.imageTransitionDuration {
            _imageTransitionDuration = Defaults.imageTransitionDuration
            changed = true
        }
        if _modelCheckPromptEnabled != Defaults.modelCheckPromptEnabled {
            _modelCheckPromptEnabled = Defaults.modelCheckPromptEnabled
            changed = true
        }
        if _cropLivePhotoConfirm != Defaults.cropLivePhotoConfirm {
            _cropLivePhotoConfirm = Defaults.cropLivePhotoConfirm
            changed = true
        }
        if _openPanelDirectoryMode != Defaults.openPanelDirectoryMode {
            _openPanelDirectoryMode = Defaults.openPanelDirectoryMode
            changed = true
        }
        if _customOpenDirectory != Defaults.customOpenDirectory() {
            _customOpenDirectory = Defaults.customOpenDirectory()
            changed = true
        }
        if _cropMode != Defaults.cropMode {
            _cropMode = Defaults.cropMode
            changed = true
        }
        // Don't reset lastOpenDirectory - it's always remembered
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

    static func clampTransitionDuration(_ value: Double) -> Double {
        return min(max(value, transitionRange.lowerBound), transitionRange.upperBound)
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
        if let v = payload.livePhotoAutoPlay { _livePhotoAutoPlay = v }
        if let v = payload.livePhotoMuted { _livePhotoMuted = v }
        // AI
        if let v = payload.aiAutoUpscaleEnabled { _aiAutoUpscaleEnabled = v }
        if let v = payload.aiAutoDewatermarkEnabled { _aiAutoDewatermarkEnabled = v }
        if let v = payload.aiEnhanceMode { _aiEnhanceMode = Self.normalizeEnhanceMode(v) }
        if let v = payload.dedupAskContinue { _dedupAskContinue = v }
        if let v = payload.dedupThreshold { _dedupThreshold = min(max(v, 0.70), 0.99) }
        if let v = payload.proxyEnabled { _proxyEnabled = v }
        if let v = payload.proxyType { _proxyType = (v == "socks") ? "socks" : "http" }
        if let v = payload.proxyHost, !v.isEmpty { _proxyHost = v }
        if let v = payload.proxyPort { _proxyPort = min(max(v, 1), 65535) }
        if let v = payload.smallImageMaxSide { _smallImageMaxSide = min(max(v, 64), 8192) }
        if let v = payload.uiLanguage { _uiLanguage = Self.normalizeLanguage(v) }
        if let v = payload.imageTransitionDuration { _imageTransitionDuration = Self.clampTransitionDuration(v) }
        if let v = payload.modelCheckPromptEnabled { _modelCheckPromptEnabled = v }
        if let v = payload.cropLivePhotoConfirm { _cropLivePhotoConfirm = v }
        // Open panel directory
        if let v = payload.openPanelDirectoryMode { _openPanelDirectoryMode = (v == "custom") ? "custom" : "last" }
        if let v = payload.customOpenDirectory, !v.isEmpty { _customOpenDirectory = (v as NSString).expandingTildeInPath }
        if let v = payload.lastOpenDirectory, !v.isEmpty { _lastOpenDirectory = (v as NSString).expandingTildeInPath }
        // AI Enhancement
        if let v = payload.enhanceVibrance { _enhanceVibrance = min(max(v, 0), 1) }
        if let v = payload.enhanceContrast { _enhanceContrast = min(max(v, 0.5), 2.0) }
        if let v = payload.enhanceSharpness { _enhanceSharpness = min(max(v, 0), 1) }
        // Watermark removal
        if let v = payload.watermarkMaskThreshold { _watermarkMaskThreshold = min(max(v, 0.1), 0.9) }
        if let v = payload.watermarkMinMaskFraction { _watermarkMinMaskFraction = min(max(v, 0.0001), 0.1) }
        if let v = payload.watermarkMaxMaskFraction { _watermarkMaxMaskFraction = min(max(v, 0.01), 0.5) }
        if let v = payload.watermarkMode { _watermarkMode = Self.normalizeWatermarkMode(v) }
        if let v = payload.watermarkFeatherRadius { _watermarkFeatherRadius = min(max(v, 0), 10) }
        if let v = payload.cropMode { _cropMode = Self.normalizeCropMode(v) }
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
            logPath: _logPath,
            livePhotoAutoPlay: _livePhotoAutoPlay,
            livePhotoMuted: _livePhotoMuted,
            aiAutoUpscaleEnabled: _aiAutoUpscaleEnabled,
            aiAutoDewatermarkEnabled: _aiAutoDewatermarkEnabled,
            aiEnhanceMode: _aiEnhanceMode,
            dedupAskContinue: _dedupAskContinue,
            dedupThreshold: _dedupThreshold,
            proxyEnabled: _proxyEnabled,
            proxyType: _proxyType,
            proxyHost: _proxyHost,
            proxyPort: _proxyPort,
            smallImageMaxSide: _smallImageMaxSide,
            uiLanguage: _uiLanguage,
            imageTransitionDuration: _imageTransitionDuration,
            modelCheckPromptEnabled: _modelCheckPromptEnabled,
            cropLivePhotoConfirm: _cropLivePhotoConfirm,
            openPanelDirectoryMode: _openPanelDirectoryMode,
            customOpenDirectory: _customOpenDirectory,
            lastOpenDirectory: _lastOpenDirectory,
            enhanceVibrance: _enhanceVibrance,
            enhanceContrast: _enhanceContrast,
            enhanceSharpness: _enhanceSharpness,
            watermarkMaskThreshold: _watermarkMaskThreshold,
            watermarkMinMaskFraction: _watermarkMinMaskFraction,
            watermarkMaxMaskFraction: _watermarkMaxMaskFraction,
            watermarkMode: _watermarkMode,
            watermarkFeatherRadius: _watermarkFeatherRadius,
            cropMode: _cropMode
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
