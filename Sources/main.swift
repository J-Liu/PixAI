import AppKit

/// Global variables to pass parsed arguments to the AppKit app.
var commandPaths: [String] = []
var isFullscreenMode = false

@main
struct PixAIEntry {
    static func main() {
        Logger.shared.log("Application starting")

        // Parse command-line arguments
        let args = CommandLine.arguments.dropFirst() // skip executable path
        var skippedNonexistent = 0
        for arg in args {
            if arg == "--fullscreen" {
                isFullscreenMode = true
            } else {
                let url = URL(fileURLWithPath: arg)
                if FileManager.default.fileExists(atPath: url.path) {
                    commandPaths.append(arg)
                } else {
                    Logger.shared.log("WARNING: Path does not exist, skipping: \(arg)")
                    skippedNonexistent += 1
                }
            }
        }

        Logger.shared.log("Parsed arguments: \(commandPaths.count) valid paths, fullscreen=\(isFullscreenMode), skipped \(skippedNonexistent) non-existent")
        for path in commandPaths {
            Logger.shared.log("  Path: \(path)")
        }

        // Create the AppKit app delegate instance
        let pixaiApp = PixAIApp()

        // Set up the application
        let app = NSApplication.shared
        app.delegate = pixaiApp
        app.run()
    }
}
