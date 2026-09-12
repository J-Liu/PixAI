import AppKit

/// The Preferences window (Cmd+, / PixAI ▸ Preferences...).
///
/// Settings are grouped into categories (General / Slideshow / Image Cache /
/// Logging). Every control writes straight to `AppConfig.shared`, which
/// persists the new value to `~/.pixai/config.json` immediately and posts a
/// change notification — so edits take effect at once without restarting.
final class PreferencesWindow {
    static let shared = PreferencesWindow()

    private var window: NSWindow?

    // Controls (kept as references so values can be refreshed).
    private var quitCheckbox: NSButton!
    private var deleteConfirmCheckbox: NSButton!
    private var liveAutoPlayCheckbox: NSButton!
    private var liveMutedCheckbox: NSButton!
    private var intervalField: NSTextField!
    private var intervalStepper: NSStepper!
    private var cacheField: NSTextField!
    private var cacheStepper: NSStepper!
    private var logEnabledCheckbox: NSButton!
    private var logPathField: NSTextField!

    private var aiAutoUpscaleCheckbox: NSButton!
    private var aiAutoDewatermarkCheckbox: NSButton!
    private var enhanceModePopup: NSPopUpButton!
    private var dedupAskContinueCheckbox: NSButton!
    private var proxyEnabledCheckbox: NSButton!
    private var proxyTypePopup: NSPopUpButton!
    private var proxyHostField: NSTextField!
    private var proxyPortField: NSTextField!
    private var proxyPortStepper: NSStepper!
    private var modelRows: [(plugin: ModelPlugin, statusLabel: NSTextField, enabledCheck: NSButton)] = []
    private var pluginObserver: NSObjectProtocol?

    private var changeObserver: NSObjectProtocol?

    private init() {}

