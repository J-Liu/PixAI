// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// The Preferences window (Cmd+, / PixAI ▸ Preferences...).
final class PreferencesWindow: NSObject {
    static let shared = PreferencesWindow()

    private var window: NSWindow?
    private var mainTabView: NSTabView!
    private var aiTabView: NSTabView!

    // Controls
    private var quitCheckbox: NSButton!
    private var deleteConfirmCheckbox: NSButton!
    private var languagePopup: NSPopUpButton!
    private var transitionField: NSTextField!
    private var transitionStepper: NSStepper!
    private var modelCheckPromptCheckbox: NSButton!
    private var cropLivePhotoConfirmCheckbox: NSButton!
    private var liveAutoPlayCheckbox: NSButton!
    private var liveMutedCheckbox: NSButton!
    private var cropModePopup: NSPopUpButton!
    private var openDirModePopup: NSPopUpButton!
    private var openDirField: NSTextField!
    private var intervalField: NSTextField!
    private var intervalStepper: NSStepper!
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
    private var smallImageThresholdField: NSTextField!
    private var smallImageThresholdStepper: NSStepper!

    // AI - Dewatermark tab
    private var aiAutoDewatermarkCheckbox: NSButton!
    private var watermarkModePopup: NSPopUpButton!
    private var watermarkThresholdField: NSTextField!
    private var watermarkThresholdStepper: NSStepper!
    private var watermarkMinFractionField: NSTextField!
    private var watermarkMinFractionStepper: NSStepper!
    private var watermarkFeatherField: NSTextField!
    private var watermarkFeatherStepper: NSStepper!

    // AI - One-click tab
    private var enhanceModePopup: NSPopUpButton!
    private var dedupAskContinueCheckbox: NSButton!
    private var dedupThresholdField: NSTextField!
    private var dedupThresholdStepper: NSStepper!
    private var oneClickStatusLabel: NSTextField!

    // Proxy
    private var proxyEnabledCheckbox: NSButton!
    private var proxyTypePopup: NSPopUpButton!
    private var proxyHostField: NSTextField!
    private var proxyPortField: NSTextField!
    private var proxyPortStepper: NSStepper!

    private var modelRows: [(plugin: ModelPlugin, nameLabel: NSTextField, statusLabel: NSTextField, downloadButton: NSButton, enabledCheck: NSButton, uninstallButton: NSButton)] = []
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

    func showAIModelsTab() {
        show()
        if mainTabView.numberOfTabViewItems > 1 {
            mainTabView.selectTabViewItem(at: 1)
        }
        if let aiTab = aiTabView, aiTab.numberOfTabViewItems > 4 {
            aiTab.selectTabViewItem(at: 4)
        }
    }

    // MARK: - Building

    private func buildWindow() {
        let contentSize = NSSize(width: 600, height: 580)
        let win = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = L10n.shared.t("Preferences")
        win.isReleasedWhenClosed = false

        let root = NSView(frame: NSRect(origin: .zero, size: contentSize))
        win.contentView = root

        let margin: CGFloat = 20
        let tabHeight: CGFloat = contentSize.height - margin * 2

        mainTabView = NSTabView(frame: NSRect(x: margin, y: margin, width: contentSize.width - margin * 2, height: tabHeight))
        mainTabView.tabViewType = .topTabsBezelBorder
        root.addSubview(mainTabView)

        let t = L10n.shared.t

        let generalTab = NSTabViewItem(identifier: "general")
        generalTab.label = t("General")
        generalTab.view = NSView(frame: NSRect(x: 0, y: 0, width: mainTabView.bounds.width - 20, height: tabHeight - 40))
        buildGeneralTab(generalTab.view!, t: t)
        mainTabView.addTabViewItem(generalTab)

        let aiTab = NSTabViewItem(identifier: "ai")
        aiTab.label = t("AI")
        aiTab.view = NSView(frame: NSRect(x: 0, y: 0, width: mainTabView.bounds.width - 20, height: tabHeight - 40))
        buildAITab(aiTab.view!, t: t)
        mainTabView.addTabViewItem(aiTab)

        let advancedTab = NSTabViewItem(identifier: "advanced")
        advancedTab.label = t("Advanced")
        advancedTab.view = NSView(frame: NSRect(x: 0, y: 0, width: mainTabView.bounds.width - 20, height: tabHeight - 40))
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

    // MARK: - Section Builder (simple NSView with title label)

    private func makeSection(_ root: NSView, title: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSView {
        let container = NSView(frame: NSRect(x: x, y: y, width: width, height: height))

        // Title label at top-left
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.sizeToFit()
        titleLabel.frame = NSRect(x: 0, y: height - 20, width: min(titleLabel.frame.width + 4, width), height: 18)
        container.addSubview(titleLabel)

        // Content view below title
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height - 28))
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        contentView.layer?.cornerRadius = 6
        contentView.layer?.borderWidth = 1
        contentView.layer?.borderColor = NSColor.separatorColor.cgColor
        container.addSubview(contentView)

        root.addSubview(container)
        return contentView
    }

    private func makeCheck(_ parent: NSView, title: String, x: CGFloat, y: CGFloat) -> NSButton {
        let check = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        check.font = NSFont.systemFont(ofSize: 13)
        check.sizeToFit()
        check.frame = NSRect(x: x, y: y, width: check.frame.width, height: check.frame.height)
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

    // MARK: - General Tab

    private func buildGeneralTab(_ root: NSView, t: (String) -> String) {
        let contentWidth = root.bounds.width - 28
        let rootHeight = root.bounds.height

        // Restore button at bottom
        let restoreButton = NSButton(frame: NSRect(x: contentWidth - 140, y: 14, width: 140, height: 26))
        restoreButton.title = t("Restore This Page Defaults")
        restoreButton.bezelStyle = .rounded
        restoreButton.target = self
        restoreButton.action = #selector(restoreGeneralDefaults(_:))
        root.addSubview(restoreButton)

        // Section fills remaining space above button
        let sectionHeight = rootHeight - 54  // 54 = 14 (margin) + 26 (button) + 14 (gap)
        let box = makeSection(root, title: t("General"), x: 14, y: 54, width: contentWidth, height: sectionHeight)

        // Content view height is sectionHeight - 28 (title space)
        let boxHeight = sectionHeight - 28
        let topPadding: CGFloat = 10  // Space from top edge
        var rowY = boxHeight - topPadding  // First item's top edge position
        quitCheckbox = makeCheck(box, title: t("Quit app when the last window is closed"), x: 14, y: rowY - 18)
        quitCheckbox.state = AppConfig.shared.quitOnLastWindowClosed ? .on : .off
        quitCheckbox.target = self
        quitCheckbox.action = #selector(toggleQuitOnLastClose(_:))
        rowY -= 28

        deleteConfirmCheckbox = makeCheck(box, title: t("Ask for confirmation before deleting a file"), x: 14, y: rowY - 18)
        deleteConfirmCheckbox.state = AppConfig.shared.deleteConfirmationEnabled ? .on : .off
        deleteConfirmCheckbox.target = self
        deleteConfirmCheckbox.action = #selector(toggleDeleteConfirm(_:))
        rowY -= 28

        let langLabel = makeLabel(box, text: t("Language"), x: 14, y: rowY - 16)
        languagePopup = makePopup(box, items: ["English", "简体中文", "繁體中文"], x: langLabel.frame.maxX + 10, y: rowY - 18, width: 120)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))
        rowY -= 28

