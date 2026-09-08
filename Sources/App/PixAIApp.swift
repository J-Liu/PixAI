import AppKit
import UniformTypeIdentifiers

/// The application delegate. Sets up the menu bar and manages viewer windows.
/// Closing a window (Cmd+W) does NOT quit the app; Cmd+N opens a new blank window.
class PixAIApp: NSObject, NSApplicationDelegate {
    /// Paths passed from command-line arguments (files or folders).
    private let paths: [String]
    /// Whether to launch in fullscreen mode.
    private let isFullscreen: Bool
    
    /// All open viewer windows (strong references; closing a window removes it).
    private var imageWindows: [ImageWindow] = []
    
    override init() {
        self.paths = commandPaths
        self.isFullscreen = isFullscreenMode
        super.init()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.log("applicationDidFinishLaunching")
        
        // Build and set the menu bar.
        NSApplication.shared.mainMenu = MenuBuilder.build()
        
        // Open: use the active window, or create one if none is open.
        MenuBuilder.openFileCallback = { [weak self] in
            guard let self = self else { return }
            if let target = self.activeWindow() {
                target.presentOpenPanel()
            } else {
                let win = self.makeNewWindow(paths: [])
                win.presentOpenPanel()
            }
        }
        
        // New Window (Cmd+N): always a blank window.
        MenuBuilder.newWindowCallback = { [weak self] in
            self?.makeNewWindow(paths: [])
        }
        
        // Create the first window with command-line paths (if any).
        let urlPaths = paths.compactMap { URL(fileURLWithPath: $0) }
        let first = makeNewWindow(paths: urlPaths)
        
        // If fullscreen flag is set, enter fullscreen immediately.
        if isFullscreen {
            first.window.toggleFullScreen(nil)
        }
        
        Logger.shared.log("PixAIApp initialized with \(imageWindows.count) window(s)")
    }
    
    /// Closing the last window does not quit the app.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// The app stays alive after all windows close; clicking its Dock icon then
    /// reopens a new blank window (per Apple docs, this delegate method fires
    /// when the Finder/Dock reactivates an already running app).
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            Logger.shared.log("Dock icon clicked with no visible windows, opening a new window")
            makeNewWindow(paths: [])
        }
        return true
    }

    /// The key viewer window, or the most recently created one.
    private func activeWindow() -> ImageWindow? {
        for win in imageWindows where win.window.isKeyWindow {
            return win
        }
        return imageWindows.last
    }
    
    /// Create and show a new viewer window, optionally loading the given paths.
    @discardableResult
    private func makeNewWindow(paths: [URL]) -> ImageWindow {
        let win = ImageWindow()
        imageWindows.append(win)
        
        win.onClose = { [weak self] closed in
            self?.removeWindow(closed)
        }
        
        win.show()
        
        if !paths.isEmpty {
            win.loadImages(from: paths)
        }
        
        return win
    }
    
    private func removeWindow(_ win: ImageWindow) {
        imageWindows.removeAll { $0 === win }
        Logger.shared.log("Window closed, \(imageWindows.count) window(s) remain")
    }
}