    /// Show the Preferences window, creating it on first use.
    func show() {
        if window == nil {
            buildWindow()
        }
        syncControlsFromConfig()
        guard let window = window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Building

    private func buildWindow() {
        let contentSize = NSSize(width: 520, height: 950)
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Preferences"
        win.isReleasedWhenClosed = false

        // Flipped container so the layout below reads top-to-bottom.
        let root = FlippedView(frame: NSRect(origin: .zero, size: contentSize))
        win.contentView = root

        let margin: CGFloat = 20
        let sectionWidth = contentSize.width - margin * 2
        var y: CGFloat = 16

        // ─── General ────────────────────────────────────────────────
        let generalContentH: CGFloat = 64
        let generalBox = makeSection(root, title: "General", x: margin, y: y, width: sectionWidth, contentHeight: generalContentH)
        quitCheckbox = makeCheck(generalBox.contentView!, title: "Quit app when the last window is closed", x: 14, y: 10)
        quitCheckbox.state = AppConfig.shared.quitOnLastWindowClosed ? .on : .off
        quitCheckbox.target = self
        quitCheckbox.action = #selector(toggleQuitOnLastClose(_:))

        deleteConfirmCheckbox = makeCheck(generalBox.contentView!, title: "Ask for confirmation before deleting a file", x: 14, y: 38)
        deleteConfirmCheckbox.state = AppConfig.shared.deleteConfirmationEnabled ? .on : .off
        deleteConfirmCheckbox.target = self
        deleteConfirmCheckbox.action = #selector(toggleDeleteConfirm(_:))
        y += generalBox.frame.height + 14

        // ─── Live Photo ─────────────────────────────────────────────
        let liveContentH: CGFloat = 64
        let liveBox = makeSection(root, title: "Live Photo", x: margin, y: y, width: sectionWidth, contentHeight: liveContentH)
        liveAutoPlayCheckbox = makeCheck(liveBox.contentView!, title: "Auto-play Live Photos when displayed", x: 14, y: 10)
        liveAutoPlayCheckbox.state = AppConfig.shared.livePhotoAutoPlay ? .on : .off
        liveAutoPlayCheckbox.target = self
        liveAutoPlayCheckbox.action = #selector(toggleLiveAutoPlay(_:))

        liveMutedCheckbox = makeCheck(liveBox.contentView!, title: "Mute Live Photo playback", x: 14, y: 38)
        liveMutedCheckbox.state = AppConfig.shared.livePhotoMuted ? .on : .off
        liveMutedCheckbox.target = self
        liveMutedCheckbox.action = #selector(toggleLiveMuted(_:))
        y += liveBox.frame.height + 14

        // ─── Slideshow ──────────────────────────────────────────────
        let slideContentH: CGFloat = 36
        let slideBox = makeSection(root, title: "Slideshow", x: margin, y: y, width: sectionWidth, contentHeight: slideContentH)
        let intervalLabel = makeLabel(slideBox.contentView!, text: "Interval per slide (1–600 s):", x: 14, y: 8)
        intervalField = makeNumberField(slideBox.contentView!, x: 14 + intervalLabel.frame.width + 10, y: 5, width: 64)
        intervalField.target = self
        intervalField.action = #selector(intervalFieldChanged(_:))
        intervalStepper = NSStepper(frame: NSRect(x: 14 + intervalLabel.frame.width + 82, y: 4, width: 19, height: 27))
        intervalStepper.minValue = 1
        intervalStepper.maxValue = 600
        intervalStepper.increment = 1
        intervalStepper.valueWraps = false
        intervalStepper.integerValue = Int(AppConfig.shared.slideshowInterval)
        intervalStepper.target = self
        intervalStepper.action = #selector(intervalStepperChanged(_:))
        slideBox.contentView!.addSubview(intervalStepper)
        y += slideBox.frame.height + 14

        // ─── Image Cache ────────────────────────────────────────────
        let cacheContentH: CGFloat = 36
        let cacheBox = makeSection(root, title: "Image Cache", x: margin, y: y, width: sectionWidth, contentHeight: cacheContentH)
        let cacheLabel = makeLabel(cacheBox.contentView!, text: "Cached images (1–20):", x: 14, y: 8)
        cacheField = makeNumberField(cacheBox.contentView!, x: 14 + cacheLabel.frame.width + 10, y: 5, width: 64)
        cacheField.target = self
        cacheField.action = #selector(cacheFieldChanged(_:))
        cacheStepper = NSStepper(frame: NSRect(x: 14 + cacheLabel.frame.width + 82, y: 4, width: 19, height: 27))
        cacheStepper.minValue = Double(AppConfig.cacheCountRange.lowerBound)
        cacheStepper.maxValue = Double(AppConfig.cacheCountRange.upperBound)
        cacheStepper.increment = 1
        cacheStepper.valueWraps = false
        cacheStepper.integerValue = AppConfig.shared.imageCacheCount
        cacheStepper.target = self
        cacheStepper.action = #selector(cacheStepperChanged(_:))
        cacheBox.contentView!.addSubview(cacheStepper)
        y += cacheBox.frame.height + 14

        // ─── AI ───────────────────────────────────────────────────────
        let aiContentH: CGFloat = 128
        let aiBox = makeSection(root, title: "AI", x: margin, y: y, width: sectionWidth, contentHeight: aiContentH)
        aiAutoUpscaleCheckbox = makeCheck(aiBox.contentView!, title: "Auto AI super-resolve small images on load", x: 14, y: 10)
        aiAutoUpscaleCheckbox.state = AppConfig.shared.aiAutoUpscaleEnabled ? .on : .off
        aiAutoUpscaleCheckbox.target = self
        aiAutoUpscaleCheckbox.action = #selector(toggleAutoUpscale(_:))

        aiAutoDewatermarkCheckbox = makeCheck(aiBox.contentView!, title: "Auto AI dewatermark on load", x: 14, y: 38)
        aiAutoDewatermarkCheckbox.state = AppConfig.shared.aiAutoDewatermarkEnabled ? .on : .off
        aiAutoDewatermarkCheckbox.target = self
        aiAutoDewatermarkCheckbox.action = #selector(toggleAutoDewatermark(_:))

        let modeLabel = makeLabel(aiBox.contentView!, text: "One-click enhance:", x: 14, y: 70)
        enhanceModePopup = makePopup(aiBox.contentView!, items: ["Both (dedup + dewatermark)", "Dedup only", "Watermark only"],
                                     x: 14 + modeLabel.frame.width + 10, y: 66, width: 230)
        enhanceModePopup.target = self
        enhanceModePopup.action = #selector(enhanceModeChanged(_:))

        dedupAskContinueCheckbox = makeCheck(aiBox.contentView!, title: "Ask to continue between duplicate groups", x: 14, y: 100)
        dedupAskContinueCheckbox.state = AppConfig.shared.dedupAskContinue ? .on : .off
        dedupAskContinueCheckbox.target = self
        dedupAskContinueCheckbox.action = #selector(toggleDedupAskContinue(_:))
        y += aiBox.frame.height + 14

        // ─── Proxy ────────────────────────────────────────────────────
        let proxyContentH: CGFloat = 70
        let proxyBox = makeSection(root, title: "Proxy", x: margin, y: y, width: sectionWidth, contentHeight: proxyContentH)
        proxyEnabledCheckbox = makeCheck(proxyBox.contentView!, title: "Enable proxy for model downloads", x: 14, y: 10)
        proxyEnabledCheckbox.state = AppConfig.shared.proxyEnabled ? .on : .off
        proxyEnabledCheckbox.target = self
        proxyEnabledCheckbox.action = #selector(toggleProxyEnabled(_:))

        _ = makeLabel(proxyBox.contentView!, text: "Type:", x: 14, y: 42)
        proxyTypePopup = makePopup(proxyBox.contentView!, items: ["HTTP", "SOCKS"], x: 58, y: 38, width: 90)
        proxyTypePopup.target = self
        proxyTypePopup.action = #selector(proxyTypeChanged(_:))

        _ = makeLabel(proxyBox.contentView!, text: "Host:", x: 162, y: 42)
        proxyHostField = NSTextField(frame: NSRect(x: 202, y: 39, width: 150, height: 24))
        proxyHostField.font = NSFont.systemFont(ofSize: 13)
        proxyHostField.placeholderString = "127.0.0.1"
        proxyHostField.target = self
        proxyHostField.action = #selector(proxyHostFieldChanged(_:))
        proxyBox.contentView!.addSubview(proxyHostField)

        _ = makeLabel(proxyBox.contentView!, text: "Port:", x: 366, y: 42)
        proxyPortField = makeNumberField(proxyBox.contentView!, x: 408, y: 39, width: 44)
        proxyPortField.target = self
        proxyPortField.action = #selector(proxyPortFieldChanged(_:))
        proxyPortStepper = NSStepper(frame: NSRect(x: 456, y: 38, width: 19, height: 27))
        proxyPortStepper.minValue = 1
        proxyPortStepper.maxValue = 65535
        proxyPortStepper.increment = 1
        proxyPortStepper.valueWraps = false
        proxyPortStepper.integerValue = AppConfig.shared.proxyPort
        proxyPortStepper.target = self
        proxyPortStepper.action = #selector(proxyPortStepperChanged(_:))
        proxyBox.contentView!.addSubview(proxyPortStepper)
        y += proxyBox.frame.height + 14

        // ─── AI Models ────────────────────────────────────────────────
        let modelsContentH: CGFloat = 72
        let modelsBox = makeSection(root, title: "AI Models", x: margin, y: y, width: sectionWidth, contentHeight: modelsContentH)
        modelRows = []
        var rowY: CGFloat = 10
        for plugin in ModelPlugin.all {
            let statusLabel = makeLabel(modelsBox.contentView!, text: plugin.displayName, x: 14, y: rowY)
            statusLabel.frame = NSRect(x: 14, y: rowY, width: 176, height: statusLabel.frame.height)

            let downloadButton = NSButton(frame: NSRect(x: 196, y: rowY - 3, width: 92, height: 26))
            downloadButton.title = "Download"
            downloadButton.bezelStyle = .rounded
            downloadButton.target = self
            downloadButton.action = #selector(modelDownloadTapped(_:))
            modelsBox.contentView!.addSubview(downloadButton)

            let enabledCheck = makeCheck(modelsBox.contentView!, title: "Enabled", x: 296, y: rowY)
            enabledCheck.frame = NSRect(x: 296, y: rowY, width: 110, height: enabledCheck.frame.height)
            enabledCheck.target = self
            enabledCheck.action = #selector(modelEnableToggled(_:))

            let uninstallButton = NSButton(frame: NSRect(x: 414, y: rowY - 3, width: 60, height: 26))
            uninstallButton.title = "Uninstall"
            uninstallButton.bezelStyle = .rounded
            uninstallButton.target = self
            uninstallButton.action = #selector(modelUninstallTapped(_:))
            modelsBox.contentView!.addSubview(uninstallButton)

            modelRows.append((plugin: plugin, statusLabel: statusLabel, enabledCheck: enabledCheck))
            rowY += 32
        }
        y += modelsBox.frame.height + 14

        // ─── Logging ────────────────────────────────────────────────
        let logContentH: CGFloat = 68
        let logBox = makeSection(root, title: "Logging", x: margin, y: y, width: sectionWidth, contentHeight: logContentH)
        logEnabledCheckbox = makeCheck(logBox.contentView!, title: "Enable logging (default: off)", x: 14, y: 10)
        logEnabledCheckbox.state = AppConfig.shared.logEnabled ? .on : .off
        logEnabledCheckbox.target = self
        logEnabledCheckbox.action = #selector(toggleLogEnabled(_:))

        let pathLabel = makeLabel(logBox.contentView!, text: "Log file:", x: 14, y: 42)
        let browseWidth: CGFloat = 70
        let fieldX = 14 + pathLabel.frame.width + 10
        let fieldW = sectionWidth - (fieldX) - browseWidth - 8 - 14
        logPathField = NSTextField(frame: NSRect(x: fieldX, y: 39, width: fieldW, height: 24))
        logPathField.font = NSFont.systemFont(ofSize: 12)
        logPathField.placeholderString = AppConfig.Defaults.logPath()
        logPathField.target = self
        logPathField.action = #selector(logPathFieldChanged(_:))
        logBox.contentView!.addSubview(logPathField)

        let browseButton = NSButton(frame: NSRect(x: fieldX + fieldW + 8, y: 38, width: browseWidth, height: 26))
        browseButton.title = "Browse..."
        browseButton.bezelStyle = .rounded
        browseButton.target = self
        browseButton.action = #selector(browseLogPath(_:))
        logBox.contentView!.addSubview(browseButton)

        // ─── Restore Defaults (bottom-right) ────────────────────────
        let restoreButton = NSButton(frame: NSRect(x: contentSize.width - margin - 120, y: contentSize.height - 46, width: 120, height: 30))
        restoreButton.title = "Restore Defaults"
        restoreButton.bezelStyle = .rounded
        restoreButton.target = self
        restoreButton.action = #selector(restoreDefaults(_:))
        root.addSubview(restoreButton)

        // Refresh the controls whenever any setting changes (e.g. the
        // "don't ask again" checkbox on the delete dialog, or Restore Defaults).
        changeObserver = NotificationCenter.default.addObserver(
            forName: AppConfig.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncControlsFromConfig()
        }

        // Refresh the AI Models rows whenever plugin states change
        // (download finished, enabled/disabled, uninstalled).
        pluginObserver = NotificationCenter.default.addObserver(
            forName: PluginManager.stateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncModelRows()
        }

        self.window = win
    }

    /// Create a titled section box and return it; its `contentView` is flipped
    /// so child controls can be placed top-to-bottom.
    private func makeSection(_ root: NSView, title: String, x: CGFloat, y: CGFloat, width: CGFloat, contentHeight: CGFloat) -> FlippedBox {
        // Titled NSBox: the title strip + borders take ~30 pt above the content.
        let titleArea: CGFloat = 30
        let box = FlippedBox(frame: NSRect(x: x, y: y, width: width, height: contentHeight + titleArea))
        box.titlePosition = .atTop
        box.titleFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
        box.title = title
        let content = FlippedView()
        box.contentView = content
        root.addSubview(box)
        return box
    }

    private func makeCheck(_ parent: NSView, title: String, x: CGFloat, y: CGFloat) -> NSButton {
        let check = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        check.font = NSFont.systemFont(ofSize: 13)
        check.sizeToFit()
        check.frame = NSRect(x: x, y: y, width: max(check.frame.width, parent.bounds.width - x - 8), height: check.frame.height)
        parent.addSubview(check)
        return check
    }

    private func makeLabel(_ parent: NSView, text: String, x: CGFloat, y: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 13)
        label.sizeToFit()
        label.frame = NSRect(x: x, y: y, width: label.frame.width, height: label.frame.height)
        parent.addSubview(label)
        return label
    }