        let openDirLabel = makeLabel(box, text: t("Default directory:"), x: 14, y: rowY - 16)
        openDirModePopup = makePopup(box, items: [t("Last open"), t("Choose...")], x: openDirLabel.frame.maxX + 10, y: rowY - 18, width: 100)
        openDirModePopup.target = self
        openDirModePopup.action = #selector(openDirModeChanged(_:))
        openDirField = NSTextField(frame: NSRect(x: openDirModePopup.frame.maxX + 10, y: rowY - 20, width: 220, height: 24))
        openDirField.font = NSFont.systemFont(ofSize: 12)
        openDirField.isEditable = false
        openDirField.isBezeled = true
        openDirField.drawsBackground = true
        openDirField.backgroundColor = NSColor.controlBackgroundColor
        openDirField.focusRingType = .none
        box.addSubview(openDirField)
        rowY -= 28

        let transitionLabel = makeLabel(box, text: t("Image transition duration (0–2 s, 0 = off):"), x: 14, y: rowY - 16)
        transitionField = NSTextField(frame: NSRect(x: transitionLabel.frame.maxX + 10, y: rowY - 20, width: 56, height: 24))
        transitionField.font = NSFont.systemFont(ofSize: 13)
        transitionField.alignment = .center
        transitionField.target = self
        transitionField.action = #selector(transitionFieldChanged(_:))
        box.addSubview(transitionField)
        transitionStepper = NSStepper(frame: NSRect(x: transitionField.frame.maxX + 4, y: rowY - 20, width: 19, height: 27))
        transitionStepper.minValue = 0
        transitionStepper.maxValue = 2
        transitionStepper.increment = 0.1
        transitionStepper.valueWraps = false
        transitionStepper.doubleValue = AppConfig.shared.imageTransitionDuration
        transitionStepper.target = self
        transitionStepper.action = #selector(transitionStepperChanged(_:))
        box.addSubview(transitionStepper)
        rowY -= 28

        let intervalLabel = makeLabel(box, text: t("Slideshow interval (1–600 s):"), x: 14, y: rowY - 16)
        intervalField = NSTextField(frame: NSRect(x: intervalLabel.frame.maxX + 10, y: rowY - 20, width: 64, height: 24))
        intervalField.font = NSFont.systemFont(ofSize: 13)
        intervalField.alignment = .center
        box.addSubview(intervalField)
        intervalField.target = self
        intervalField.action = #selector(intervalFieldChanged(_:))
        intervalStepper = NSStepper(frame: NSRect(x: intervalField.frame.maxX + 4, y: rowY - 20, width: 19, height: 27))
        intervalStepper.minValue = 1
        intervalStepper.maxValue = 600
        intervalStepper.increment = 1
        intervalStepper.valueWraps = false
        intervalStepper.integerValue = Int(AppConfig.shared.slideshowInterval)
        intervalStepper.target = self
        intervalStepper.action = #selector(intervalStepperChanged(_:))
        box.addSubview(intervalStepper)
        rowY -= 28

        modelCheckPromptCheckbox = makeCheck(box, title: t("Ask to download AI models at startup when missing"), x: 14, y: rowY - 18)
        modelCheckPromptCheckbox.state = AppConfig.shared.modelCheckPromptEnabled ? .on : .off
        modelCheckPromptCheckbox.target = self
        modelCheckPromptCheckbox.action = #selector(toggleModelCheckPrompt(_:))
        rowY -= 28

        cropLivePhotoConfirmCheckbox = makeCheck(box, title: t("Confirm before cropping a Live Photo (result is a still image)"), x: 14, y: rowY - 18)
        cropLivePhotoConfirmCheckbox.state = AppConfig.shared.cropLivePhotoConfirm ? .on : .off
        cropLivePhotoConfirmCheckbox.target = self
        cropLivePhotoConfirmCheckbox.action = #selector(toggleCropLivePhotoConfirm(_:))
        rowY -= 28

        liveAutoPlayCheckbox = makeCheck(box, title: t("Auto-play Live Photos when displayed"), x: 14, y: rowY - 18)
        liveAutoPlayCheckbox.state = AppConfig.shared.livePhotoAutoPlay ? .on : .off
        liveAutoPlayCheckbox.target = self
        liveAutoPlayCheckbox.action = #selector(toggleLiveAutoPlay(_:))
        rowY -= 28

        liveMutedCheckbox = makeCheck(box, title: t("Mute Live Photo playback"), x: 14, y: rowY - 18)
        liveMutedCheckbox.state = AppConfig.shared.livePhotoMuted ? .on : .off
        liveMutedCheckbox.target = self
        liveMutedCheckbox.action = #selector(toggleLiveMuted(_:))
        rowY -= 28

