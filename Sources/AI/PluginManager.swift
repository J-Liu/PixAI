// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation
import CryptoKit
import CFNetwork

/// Manages downloadable AI model plugins under `~/.pixai/models`.
///
/// The main app has zero hard dependency on the model binaries: a plugin that
/// is not downloaded simply disables its features. Downloading verifies SHA256
/// of every file; a mismatch deletes the file and reports an error so the user
/// can re-download. Downloads honor the proxy settings in `AppConfig`.
final class PluginManager {
    static let shared = PluginManager()

    /// Posted on the main thread whenever any plugin state changes.
    static let stateDidChangeNotification = Notification.Name("PluginManager.stateDidChange")

    enum PluginError: LocalizedError {
        case shaMismatch(pluginID: String, path: String, expected: String, actual: String)
        case downloadFailed(String)
        case notDownloaded

        var errorDescription: String? {
            switch self {
            case .shaMismatch(let id, let path, let expected, let actual):
                return "SHA256 mismatch for \(id)/\(path)\nExpected: \(expected)\nActual:   \(actual)\nThe file was deleted. Please download again."
            case .downloadFailed(let msg):
                return "Download failed: \(msg)"
            case .notDownloaded:
                return "Model is not downloaded"
            }
        }
    }

    private let lock = NSLock()
    /// True while the singleton's init is running. The initial refresh posts
    /// stateDidChangeNotification; posting it synchronously would re-enter
    /// this very dispatch_once (observers read shared again) and crash with
    /// "BUG IN CLIENT OF LIBDISPATCH: trying to lock recursively". While true,
    /// postChange defers the post to the next main run-loop tick instead.
    private var isInitializing = false
    private var states: [String: PluginState] = [:]
    private var activeTasks: [String: URLSessionTask] = [:]
    private var activeSessions: [String: URLSession] = [:]  // Keep sessions alive during download
    private var cancelled: Set<String> = []
    private var progressCallbacks: [String: (Double) -> Void] = [:]

    private init() {
        isInitializing = true
        refreshStates()
        isInitializing = false
    }

    // MARK: - State

    /// Re-scan local files and rebuild states (downloaded & hash-verified → ready).
    func refreshStates() {
        lock.lock()
        for plugin in ModelPlugin.all where activeTasks[plugin.id] == nil {
            states[plugin.id] = Self.scanState(for: plugin)
        }
        lock.unlock()
        postChange()
    }

    private static func scanState(for plugin: ModelPlugin) -> PluginState {
        let fm = FileManager.default
        // Use verifyFiles for checking if model is ready (after extraction)
        for file in plugin.verifyFiles {
            let url = plugin.localURL(forPath: file.path)
            guard fm.fileExists(atPath: url.path) else {
                return .notDownloaded
            }
            // Empty SHA256 means directory package (e.g. .mlpackage), just check existence
            if !file.sha256.isEmpty {
                guard let actual = sha256Hex(ofFile: url),
                      actual.lowercased() == file.sha256.lowercased() else {
                    return .notDownloaded
                }
            }
        }
        return .ready
    }

    func state(for plugin: ModelPlugin) -> PluginState {
        lock.lock(); defer { lock.unlock() }
        return states[plugin.id] ?? .notDownloaded
    }

    func isReady(_ plugin: ModelPlugin) -> Bool {
        if case .ready = state(for: plugin) { return true }
        return false
    }

    /// Whether the plugin is downloaded AND enabled (marker file `.enabled`).
    func isEnabled(_ plugin: ModelPlugin) -> Bool {
        guard isReady(plugin) else { return false }
        return FileManager.default.fileExists(atPath: plugin.localDir.appendingPathComponent(".enabled").path)
    }

    /// Enable/disable a downloaded plugin (feature on/off without deleting files).
    func setEnabled(_ plugin: ModelPlugin, enabled: Bool) {
        guard isReady(plugin) else { return }
        let marker = plugin.localDir.appendingPathComponent(".enabled")
        do {
            if enabled {
                try FileManager.default.createDirectory(at: plugin.localDir, withIntermediateDirectories: true)
                try Data("1".utf8).write(to: marker, options: .atomic)
            } else if FileManager.default.fileExists(atPath: marker.path) {
                try FileManager.default.removeItem(at: marker)
            }
        } catch {
            Logger.shared.log("PluginManager: failed to set enabled for \(plugin.id): \(error)")
        }
        postChange()
    }

    /// Delete all local files of a plugin (uninstall).
    func uninstall(_ plugin: ModelPlugin) {
        cancelDownload(plugin)
        do {
            try FileManager.default.removeItem(at: plugin.localDir)
        } catch {
            Logger.shared.log("PluginManager: uninstall failed for \(plugin.id): \(error)")
        }
        lock.lock()
        states[plugin.id] = .notDownloaded
        lock.unlock()
        postChange()
    }

    // MARK: - Download