    private func makeNumberField(_ parent: NSView, x: CGFloat, y: CGFloat, width: CGFloat) -> NSTextField {
        let field = NSTextField(frame: NSRect(x: x, y: y, width: width, height: 24))
        field.font = NSFont.systemFont(ofSize: 13)
        field.alignment = .center
        parent.addSubview(field)
        return field
    }

    // MARK: - Syncing

    /// Copy the current config values into the controls (used on show and after
    /// any external change, e.g. "Restore Defaults" or the delete dialog).
    private func syncControlsFromConfig() {
        guard window != nil else { return }
        // Defer one runloop tick so a notification fired from our own control
        // action does not fight the user's in-progress edit.
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.quitCheckbox.state = AppConfig.shared.quitOnLastWindowClosed ? .on : .off
            self.deleteConfirmCheckbox.state = AppConfig.shared.deleteConfirmationEnabled ? .on : .off
            self.liveAutoPlayCheckbox.state = AppConfig.shared.livePhotoAutoPlay ? .on : .off
            self.liveMutedCheckbox.state = AppConfig.shared.livePhotoMuted ? .on : .off
            let interval = Int(AppConfig.shared.slideshowInterval)
            if self.intervalField.integerValue != interval { self.intervalField.integerValue = interval }
            if self.intervalStepper.integerValue != interval { self.intervalStepper.integerValue = interval }
            let cache = AppConfig.shared.imageCacheCount
            if self.cacheField.integerValue != cache { self.cacheField.integerValue = cache }
            if self.cacheStepper.integerValue != cache { self.cacheStepper.integerValue = cache }
            self.logEnabledCheckbox.state = AppConfig.shared.logEnabled ? .on : .off
            let path = AppConfig.shared.logPath
            if self.logPathField.stringValue != path { self.logPathField.stringValue = path }
            self.aiAutoUpscaleCheckbox.state = AppConfig.shared.aiAutoUpscaleEnabled ? .on : .off
            self.aiAutoDewatermarkCheckbox.state = AppConfig.shared.aiAutoDewatermarkEnabled ? .on : .off
            let modeIdx: Int
            switch AppConfig.shared.aiEnhanceMode {
            case "dedupOnly": modeIdx = 1
            case "watermarkOnly": modeIdx = 2
            default: modeIdx = 0
            }
            if self.enhanceModePopup.indexOfSelectedItem != modeIdx { self.enhanceModePopup.selectItem(at: modeIdx) }
            self.dedupAskContinueCheckbox.state = AppConfig.shared.dedupAskContinue ? .on : .off
            self.proxyEnabledCheckbox.state = AppConfig.shared.proxyEnabled ? .on : .off
            let typeIdx = (AppConfig.shared.proxyType == "socks") ? 1 : 0
            if self.proxyTypePopup.indexOfSelectedItem != typeIdx { self.proxyTypePopup.selectItem(at: typeIdx) }
            if self.proxyHostField.stringValue != AppConfig.shared.proxyHost { self.proxyHostField.stringValue = AppConfig.shared.proxyHost }
            let port = AppConfig.shared.proxyPort
            if self.proxyPortField.integerValue != port { self.proxyPortField.integerValue = port }
            if self.proxyPortStepper.integerValue != port { self.proxyPortStepper.integerValue = port }
            self.syncModelRows()
        }
    }

    // MARK: - Actions (each writes to AppConfig → instant effect + persist)

    @objc private func toggleQuitOnLastClose(_ sender: NSButton) {
        AppConfig.shared.quitOnLastWindowClosed = (sender.state == .on)
    }

    @objc private func toggleDeleteConfirm(_ sender: NSButton) {
        AppConfig.shared.deleteConfirmationEnabled = (sender.state == .on)
    }

    @objc private func toggleLiveAutoPlay(_ sender: NSButton) {
        AppConfig.shared.livePhotoAutoPlay = (sender.state == .on)
    }

    @objc private func toggleLiveMuted(_ sender: NSButton) {
        AppConfig.shared.livePhotoMuted = (sender.state == .on)
    }

    @objc private func intervalStepperChanged(_ sender: NSStepper) {
        let value = Double(sender.integerValue)
        intervalField.integerValue = sender.integerValue
        AppConfig.shared.slideshowInterval = value
    }

    @objc private func intervalFieldChanged(_ sender: NSTextField) {
        guard let value = Double(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig()
            return
        }
        let clamped = Int(AppConfig.clampInterval(value))
        sender.integerValue = clamped
        intervalStepper.integerValue = clamped
        AppConfig.shared.slideshowInterval = Double(clamped)
    }

    @objc private func cacheStepperChanged(_ sender: NSStepper) {
        cacheField.integerValue = sender.integerValue
        AppConfig.shared.imageCacheCount = sender.integerValue
    }

    @objc private func cacheFieldChanged(_ sender: NSTextField) {
        guard let value = Int(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig()
            return
        }
        let clamped = AppConfig.clampCacheCount(value)
        sender.integerValue = clamped
        cacheStepper.integerValue = clamped
        AppConfig.shared.imageCacheCount = clamped
    }

    @objc private func toggleLogEnabled(_ sender: NSButton) {
        AppConfig.shared.logEnabled = (sender.state == .on)
    }

    @objc private func logPathFieldChanged(_ sender: NSTextField) {
        let trimmed = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        AppConfig.shared.logPath = trimmed
        sender.stringValue = AppConfig.shared.logPath
    }

    @objc private func browseLogPath(_ sender: Any?) {
        guard let window = window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Select"
        panel.message = "Choose the directory for the log file (PixAI.log will be created inside it)."

        var startDir = URL(fileURLWithPath: AppConfig.shared.logPath, isDirectory: false)
            .deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: startDir.path) {
            startDir = FileManager.default.homeDirectoryForCurrentUser
        }
        panel.directoryURL = startDir

        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let dir = panel.url else { return }
            let path = dir.appendingPathComponent("PixAI.log").path
            AppConfig.shared.logPath = path
            self?.logPathField.stringValue = path
        }
    }

    @objc private func restoreDefaults(_ sender: Any?) {
        AppConfig.shared.resetToDefaults()
        // syncControlsFromConfig is triggered by the change notification.
    }

    // MARK: - AI / Proxy / Model actions (each writes to AppConfig or PluginManager)

    @objc private func toggleAutoUpscale(_ sender: NSButton) {
        AppConfig.shared.aiAutoUpscaleEnabled = (sender.state == .on)
    }

    @objc private func toggleAutoDewatermark(_ sender: NSButton) {
        AppConfig.shared.aiAutoDewatermarkEnabled = (sender.state == .on)
    }

    @objc private func enhanceModeChanged(_ sender: NSPopUpButton) {
        switch sender.indexOfSelectedItem {
        case 1: AppConfig.shared.aiEnhanceMode = "dedupOnly"
        case 2: AppConfig.shared.aiEnhanceMode = "watermarkOnly"
        default: AppConfig.shared.aiEnhanceMode = "both"
        }
    }

    @objc private func toggleDedupAskContinue(_ sender: NSButton) {
        AppConfig.shared.dedupAskContinue = (sender.state == .on)
    }

    @objc private func toggleProxyEnabled(_ sender: NSButton) {
        AppConfig.shared.proxyEnabled = (sender.state == .on)
    }

    @objc private func proxyTypeChanged(_ sender: NSPopUpButton) {
        AppConfig.shared.proxyType = (sender.indexOfSelectedItem == 1) ? "socks" : "http"
    }

    @objc private func proxyHostFieldChanged(_ sender: NSTextField) {
        let trimmed = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        AppConfig.shared.proxyHost = trimmed
        sender.stringValue = AppConfig.shared.proxyHost
    }

    @objc private func proxyPortStepperChanged(_ sender: NSStepper) {
        proxyPortField.integerValue = sender.integerValue
        AppConfig.shared.proxyPort = sender.integerValue
    }

    @objc private func proxyPortFieldChanged(_ sender: NSTextField) {
        guard let value = Int(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig()
            return
        }
        let clamped = min(max(value, 1), 65535)
        sender.integerValue = clamped
        proxyPortStepper.integerValue = clamped
        AppConfig.shared.proxyPort = clamped
    }

    private func modelRow(forControl view: NSView) -> (plugin: ModelPlugin, statusLabel: NSTextField, enabledCheck: NSButton)? {
        for row in modelRows where row.statusLabel === view || row.enabledCheck === view {
            return row
        }
        return nil
    }

    @objc private func modelDownloadTapped(_ sender: NSButton) {
        guard let row = modelRow(forControl: sender) else { return }
        if case .downloading = PluginManager.shared.state(for: row.plugin) { return }
        row.statusLabel.stringValue = "Downloading…"
        PluginManager.shared.download(row.plugin, progress: { p in
            self.modelRows.first { $0.plugin == row.plugin }?.statusLabel.stringValue = String(format: "Downloading… %.0f%%", p * 100)
        }, completion: { result in
            switch result {
            case .success:
                self.syncModelRows()
            case .failure(let error):
                self.modelRows.first { $0.plugin == row.plugin }?.statusLabel.stringValue = "Error: \(error.localizedDescription)"
            }
        })
    }

    @objc private func modelEnableToggled(_ sender: NSButton) {
        guard let row = modelRow(forControl: sender) else { return }
        let enabled = (sender.state == .on)
        if enabled, !PluginManager.shared.isReady(row.plugin) {
            // Cannot enable a model that is not downloaded yet.
            sender.state = .off
            row.statusLabel.stringValue = "Not downloaded"
            return
        }
        PluginManager.shared.setEnabled(row.plugin, enabled: enabled)
    }

    @objc private func modelUninstallTapped(_ sender: NSButton) {
        guard let row = modelRow(forControl: sender) else { return }
        let alert = NSAlert()
        alert.messageText = "Uninstall \(row.plugin.displayName)?"
        alert.informativeText = "The downloaded model files will be deleted. You can download them again later."
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        PluginManager.shared.uninstall(row.plugin)
    }

    /// Refresh the AI Models rows from live plugin states.
    private func syncModelRows() {
        for i in modelRows.indices {
            let plugin = modelRows[i].plugin
            let state = PluginManager.shared.state(for: plugin)
            let enabled = PluginManager.shared.isEnabled(plugin)
            switch state {
            case .notDownloaded:
                modelRows[i].statusLabel.stringValue = "Not downloaded"
            case .downloading(let p):
                modelRows[i].statusLabel.stringValue = String(format: "Downloading… %.0f%%", p * 100)
            case .ready:
                modelRows[i].statusLabel.stringValue = enabled ? "Enabled" : "Ready (disabled)"
            case .error(let msg):
                modelRows[i].statusLabel.stringValue = "Error: \(msg)"
            }
            let wantState: Int = enabled ? 1 : 0
            if modelRows[i].enabledCheck.state.rawValue != wantState {
                modelRows[i].enabledCheck.state = (enabled ? .on : .off)
            }
        }
    }

    private func makePopup(_ parent: NSView, items: [String], x: CGFloat, y: CGFloat, width: CGFloat) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: NSRect(x: x, y: y, width: width, height: 25), pullsDown: false)
        popup.font = NSFont.systemFont(ofSize: 13)
        popup.addItems(withTitles: items)
        parent.addSubview(popup)
        return popup
    }
}

/// NSView subclass with a top-left origin (y grows downward) so the
/// Preferences layout can be written top-to-bottom.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// NSBox subclass whose own coordinate system is flipped (used for the
/// section frames inside the flipped root view).
private final class FlippedBox: NSBox {
    override var isFlipped: Bool { true }
}
