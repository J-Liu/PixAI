import Foundation

/// Simple file-based logger for the application.
/// All log messages are written to a file in the project root directory.
class Logger {
    static let shared = Logger()
    
    private var logFileURL: URL
    
    init() {
        // Log file location: project root / PixAI.log (always try this first)
        let possiblePaths = [
            "/Users/jia/Desktop/PixAI/PixAI.log",
            FileManager.default.currentDirectoryPath + "/PixAI.log",
        ]
        
        var foundURL: URL? = nil
        for path in possiblePaths {
            let url = URL(fileURLWithPath: path)
            do {
                try "".write(to: url, atomically: true, encoding: .utf8)
                foundURL = url
                break
            } catch {
                // Try next path
                continue
            }
        }
        
        if let url = foundURL {
            logFileURL = url
        } else {
            // Ultimate fallback: write to home directory
            logFileURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("PixAI.log")
            do {
                try "".write(to: logFileURL, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to create log file in any location: \(error)")
                // Last resort: use /tmp (may not work in sandbox but worth trying)
                logFileURL = URL(fileURLWithPath: "/tmp/PixAI.log")
                do {
                    try "".write(to: logFileURL, atomically: true, encoding: .utf8)
                } catch {
                    print("Failed to create log file in /tmp either")
                }
            }
        }
        
        // Ensure the log file exists
        if !FileManager.default.fileExists(atPath: logFileURL.path) {
            do {
                try "".write(to: logFileURL, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to create log file: \(error)")
            }
        }
    }
    
    /// Log a message with timestamp.
    func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let logEntry = "[\(timestamp)] \(message)\n"
        
        // Append to file
        if let handle = try? FileHandle(forWritingTo: logFileURL) {
            handle.seekToEndOfFile()
            if let data = logEntry.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        } else {
            // Fallback: read existing content and write the whole file
            do {
                var existingContent = ""
                if let content = try? String(contentsOf: logFileURL, encoding: .utf8) {
                    existingContent = content
                }
                try (existingContent + logEntry).write(to: logFileURL, atomically: true, encoding: .utf8)
            } catch {
                print("Failed to write log: \(error)")
            }
        }
    }
}
