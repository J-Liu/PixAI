import AppKit

/// Builds the complete application menu bar.
/// The menu items are wired to standard AppKit selectors or custom actions.
class MenuBuilder {
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
        // Hide Others needs Cmd+Opt+H — set modifier on the item
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
        fileMenu.addItem(withTitle: "Open...", action: #selector(openFile(_:)), keyEquivalent: "o")

        // Open Recent — placeholder, disabled until implemented
        let recentMenu = NSMenu(title: "Open Recent")
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recentMenu
        fileMenu.addItem(recentItem)

        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "Close Window", action: #selector(closeWindow(_:)), keyEquivalent: "w")

        // Save — disabled for now (no image loaded yet)
        let saveItem = NSMenuItem(title: "Save", action: nil, keyEquivalent: "s")
        saveItem.isEnabled = false
        fileMenu.addItem(saveItem)

        let fileMenuItem = NSMenuItem()
        fileMenuItem.title = "File"
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // ─── View Menu ───────────────────────────────────────────────
        let viewMenu = NSMenu(title: "View")
        viewMenu.addItem(withTitle: "Full Screen", action: #selector(toggleFullScreen(_:)), keyEquivalent: "f")
        viewMenu.addItem(NSMenuItem.separator())
        viewMenu.addItem(withTitle: "Zoom In", action: #selector(zoomIn(_:)), keyEquivalent: "=")
        // Zoom In modifier is Cmd+Shift+= on macOS, but we'll use Cmd+= as requested
        let zoomInItem = viewMenu.items.last!
        zoomInItem.keyEquivalentModifierMask = [.command]

        viewMenu.addItem(withTitle: "Zoom Out", action: #selector(zoomOut(_:)), keyEquivalent: "-")
        let zoomOutItem = viewMenu.items.last!
        zoomOutItem.keyEquivalentModifierMask = [.command]

        viewMenu.addItem(withTitle: "Actual Size", action: #selector(actualSize(_:)), keyEquivalent: "0")
        let actualSizeItem = viewMenu.items.last!
        actualSizeItem.keyEquivalentModifierMask = [.command]

        let viewMenuItem = NSMenuItem()
        viewMenuItem.title = "View"
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // ─── Window Menu ─────────────────────────────────────────────
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(minimize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(toggleZoom(_:)), keyEquivalent: "")

        let windowMenuItem = NSMenuItem()
        windowMenuItem.title = "Window"
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        // ─── Help Menu ───────────────────────────────────────────────
        let helpMenu = NSMenu(title: "Help")
        // Placeholder: Shortcuts (?)
        helpMenu.addItem(withTitle: "Shortcuts", action: #selector(showShortcuts(_:)), keyEquivalent: "?")

        let helpMenuItem = NSMenuItem()
        helpMenuItem.title = "Help"
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        return mainMenu
    }

    // MARK: - Action Handlers (can be extended later)

    @objc class func openFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.image, .folder]
        panel.begin { response in
            if response == .OK {
                // Handle opened files/folders — will be wired to ContentView later
                print("Open panel selected: \(panel.urls)")
            }
        }
    }

    @objc class func closeWindow(_ sender: Any?) {
        NSApplication.shared.mainWindow?.performClose(nil)
    }

    @objc class func toggleFullScreen(_ sender: Any?) {
        guard let window = NSApplication.shared.mainWindow else { return }
        window.toggleFullScreen(nil)
    }

    @objc class func zoomIn(_ sender: Any?) {
        // Placeholder — will be wired to image zooming later
        print("Zoom In (placeholder)")
    }

    @objc class func zoomOut(_ sender: Any?) {
        // Placeholder
        print("Zoom Out (placeholder)")
    }

    @objc class func actualSize(_ sender: Any?) {
        // Placeholder
        print("Actual Size (placeholder)")
    }

    @objc class func toggleZoom(_ sender: Any?) {
        guard let window = NSApplication.shared.mainWindow else { return }
        window.performZoom(nil)
    }

    @objc class func showShortcuts(_ sender: Any?) {
        // Placeholder — will be replaced with a real shortcuts window later
        print("Shortcuts (placeholder)")
    }

    @objc class func minimize(_ sender: Any?) {
        guard let window = NSApplication.shared.mainWindow else { return }
        window.miniaturize(nil)
    }
}
