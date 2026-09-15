// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// The Preferences window (Cmd+, / PixAI ▸ Preferences...).
///
/// Settings are grouped into tabs (General / AI / Advanced).
/// AI tab has sub-tabs for each AI feature (Enhance / Upscale / Dewatermark / One-click).
/// Every control writes straight to `AppConfig.shared`, which persists the
/// new value to `~/.pixai/config.json` immediately and posts a change
/// notification — so edits take effect at once without restarting.
final class PreferencesWindow: NSObject {
    static let shared = PreferencesWindow()

    private var window: NSWindow?
    private var mainTabView: NSTabView!
    private var aiTabView: NSTabView!

    // Controls (kept as references so values can be refreshed).
    private var quitCheckbox: NSButton!
    private var deleteConfirmCheckbox: NSButton!
    private var languagePopup: NSPopUpButton!
    private var transitionField: NSTextField!
    private var transitionStepper: NSStepper!
    private var modelCheckPromptCheckbox: NSButton!
    private var cropLivePhotoConfirmCheckbox: NSButton!
    private var liveAutoPlayCheckbox: NSButton!
    private var liveMutedCheckbox: NSButton!
    private var openDirModePopup: NSPopUpButton!
    private var openDirField: NSTextField!
    // Slideshow (moved to General)
    private var intervalField: NSTextField!
    private var intervalStepper: NSStepper!
    // Advanced
    private var cacheField: NSTextField!
    private var cacheStepper: NSStepper!
    private var logEnabledCheckbox: NSButton!
    private var logPathField: NSTextField!

    // AI - Enhance tab
    private var enhanceVibranceField: NSTextField!
    private var enhanceVibranceStepper: NSStepper!
    private var enhanceContrastField: NSTextField!
    private var enhanceContrastStepper: NSStepper!
    private var enhanceSharpnessField: NSTextField!
    private var enhanceSharpnessStepper: NSStepper!

    // AI - Upscale tab
    private var aiAutoUpscaleCheckbox: NSButton!

    // AI - Dewatermark tab
    private var aiAutoDewatermarkCheckbox: NSButton!

    // AI - One-click tab
    private var enhanceModePopup: NSPopUpButton!
    private var dedupAskContinueCheckbox: NSButton!

    // Proxy
    private var proxyEnabledCheckbox: NSButton!
    private var proxyTypePopup: NSPopUpButton!
    private var proxyHostField: NSTextField!
    private var proxyPortField: NSTextField!
    private var proxyPortStepper: NSStepper!

    private var modelRows: [(plugin: ModelPlugin, statusLabel: NSTextField, enabledCheck: NSButton)] = []
    private var pluginObserver: NSObjectProtocol?

    private var changeObserver: NSObjectProtocol?
    private var l10nObserver: NSObjectProtocol?

    private override init() {
        super.init()
    }

    func show() {
        if window == nil {
            buildWindow()
        }
        syncControlsFromConfig()
        guard let window = window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: - Building

    private func buildWindow() {
        let contentSize = NSSize(width: 600, height: 520)
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = L10n.shared.t("Preferences")
        win.isReleasedWhenClosed = false

        let root = FlippedView(frame: NSRect(origin: .zero, size: contentSize))
        win.contentView = root

        let margin: CGFloat = 20
        let tabHeight: CGFloat = contentSize.height - margin * 2

        mainTabView = NSTabView(frame: NSRect(x: margin, y: margin, width: contentSize.width - margin * 2, height: tabHeight))
        mainTabView.tabViewType = .topTabsBezelBorder
        root.addSubview(mainTabView)

        let t = L10n.shared.t

        // ─── General Tab ───────────────────────────────────────────────
        let generalTab = NSTabViewItem(identifier: "general")
        generalTab.label = t("General")
        generalTab.view = FlippedView(frame: NSRect(x: 0, y: 0, width: mainTabView.bounds.width - 20, height: tabHeight - 40))
        buildGeneralTab(generalTab.view!, t: t)
        mainTabView.addTabViewItem(generalTab)

        // ─── AI Tab ────────────────────────────────────────────────────
        let aiTab = NSTabViewItem(identifier: "ai")
        aiTab.label = t("AI")
        aiTab.view = FlippedView(frame: NSRect(x: 0, y: 0, width: mainTabView.bounds.width - 20, height: tabHeight - 40))
        buildAITab(aiTab.view!, t: t)
        mainTabView.addTabViewItem(aiTab)

        // ─── Advanced Tab ──────────────────────────────────────────────
        let advancedTab = NSTabViewItem(identifier: "advanced")
        advancedTab.label = t("Advanced")
        advancedTab.view = FlippedView(frame: NSRect(x: 0, y: 0, width: mainTabView.bounds.width - 20, height: tabHeight - 40))
        buildAdvancedTab(advancedTab.view!, t: t)
        mainTabView.addTabViewItem(advancedTab)

        changeObserver = NotificationCenter.default.addObserver(
            forName: AppConfig.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncControlsFromConfig()
        }

        l10nObserver = NotificationCenter.default.addObserver(
            forName: L10n.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let wasVisible = self.window?.isVisible ?? false
            self.window?.close()
            self.window = nil
            if wasVisible { self.show() }
        }

        pluginObserver = NotificationCenter.default.addObserver(
            forName: PluginManager.stateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.syncModelRows()
        }

        mainTabView.delegate = self

        self.window = win
    }

    private func buildGeneralTab(_ root: NSView, t: (String) -> String) {
        var y: CGFloat = 14
        let contentWidth = root.bounds.width - 28
        let sectionHeight: CGFloat = 350

        let box = makeSection(root, title: t("General"), x: 14, y: y, width: contentWidth, contentHeight: sectionHeight)
        quitCheckbox = makeCheck(box.contentView!, title: t("Quit app when the last window is closed"), x: 14, y: 10)
        quitCheckbox.state = AppConfig.shared.quitOnLastWindowClosed ? .on : .off
        quitCheckbox.target = self
        quitCheckbox.action = #selector(toggleQuitOnLastClose(_:))

        deleteConfirmCheckbox = makeCheck(box.contentView!, title: t("Ask for confirmation before deleting a file"), x: 14, y: 38)
        deleteConfirmCheckbox.state = AppConfig.shared.deleteConfirmationEnabled ? .on : .off
        deleteConfirmCheckbox.target = self
        deleteConfirmCheckbox.action = #selector(toggleDeleteConfirm(_:))

        let langLabel = makeLabel(box.contentView!, text: t("Language"), x: 14, y: 68)
        languagePopup = makePopup(box.contentView!, items: ["English", "简体中文", "繁體中文"], x: 14 + langLabel.frame.width + 10, y: 64, width: 120)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))

