import SwiftUI
import AppKit

/// The application delegate. Sets the icon, menu bar, and creates the main window.
class PixAIApp: NSObject, NSApplicationDelegate {
    /// Paths passed from command-line arguments (files or folders).
    private let paths: [String]
    /// Whether to launch in fullscreen mode.
    private let isFullscreen: Bool

    override init() {
        // Read global variables set by main.swift
        self.paths = commandPaths
        self.isFullscreen = isFullscreenMode
        super.init()

        // Set the application icon from the embedded .icns resource.
        // Try to find the icon in the app bundle's resources.
        if let icnsURL = Bundle.main.url(forResource: "PixAI", withExtension: "icns") {
            NSApplication.shared.applicationIconImage = NSImage(contentsOf: icnsURL)
        } else {
            // Fallback: try to find the icon in the executable's bundle.
            let exePath = Bundle.main.executablePath!
            if let appBundlePath = (exePath as NSString).deletingLastPathComponent as? URL {
                let icnsPath = appBundlePath.appendingPathComponent("PixAI.icns")
                if FileManager.default.fileExists(atPath: icnsPath.path) {
                    NSApplication.shared.applicationIconImage = NSImage(contentsOf: icnsPath)
                }
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Build and set the menu bar.
        NSApplication.shared.mainMenu = MenuBuilder.build()

        // Create the main window.
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PixAI"
        window.center()

        // Embed the SwiftUI content view in a NSHostingController.
        let hostingController = NSHostingController(rootView: ContentView(paths: paths))
        window.contentView = hostingController.view
        window.makeKeyAndOrderFront(nil)

        // If fullscreen flag is set, enter fullscreen immediately.
        if isFullscreen {
            window.toggleFullScreen(nil)
        }
    }
}
