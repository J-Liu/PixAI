import AppKit

/// Builds the complete application menu bar.
class MenuBuilder {
    /// Optional callback for the Open File action (set by PixAIApp).
    static var openFileCallback: (() -> Void)?
    
    static func build() -> NSMenu {
        let mainMenu = NSMenu(title: "PixAI")

        // ─── PixAI Menu ──────────────────────────────────────────────
        let pixaiMenu = NSMenu(title: "PixAI")
        pixaiMenu.addItem(withTitle: "About PixAI", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        pixaiMenu.addItem(NSMenuItem.separator())

        // Preferences (Cmd+,) — placeholder, disabled until implemented
        let prefsItem = NSMenuItem(title: "Preferences...", action: nil, keyEquivalent: ",")
        prefsItem.isEnabled = false
        pixaiMenu.addItem(prefsItem)

        pixaiMenu.addItem(NSMenuItem.separator())
        pixaiMenu.addItem(withTitle: "Services", action: nil, keyEquivalent: "")

        pixaiMenu.addItem(NSMenuItem.separator())
        pixaiMenu.addItem(withTitle: "Hide PixAI", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        pixaiMenu.addItem(hideOthersItem)

        pixaiMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")

        pixaiMenu.addItem(NSMenuItem.separator())
        pixaiMenu.addItem(withTitle: "Quit PixAI", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Add submenu to main menu
        let pixaiMenuItem = NSMenuItem()
        pixaiMenuItem.title = "PixAI"
        pixaiMenuItem.submenu = pixaiMenu
        mainMenu.addItem(pixaiMenuItem)

        // ─── File Menu ───────────────────────────────────────────────
        let fileMenu = NSMenu(title: "File")
        
        let openItem = NSMenuItem(title: "Open...", action: #selector(openFile(_:)), keyEquivalent: "o")
        openItem.target = self
        fileMenu.addItem(openItem)

        let fileMenuItem = NSMenuItem()
        fileMenuItem.title = "File"
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // ─── View Menu ───────────────────────────────────────────────
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Full Screen", action: #selector(toggleFullScreen(_:)), keyEquivalent: "f")
        viewMenu.addItem(NSMenuItem.separator())

        let viewMenuItem = NSMenuItem()
        viewMenuItem.title = "View"
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // ─── Window Menu ─────────────────────────────────────────────
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(minimize(_:)), keyEquivalent: "m")

        let windowMenuItem = NSMenuItem()
        windowMenuItem.title = "Window"
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        // ─── Help Menu ───────────────────────────────────────────────
        let helpMenu = NSMenu(title: "Help")
        helpMenu.addItem(withTitle: "Shortcuts", action: #selector(showShortcuts(_:)), keyEquivalent: "?")

        let helpMenuItem = NSMenuItem()
        helpMenuItem.title = "Help"
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        return mainMenu
    }

    @objc class func openFile(_ sender: Any?) {
        Logger.shared.log("MenuBuilder.openFile called")
        if let callback = openFileCallback {
            callback()
        } else {
            Logger.shared.log("No openFileCallback set")
        }
    }

    @objc class func toggleFullScreen(_ sender: Any?) {
        guard let window = NSApplication.shared.mainWindow else { return }
        window.toggleFullScreen(nil)
    }

    @objc class func minimize(_ sender: Any?) {
        guard let window = NSApplication.shared.mainWindow else { return }
        window.miniaturize(nil)
    }

    @objc class func showShortcuts(_ sender: Any?) {
        Logger.shared.log("Shortcuts (placeholder)")
    }
}
