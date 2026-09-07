import AppKit

/// Global variables to pass parsed arguments to the SwiftUI app.
var commandPaths: [String] = []
var isFullscreenMode = false

/// Parse command-line arguments and launch the application.
/// Supports:
/// - `./PixAI /path/to/image.jpg`
/// - `./PixAI /path/to/folder/`
/// - `./PixAI /folder1/ /folder2/`
/// - `./PixAI --fullscreen`

let args = CommandLine.arguments.dropFirst() // skip executable path
for arg in args {
    if arg == "--fullscreen" {
        isFullscreenMode = true
    } else {
        commandPaths.append(arg)
    }
}

// Create the SwiftUI app instance (it will be used as the delegate)
let pixaiApp = PixAIApp()

// Set up the application
let app = NSApplication.shared
app.delegate = pixaiApp
app.run()