    /// Download all files of `plugin` (skipping ones already verified), with
    /// per-file SHA256 verification. `progress` is called on the main thread
    /// with overall progress 0.0...1.0; `completion` likewise.
    func download(_ plugin: ModelPlugin,
                  progress: @escaping (Double) -> Void,
                  completion: @escaping (Result<Void, Error>) -> Void) {
        lock.lock()
        if activeTasks[plugin.id] != nil {
            lock.unlock()
            return
        }
        cancelled.remove(plugin.id)
        states[plugin.id] = .downloading(progress: 0)
        progressCallbacks[plugin.id] = progress
        lock.unlock()
        postChange()

        let session = makeSession()
        let files = plugin.files

        // Serialize file downloads; each file: download → verify → move.
        let queue = DispatchQueue(label: "pixai.plugin.download", qos: .userInitiated)
        queue.async { [weak self] in
            guard let self = self else { return }
            var completed = 0
            for file in files {
                self.lock.lock()
                let isCancelled = self.cancelled.contains(plugin.id)
                self.lock.unlock()
                if isCancelled {
                    self.finishDownload(plugin, overall: Double(completed) / Double(files.count),
                                        result: .failure(PluginError.downloadFailed("cancelled")))
                    return
                }

                do {
                    try self.downloadFile(plugin, file: file, session: session,
                                          baseProgress: Double(completed) / Double(files.count),
                                          fileFraction: 1.0 / Double(files.count))
                    completed += 1
                } catch {
                    self.finishDownload(plugin, overall: Double(completed) / Double(files.count),
                                        result: .failure(error))
                    return
                }
            }
            // All files verified → plugin ready and enabled by default.
            try? FileManager.default.createDirectory(at: plugin.localDir, withIntermediateDirectories: true)
            try? Data("1".utf8).write(to: plugin.localDir.appendingPathComponent(".enabled"), options: .atomic)
            self.lock.lock()
            self.states[plugin.id] = .ready
            self.activeTasks.removeValue(forKey: plugin.id)
            self.progressCallbacks.removeValue(forKey: plugin.id)
            self.lock.unlock()
            postChange()
            DispatchQueue.main.async {
                completion(.success(()))
            }
        }
    }

    private func finishDownload(_ plugin: ModelPlugin, overall: Double, result: Result<Void, Error>) {
        lock.lock()
        if case .failure(let error) = result {
            states[plugin.id] = .error(error.localizedDescription)
        } else {
            states[plugin.id] = .ready
        }
        activeTasks.removeValue(forKey: plugin.id)
        activeSessions.removeValue(forKey: plugin.id)
        cancelled.remove(plugin.id)
        progressCallbacks.removeValue(forKey: plugin.id)
        lock.unlock()
        postChange()
        DispatchQueue.main.async { [weak self] in
            switch result {
            case .success:
                self?.refreshStates()
            case .failure(let error):
                Logger.shared.log("PluginManager: download failed for \(plugin.id): \(error.localizedDescription)")
            }
        }
    }

    func cancelDownload(_ plugin: ModelPlugin) {
        lock.lock()
        if let task = activeTasks[plugin.id] {
            task.cancel()
        }
        cancelled.insert(plugin.id)
        activeTasks.removeValue(forKey: plugin.id)
        activeSessions.removeValue(forKey: plugin.id)
        progressCallbacks.removeValue(forKey: plugin.id)
        states[plugin.id] = .notDownloaded
        lock.unlock()
        postChange()
    }

    // MARK: - Single file download + verify

    private func downloadFile(_ plugin: ModelPlugin,
                              file: (path: String, sha256: String),
                              session: URLSession,
                              baseProgress: Double,
                              fileFraction: Double) throws {
        let destURL = plugin.localURL(forPath: file.path)
        let fm = FileManager.default

        // Already present and verified? Skip.
        if fm.fileExists(atPath: destURL.path),
           let actual = Self.sha256Hex(ofFile: destURL),
           actual.lowercased() == file.sha256.lowercased() {
            setDownloadProgress(plugin, baseProgress + fileFraction)
            return
        }
        try? fm.removeItem(at: destURL)
        try fm.createDirectory(at: destURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let remoteURL = URL(string: "\(plugin.downloadBaseURL)/\(file.path)")!
        Logger.shared.log("PluginManager: downloading from \(remoteURL.absoluteString)")

        // Download with progress via delegate.
        let delegate = DownloadDelegate()
        delegate.onProgress = { [weak self] (written, total) in
            guard let self = self else { return }
            let frac = total > 0 ? Double(written) / Double(total) : 0
            self.setDownloadProgress(plugin, baseProgress + frac * fileFraction)
        }

        // Create a session with the delegate for progress callbacks
        let cfg = Self.makeProxyConfiguration()
        let delegateSession = URLSession(configuration: cfg, delegate: delegate, delegateQueue: nil)

        let task = delegateSession.downloadTask(with: remoteURL)
        lock.lock()
        activeTasks[plugin.id] = task
        activeSessions[plugin.id] = delegateSession  // Keep session alive
        lock.unlock()
        task.resume()

        // Pump the run loop until the task finishes (this runs on a background queue).
        while task.state == .running || task.state == .suspended {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.2))
        }

