// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Builds the complete application menu bar.
///
/// Every custom action item targets `MenuActions.shared` (an
/// NSMenuItemValidation conformer) so AppKit can enable/disable items from the
/// key window's state. All titles go through L10n; PixAIApp rebuilds the whole
/// bar when the UI language changes.
class MenuBuilder {
    /// Optional callbacks (set by PixAIApp).
    static var openFileCallback: (() -> Void)?

    /// Optional callback for the New Window action (set by PixAIApp).
    static var newWindowCallback: (() -> Void)?

    /// Optional callback for the Preferences action (set by PixAIApp).
    static var preferencesCallback: (() -> Void)?

    /// Optional callback for the Check for Updates action (set by PixAIApp).
    static var checkForUpdatesCallback: (() -> Void)?

    /// Provides the active viewer window for validation + routing (set by PixAIApp).
    static var activeWindowProvider: (() -> ImageWindow?)?

    static func build() -> NSMenu {
        let t = L10n.shared.t
        let actions = MenuActions.shared
        let mainMenu = NSMenu(title: "PixAI")

        /// Add an item that routes through `MenuActions` (validated per window).
        func actionItem(_ menu: NSMenu, _ title: String, _ selector: Selector,
                        key: String = "", mask: NSEvent.ModifierFlags = .command) {
            let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
            if !key.isEmpty { item.keyEquivalentModifierMask = mask }
            item.target = actions
            menu.addItem(item)
        }

        // ─── PixAI Menu ──────────────────────────────────────────────
        let pixaiMenu = NSMenu(title: "PixAI")

        let aboutItem = NSMenuItem(title: t("About PixAI"), action: #selector(MenuActions.showAbout(_:)), keyEquivalent: "")
        aboutItem.target = actions
        pixaiMenu.addItem(aboutItem)

        let updatesItem = NSMenuItem(title: t("Check for Updates..."), action: #selector(MenuActions.checkForUpdates(_:)), keyEquivalent: "")
        updatesItem.target = actions
        pixaiMenu.addItem(updatesItem)

        pixaiMenu.addItem(NSMenuItem.separator())

        let prefsItem = NSMenuItem(title: t("Preferences..."), action: #selector(MenuActions.showPreferences(_:)), keyEquivalent: ",")
        prefsItem.target = actions
        pixaiMenu.addItem(prefsItem)

        pixaiMenu.addItem(NSMenuItem.separator())

        let servicesItem = NSMenuItem(title: t("Services"), action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        servicesItem.submenu = servicesMenu
        NSApplication.shared.servicesMenu = servicesMenu
        pixaiMenu.addItem(servicesItem)

        pixaiMenu.addItem(NSMenuItem.separator())

        pixaiMenu.addItem(withTitle: t("Hide PixAI"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: t("Hide Others"), action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        pixaiMenu.addItem(hideOthersItem)
        pixaiMenu.addItem(withTitle: t("Show All"), action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")

        pixaiMenu.addItem(NSMenuItem.separator())
        pixaiMenu.addItem(withTitle: t("Quit PixAI"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let pixaiMenuItem = NSMenuItem()
        pixaiMenuItem.title = "PixAI"
        pixaiMenuItem.submenu = pixaiMenu
        mainMenu.addItem(pixaiMenuItem)

        // ─── File Menu ───────────────────────────────────────────────
        let fileMenu = NSMenu(title: t("File"))

        actionItem(fileMenu, t("Open..."), #selector(MenuActions.openFile(_:)), key: "o")
        actionItem(fileMenu, t("New Window"), #selector(MenuActions.newWindow(_:)), key: "n")
        fileMenu.addItem(NSMenuItem.separator())
        actionItem(fileMenu, t("Save"), #selector(MenuActions.save(_:)), key: "s")
        actionItem(fileMenu, t("Save As..."), #selector(MenuActions.saveAs(_:)), key: "s", mask: [.command, .shift])
        actionItem(fileMenu, t("Rename..."), #selector(MenuActions.rename(_:)))
        actionItem(fileMenu, t("Delete"), #selector(MenuActions.delete(_:)), key: "\u{7F}")
        fileMenu.addItem(NSMenuItem.separator())

        // Standard close: goes through the responder chain to the key window.
        let closeWindowItem = NSMenuItem(title: t("Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeWindowItem.target = nil
        fileMenu.addItem(closeWindowItem)

        let fileMenuItem = NSMenuItem()
        fileMenuItem.title = t("File")
        fileMenuItem.submenu = fileMenu
        mainMenu.addItem(fileMenuItem)

        // ─── Edit Menu ───────────────────────────────────────────────
        let editMenu = NSMenu(title: t("Edit"))
        actionItem(editMenu, t("Copy"), #selector(MenuActions.copy(_:)), key: "c")
        actionItem(editMenu, t("Paste"), #selector(MenuActions.paste(_:)), key: "v")

        let editMenuItem = NSMenuItem()
        editMenuItem.title = t("Edit")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // ─── View Menu ───────────────────────────────────────────────
        let viewMenu = NSMenu(title: t("View"))

        actionItem(viewMenu, t("Zoom In"), #selector(MenuActions.zoomIn(_:)))
        actionItem(viewMenu, t("Zoom Out"), #selector(MenuActions.zoomOut(_:)))
        actionItem(viewMenu, t("Fit / 100%"), #selector(MenuActions.fitToggle(_:)))
        actionItem(viewMenu, t("Crop"), #selector(MenuActions.crop(_:)))
        viewMenu.addItem(NSMenuItem.separator())
        // Bare-R rotation is handled by the window's keyboard handler; only
        // the ⌘R (counterclockwise) binding lives in the menu.
        actionItem(viewMenu, t("Rotate Clockwise"), #selector(MenuActions.rotateClockwiseAction(_:)))
        actionItem(viewMenu, t("Rotate Counterclockwise"), #selector(MenuActions.rotateCounterclockwiseAction(_:)), key: "r")
        viewMenu.addItem(NSMenuItem.separator())
        actionItem(viewMenu, t("Play/Pause"), #selector(MenuActions.playPause(_:)))
        actionItem(viewMenu, t("Start/Stop Slideshow"), #selector(MenuActions.startStopSlideshow(_:)))
        viewMenu.addItem(NSMenuItem.separator())

        let enterFullScreenItem = NSMenuItem(title: t("Enter Full Screen"), action: #selector(MenuActions.toggleFullScreenAction(_:)), keyEquivalent: "")
        enterFullScreenItem.target = actions
        viewMenu.addItem(enterFullScreenItem)
        // Standard ⌃⌘F binding through the responder chain (key window).
        let toggleFullScreenItem = NSMenuItem(title: t("Toggle Full Screen"), action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        toggleFullScreenItem.keyEquivalentModifierMask = [.command, .control]
        toggleFullScreenItem.target = nil
        viewMenu.addItem(toggleFullScreenItem)

        let viewMenuItem = NSMenuItem()
        viewMenuItem.title = t("View")
        viewMenuItem.submenu = viewMenu
        mainMenu.addItem(viewMenuItem)

        // ─── AI Menu (between View and Window) ───────────────────────
        let aiMenu = NSMenu(title: "AI")

        actionItem(aiMenu, t("AI Super-Resolution"), #selector(MenuActions.aiUpscale(_:)))
        actionItem(aiMenu, t("AI Watermark Removal"), #selector(MenuActions.aiDewatermark(_:)))
        actionItem(aiMenu, t("AI Manual Watermark Removal"), #selector(MenuActions.aiManualDewatermark(_:)))
        actionItem(aiMenu, t("AI Quality Enhance"), #selector(MenuActions.aiEnhance(_:)))
        aiMenu.addItem(NSMenuItem.separator())
        actionItem(aiMenu, t("AI Dedup"), #selector(MenuActions.aiDedup(_:)))
        actionItem(aiMenu, t("One-Click AI Auto-Enhance"), #selector(MenuActions.aiOneClick(_:)))

        let aiMenuItem = NSMenuItem()
        aiMenuItem.title = "AI"
        aiMenuItem.submenu = aiMenu
        mainMenu.addItem(aiMenuItem)

        // ─── Window Menu ─────────────────────────────────────────────
        let windowMenu = NSMenu(title: t("Window"))

        let minimizeItem = NSMenuItem(title: t("Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        minimizeItem.target = nil
        windowMenu.addItem(minimizeItem)

        let zoomItem = NSMenuItem(title: t("Zoom"), action: #selector(NSWindow.zoom(_:)), keyEquivalent: "")
        zoomItem.target = nil
        windowMenu.addItem(zoomItem)

        // Standard close: goes through the responder chain to the key window.
        let closeItem = NSMenuItem(title: t("Close Window"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        closeItem.target = nil
        windowMenu.addItem(closeItem)

        // AppKit appends the open-window list to the designated windows menu.
        NSApplication.shared.windowsMenu = windowMenu

        let windowMenuItem = NSMenuItem()
        windowMenuItem.title = t("Window")
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        // ─── Help Menu ───────────────────────────────────────────────
        let helpMenu = NSMenu(title: t("Help"))

        let shortcutsItem = NSMenuItem(title: t("Shortcuts"), action: #selector(MenuActions.showShortcuts(_:)), keyEquivalent: "?")
        shortcutsItem.target = actions
        helpMenu.addItem(shortcutsItem)

        let helpMenuItem = NSMenuItem()
        helpMenuItem.title = t("Help")
        helpMenuItem.submenu = helpMenu
        mainMenu.addItem(helpMenuItem)

        return mainMenu
    }
}

/// Target for all custom menu items. Implements `NSMenuItemValidation` so
/// AppKit can enable/disable items from the key window's state (has image /
/// batch running / model availability).
final class MenuActions: NSObject, NSMenuItemValidation {
    static let shared = MenuActions()
    private override init() {}

    // MARK: - Always-available actions

    /// About panel with the project homepage link + copyright line.
    @objc func showAbout(_ sender: Any?) {
        let credits = NSMutableAttributedString()
        let homeURL = URL(string: "https://github.com/J-Liu/PixAI")!
        credits.append(NSAttributedString(string: "https://github.com/J-Liu/PixAI", attributes: [
            .link: homeURL,
            .font: NSFont.systemFont(ofSize: 11)
        ]))
        credits.append(NSAttributedString(string: "\n\nCopyright © 2026 Jia Liu All rights reserved.", attributes: [
            .font: NSFont.systemFont(ofSize: 11)
        ]))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    @objc func checkForUpdates(_ sender: Any?) {
        Logger.shared.log("MenuBuilder.checkForUpdates called")
        MenuBuilder.checkForUpdatesCallback?()
    }

    @objc func showPreferences(_ sender: Any?) {
        Logger.shared.log("MenuBuilder.showPreferences called")
        MenuBuilder.preferencesCallback?()
    }

    @objc func openFile(_ sender: Any?) {
        Logger.shared.log("MenuBuilder.openFile called")
        MenuBuilder.openFileCallback?()
    }

    @objc func newWindow(_ sender: Any?) {
        Logger.shared.log("MenuBuilder.newWindow called")
        MenuBuilder.newWindowCallback?()
    }

    @objc func showShortcuts(_ sender: Any?) {
        ShortcutsHelpWindow.shared.show()
    }

    // MARK: - Window-scoped actions (routed to the active window)

    @objc func save(_ sender: Any?) { MenuBuilder.activeWindowProvider?()?.saveCurrentRotation() }
    @objc func saveAs(_ sender: Any?) { MenuBuilder.activeWindowProvider?()?.saveAsImage() }
    @objc func rename(_ sender: Any?) { MenuBuilder.activeWindowProvider?()?.renameCurrentImage() }
    @objc func delete(_ sender: Any?) { MenuBuilder.activeWindowProvider?()?.deleteCurrentImage() }
    @objc func crop(_ sender: Any?) { MenuBuilder.activeWindowProvider?()?.toggleCropMode() }
    @objc func rotateClockwiseAction(_ sender: Any?) { MenuBuilder.activeWindowProvider?()?.rotateClockwise() }
    @objc func rotateCounterclockwiseAction(_ sender: Any?) { MenuBuilder.activeWindowProvider?()?.rotateCounterclockwise() }
    @objc func zoomIn(_ sender: Any?) { MenuBuilder.activeWindowProvider?()?.zoomIn() }
    @objc func zoomOut(_ sender: Any?) { MenuBuilder.activeWindowProvider?()?.zoomOut() }
    @objc func fitToggle(_ sender: Any?) { MenuBuilder.activeWindowProvider?()?.toggleFitOr100Percent() }
    @objc func playPause(_ sender: Any?) { MenuBuilder.activeWindowProvider?()?.togglePlayPause() }
    @objc func startStopSlideshow(_ sender: Any?) { MenuBuilder.activeWindowProvider?()?.startOrStopSlideshow() }
    @objc func toggleFullScreenAction(_ sender: Any?) { MenuBuilder.activeWindowProvider?()?.toggleFullScreen() }
    @objc func aiUpscale(_ sender: Any?) { MenuBuilder.activeWindowProvider?()?.toggleAIUpscale() }
    @objc func aiDewatermark(_ sender: Any?) { MenuBuilder.activeWindowProvider?()?.toggleAIDewatermark() }
    @objc func aiManualDewatermark(_ sender: Any?) { MenuBuilder.activeWindowProvider?()?.startManualWatermarkRemoval() }
    @objc func aiEnhance(_ sender: Any?) { MenuBuilder.activeWindowProvider?()?.toggleAIEnhance() }
    @objc func aiDedup(_ sender: Any?) { MenuBuilder.activeWindowProvider?()?.runAIDedup() }
    @objc func aiOneClick(_ sender: Any?) { MenuBuilder.activeWindowProvider?()?.runAIOneClickEnhance() }
    @objc func copy(_ sender: Any?) { MenuBuilder.activeWindowProvider?()?.copyImage() }
    @objc func paste(_ sender: Any?) { MenuBuilder.activeWindowProvider?()?.pasteImage() }

    // MARK: - NSMenuItemValidation

    /// Enable state: items acting on the current image require a window with an
    /// image loaded and no running batch; model-backed AI items additionally
    /// require the model to be downloaded.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else { return false }
        switch action {
        case #selector(showAbout(_:)), #selector(checkForUpdates(_:)), #selector(showPreferences(_:)),
             #selector(openFile(_:)), #selector(newWindow(_:)), #selector(showShortcuts(_:)):
            return true
        default:
            break
        }
        guard let provider = MenuBuilder.activeWindowProvider,
              let win = provider() else { return false }
        switch action {
        case #selector(aiUpscale(_:)):
            return win.hasCurrentImage && !win.isBatchRunning && RealESRGANEngine.shared.isAvailable
        case #selector(aiDewatermark(_:)), #selector(aiManualDewatermark(_:)):
            return win.hasCurrentImage && !win.isBatchRunning && U2NetEngine.shared.isAvailable
        case #selector(aiDedup(_:)):
            return win.hasCurrentImage && !win.isBatchRunning && win.imageCount > 1
        default:
            break
        }
        return win.hasCurrentImage && !win.isBatchRunning
    }
}