        // Open directory mode
        let openDirLabel = makeLabel(box.contentView!, text: t("Default directory:"), x: 14, y: 96)
        openDirModePopup = makePopup(box.contentView!, items: [t("Last open"), t("Choose...")], x: 14 + openDirLabel.frame.width + 10, y: 92, width: 100)
        openDirModePopup.target = self
        openDirModePopup.action = #selector(openDirModeChanged(_:))

        openDirField = NSTextField(frame: NSRect(x: 126 + openDirLabel.frame.width + 10, y: 93, width: 260, height: 24))
        openDirField.font = NSFont.systemFont(ofSize: 12)
        openDirField.isEditable = false
        openDirField.isBezeled = true
        openDirField.drawsBackground = true
        openDirField.backgroundColor = NSColor.controlBackgroundColor
        openDirField.focusRingType = .none
        box.contentView!.addSubview(openDirField)

        let transitionLabel = makeLabel(box.contentView!, text: t("Image transition duration (0–2 s, 0 = off):"), x: 14, y: 124)
        transitionField = NoAutoFocusTextField(frame: NSRect(x: 14 + transitionLabel.frame.width + 10, y: 121, width: 56, height: 24))
        transitionField.font = NSFont.systemFont(ofSize: 13)
        transitionField.alignment = .center
        transitionField.target = self
        transitionField.action = #selector(transitionFieldChanged(_:))
        box.contentView!.addSubview(transitionField)
        transitionStepper = NSStepper(frame: NSRect(x: 14 + transitionLabel.frame.width + 78, y: 120, width: 19, height: 27))
        transitionStepper.minValue = 0
        transitionStepper.maxValue = 2
        transitionStepper.increment = 0.1
        transitionStepper.valueWraps = false
        transitionStepper.doubleValue = AppConfig.shared.imageTransitionDuration
        transitionStepper.target = self
        transitionStepper.action = #selector(transitionStepperChanged(_:))
        box.contentView!.addSubview(transitionStepper)

        // Slideshow interval (moved here)
        let intervalLabel = makeLabel(box.contentView!, text: t("Slideshow interval (1–600 s):"), x: 14, y: 152)
        intervalField = NoAutoFocusNumberField(frame: NSRect(x: 14 + intervalLabel.frame.width + 10, y: 149, width: 64, height: 24))
        intervalField.font = NSFont.systemFont(ofSize: 13)
        intervalField.alignment = .center
        box.contentView!.addSubview(intervalField)
        intervalField.target = self
        intervalField.action = #selector(intervalFieldChanged(_:))
        intervalStepper = NSStepper(frame: NSRect(x: 14 + intervalLabel.frame.width + 82, y: 148, width: 19, height: 27))
        intervalStepper.minValue = 1
        intervalStepper.maxValue = 600
        intervalStepper.increment = 1
        intervalStepper.valueWraps = false
        intervalStepper.integerValue = Int(AppConfig.shared.slideshowInterval)
        intervalStepper.target = self
        intervalStepper.action = #selector(intervalStepperChanged(_:))
        box.contentView!.addSubview(intervalStepper)

        modelCheckPromptCheckbox = makeCheck(box.contentView!, title: t("Ask to download AI models at startup when missing"), x: 14, y: 180)
        modelCheckPromptCheckbox.state = AppConfig.shared.modelCheckPromptEnabled ? .on : .off
        modelCheckPromptCheckbox.target = self
        modelCheckPromptCheckbox.action = #selector(toggleModelCheckPrompt(_:))

        cropLivePhotoConfirmCheckbox = makeCheck(box.contentView!, title: t("Confirm before cropping a Live Photo (result is a still image)"), x: 14, y: 208)
        cropLivePhotoConfirmCheckbox.state = AppConfig.shared.cropLivePhotoConfirm ? .on : .off
        cropLivePhotoConfirmCheckbox.target = self
        cropLivePhotoConfirmCheckbox.action = #selector(toggleCropLivePhotoConfirm(_:))

        liveAutoPlayCheckbox = makeCheck(box.contentView!, title: t("Auto-play Live Photos when displayed"), x: 14, y: 236)
        liveAutoPlayCheckbox.state = AppConfig.shared.livePhotoAutoPlay ? .on : .off
        liveAutoPlayCheckbox.target = self
        liveAutoPlayCheckbox.action = #selector(toggleLiveAutoPlay(_:))

        liveMutedCheckbox = makeCheck(box.contentView!, title: t("Mute Live Photo playback"), x: 14, y: 264)
        liveMutedCheckbox.state = AppConfig.shared.livePhotoMuted ? .on : .off
        liveMutedCheckbox.target = self
        liveMutedCheckbox.action = #selector(toggleLiveMuted(_:))
        y += box.frame.height + 14