        // Clean up session reference
        lock.lock()
        activeSessions.removeValue(forKey: plugin.id)
        let wasCancelled = cancelled.contains(plugin.id)
        lock.unlock()

        let taskError = task.error
        if wasCancelled || taskError != nil {
            if let error = taskError, (error as NSError).code != NSURLErrorCancelled {
                Logger.shared.log("PluginManager: download error: \(error.localizedDescription)")
                throw PluginError.downloadFailed(error.localizedDescription)
            } else {
                throw PluginError.downloadFailed("cancelled")
            }
        }

        guard let location = delegate.location else {
            Logger.shared.log("PluginManager: no temporary file delivered")
            throw PluginError.downloadFailed("no temporary file delivered")
        }

        // Verify SHA256 of the downloaded bytes before moving into place.
        // Empty SHA256 means directory package - just check existence after move.
        if !file.sha256.isEmpty {
            let actual = Self.sha256Hex(ofFile: location) ?? ""
            if actual.lowercased() != file.sha256.lowercased() {
                try? fm.removeItem(at: location)
                throw PluginError.shaMismatch(pluginID: plugin.id, path: file.path,
                                              expected: file.sha256, actual: actual)
            }
        }
        try fm.moveItem(at: location, to: destURL)

        // Extract .zip files automatically
        if destURL.pathExtension.lowercased() == "zip" {
            let parentDir = destURL.deletingLastPathComponent()
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            task.arguments = ["-o", destURL.path, "-d", parentDir.path]
            try task.run()
            task.waitUntilExit()
            // Delete the zip after extraction
            try? fm.removeItem(at: destURL)
        }

        setDownloadProgress(plugin, baseProgress + fileFraction)
    }

    /// Update the in-flight download progress state (main-thread safe).
    private func setDownloadProgress(_ plugin: ModelPlugin, _ value: Double) {
        lock.lock()
        if case .downloading = states[plugin.id] ?? .notDownloaded {
            states[plugin.id] = .downloading(progress: value)
        }
        let callback = progressCallbacks[plugin.id]
        lock.unlock()
        postChange()
        // Call progress callback on main thread
        if let callback = callback {
            DispatchQueue.main.async {
                callback(value)
            }
        }
    }

    /// Minimal URLSessionDownloadTask delegate capturing the temp file URL and progress.
    private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate {
        var location: URL?
        var onProgress: ((Int64, Int64) -> Void)?

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            onProgress?(totalBytesWritten, totalBytesExpectedToWrite)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            self.location = location
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            if let error = error {
                Logger.shared.log("PluginManager: download task completed with error: \(error.localizedDescription)")
            } else {
                Logger.shared.log("PluginManager: download task completed successfully")
            }
        }

        // Handle redirects for ModelScope CDN
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) {
            Logger.shared.log("PluginManager: redirecting to \(request.url?.absoluteString ?? "unknown")")
            completionHandler(request)
        }
    }

    // MARK: - Proxy-aware session

    /// Build a URLSessionConfiguration honoring the configured proxy.
    /// HTTP/HTTPS proxies are used directly; SOCKS is passed through CFNetwork's
    /// SOCKS proxy keys (supported by CFNetwork's proxy dictionary).
    static func makeProxyConfiguration() -> URLSessionConfiguration {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 300
        cfg.timeoutIntervalForResource = 4 * 3600
        cfg.httpMaximumConnectionsPerHost = 2

        let app = AppConfig.shared
        if app.proxyEnabled, !app.proxyHost.isEmpty {
            let host = app.proxyHost
            let port = app.proxyPort
            var dict: [AnyHashable: Any] = [:]
            if app.proxyType == "socks" {
                dict["SOCKSProxy"] = host
                dict["SOCKSPort"] = port
            } else {
                dict["HTTPProxy"] = host
                dict["HTTPPort"] = port
                dict["HTTPSProxy"] = host
                dict["HTTPSPort"] = port
            }
            cfg.connectionProxyDictionary = dict
        }
        return cfg
    }

    private func makeSession() -> URLSession {
        return URLSession(configuration: Self.makeProxyConfiguration(),
                          delegate: nil,
                          delegateQueue: OperationQueue())
    }

    // MARK: - SHA256

    /// Streaming SHA256 of a file (hex string), without loading it into memory.
    static func sha256Hex(ofFile url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = handle.readData(ofLength: 1 << 20)
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func postChange() {
        let post = {
            NotificationCenter.default.post(name: PluginManager.stateDidChangeNotification, object: self)
        }
        if isInitializing || !Thread.isMainThread {
            // During singleton init a synchronous post would re-enter the
            // dispatch_once that is currently running this init (observers
            // read shared again) → recursive-lock crash. Defer one tick.
            DispatchQueue.main.async(execute: post)
        } else {
            post()
        }
    }
}
