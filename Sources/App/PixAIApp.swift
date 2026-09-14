// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

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

    /// Rebuilds the menu bar when the UI language changes.
    private var l10nMenuObserver: NSObjectProtocol?
    /// Guards the one-shot startup model check.
    private var modelCheckDone = false

    override init() {
        self.paths = commandPaths
        self.isFullscreen = isFullscreenMode
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Log the loaded config state (no-op while logging is disabled).
        AppConfig.shared.logLoadedState()
        Logger.shared.log("applicationDidFinishLaunching")

        // Clear the image cache when the system signals a memory warning
        // (Dispatch memory-pressure source — macOS has no AppKit equivalent
        // of UIApplication.didReceiveMemoryWarningNotification).
        MemoryPressureMonitor.shared.start()

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

        // Check for Updates: open the GitHub releases page (hardcoded URL, no
        // real version check).
        MenuBuilder.checkForUpdatesCallback = {
            if let url = URL(string: "https://github.com/J-Liu/PixAI/releases") {
                NSWorkspace.shared.open(url)
            }
        }

        // Preferences (Cmd+,): show the shared Preferences window.
        MenuBuilder.preferencesCallback = {
            PreferencesWindow.shared.show()
        }

        // Menu validation + action routing use the active viewer window.
        MenuBuilder.activeWindowProvider = { [weak self] in self?.activeWindow() }

        // Create the first window with command-line paths (if any).
        // Skip if windows already exist (e.g., from application:openFile: called before didFinishLaunching).
        let urlPaths = paths.compactMap { URL(fileURLWithPath: $0) }
        var first: ImageWindow?
        if imageWindows.isEmpty {
            first = makeNewWindow(paths: urlPaths)
        } else if !urlPaths.isEmpty {
            // If we have command-line paths but already have windows, load into the first one.
            imageWindows.first?.loadImages(from: urlPaths)
        }

        // If fullscreen flag is set, enter fullscreen immediately.
        if isFullscreen, let first = first {
            first.window.toggleFullScreen(nil)
        }

        Logger.shared.log("PixAIApp initialized with \(imageWindows.count) window(s)")

        // Rebuild the menu bar when the UI language changes (all titles go
        // through L10n).
        self.l10nMenuObserver = NotificationCenter.default.addObserver(
            forName: L10n.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            NSApplication.shared.mainMenu = MenuBuilder.build()
        }

        // Startup AI-model check (config: ask to download when missing).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.checkAIModelsOnStartup()
        }
    }

    /// Whether closing the last window quits the app (configurable in
    /// Preferences; default: keep running).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return AppConfig.shared.quitOnLastWindowClosed
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
        // All windows closed: release every cached image. The app keeps
        // running (default setting); the cache refills as new images load.
        if imageWindows.isEmpty {
            Logger.shared.log("All windows closed — releasing all image cache")
            ImageCache.shared.removeAll()
        }
        Logger.shared.log("Window closed, \(imageWindows.count) window(s) remain")
    }

    /// Handle file open from Finder (double-click or "Open With").
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        if let win = activeWindow() {
            win.loadImages(from: [url])
        } else {
            _ = makeNewWindow(paths: [url])
        }
        return true
    }

    /// Handle multiple files opened from Finder.
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        if let win = activeWindow() {
            win.loadImages(from: urls)
        } else {
            _ = makeNewWindow(paths: urls)
        }
    }

    /// One-shot startup check: if "ask to download" is enabled and any model
    /// plugin is missing (not downloaded / corrupted / deleted / moved), offer
    /// to open Preferences ▸ AI Models on the first window.
    private func checkAIModelsOnStartup() {
        guard !modelCheckDone else { return }
        modelCheckDone = true
        guard AppConfig.shared.modelCheckPromptEnabled else { return }
        let missing = ModelPlugin.all.filter { !PluginManager.shared.isReady($0) }
        guard !missing.isEmpty, let win = activeWindow() else { return }

        let t = L10n.shared.t
        let alert = NSAlert()
        alert.messageText = t("AI models are missing")
        alert.informativeText = t("The following AI models are not downloaded (or are corrupted / deleted / moved):")
            + "\n" + missing.map { "• \($0.displayName)" }.joined(separator: "\n")
        alert.addButton(withTitle: t("Download now?"))
        alert.addButton(withTitle: t("Later"))
        let check = NSButton(checkboxWithTitle: t("Don't ask again"), target: nil, action: nil)
        alert.accessoryView = check
        alert.beginSheetModal(for: win.window) { response in
            if check.state == .on {
                AppConfig.shared.modelCheckPromptEnabled = false
            }
            if response == .alertFirstButtonReturn {
                PreferencesWindow.shared.show()
            }
        }
    }
}