        // Crop mode
        let cropModeLabel = makeLabel(box, text: t("Crop region selection:"), x: 14, y: rowY - 16)
        cropModePopup = makePopup(box, items: [t("Full image"), t("Drag to select")], x: cropModeLabel.frame.maxX + 10, y: rowY - 18, width: 140)
        cropModePopup.target = self
        cropModePopup.action = #selector(cropModeChanged(_:))
        let savedCropMode = AppConfig.shared.cropMode
        if savedCropMode == "select" {
            cropModePopup.selectItem(at: 1)
        } else {
            cropModePopup.selectItem(at: 0)
        }
    }

    // MARK: - AI Tab

    private func buildAITab(_ root: NSView, t: (String) -> String) {
        let contentWidth = root.bounds.width - 28

        // AI tab view fills the available space
        aiTabView = NSTabView(frame: NSRect(x: 14, y: 14, width: contentWidth, height: root.bounds.height - 28))
        aiTabView.tabViewType = .topTabsBezelBorder
        root.addSubview(aiTabView)

        let enhanceTab = NSTabViewItem(identifier: "enhance")
        enhanceTab.label = t("Quality Enhance")
        enhanceTab.view = NSView(frame: NSRect(x: 0, y: 0, width: aiTabView.bounds.width - 20, height: aiTabView.bounds.height - 40))
        buildEnhanceTab(enhanceTab.view!, t: t)
        aiTabView.addTabViewItem(enhanceTab)

        let upscaleTab = NSTabViewItem(identifier: "upscale")
        upscaleTab.label = t("Super Resolution")
        upscaleTab.view = NSView(frame: NSRect(x: 0, y: 0, width: aiTabView.bounds.width - 20, height: aiTabView.bounds.height - 40))
        buildUpscaleTab(upscaleTab.view!, t: t)
        aiTabView.addTabViewItem(upscaleTab)

        let dewatermarkTab = NSTabViewItem(identifier: "dewatermark")
        dewatermarkTab.label = t("Remove Watermark")
        dewatermarkTab.view = NSView(frame: NSRect(x: 0, y: 0, width: aiTabView.bounds.width - 20, height: aiTabView.bounds.height - 40))
        buildDewatermarkTab(dewatermarkTab.view!, t: t)
        aiTabView.addTabViewItem(dewatermarkTab)

        let dedupTab = NSTabViewItem(identifier: "dedup")
        dedupTab.label = t("AI Dedup")
        dedupTab.view = NSView(frame: NSRect(x: 0, y: 0, width: aiTabView.bounds.width - 20, height: aiTabView.bounds.height - 40))
        buildDedupTab(dedupTab.view!, t: t)
        aiTabView.addTabViewItem(dedupTab)

        let oneClickTab = NSTabViewItem(identifier: "oneclick")
        oneClickTab.label = t("One-click Enhance")
        oneClickTab.view = NSView(frame: NSRect(x: 0, y: 0, width: aiTabView.bounds.width - 20, height: aiTabView.bounds.height - 40))
        buildOneClickTab(oneClickTab.view!, t: t)
        aiTabView.addTabViewItem(oneClickTab)

        let modelsTab = NSTabViewItem(identifier: "models")
        modelsTab.label = t("AI Models")
        modelsTab.view = NSView(frame: NSRect(x: 0, y: 0, width: aiTabView.bounds.width - 20, height: aiTabView.bounds.height - 40))
        buildModelsTab(modelsTab.view!, t: t)
        aiTabView.addTabViewItem(modelsTab)

        aiTabView.delegate = self
    }

    private func buildEnhanceTab(_ root: NSView, t: (String) -> String) {
        let contentWidth = root.bounds.width - 28
        let rootHeight = root.bounds.height

        // Restore button at bottom
        let restoreButton = NSButton(frame: NSRect(x: contentWidth - 140, y: 14, width: 140, height: 26))
        restoreButton.title = t("Restore This Page Defaults")
        restoreButton.bezelStyle = .rounded
        restoreButton.target = self
        restoreButton.action = #selector(restoreEnhanceDefaults(_:))
        root.addSubview(restoreButton)

        // Section fills remaining space
        let sectionHeight = rootHeight - 54
        let box = makeSection(root, title: t("Enhancement Parameters"), x: 14, y: 54, width: contentWidth, height: sectionHeight)

        // Content view height is sectionHeight - 28 (title space)
        let boxHeight = sectionHeight - 28
        let topPadding: CGFloat = 10
        var rowY = boxHeight - topPadding
        let vibranceLabel = makeLabel(box, text: t("Vibrance (0–1):"), x: 14, y: rowY - 16)
        enhanceVibranceField = NSTextField(frame: NSRect(x: vibranceLabel.frame.maxX + 10, y: rowY - 20, width: 64, height: 24))
        enhanceVibranceField.font = NSFont.systemFont(ofSize: 13)
        enhanceVibranceField.alignment = .center
        box.addSubview(enhanceVibranceField)
        enhanceVibranceField.target = self
        enhanceVibranceField.action = #selector(enhanceVibranceFieldChanged(_:))
        enhanceVibranceStepper = NSStepper(frame: NSRect(x: enhanceVibranceField.frame.maxX + 4, y: rowY - 20, width: 19, height: 27))
        enhanceVibranceStepper.minValue = 0
        enhanceVibranceStepper.maxValue = 1
        enhanceVibranceStepper.increment = 0.05
        enhanceVibranceStepper.valueWraps = false
        enhanceVibranceStepper.doubleValue = AppConfig.shared.enhanceVibrance
        enhanceVibranceStepper.target = self
        enhanceVibranceStepper.action = #selector(enhanceVibranceStepperChanged(_:))
        box.addSubview(enhanceVibranceStepper)
        rowY -= 34

        let contrastLabel = makeLabel(box, text: t("Contrast (0.5–2.0, 1.0 = off):"), x: 14, y: rowY - 16)
        enhanceContrastField = NSTextField(frame: NSRect(x: contrastLabel.frame.maxX + 10, y: rowY - 20, width: 64, height: 24))
        enhanceContrastField.font = NSFont.systemFont(ofSize: 13)
        enhanceContrastField.alignment = .center
        box.addSubview(enhanceContrastField)
        enhanceContrastField.target = self
        enhanceContrastField.action = #selector(enhanceContrastFieldChanged(_:))
        enhanceContrastStepper = NSStepper(frame: NSRect(x: enhanceContrastField.frame.maxX + 4, y: rowY - 20, width: 19, height: 27))
        enhanceContrastStepper.minValue = 0.5
        enhanceContrastStepper.maxValue = 2.0
        enhanceContrastStepper.increment = 0.05
        enhanceContrastStepper.valueWraps = false
        enhanceContrastStepper.doubleValue = AppConfig.shared.enhanceContrast
        enhanceContrastStepper.target = self
        enhanceContrastStepper.action = #selector(enhanceContrastStepperChanged(_:))
        box.addSubview(enhanceContrastStepper)
        rowY -= 34

        let sharpnessLabel = makeLabel(box, text: t("Sharpness (0–1):"), x: 14, y: rowY - 16)
        enhanceSharpnessField = NSTextField(frame: NSRect(x: sharpnessLabel.frame.maxX + 10, y: rowY - 20, width: 64, height: 24))
        enhanceSharpnessField.font = NSFont.systemFont(ofSize: 13)
        enhanceSharpnessField.alignment = .center
        box.addSubview(enhanceSharpnessField)
        enhanceSharpnessField.target = self
        enhanceSharpnessField.action = #selector(enhanceSharpnessFieldChanged(_:))
        enhanceSharpnessStepper = NSStepper(frame: NSRect(x: enhanceSharpnessField.frame.maxX + 4, y: rowY - 20, width: 19, height: 27))
        enhanceSharpnessStepper.minValue = 0
        enhanceSharpnessStepper.maxValue = 1
        enhanceSharpnessStepper.increment = 0.05
        enhanceSharpnessStepper.valueWraps = false
        enhanceSharpnessStepper.doubleValue = AppConfig.shared.enhanceSharpness
        enhanceSharpnessStepper.target = self
        enhanceSharpnessStepper.action = #selector(enhanceSharpnessStepperChanged(_:))
        box.addSubview(enhanceSharpnessStepper)
    }

    private func buildUpscaleTab(_ root: NSView, t: (String) -> String) {
        let contentWidth = root.bounds.width - 28
        let rootHeight = root.bounds.height

        // Restore button at bottom
        let restoreButton = NSButton(frame: NSRect(x: contentWidth - 140, y: 14, width: 140, height: 26))
        restoreButton.title = t("Restore This Page Defaults")
        restoreButton.bezelStyle = .rounded
        restoreButton.target = self
        restoreButton.action = #selector(restoreUpscaleDefaults(_:))
        root.addSubview(restoreButton)

        // Section fills remaining space
        let sectionHeight = rootHeight - 54
        let box = makeSection(root, title: t("Super Resolution (Real-ESRGAN 4x)"), x: 14, y: 54, width: contentWidth, height: sectionHeight)

        // Content view height is sectionHeight - 28 (title space)
        let boxHeight = sectionHeight - 28
        let topPadding: CGFloat = 10
        var rowY = boxHeight - topPadding

        let modelReady = PluginManager.shared.isReady(.realesrgan)
        if modelReady {
            aiAutoUpscaleCheckbox = makeCheck(box, title: t("Auto AI super-resolve small images on load"), x: 14, y: rowY - 18)
            aiAutoUpscaleCheckbox.state = AppConfig.shared.aiAutoUpscaleEnabled ? .on : .off
            aiAutoUpscaleCheckbox.target = self
            aiAutoUpscaleCheckbox.action = #selector(toggleAutoUpscale(_:))
            rowY -= 32

            // Small image threshold
            let thresholdLabel = makeLabel(box, text: t("Small image threshold (px, longest side):"), x: 14, y: rowY - 16)
            smallImageThresholdField = NSTextField(frame: NSRect(x: thresholdLabel.frame.maxX + 10, y: rowY - 20, width: 64, height: 24))
            smallImageThresholdField.font = NSFont.systemFont(ofSize: 13)
            smallImageThresholdField.alignment = .center
            smallImageThresholdField.target = self
            smallImageThresholdField.action = #selector(smallImageThresholdFieldChanged(_:))
            box.addSubview(smallImageThresholdField)
            smallImageThresholdStepper = NSStepper(frame: NSRect(x: smallImageThresholdField.frame.maxX + 4, y: rowY - 20, width: 19, height: 27))
            smallImageThresholdStepper.minValue = 64
            smallImageThresholdStepper.maxValue = 8192
            smallImageThresholdStepper.increment = 128
            smallImageThresholdStepper.valueWraps = false
            smallImageThresholdStepper.integerValue = AppConfig.shared.smallImageMaxSide
            smallImageThresholdStepper.target = self
            smallImageThresholdStepper.action = #selector(smallImageThresholdStepperChanged(_:))
            box.addSubview(smallImageThresholdStepper)
        } else {
            let statusLabel = NSTextField(frame: NSRect(x: 14, y: rowY - 20, width: contentWidth - 28, height: 20))
            statusLabel.stringValue = t("Model not downloaded. Please download in AI Models tab.")
            statusLabel.font = NSFont.systemFont(ofSize: 12)
            statusLabel.textColor = NSColor.secondaryLabelColor
            statusLabel.isBezeled = false
            statusLabel.drawsBackground = false
            statusLabel.isEditable = false
            statusLabel.isSelectable = false
            box.addSubview(statusLabel)
        }
    }

    private func buildDewatermarkTab(_ root: NSView, t: (String) -> String) {
        let contentWidth = root.bounds.width - 28
        let rootHeight = root.bounds.height

        // Restore button at bottom
        let restoreButton = NSButton(frame: NSRect(x: contentWidth - 140, y: 14, width: 140, height: 26))
        restoreButton.title = t("Restore This Page Defaults")
        restoreButton.bezelStyle = .rounded
        restoreButton.target = self
        restoreButton.action = #selector(restoreDewatermarkDefaults(_:))
        root.addSubview(restoreButton)

        // Section fills remaining space
        let sectionHeight = rootHeight - 54
        let box = makeSection(root, title: t("Watermark Removal (U2Net + LaMa)"), x: 14, y: 54, width: contentWidth, height: sectionHeight)

        // Content view height is sectionHeight - 28 (title space)
        // Add padding from the box's border (8px for corner radius + border)
        let boxHeight = sectionHeight - 28
        let padding: CGFloat = 12  // Padding from box edges
        var rowY = boxHeight - padding

        // Check both models: U2Net for detection, LaMa for inpainting
        let u2netReady = PluginManager.shared.isReady(.u2net)
        let lamaReady = PluginManager.shared.isReady(.lama)
        let autoReady = u2netReady && lamaReady
        let manualReady = lamaReady

        if autoReady || manualReady {
            // Mode selection
            let modeLabel = makeLabel(box, text: t("Mode:"), x: padding, y: rowY - 16)
            watermarkModePopup = makePopup(box, items: [t("Auto (detect watermark automatically)"), t("Manual (select region manually)")],
                                           x: modeLabel.frame.maxX + 10, y: rowY - 18, width: 260)
            watermarkModePopup.target = self
            watermarkModePopup.action = #selector(watermarkModeChanged(_:))
            let savedMode = AppConfig.shared.watermarkMode
            if savedMode == "manual" {
                watermarkModePopup.selectItem(at: 1)
            } else {
                watermarkModePopup.selectItem(at: 0)
            }
            // Disable auto mode if U2Net not ready
            if !u2netReady {
                watermarkModePopup.item(at: 0)?.isEnabled = false
                watermarkModePopup.selectItem(at: 1)
            }
            rowY -= 32

            // Auto mode on load
            aiAutoDewatermarkCheckbox = makeCheck(box, title: t("Auto remove watermark on image load"), x: padding, y: rowY - 18)
            aiAutoDewatermarkCheckbox.state = AppConfig.shared.aiAutoDewatermarkEnabled ? .on : .off
            aiAutoDewatermarkCheckbox.target = self
            aiAutoDewatermarkCheckbox.action = #selector(toggleAutoDewatermark(_:))
            rowY -= 32

            // Detection threshold (U2Net, auto mode only)
            if u2netReady {
                let thresholdLabel = makeLabel(box, text: t("Detection sensitivity (0.1–0.9, lower = more sensitive):"), x: padding, y: rowY - 16)
                watermarkThresholdField = NSTextField(frame: NSRect(x: thresholdLabel.frame.maxX + 10, y: rowY - 20, width: 56, height: 24))
                watermarkThresholdField.font = NSFont.systemFont(ofSize: 13)
                watermarkThresholdField.alignment = .center
                watermarkThresholdField.target = self
                watermarkThresholdField.action = #selector(watermarkThresholdFieldChanged(_:))
                box.addSubview(watermarkThresholdField)
                watermarkThresholdStepper = NSStepper(frame: NSRect(x: watermarkThresholdField.frame.maxX + 4, y: rowY - 20, width: 19, height: 27))
                watermarkThresholdStepper.minValue = 0.1
                watermarkThresholdStepper.maxValue = 0.9
                watermarkThresholdStepper.increment = 0.05
                watermarkThresholdStepper.valueWraps = false
                watermarkThresholdStepper.doubleValue = AppConfig.shared.watermarkMaskThreshold
                watermarkThresholdStepper.target = self
                watermarkThresholdStepper.action = #selector(watermarkThresholdStepperChanged(_:))
                box.addSubview(watermarkThresholdStepper)
                rowY -= 34

                // Minimum fraction
                let minFractionLabel = makeLabel(box, text: t("Min. watermark size (0.0001–0.1, lower = detect smaller):"), x: padding, y: rowY - 16)
                watermarkMinFractionField = NSTextField(frame: NSRect(x: minFractionLabel.frame.maxX + 10, y: rowY - 20, width: 64, height: 24))
                watermarkMinFractionField.font = NSFont.systemFont(ofSize: 13)
                watermarkMinFractionField.alignment = .center
                watermarkMinFractionField.target = self
                watermarkMinFractionField.action = #selector(watermarkMinFractionFieldChanged(_:))
                box.addSubview(watermarkMinFractionField)
                watermarkMinFractionStepper = NSStepper(frame: NSRect(x: watermarkMinFractionField.frame.maxX + 4, y: rowY - 20, width: 19, height: 27))
                watermarkMinFractionStepper.minValue = 0.0001
                watermarkMinFractionStepper.maxValue = 0.1
                watermarkMinFractionStepper.increment = 0.0001
                watermarkMinFractionStepper.valueWraps = false
                watermarkMinFractionStepper.doubleValue = AppConfig.shared.watermarkMinMaskFraction
                watermarkMinFractionStepper.target = self
                watermarkMinFractionStepper.action = #selector(watermarkMinFractionStepperChanged(_:))
                box.addSubview(watermarkMinFractionStepper)
                rowY -= 34
            }

            // Feather radius (LaMa, both modes)
            let featherLabel = makeLabel(box, text: t("Mask edge feather (0–10 px, for smoother blending):"), x: padding, y: rowY - 16)
            watermarkFeatherField = NSTextField(frame: NSRect(x: featherLabel.frame.maxX + 10, y: rowY - 20, width: 40, height: 24))
            watermarkFeatherField.font = NSFont.systemFont(ofSize: 13)
            watermarkFeatherField.alignment = .center
            watermarkFeatherField.target = self
            watermarkFeatherField.action = #selector(watermarkFeatherFieldChanged(_:))
            box.addSubview(watermarkFeatherField)
            watermarkFeatherStepper = NSStepper(frame: NSRect(x: watermarkFeatherField.frame.maxX + 4, y: rowY - 20, width: 19, height: 27))
            watermarkFeatherStepper.minValue = 0
            watermarkFeatherStepper.maxValue = 10
            watermarkFeatherStepper.increment = 1
            watermarkFeatherStepper.valueWraps = false
            watermarkFeatherStepper.integerValue = AppConfig.shared.watermarkFeatherRadius
            watermarkFeatherStepper.target = self
            watermarkFeatherStepper.action = #selector(watermarkFeatherStepperChanged(_:))
            box.addSubview(watermarkFeatherStepper)
        } else {
            let statusLabel = NSTextField(frame: NSRect(x: padding, y: rowY - 20, width: contentWidth - padding * 2 - 28, height: 40))
            var msg = t("Models not downloaded. Please download in AI Models tab.")
            if !lamaReady {
                msg = t("LaMa model required. Please download in AI Models tab.")
            }
            statusLabel.stringValue = msg
            statusLabel.font = NSFont.systemFont(ofSize: 12)
            statusLabel.textColor = NSColor.secondaryLabelColor
            statusLabel.isBezeled = false
            statusLabel.drawsBackground = false
            statusLabel.isEditable = false
            statusLabel.isSelectable = false
            box.addSubview(statusLabel)
        }
    }

    private func buildDedupTab(_ root: NSView, t: (String) -> String) {
        let contentWidth = root.bounds.width - 28
        let rootHeight = root.bounds.height

        // Restore button at bottom
        let restoreButton = NSButton(frame: NSRect(x: contentWidth - 140, y: 14, width: 140, height: 26))
        restoreButton.title = t("Restore This Page Defaults")
        restoreButton.bezelStyle = .rounded
        restoreButton.target = self
        restoreButton.action = #selector(restoreDedupDefaults(_:))
        root.addSubview(restoreButton)

        // Section fills remaining space
        let sectionHeight = rootHeight - 54
        let box = makeSection(root, title: t("AI Dedup Settings"), x: 14, y: 54, width: contentWidth, height: sectionHeight)

        // Content view height is sectionHeight - 28 (title space)
        let boxHeight = sectionHeight - 28
        let topPadding: CGFloat = 10
        var rowY = boxHeight - topPadding

        let thresholdLabel = makeLabel(box, text: t("Similarity threshold (0.70–0.99, higher = stricter):"), x: 14, y: rowY - 16)
        dedupThresholdField = NSTextField(frame: NSRect(x: thresholdLabel.frame.maxX + 10, y: rowY - 20, width: 56, height: 24))
        dedupThresholdField.font = NSFont.systemFont(ofSize: 13)
        dedupThresholdField.alignment = .center
        dedupThresholdField.target = self
        dedupThresholdField.action = #selector(dedupThresholdFieldChanged(_:))
        box.addSubview(dedupThresholdField)
        dedupThresholdStepper = NSStepper(frame: NSRect(x: dedupThresholdField.frame.maxX + 4, y: rowY - 20, width: 19, height: 27))
        dedupThresholdStepper.minValue = 0.70
        dedupThresholdStepper.maxValue = 0.99
        dedupThresholdStepper.increment = 0.01
        dedupThresholdStepper.valueWraps = false
        dedupThresholdStepper.doubleValue = AppConfig.shared.dedupThreshold
        dedupThresholdStepper.target = self
        dedupThresholdStepper.action = #selector(dedupThresholdStepperChanged(_:))
        box.addSubview(dedupThresholdStepper)
        rowY -= 28

        dedupAskContinueCheckbox = makeCheck(box, title: t("Ask to continue between duplicate groups"), x: 14, y: rowY - 18)
        dedupAskContinueCheckbox.state = AppConfig.shared.dedupAskContinue ? .on : .off
        dedupAskContinueCheckbox.target = self
        dedupAskContinueCheckbox.action = #selector(toggleDedupAskContinue(_:))
    }

    private func buildOneClickTab(_ root: NSView, t: (String) -> String) {
        let contentWidth = root.bounds.width - 28
        let rootHeight = root.bounds.height

        // Restore button at bottom
        let restoreButton = NSButton(frame: NSRect(x: contentWidth - 140, y: 14, width: 140, height: 26))
        restoreButton.title = t("Restore This Page Defaults")
        restoreButton.bezelStyle = .rounded
        restoreButton.target = self
        restoreButton.action = #selector(restoreOneClickDefaults(_:))
        root.addSubview(restoreButton)

        // Section fills remaining space
        let sectionHeight = rootHeight - 54
        let box = makeSection(root, title: t("One-click Enhance Settings"), x: 14, y: 54, width: contentWidth, height: sectionHeight)

        // Content view height is sectionHeight - 28 (title space)
        let boxHeight = sectionHeight - 28
        let topPadding: CGFloat = 10
        var rowY = boxHeight - topPadding
        let modeLabel = makeLabel(box, text: t("One-click enhance:"), x: 14, y: rowY - 16)
        enhanceModePopup = makePopup(box, items: [t("Both (dedup + dewatermark)"), t("Dedup only"), t("Dewatermark only")],
                                     x: modeLabel.frame.maxX + 10, y: rowY - 18, width: 230)
        enhanceModePopup.target = self
        enhanceModePopup.action = #selector(enhanceModeChanged(_:))

        let savedMode = AppConfig.shared.aiEnhanceMode
        if savedMode == "dedupOnly" {
            enhanceModePopup.selectItem(at: 1)
        } else if savedMode == "watermarkOnly" {
            enhanceModePopup.selectItem(at: 2)
        } else {
            enhanceModePopup.selectItem(at: 0)
        }
        rowY -= 28

        let statusLabel = NSTextField(frame: NSRect(x: 14, y: rowY - 16, width: contentWidth - 28, height: 20))
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = NSColor.secondaryLabelColor
        statusLabel.isBezeled = false
        statusLabel.drawsBackground = false
        statusLabel.isEditable = false
        statusLabel.isSelectable = false
        statusLabel.stringValue = ""
        box.addSubview(statusLabel)

        oneClickStatusLabel = statusLabel
        updateOneClickStatus()
    }

    private func buildModelsTab(_ root: NSView, t: (String) -> String) {
        let contentWidth = root.bounds.width - 28
        let rootHeight = root.bounds.height

        // Section fills available space
        let sectionHeight = rootHeight - 28  // 28 = 14 (bottom margin) + 14 (top margin)
        let box = makeSection(root, title: t("AI Models"), x: 14, y: 14, width: contentWidth, height: sectionHeight)

        // Content view height is sectionHeight - 28 (title space)
        let boxHeight = sectionHeight - 28
        let topPadding: CGFloat = 10
        let headerLabel = makeLabel(box, text: t("Download third-party models for AI features:"), x: 14, y: (boxHeight - topPadding) - 16)
        headerLabel.font = NSFont.systemFont(ofSize: 12)

        modelRows = []
        var rowY = boxHeight - topPadding - 54
        for plugin in ModelPlugin.all {
            let funcText: String
            let nameText: String
            switch plugin {
            case .realesrgan:
                funcText = t("Super Resolution")
                nameText = "Real-ESRGAN 4x"
            case .u2net:
                funcText = t("Watermark Detection")
                nameText = "U2Net Saliency"
            case .lama:
                funcText = t("Watermark Inpainting")
                nameText = "LaMa"
            default:
                funcText = plugin.displayName
                nameText = plugin.displayName
            }
            let funcLabel = makeLabel(box, text: funcText, x: 14, y: rowY)
            funcLabel.font = NSFont.systemFont(ofSize: 12)
            funcLabel.textColor = NSColor.secondaryLabelColor
            let nameLabel = makeLabel(box, text: nameText, x: 14, y: rowY - 18)
            nameLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)

            let statusLabel = NSTextField(frame: NSRect(x: 120, y: rowY - 18, width: 100, height: 16))
            statusLabel.font = NSFont.systemFont(ofSize: 11)
            statusLabel.textColor = NSColor.secondaryLabelColor
            statusLabel.isBezeled = false
            statusLabel.drawsBackground = false
            statusLabel.isEditable = false
            statusLabel.isSelectable = false
            box.addSubview(statusLabel)

            let downloadButton = NSButton(frame: NSRect(x: 230, y: rowY - 21, width: 80, height: 26))
            downloadButton.title = t("Download")
            downloadButton.bezelStyle = .rounded
            downloadButton.target = self
            downloadButton.action = #selector(modelDownloadTapped(_:))
            box.addSubview(downloadButton)

            let enabledCheck = makeCheck(box, title: t("On"), x: 320, y: rowY - 18)
            enabledCheck.target = self
            enabledCheck.action = #selector(modelEnableToggled(_:))

            let uninstallButton = NSButton(frame: NSRect(x: 380, y: rowY - 21, width: 30, height: 26))
            uninstallButton.bezelStyle = .rounded
            uninstallButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: t("Uninstall"))
            uninstallButton.imagePosition = .imageOnly
            uninstallButton.target = self
            uninstallButton.action = #selector(modelUninstallTapped(_:))
            box.addSubview(uninstallButton)

            modelRows.append((plugin: plugin, nameLabel: nameLabel, statusLabel: statusLabel, downloadButton: downloadButton, enabledCheck: enabledCheck, uninstallButton: uninstallButton))
            rowY -= 52
        }
    }

    private func buildAdvancedTab(_ root: NSView, t: (String) -> String) {
        let contentWidth = root.bounds.width - 28
        let rootHeight = root.bounds.height

        // Section heights
        let logHeight: CGFloat = 96
        let cacheHeight: CGFloat = 64
        let proxyHeight: CGFloat = 98
        let gap: CGFloat = 14

        // Restore button at bottom
        let restoreButton = NSButton(frame: NSRect(x: contentWidth - 140, y: 14, width: 140, height: 26))
        restoreButton.title = t("Restore This Page Defaults")
        restoreButton.bezelStyle = .rounded
        restoreButton.target = self
        restoreButton.action = #selector(restoreAdvancedDefaults(_:))
        root.addSubview(restoreButton)

        // Start from top, spacer will be at bottom
        var y = rootHeight - proxyHeight - 14
        let padding: CGFloat = 10

        // Proxy at top
        let proxyBox = makeSection(root, title: t("Proxy"), x: 14, y: y, width: contentWidth, height: proxyHeight)
        let proxyContentH = proxyHeight - 28
        proxyEnabledCheckbox = makeCheck(proxyBox, title: t("Enable proxy for model downloads"), x: 14, y: proxyContentH - padding - 18)
        proxyEnabledCheckbox.state = AppConfig.shared.proxyEnabled ? .on : .off
        proxyEnabledCheckbox.target = self
        proxyEnabledCheckbox.action = #selector(toggleProxyEnabled(_:))

        _ = makeLabel(proxyBox, text: t("Type:"), x: 14, y: proxyContentH - padding - 48)
        proxyTypePopup = makePopup(proxyBox, items: ["HTTP", "SOCKS"], x: 58, y: proxyContentH - padding - 50, width: 90)
        proxyTypePopup.target = self
        proxyTypePopup.action = #selector(proxyTypeChanged(_:))

        _ = makeLabel(proxyBox, text: t("Host:"), x: 162, y: proxyContentH - padding - 48)
        proxyHostField = NSTextField(frame: NSRect(x: 202, y: proxyContentH - padding - 48, width: 150, height: 24))
        proxyHostField.font = NSFont.systemFont(ofSize: 13)
        proxyHostField.placeholderString = "127.0.0.1"
        proxyHostField.target = self
        proxyHostField.action = #selector(proxyHostFieldChanged(_:))
        proxyBox.addSubview(proxyHostField)

        _ = makeLabel(proxyBox, text: t("Port:"), x: 366, y: proxyContentH - padding - 48)
        proxyPortField = NSTextField(frame: NSRect(x: 408, y: proxyContentH - padding - 48, width: 60, height: 24))
        proxyPortField.font = NSFont.systemFont(ofSize: 13)
        proxyPortField.alignment = .center
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        proxyPortField.formatter = formatter
        proxyBox.addSubview(proxyPortField)
        proxyPortField.target = self
        proxyPortField.action = #selector(proxyPortFieldChanged(_:))
        proxyPortStepper = NSStepper(frame: NSRect(x: 474, y: proxyContentH - padding - 50, width: 19, height: 27))
        proxyPortStepper.minValue = 1
        proxyPortStepper.maxValue = 65535
        proxyPortStepper.increment = 1
        proxyPortStepper.valueWraps = false
        proxyPortStepper.integerValue = AppConfig.shared.proxyPort
        proxyPortStepper.target = self
        proxyPortStepper.action = #selector(proxyPortStepperChanged(_:))
        proxyBox.addSubview(proxyPortStepper)
        y -= cacheHeight + gap

        // Cache in middle
        let cacheBox = makeSection(root, title: t("Image Cache"), x: 14, y: y, width: contentWidth, height: cacheHeight)
        let cacheContentH = cacheHeight - 28
        let cacheLabel = makeLabel(cacheBox, text: t("Cached images (1–20):"), x: 14, y: cacheContentH - padding - 16)
        cacheField = NSTextField(frame: NSRect(x: cacheLabel.frame.maxX + 10, y: cacheContentH - padding - 20, width: 64, height: 24))
        cacheField.font = NSFont.systemFont(ofSize: 13)
        cacheField.alignment = .center
        cacheBox.addSubview(cacheField)
        cacheField.target = self
        cacheField.action = #selector(cacheFieldChanged(_:))
        cacheStepper = NSStepper(frame: NSRect(x: cacheField.frame.maxX + 4, y: cacheContentH - padding - 20, width: 19, height: 27))
        cacheStepper.minValue = Double(AppConfig.cacheCountRange.lowerBound)
        cacheStepper.maxValue = Double(AppConfig.cacheCountRange.upperBound)
        cacheStepper.increment = 1
        cacheStepper.valueWraps = false
        cacheStepper.integerValue = AppConfig.shared.imageCacheCount
        cacheStepper.target = self
        cacheStepper.action = #selector(cacheStepperChanged(_:))
        cacheBox.addSubview(cacheStepper)
        y -= logHeight + gap

        // Logging at bottom (above restore button)
        let logBox = makeSection(root, title: t("Logging"), x: 14, y: y, width: contentWidth, height: logHeight)
        let logContentH = logHeight - 28
        logEnabledCheckbox = makeCheck(logBox, title: t("Enable logging (default: off)"), x: 14, y: logContentH - padding - 18)
        logEnabledCheckbox.state = AppConfig.shared.logEnabled ? .on : .off
        logEnabledCheckbox.target = self
        logEnabledCheckbox.action = #selector(toggleLogEnabled(_:))

        let pathLabel = makeLabel(logBox, text: t("Log file:"), x: 14, y: logContentH - padding - 48)
        let browseWidth: CGFloat = 70
        let fieldX = pathLabel.frame.maxX + 10
        let fieldW = contentWidth - fieldX - browseWidth - 8 - 14
        logPathField = NSTextField(frame: NSRect(x: fieldX, y: logContentH - padding - 48, width: fieldW, height: 24))
        logPathField.font = NSFont.systemFont(ofSize: 12)
        logPathField.placeholderString = AppConfig.Defaults.logPath()
        logPathField.target = self
        logPathField.action = #selector(logPathFieldChanged(_:))
        logBox.addSubview(logPathField)

        let browseButton = NSButton(frame: NSRect(x: fieldX + fieldW + 8, y: logContentH - padding - 49, width: browseWidth, height: 26))
        browseButton.title = t("Browse...")
        browseButton.bezelStyle = .rounded
        browseButton.target = self
        browseButton.action = #selector(browseLogPath(_:))
        logBox.addSubview(browseButton)
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

            let cropMode = AppConfig.shared.cropMode
            let cropModeIdx = (cropMode == "select") ? 1 : 0
            if self.cropModePopup.indexOfSelectedItem != cropModeIdx { self.cropModePopup.selectItem(at: cropModeIdx) }

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

            let vibrance = AppConfig.shared.enhanceVibrance
            if abs(self.enhanceVibranceField.doubleValue - vibrance) > 0.001 { self.enhanceVibranceField.stringValue = String(format: "%.2f", vibrance) }
            if abs(self.enhanceVibranceStepper.doubleValue - vibrance) > 0.001 { self.enhanceVibranceStepper.doubleValue = vibrance }
            let contrast = AppConfig.shared.enhanceContrast
            if abs(self.enhanceContrastField.doubleValue - contrast) > 0.001 { self.enhanceContrastField.stringValue = String(format: "%.2f", contrast) }
            if abs(self.enhanceContrastStepper.doubleValue - contrast) > 0.001 { self.enhanceContrastStepper.doubleValue = contrast }
            let sharpness = AppConfig.shared.enhanceSharpness
            if abs(self.enhanceSharpnessField.doubleValue - sharpness) > 0.001 { self.enhanceSharpnessField.stringValue = String(format: "%.2f", sharpness) }
            if abs(self.enhanceSharpnessStepper.doubleValue - sharpness) > 0.001 { self.enhanceSharpnessStepper.doubleValue = sharpness }

            self.aiAutoUpscaleCheckbox?.state = AppConfig.shared.aiAutoUpscaleEnabled ? .on : .off

            // Super resolution settings
            let smallThreshold = AppConfig.shared.smallImageMaxSide
            if let field = self.smallImageThresholdField, field.integerValue != smallThreshold {
                field.stringValue = String(smallThreshold)
            }
            if let stepper = self.smallImageThresholdStepper, stepper.integerValue != smallThreshold {
                stepper.integerValue = smallThreshold
            }

            self.aiAutoDewatermarkCheckbox?.state = AppConfig.shared.aiAutoDewatermarkEnabled ? .on : .off

            // Watermark removal settings
            let threshold = AppConfig.shared.watermarkMaskThreshold
            if let field = self.watermarkThresholdField, abs(field.doubleValue - threshold) > 0.001 {
                field.stringValue = String(format: "%.2f", threshold)
            }
            if let stepper = self.watermarkThresholdStepper, abs(stepper.doubleValue - threshold) > 0.001 {
                stepper.doubleValue = threshold
            }
            let minFraction = AppConfig.shared.watermarkMinMaskFraction
            if let field = self.watermarkMinFractionField, abs(field.doubleValue - minFraction) > 0.00001 {
                field.stringValue = String(format: "%.4f", minFraction)
            }
            if let stepper = self.watermarkMinFractionStepper, abs(stepper.doubleValue - minFraction) > 0.00001 {
                stepper.doubleValue = minFraction
            }

            // Watermark mode
            let watermarkModeIdx = AppConfig.shared.watermarkMode == "manual" ? 1 : 0
            if let popup = self.watermarkModePopup, popup.indexOfSelectedItem != watermarkModeIdx {
                popup.selectItem(at: watermarkModeIdx)
            }

            // Feather radius
            let feather = AppConfig.shared.watermarkFeatherRadius
            if let field = self.watermarkFeatherField, field.integerValue != feather {
                field.stringValue = String(feather)
            }
            if let stepper = self.watermarkFeatherStepper, stepper.integerValue != feather {
                stepper.integerValue = feather
            }

            let modeIdx: Int
            switch AppConfig.shared.aiEnhanceMode {
            case "dedupOnly": modeIdx = 1
            case "watermarkOnly": modeIdx = 2
            default: modeIdx = 0
            }
            if self.enhanceModePopup.indexOfSelectedItem != modeIdx { self.enhanceModePopup.selectItem(at: modeIdx) }
            self.dedupAskContinueCheckbox.state = AppConfig.shared.dedupAskContinue ? .on : .off
            let dedupThreshold = AppConfig.shared.dedupThreshold
            if let field = self.dedupThresholdField, abs(field.doubleValue - dedupThreshold) > 0.001 {
                field.stringValue = String(format: "%.2f", dedupThreshold)
            }
            if let stepper = self.dedupThresholdStepper, abs(stepper.doubleValue - dedupThreshold) > 0.001 {
                stepper.doubleValue = dedupThreshold
            }
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

    @objc private func cropModeChanged(_ sender: NSPopUpButton) {
        let mode = sender.indexOfSelectedItem == 1 ? "select" : "full"
        AppConfig.shared.cropMode = mode
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

    // MARK: - Watermark Removal Actions

    @objc private func watermarkThresholdStepperChanged(_ sender: NSStepper) {
        let value = sender.doubleValue
        watermarkThresholdField.stringValue = String(format: "%.2f", value)
        AppConfig.shared.watermarkMaskThreshold = value
    }

    @objc private func watermarkThresholdFieldChanged(_ sender: NSTextField) {
        guard let value = Double(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig()
            return
        }
        let clamped = min(max(value, 0.1), 0.9)
        sender.stringValue = String(format: "%.2f", clamped)
        watermarkThresholdStepper.doubleValue = clamped
        AppConfig.shared.watermarkMaskThreshold = clamped
    }

    @objc private func watermarkMinFractionStepperChanged(_ sender: NSStepper) {
        let value = sender.doubleValue
        watermarkMinFractionField.stringValue = String(format: "%.4f", value)
        AppConfig.shared.watermarkMinMaskFraction = value
    }

    @objc private func watermarkMinFractionFieldChanged(_ sender: NSTextField) {
        guard let value = Double(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig()
            return
        }
        let clamped = min(max(value, 0.0001), 0.1)
        sender.stringValue = String(format: "%.4f", clamped)
        watermarkMinFractionStepper.doubleValue = clamped
        AppConfig.shared.watermarkMinMaskFraction = clamped
    }

    @objc private func watermarkModeChanged(_ sender: NSPopUpButton) {
        let mode = sender.indexOfSelectedItem == 1 ? "manual" : "auto"
        AppConfig.shared.watermarkMode = mode
    }

    @objc private func watermarkFeatherStepperChanged(_ sender: NSStepper) {
        let value = sender.integerValue
        watermarkFeatherField.stringValue = String(value)
        AppConfig.shared.watermarkFeatherRadius = value
    }

    @objc private func watermarkFeatherFieldChanged(_ sender: NSTextField) {
        guard let value = Int(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig()
            return
        }
        let clamped = min(max(value, 0), 10)
        sender.stringValue = String(clamped)
        watermarkFeatherStepper.integerValue = clamped
        AppConfig.shared.watermarkFeatherRadius = clamped
    }

    @objc private func toggleAutoUpscale(_ sender: NSButton) {
        AppConfig.shared.aiAutoUpscaleEnabled = (sender.state == .on)
    }

    @objc private func smallImageThresholdStepperChanged(_ sender: NSStepper) {
        let value = sender.integerValue
        smallImageThresholdField.stringValue = String(value)
        AppConfig.shared.smallImageMaxSide = value
    }

    @objc private func smallImageThresholdFieldChanged(_ sender: NSTextField) {
        guard let value = Int(sender.stringValue.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "")) else {
            syncControlsFromConfig()
            return
        }
        let clamped = min(max(value, 64), 8192)
        sender.stringValue = String(clamped)
        smallImageThresholdStepper.integerValue = clamped
        AppConfig.shared.smallImageMaxSide = clamped
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

    @objc private func dedupThresholdStepperChanged(_ sender: NSStepper) {
        let value = sender.doubleValue
        dedupThresholdField.stringValue = String(format: "%.2f", value)
        AppConfig.shared.dedupThreshold = value
    }

    @objc private func dedupThresholdFieldChanged(_ sender: NSTextField) {
        guard let value = Double(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig()
            return
        }
        let clamped = min(max(value, 0.70), 0.99)
        sender.stringValue = String(format: "%.2f", clamped)
        dedupThresholdStepper.doubleValue = clamped
        AppConfig.shared.dedupThreshold = clamped
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

    // MARK: - Restore Defaults

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
        AppConfig.shared.cropMode = AppConfig.Defaults.cropMode
    }

    @objc private func restoreEnhanceDefaults(_ sender: Any?) {
        AppConfig.shared.enhanceVibrance = AppConfig.Defaults.enhanceVibrance
        AppConfig.shared.enhanceContrast = AppConfig.Defaults.enhanceContrast
        AppConfig.shared.enhanceSharpness = AppConfig.Defaults.enhanceSharpness
    }

    @objc private func restoreUpscaleDefaults(_ sender: Any?) {
        AppConfig.shared.aiAutoUpscaleEnabled = AppConfig.Defaults.aiAutoUpscaleEnabled
        AppConfig.shared.smallImageMaxSide = AppConfig.Defaults.smallImageMaxSide
    }

    @objc private func restoreDewatermarkDefaults(_ sender: Any?) {
        AppConfig.shared.aiAutoDewatermarkEnabled = AppConfig.Defaults.aiAutoDewatermarkEnabled
        AppConfig.shared.watermarkMaskThreshold = AppConfig.Defaults.watermarkMaskThreshold
        AppConfig.shared.watermarkMinMaskFraction = AppConfig.Defaults.watermarkMinMaskFraction
        AppConfig.shared.watermarkMode = AppConfig.Defaults.watermarkMode
        AppConfig.shared.watermarkFeatherRadius = AppConfig.Defaults.watermarkFeatherRadius
    }

    @objc private func restoreDedupDefaults(_ sender: Any?) {
        AppConfig.shared.dedupAskContinue = AppConfig.Defaults.dedupAskContinue
        AppConfig.shared.dedupThreshold = AppConfig.Defaults.dedupThreshold
    }

    @objc private func restoreOneClickDefaults(_ sender: Any?) {
        AppConfig.shared.aiEnhanceMode = AppConfig.Defaults.aiEnhanceMode
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

    // MARK: - Model Management

    private func modelRow(forControl view: NSView) -> (plugin: ModelPlugin, nameLabel: NSTextField, statusLabel: NSTextField, downloadButton: NSButton, enabledCheck: NSButton, uninstallButton: NSButton)? {
        for row in modelRows where row.downloadButton === view || row.enabledCheck === view || row.uninstallButton === view {
            return row
        }
        return nil
    }

    @objc private func modelDownloadTapped(_ sender: NSButton) {
        guard let row = modelRow(forControl: sender) else { return }
        if case .downloading = PluginManager.shared.state(for: row.plugin) { return }

        // For Real-ESRGAN (no mirror), check if user is in China and suggest proxy
        if row.plugin.id == "realesrgan-x4" && ModelPlugin.isInChina && !AppConfig.shared.proxyEnabled {
            let t = L10n.shared.t
            let alert = NSAlert()
            alert.messageText = t("Proxy Recommended")
            alert.informativeText = t("Super-Resolution model is hosted on HuggingFace. Download may be slow or fail in mainland China. Enable proxy?")
            alert.addButton(withTitle: t("Enable Proxy"))
            alert.addButton(withTitle: t("Cancel"))
            alert.beginSheetModal(for: window!) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    // Switch to Advanced tab and focus on proxy settings
                    self?.switchToProxySettings()
                }
            }
            return
        }

        row.statusLabel.stringValue = L10n.shared.t("Downloading…")
        row.downloadButton.isEnabled = false
        PluginManager.shared.download(row.plugin, progress: { p in
            DispatchQueue.main.async {
                if let r = self.modelRows.first(where: { $0.plugin == row.plugin }) {
                    r.statusLabel.stringValue = L10n.shared.tf("%.0f%%", p * 100)
                }
            }
        }, completion: { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self.syncModelRows()
                case .failure(let error):
                    if let r = self.modelRows.first(where: { $0.plugin == row.plugin }) {
                        r.statusLabel.stringValue = L10n.shared.tf("Error: %@", error.localizedDescription)
                        r.downloadButton.isEnabled = true
                    }
                }
            }
        })
    }

    /// Switch to Advanced tab and scroll to proxy settings
    private func switchToProxySettings() {
        // Select the Advanced tab in main tab view (0=General, 1=AI, 2=Advanced)
        mainTabView?.selectTabViewItem(at: 2)
        // Enable proxy
        proxyEnabledCheckbox?.state = .on
        toggleProxyEnabled(proxyEnabledCheckbox!)
        // Focus on host field
        proxyHostField?.becomeFirstResponder()
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
        let nameText: String
        switch row.plugin {
        case .realesrgan:
            nameText = L10n.shared.t("Super Resolution (Real-ESRGAN 4x)")
        case .u2net:
            nameText = L10n.shared.t("Watermark Detection (U2Net)")
        case .lama:
            nameText = L10n.shared.t("Watermark Inpainting (LaMa)")
        default:
            nameText = row.plugin.displayName
        }
        let alert = NSAlert()
        alert.messageText = L10n.shared.tf("Uninstall %@?", nameText)
        alert.informativeText = L10n.shared.t("The downloaded model files will be deleted. You can download them again later.")
        alert.addButton(withTitle: L10n.shared.t("Uninstall"))
        alert.addButton(withTitle: L10n.shared.t("Cancel"))
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
                modelRows[i].statusLabel.stringValue = ""
                modelRows[i].downloadButton.title = L10n.shared.t("Download")
                modelRows[i].downloadButton.isEnabled = true
                modelRows[i].uninstallButton.isHidden = true
            case .downloading(let p):
                modelRows[i].statusLabel.stringValue = L10n.shared.tf("%.0f%%", p * 100)
                modelRows[i].downloadButton.title = L10n.shared.t("Downloading…")
                modelRows[i].downloadButton.isEnabled = false
                modelRows[i].uninstallButton.isHidden = true
            case .ready:
                modelRows[i].statusLabel.stringValue = ""
                modelRows[i].downloadButton.title = L10n.shared.t("Downloaded")
                modelRows[i].downloadButton.isEnabled = false
                modelRows[i].uninstallButton.isHidden = false
            case .error(let msg):
                modelRows[i].statusLabel.stringValue = L10n.shared.tf("Error: %@", msg)
                modelRows[i].downloadButton.title = L10n.shared.t("Download")
                modelRows[i].downloadButton.isEnabled = true
                modelRows[i].uninstallButton.isHidden = true
            }
            let wantState: Int = enabled ? 1 : 0
            if modelRows[i].enabledCheck.state.rawValue != wantState {
                modelRows[i].enabledCheck.state = (enabled ? .on : .off)
            }
        }
        updateOneClickStatus()
    }

    private func updateOneClickStatus() {
        let t = L10n.shared.t
        let watermarkReady = PluginManager.shared.isReady(.u2net)

        var statusText = ""
        if !watermarkReady {
            statusText = t("Missing model for") + ": " + t("Remove Watermark")
            oneClickStatusLabel?.textColor = NSColor.systemOrange
        } else {
            statusText = t("All models ready")
            oneClickStatusLabel?.textColor = NSColor.systemGreen
        }
        oneClickStatusLabel?.stringValue = statusText

        // Logic: if watermark model is ready, all options available; otherwise only "Dedup only"
        if let menu = enhanceModePopup?.menu {
            menu.item(at: 0)?.isEnabled = watermarkReady  // Both
            menu.item(at: 1)?.isEnabled = true            // Dedup only (always available)
            menu.item(at: 2)?.isEnabled = watermarkReady  // Dewatermark only
        }

        let currentMode = AppConfig.shared.aiEnhanceMode

        // If current mode is not available, switch to "dedup only" (always available)
        if (currentMode == "both" || currentMode == "watermarkOnly") && !watermarkReady {
            enhanceModePopup?.selectItem(at: 1)
            AppConfig.shared.aiEnhanceMode = "dedupOnly"
        }
    }
}

extension PreferencesWindow: NSTabViewDelegate {
    func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        window?.makeFirstResponder(nil)
    }
}