        let restoreButton = NSButton(frame: NSRect(x: contentWidth - 140, y: y, width: 140, height: 26))
        restoreButton.title = t("Restore This Page Defaults")
        restoreButton.bezelStyle = .rounded
        restoreButton.target = self
        restoreButton.action = #selector(restoreGeneralDefaults(_:))
        root.addSubview(restoreButton)
    }

    private func buildAITab(_ root: NSView, t: (String) -> String) {
        let y: CGFloat = 14
        let contentWidth = root.bounds.width - 28

        // Create inner tab view for AI sub-tabs
        aiTabView = NSTabView(frame: NSRect(x: 14, y: y, width: contentWidth, height: root.bounds.height - y - 50))
        aiTabView.tabViewType = .topTabsBezelBorder
        root.addSubview(aiTabView)

        // ─── Enhance sub-tab ──────────────────────────────────────────
        let enhanceTab = NSTabViewItem(identifier: "enhance")
        enhanceTab.label = t("Quality Enhance")
        enhanceTab.view = FlippedView(frame: NSRect(x: 0, y: 0, width: aiTabView.bounds.width - 20, height: aiTabView.bounds.height - 40))
        buildEnhanceTab(enhanceTab.view!, t: t)
        aiTabView.addTabViewItem(enhanceTab)

        // ─── Upscale sub-tab ──────────────────────────────────────────
        let upscaleTab = NSTabViewItem(identifier: "upscale")
        upscaleTab.label = t("Super Resolution")
        upscaleTab.view = FlippedView(frame: NSRect(x: 0, y: 0, width: aiTabView.bounds.width - 20, height: aiTabView.bounds.height - 40))
        buildUpscaleTab(upscaleTab.view!, t: t)
        aiTabView.addTabViewItem(upscaleTab)

        // ─── Dewatermark sub-tab ──────────────────────────────────────
        let dewatermarkTab = NSTabViewItem(identifier: "dewatermark")
        dewatermarkTab.label = t("Remove Watermark")
        dewatermarkTab.view = FlippedView(frame: NSRect(x: 0, y: 0, width: aiTabView.bounds.width - 20, height: aiTabView.bounds.height - 40))
        buildDewatermarkTab(dewatermarkTab.view!, t: t)
        aiTabView.addTabViewItem(dewatermarkTab)

        // ─── One-click sub-tab ────────────────────────────────────────
        let oneClickTab = NSTabViewItem(identifier: "oneclick")
        oneClickTab.label = t("One-click Enhance")
        oneClickTab.view = FlippedView(frame: NSRect(x: 0, y: 0, width: aiTabView.bounds.width - 20, height: aiTabView.bounds.height - 40))
        buildOneClickTab(oneClickTab.view!, t: t)
        aiTabView.addTabViewItem(oneClickTab)

        aiTabView.delegate = self
    }

    private func buildEnhanceTab(_ root: NSView, t: (String) -> String) {
        var y: CGFloat = 14
        let contentWidth = root.bounds.width - 28
        let box = makeSection(root, title: t("Enhancement Parameters"), x: 14, y: y, width: contentWidth, contentHeight: 110)
        y += box.frame.height + 14
        
        var rowY: CGFloat = 10
        
        // Vibrance
        let vibranceLabel = makeLabel(box.contentView!, text: t("Vibrance (0–1):"), x: 14, y: rowY)
        enhanceVibranceField = NoAutoFocusNumberField(frame: NSRect(x: 14 + vibranceLabel.frame.width + 10, y: rowY - 3, width: 64, height: 24))
        enhanceVibranceField.font = NSFont.systemFont(ofSize: 13)
        enhanceVibranceField.alignment = .center
        box.contentView!.addSubview(enhanceVibranceField)
        enhanceVibranceField.target = self
        enhanceVibranceField.action = #selector(enhanceVibranceFieldChanged(_:))
        enhanceVibranceStepper = NSStepper(frame: NSRect(x: 14 + vibranceLabel.frame.width + 82, y: rowY - 4, width: 19, height: 27))
        enhanceVibranceStepper.minValue = 0
        enhanceVibranceStepper.maxValue = 1
        enhanceVibranceStepper.increment = 0.05
        enhanceVibranceStepper.valueWraps = false
        enhanceVibranceStepper.doubleValue = AppConfig.shared.enhanceVibrance
        enhanceVibranceStepper.target = self
        enhanceVibranceStepper.action = #selector(enhanceVibranceStepperChanged(_:))
        box.contentView!.addSubview(enhanceVibranceStepper)
        rowY += 32

        // Contrast
        let contrastLabel = makeLabel(box.contentView!, text: t("Contrast (0.5–2.0, 1.0 = off):"), x: 14, y: rowY)
        enhanceContrastField = NoAutoFocusNumberField(frame: NSRect(x: 14 + contrastLabel.frame.width + 10, y: rowY - 3, width: 64, height: 24))
        enhanceContrastField.font = NSFont.systemFont(ofSize: 13)
        enhanceContrastField.alignment = .center
        box.contentView!.addSubview(enhanceContrastField)
        enhanceContrastField.target = self
        enhanceContrastField.action = #selector(enhanceContrastFieldChanged(_:))
        enhanceContrastStepper = NSStepper(frame: NSRect(x: 14 + contrastLabel.frame.width + 82, y: rowY - 4, width: 19, height: 27))
        enhanceContrastStepper.minValue = 0.5
        enhanceContrastStepper.maxValue = 2.0
        enhanceContrastStepper.increment = 0.05
        enhanceContrastStepper.valueWraps = false
        enhanceContrastStepper.doubleValue = AppConfig.shared.enhanceContrast
        enhanceContrastStepper.target = self
        enhanceContrastStepper.action = #selector(enhanceContrastStepperChanged(_:))
        box.contentView!.addSubview(enhanceContrastStepper)
        rowY += 32

        // Sharpness
        let sharpnessLabel = makeLabel(box.contentView!, text: t("Sharpness (0–1):"), x: 14, y: rowY)
        enhanceSharpnessField = NoAutoFocusNumberField(frame: NSRect(x: 14 + sharpnessLabel.frame.width + 10, y: rowY - 3, width: 64, height: 24))
        enhanceSharpnessField.font = NSFont.systemFont(ofSize: 13)
        enhanceSharpnessField.alignment = .center
        box.contentView!.addSubview(enhanceSharpnessField)
        enhanceSharpnessField.target = self
        enhanceSharpnessField.action = #selector(enhanceSharpnessFieldChanged(_:))
        enhanceSharpnessStepper = NSStepper(frame: NSRect(x: 14 + sharpnessLabel.frame.width + 82, y: rowY - 4, width: 19, height: 27))
        enhanceSharpnessStepper.minValue = 0
        enhanceSharpnessStepper.maxValue = 1
        enhanceSharpnessStepper.increment = 0.05
        enhanceSharpnessStepper.valueWraps = false
        enhanceSharpnessStepper.doubleValue = AppConfig.shared.enhanceSharpness
        enhanceSharpnessStepper.target = self
        enhanceSharpnessStepper.action = #selector(enhanceSharpnessStepperChanged(_:))
        box.contentView!.addSubview(enhanceSharpnessStepper)

        let restoreButton = NSButton(frame: NSRect(x: contentWidth - 140, y: y, width: 140, height: 26))
        restoreButton.title = t("Restore This Page Defaults")
        restoreButton.bezelStyle = .rounded
        restoreButton.target = self
        restoreButton.action = #selector(restoreEnhanceDefaults(_:))
        root.addSubview(restoreButton)
    }

    private func buildUpscaleTab(_ root: NSView, t: (String) -> String) {
        var y: CGFloat = 14
        let contentWidth = root.bounds.width - 28
        let box = makeSection(root, title: t("Super Resolution (Real-ESRGAN 4x)"), x: 14, y: y, width: contentWidth, contentHeight: 36)
        y += box.frame.height + 14
        
        aiAutoUpscaleCheckbox = makeCheck(box.contentView!, title: t("Auto AI super-resolve small images on load"), x: 14, y: 8)
        aiAutoUpscaleCheckbox.state = AppConfig.shared.aiAutoUpscaleEnabled ? .on : .off
        aiAutoUpscaleCheckbox.target = self
        aiAutoUpscaleCheckbox.action = #selector(toggleAutoUpscale(_:))

        let restoreButton = NSButton(frame: NSRect(x: contentWidth - 140, y: y, width: 140, height: 26))
        restoreButton.title = t("Restore This Page Defaults")
        restoreButton.bezelStyle = .rounded
        restoreButton.target = self
        restoreButton.action = #selector(restoreUpscaleDefaults(_:))
        root.addSubview(restoreButton)
    }

    private func buildDewatermarkTab(_ root: NSView, t: (String) -> String) {
        var y: CGFloat = 14
        let contentWidth = root.bounds.width - 28
        let box = makeSection(root, title: t("Watermark Removal (U2Net)"), x: 14, y: y, width: contentWidth, contentHeight: 36)
        y += box.frame.height + 14
        
        aiAutoDewatermarkCheckbox = makeCheck(box.contentView!, title: t("Auto AI dewatermark on load"), x: 14, y: 8)
        aiAutoDewatermarkCheckbox.state = AppConfig.shared.aiAutoDewatermarkEnabled ? .on : .off
        aiAutoDewatermarkCheckbox.target = self
        aiAutoDewatermarkCheckbox.action = #selector(toggleAutoDewatermark(_:))

        let restoreButton = NSButton(frame: NSRect(x: contentWidth - 140, y: y, width: 140, height: 26))
        restoreButton.title = t("Restore This Page Defaults")
        restoreButton.bezelStyle = .rounded
        restoreButton.target = self
        restoreButton.action = #selector(restoreDewatermarkDefaults(_:))
        root.addSubview(restoreButton)
    }

    private func buildOneClickTab(_ root: NSView, t: (String) -> String) {
        var y: CGFloat = 14
        let contentWidth = root.bounds.width - 28

        let box = makeSection(root, title: t("One-click Enhance Settings"), x: 14, y: y, width: contentWidth, contentHeight: 70)
        
        let modeLabel = makeLabel(box.contentView!, text: t("One-click enhance:"), x: 14, y: 10)
        enhanceModePopup = makePopup(box.contentView!, items: [t("Both (dedup + dewatermark)"), t("Dedup only"), t("Watermark only")],
                                     x: 14 + modeLabel.frame.width + 10, y: 6, width: 230)
        enhanceModePopup.target = self
        enhanceModePopup.action = #selector(enhanceModeChanged(_:))

        dedupAskContinueCheckbox = makeCheck(box.contentView!, title: t("Ask to continue between duplicate groups"), x: 14, y: 38)
        dedupAskContinueCheckbox.state = AppConfig.shared.dedupAskContinue ? .on : .off
        dedupAskContinueCheckbox.target = self
        dedupAskContinueCheckbox.action = #selector(toggleDedupAskContinue(_:))
        y += box.frame.height + 14

        // AI Models section
        let modelsBox = makeSection(root, title: t("AI Models"), x: 14, y: y, width: contentWidth, contentHeight: 72)
        modelRows = []
        var rowY: CGFloat = 10
        for plugin in ModelPlugin.all {
            let statusLabel = makeLabel(modelsBox.contentView!, text: plugin.displayName, x: 14, y: rowY)
            statusLabel.frame = NSRect(x: 14, y: rowY, width: 176, height: statusLabel.frame.height)

            let downloadButton = NSButton(frame: NSRect(x: 196, y: rowY - 3, width: 92, height: 26))
            downloadButton.title = t("Download")
            downloadButton.bezelStyle = .rounded
            downloadButton.target = self
            downloadButton.action = #selector(modelDownloadTapped(_:))
            modelsBox.contentView!.addSubview(downloadButton)

            let enabledCheck = makeCheck(modelsBox.contentView!, title: t("Enabled"), x: 296, y: rowY)
            enabledCheck.frame = NSRect(x: 296, y: rowY, width: 110, height: enabledCheck.frame.height)
            enabledCheck.target = self
            enabledCheck.action = #selector(modelEnableToggled(_:))

            let uninstallButton = NSButton(frame: NSRect(x: 414, y: rowY - 3, width: 60, height: 26))
            uninstallButton.title = t("Uninstall")
            uninstallButton.bezelStyle = .rounded
            uninstallButton.target = self
            uninstallButton.action = #selector(modelUninstallTapped(_:))
            modelsBox.contentView!.addSubview(uninstallButton)

            modelRows.append((plugin: plugin, statusLabel: statusLabel, enabledCheck: enabledCheck))
            rowY += 32
        }
        y += modelsBox.frame.height + 14

        let restoreButton = NSButton(frame: NSRect(x: contentWidth - 140, y: y, width: 140, height: 26))
        restoreButton.title = t("Restore This Page Defaults")
        restoreButton.bezelStyle = .rounded
        restoreButton.target = self
        restoreButton.action = #selector(restoreOneClickDefaults(_:))
        root.addSubview(restoreButton)
    }

    private func buildAdvancedTab(_ root: NSView, t: (String) -> String) {
        var y: CGFloat = 14
        let contentWidth = root.bounds.width - 28

        let proxyBox = makeSection(root, title: t("Proxy"), x: 14, y: y, width: contentWidth, contentHeight: 70)
        proxyEnabledCheckbox = makeCheck(proxyBox.contentView!, title: t("Enable proxy for model downloads"), x: 14, y: 10)
        proxyEnabledCheckbox.state = AppConfig.shared.proxyEnabled ? .on : .off
        proxyEnabledCheckbox.target = self
        proxyEnabledCheckbox.action = #selector(toggleProxyEnabled(_:))

        _ = makeLabel(proxyBox.contentView!, text: t("Type:"), x: 14, y: 42)
        proxyTypePopup = makePopup(proxyBox.contentView!, items: ["HTTP", "SOCKS"], x: 58, y: 38, width: 90)
        proxyTypePopup.target = self
        proxyTypePopup.action = #selector(proxyTypeChanged(_:))

        _ = makeLabel(proxyBox.contentView!, text: t("Host:"), x: 162, y: 42)
        proxyHostField = NoAutoFocusTextField(frame: NSRect(x: 202, y: 39, width: 150, height: 24))
        proxyHostField.font = NSFont.systemFont(ofSize: 13)
        proxyHostField.placeholderString = "127.0.0.1"
        proxyHostField.target = self
        proxyHostField.action = #selector(proxyHostFieldChanged(_:))
        proxyBox.contentView!.addSubview(proxyHostField)

        _ = makeLabel(proxyBox.contentView!, text: t("Port:"), x: 366, y: 42)
        proxyPortField = NoAutoFocusNumberField(frame: NSRect(x: 408, y: 39, width: 60, height: 24))
        proxyPortField.font = NSFont.systemFont(ofSize: 13)
        proxyPortField.alignment = .center
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        proxyPortField.formatter = formatter
        proxyBox.contentView!.addSubview(proxyPortField)
        proxyPortField.target = self
        proxyPortField.action = #selector(proxyPortFieldChanged(_:))
        proxyPortStepper = NSStepper(frame: NSRect(x: 474, y: 38, width: 19, height: 27))
        proxyPortStepper.minValue = 1
        proxyPortStepper.maxValue = 65535
        proxyPortStepper.increment = 1
        proxyPortStepper.valueWraps = false
        proxyPortStepper.integerValue = AppConfig.shared.proxyPort
        proxyPortStepper.target = self
        proxyPortStepper.action = #selector(proxyPortStepperChanged(_:))
        proxyBox.contentView!.addSubview(proxyPortStepper)
        y += proxyBox.frame.height + 14

        let cacheBox = makeSection(root, title: t("Image Cache"), x: 14, y: y, width: contentWidth, contentHeight: 36)
        let cacheLabel = makeLabel(cacheBox.contentView!, text: t("Cached images (1–20):"), x: 14, y: 8)
        cacheField = NoAutoFocusNumberField(frame: NSRect(x: 14 + cacheLabel.frame.width + 10, y: 5, width: 64, height: 24))
        cacheField.font = NSFont.systemFont(ofSize: 13)
        cacheField.alignment = .center
        cacheBox.contentView!.addSubview(cacheField)
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

        let logBox = makeSection(root, title: t("Logging"), x: 14, y: y, width: contentWidth, contentHeight: 68)
        logEnabledCheckbox = makeCheck(logBox.contentView!, title: t("Enable logging (default: off)"), x: 14, y: 10)
        logEnabledCheckbox.state = AppConfig.shared.logEnabled ? .on : .off
        logEnabledCheckbox.target = self
        logEnabledCheckbox.action = #selector(toggleLogEnabled(_:))

        let pathLabel = makeLabel(logBox.contentView!, text: t("Log file:"), x: 14, y: 42)
        let browseWidth: CGFloat = 70
        let fieldX = 14 + pathLabel.frame.width + 10
        let fieldW = contentWidth - (fieldX) - browseWidth - 8 - 14
        logPathField = NoAutoFocusTextField(frame: NSRect(x: fieldX, y: 39, width: fieldW, height: 24))
        logPathField.font = NSFont.systemFont(ofSize: 12)
        logPathField.placeholderString = AppConfig.Defaults.logPath()
        logPathField.target = self
        logPathField.action = #selector(logPathFieldChanged(_:))
        logBox.contentView!.addSubview(logPathField)

        let browseButton = NSButton(frame: NSRect(x: fieldX + fieldW + 8, y: 38, width: browseWidth, height: 26))
        browseButton.title = t("Browse...")
        browseButton.bezelStyle = .rounded
        browseButton.target = self
        browseButton.action = #selector(browseLogPath(_:))
        logBox.contentView!.addSubview(browseButton)
        y += logBox.frame.height + 14

        let restoreButton = NSButton(frame: NSRect(x: contentWidth - 140, y: y, width: 140, height: 26))
        restoreButton.title = t("Restore This Page Defaults")
        restoreButton.bezelStyle = .rounded
        restoreButton.target = self
        restoreButton.action = #selector(restoreAdvancedDefaults(_:))
        root.addSubview(restoreButton)
    }

    private func makeSection(_ root: NSView, title: String, x: CGFloat, y: CGFloat, width: CGFloat, contentHeight: CGFloat) -> FlippedBox {
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

    private func makePopup(_ parent: NSView, items: [String], x: CGFloat, y: CGFloat, width: CGFloat) -> NSPopUpButton {
        let popup = NSPopUpButton(frame: NSRect(x: x, y: y, width: width, height: 25), pullsDown: false)
        popup.font = NSFont.systemFont(ofSize: 13)
        popup.addItems(withTitles: items)
        parent.addSubview(popup)
        return popup
    }

    // MARK: - Syncing

    private func syncControlsFromConfig() {
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.quitCheckbox.state = AppConfig.shared.quitOnLastWindowClosed ? .on : .off
            self.deleteConfirmCheckbox.state = AppConfig.shared.deleteConfirmationEnabled ? .on : .off
            let langIdx: Int
            switch AppConfig.shared.uiLanguage {
            case "zh": langIdx = 1
            case "zh-Hant": langIdx = 2
            default: langIdx = 0
            }
            if self.languagePopup.indexOfSelectedItem != langIdx { self.languagePopup.selectItem(at: langIdx) }
            let transition = AppConfig.shared.imageTransitionDuration
            if abs(self.transitionField.doubleValue - transition) > 0.001 { self.transitionField.stringValue = String(format: "%.1f", transition) }
            if abs(self.transitionStepper.doubleValue - transition) > 0.001 { self.transitionStepper.doubleValue = transition }
            
            let interval = Int(AppConfig.shared.slideshowInterval)
            if self.intervalField.integerValue != interval { self.intervalField.integerValue = interval }
            if self.intervalStepper.integerValue != interval { self.intervalStepper.integerValue = interval }
            
            self.modelCheckPromptCheckbox.state = AppConfig.shared.modelCheckPromptEnabled ? .on : .off
            self.cropLivePhotoConfirmCheckbox.state = AppConfig.shared.cropLivePhotoConfirm ? .on : .off
            self.liveAutoPlayCheckbox.state = AppConfig.shared.livePhotoAutoPlay ? .on : .off
            self.liveMutedCheckbox.state = AppConfig.shared.livePhotoMuted ? .on : .off
            let openDirMode = AppConfig.shared.openPanelDirectoryMode
            let openDirModeIdx = (openDirMode == "custom") ? 1 : 0
            if self.openDirModePopup.indexOfSelectedItem != openDirModeIdx { self.openDirModePopup.selectItem(at: openDirModeIdx) }
            let currentDir = AppConfig.shared.getOpenPanelDirectory()
            let displayDir = currentDir?.lastPathComponent ?? ""
            if self.openDirField.stringValue != displayDir { self.openDirField.stringValue = displayDir }
            
            let cache = AppConfig.shared.imageCacheCount
            if self.cacheField.integerValue != cache { self.cacheField.integerValue = cache }
            if self.cacheStepper.integerValue != cache { self.cacheStepper.integerValue = cache }
            self.logEnabledCheckbox.state = AppConfig.shared.logEnabled ? .on : .off
            let path = AppConfig.shared.logPath
            if self.logPathField.stringValue != path { self.logPathField.stringValue = path }
            
            // AI Enhance
            let vibrance = AppConfig.shared.enhanceVibrance
            if abs(self.enhanceVibranceField.doubleValue - vibrance) > 0.001 { self.enhanceVibranceField.stringValue = String(format: "%.2f", vibrance) }
            if abs(self.enhanceVibranceStepper.doubleValue - vibrance) > 0.001 { self.enhanceVibranceStepper.doubleValue = vibrance }
            let contrast = AppConfig.shared.enhanceContrast
            if abs(self.enhanceContrastField.doubleValue - contrast) > 0.001 { self.enhanceContrastField.stringValue = String(format: "%.2f", contrast) }
            if abs(self.enhanceContrastStepper.doubleValue - contrast) > 0.001 { self.enhanceContrastStepper.doubleValue = contrast }
            let sharpness = AppConfig.shared.enhanceSharpness
            if abs(self.enhanceSharpnessField.doubleValue - sharpness) > 0.001 { self.enhanceSharpnessField.stringValue = String(format: "%.2f", sharpness) }
            if abs(self.enhanceSharpnessStepper.doubleValue - sharpness) > 0.001 { self.enhanceSharpnessStepper.doubleValue = sharpness }
            
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

    // MARK: - Actions

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

    @objc private func openDirModeChanged(_ sender: NSPopUpButton) {
        let isChoose = sender.indexOfSelectedItem == 1
        if isChoose {
            guard let window = window else { return }
            let panel = NSOpenPanel()
            panel.canChooseDirectories = true
            panel.canChooseFiles = false
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.prompt = "Select"
            panel.message = "Choose the default directory for the Open panel."
            var startDir = URL(fileURLWithPath: AppConfig.shared.customOpenDirectory, isDirectory: true)
            if !FileManager.default.fileExists(atPath: startDir.path) {
                startDir = FileManager.default.homeDirectoryForCurrentUser
            }
            panel.directoryURL = startDir
            panel.beginSheetModal(for: window) { [weak self] response in
                if response == .OK, let dir = panel.url {
                    AppConfig.shared.openPanelDirectoryMode = "custom"
                    AppConfig.shared.customOpenDirectory = dir.path
                    self?.openDirField.stringValue = dir.lastPathComponent
                } else {
                    self?.openDirModePopup.selectItem(at: 0)
                    AppConfig.shared.openPanelDirectoryMode = "last"
                }
            }
        } else {
            AppConfig.shared.openPanelDirectoryMode = "last"
        }
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

    @objc private func languageChanged(_ sender: NSPopUpButton) {
        let lang: String
        switch sender.indexOfSelectedItem {
        case 1: lang = "zh"
        case 2: lang = "zh-Hant"
        default: lang = "en"
        }
        AppConfig.shared.uiLanguage = lang
    }

    @objc private func transitionStepperChanged(_ sender: NSStepper) {
        let value = AppConfig.clampTransitionDuration(sender.doubleValue)
        if abs(transitionField.doubleValue - value) > 0.001 { transitionField.stringValue = String(format: "%.1f", value) }
        AppConfig.shared.imageTransitionDuration = value
    }

    @objc private func transitionFieldChanged(_ sender: NSTextField) {
        guard let value = Double(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig()
            return
        }
        let clamped = AppConfig.clampTransitionDuration(value)
        sender.doubleValue = clamped
        transitionStepper.doubleValue = clamped
        AppConfig.shared.imageTransitionDuration = clamped
    }

    @objc private func toggleModelCheckPrompt(_ sender: NSButton) {
        AppConfig.shared.modelCheckPromptEnabled = (sender.state == .on)
    }

    @objc private func toggleCropLivePhotoConfirm(_ sender: NSButton) {
        AppConfig.shared.cropLivePhotoConfirm = (sender.state == .on)
    }

    // MARK: - AI Enhance Actions

    @objc private func enhanceVibranceStepperChanged(_ sender: NSStepper) {
        let value = sender.doubleValue
        enhanceVibranceField.stringValue = String(format: "%.2f", value)
        AppConfig.shared.enhanceVibrance = value
    }

    @objc private func enhanceVibranceFieldChanged(_ sender: NSTextField) {
        guard let value = Double(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig()
            return
        }
        let clamped = min(max(value, 0), 1)
        sender.stringValue = String(format: "%.2f", clamped)
        enhanceVibranceStepper.doubleValue = clamped
        AppConfig.shared.enhanceVibrance = clamped
    }

    @objc private func enhanceContrastStepperChanged(_ sender: NSStepper) {
        let value = sender.doubleValue
        enhanceContrastField.stringValue = String(format: "%.2f", value)
        AppConfig.shared.enhanceContrast = value
    }

    @objc private func enhanceContrastFieldChanged(_ sender: NSTextField) {
        guard let value = Double(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig()
            return
        }
        let clamped = min(max(value, 0.5), 2.0)
        sender.stringValue = String(format: "%.2f", clamped)
        enhanceContrastStepper.doubleValue = clamped
        AppConfig.shared.enhanceContrast = clamped
    }

    @objc private func enhanceSharpnessStepperChanged(_ sender: NSStepper) {
        let value = sender.doubleValue
        enhanceSharpnessField.stringValue = String(format: "%.2f", value)
        AppConfig.shared.enhanceSharpness = value
    }

    @objc private func enhanceSharpnessFieldChanged(_ sender: NSTextField) {
        guard let value = Double(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig()
            return
        }
        let clamped = min(max(value, 0), 1)
        sender.stringValue = String(format: "%.2f", clamped)
        enhanceSharpnessStepper.doubleValue = clamped
        AppConfig.shared.enhanceSharpness = clamped
    }

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

    // MARK: - Restore Defaults (per tab)

    @objc private func restoreGeneralDefaults(_ sender: Any?) {
        AppConfig.shared.quitOnLastWindowClosed = AppConfig.Defaults.quitOnLastWindowClosed
        AppConfig.shared.deleteConfirmationEnabled = AppConfig.Defaults.deleteConfirmationEnabled
        AppConfig.shared.uiLanguage = AppConfig.Defaults.uiLanguage
        AppConfig.shared.imageTransitionDuration = AppConfig.Defaults.imageTransitionDuration
        AppConfig.shared.modelCheckPromptEnabled = AppConfig.Defaults.modelCheckPromptEnabled
        AppConfig.shared.cropLivePhotoConfirm = AppConfig.Defaults.cropLivePhotoConfirm
        AppConfig.shared.livePhotoAutoPlay = AppConfig.Defaults.livePhotoAutoPlay
        AppConfig.shared.livePhotoMuted = AppConfig.Defaults.livePhotoMuted
        AppConfig.shared.openPanelDirectoryMode = AppConfig.Defaults.openPanelDirectoryMode
        AppConfig.shared.customOpenDirectory = AppConfig.Defaults.customOpenDirectory()
        AppConfig.shared.slideshowInterval = AppConfig.Defaults.slideshowInterval
    }

    @objc private func restoreEnhanceDefaults(_ sender: Any?) {
        AppConfig.shared.enhanceVibrance = AppConfig.Defaults.enhanceVibrance
        AppConfig.shared.enhanceContrast = AppConfig.Defaults.enhanceContrast
        AppConfig.shared.enhanceSharpness = AppConfig.Defaults.enhanceSharpness
    }

    @objc private func restoreUpscaleDefaults(_ sender: Any?) {
        AppConfig.shared.aiAutoUpscaleEnabled = AppConfig.Defaults.aiAutoUpscaleEnabled
    }

    @objc private func restoreDewatermarkDefaults(_ sender: Any?) {
        AppConfig.shared.aiAutoDewatermarkEnabled = AppConfig.Defaults.aiAutoDewatermarkEnabled
    }

    @objc private func restoreOneClickDefaults(_ sender: Any?) {
        AppConfig.shared.aiEnhanceMode = AppConfig.Defaults.aiEnhanceMode
        AppConfig.shared.dedupAskContinue = AppConfig.Defaults.dedupAskContinue
    }

    @objc private func restoreAdvancedDefaults(_ sender: Any?) {
        AppConfig.shared.proxyEnabled = AppConfig.Defaults.proxyEnabled
        AppConfig.shared.proxyType = AppConfig.Defaults.proxyType
        AppConfig.shared.proxyHost = AppConfig.Defaults.proxyHost
        AppConfig.shared.proxyPort = AppConfig.Defaults.proxyPort
        AppConfig.shared.imageCacheCount = AppConfig.Defaults.imageCacheCount
        AppConfig.shared.logEnabled = AppConfig.Defaults.logEnabled
        AppConfig.shared.logPath = AppConfig.Defaults.logPath()
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
        row.statusLabel.stringValue = L10n.shared.t("Downloading…")
        PluginManager.shared.download(row.plugin, progress: { p in
            self.modelRows.first { $0.plugin == row.plugin }?.statusLabel.stringValue = L10n.shared.tf("Downloading… %.0f%%", p * 100)
        }, completion: { result in
            switch result {
            case .success:
                self.syncModelRows()
            case .failure(let error):
                self.modelRows.first { $0.plugin == row.plugin }?.statusLabel.stringValue = L10n.shared.tf("Error: %@", error.localizedDescription)
            }
        })
    }

    @objc private func modelEnableToggled(_ sender: NSButton) {
        guard let row = modelRow(forControl: sender) else { return }
        let enabled = (sender.state == .on)
        if enabled, !PluginManager.shared.isReady(row.plugin) {
            sender.state = .off
            row.statusLabel.stringValue = L10n.shared.t("Not downloaded")
            return
        }
        PluginManager.shared.setEnabled(row.plugin, enabled: enabled)
    }

    @objc private func modelUninstallTapped(_ sender: NSButton) {
        guard let row = modelRow(forControl: sender) else { return }
        let alert = NSAlert()
        alert.messageText = L10n.shared.tf("Uninstall %@?", row.plugin.displayName)
        alert.informativeText = L10n.shared.t("The downloaded model files will be deleted. You can download them again later.")
        alert.addButton(withTitle: L10n.shared.t("Uninstall"))
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        PluginManager.shared.uninstall(row.plugin)
    }

    private func syncModelRows() {
        for i in modelRows.indices {
            let plugin = modelRows[i].plugin
            let state = PluginManager.shared.state(for: plugin)
            let enabled = PluginManager.shared.isEnabled(plugin)
            switch state {
            case .notDownloaded:
                modelRows[i].statusLabel.stringValue = L10n.shared.t("Not downloaded")
            case .downloading(let p):
                modelRows[i].statusLabel.stringValue = L10n.shared.tf("Downloading… %.0f%%", p * 100)
            case .ready:
                modelRows[i].statusLabel.stringValue = enabled ? L10n.shared.t("Enabled") : L10n.shared.t("Ready (disabled)")
            case .error(let msg):
                modelRows[i].statusLabel.stringValue = L10n.shared.tf("Error: %@", msg)
            }
            let wantState: Int = enabled ? 1 : 0
            if modelRows[i].enabledCheck.state.rawValue != wantState {
                modelRows[i].enabledCheck.state = (enabled ? .on : .off)
            }
        }
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

private final class FlippedBox: NSBox {
    override var isFlipped: Bool { true }
}

private final class NoAutoFocusTextField: NSTextField {
    private var allowFocus = false

    func enableFocus() {
        allowFocus = true
        window?.makeFirstResponder(self)
        allowFocus = false
    }

    override var acceptsFirstResponder: Bool { allowFocus }

    override func mouseDown(with event: NSEvent) {
        enableFocus()
        super.mouseDown(with: event)
    }
}

private final class NoAutoFocusNumberField: NSTextField {
    private var allowFocus = false

    func enableFocus() {
        allowFocus = true
        window?.makeFirstResponder(self)
        allowFocus = false
    }

    override var acceptsFirstResponder: Bool { allowFocus }

    override func mouseDown(with event: NSEvent) {
        enableFocus()
        super.mouseDown(with: event)
    }
}

// MARK: - NSTabViewDelegate

extension PreferencesWindow: NSTabViewDelegate {
    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        window?.makeFirstResponder(nil)
    }
}