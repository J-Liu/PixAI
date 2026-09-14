// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

/// Simple file-based logger for the application.
///
/// Logging is OFF by default (`AppConfig.logEnabled == false`); while disabled,
/// `log(_:)` is a no-op. When enabled, entries are appended to the configured
/// log file (`AppConfig.logPath`, default `~/.pixai/PixAI.log`). Both values
/// are read on every call, so toggling them in Preferences takes effect at once.
class Logger {
    static let shared = Logger()

    /// Intentionally empty: the first access to `Logger.shared` may be triggered
    /// from inside `AppConfig.init`, so this init must not touch AppConfig.
    private init() {}

    /// Append a timestamped message when logging is enabled.
    func log(_ message: String) {
        guard AppConfig.shared.logEnabled else { return }

        let url = URL(fileURLWithPath: AppConfig.shared.logPath, isDirectory: false)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logEntry = "[\(timestamp)] \(message)\n"

        // Make sure the parent directory exists (the path may have just changed).
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            if let data = logEntry.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        } else {
            // File missing or unreadable: (re)create it, then retry once.
            do {
                try logEntry.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                FileHandle.standardError.write(Data("PixAI: failed to write log to \(url.path): \(error)\n".utf8))
            }
        }
    }
}
