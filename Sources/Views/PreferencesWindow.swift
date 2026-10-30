// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

final class PreferencesWindow: NSObject {
    static let shared = PreferencesWindow()

    private var window: NSWindow?
    private var tabView: NSTabView!
    private var aiTabView: NSTabView!

    private let labelWidth: CGFloat = 180
    private let controlWidth: CGFloat = 200
    private let rowSpacing: CGFloat = 12

    // Controls – General
    private var quitCheckbox: NSButton!
    private var deleteConfirmCheckbox: NSButton!
    private var languagePopup: NSPopUpButton!
    private var openDirModePopup: NSPopUpButton!
    private var openDirField: NSTextField!
    private var transitionField: NSTextField!
    private var transitionStepper: NSStepper!
    private var intervalField: NSTextField!
    private var intervalStepper: NSStepper!
    private var slideshowEndModePopup: NSPopUpButton!
    private var modelCheckPromptCheckbox: NSButton!
    private var cropLivePhotoConfirmCheckbox: NSButton!
    private var liveAutoPlayCheckbox: NSButton!
    private var liveMutedCheckbox: NSButton!
    private var cropModePopup: NSPopUpButton!
    private var toolbarHiddenAlphaField: NSTextField!
    private var toolbarHiddenAlphaStepper: NSStepper!
    private var updateFrequencyPopup: NSPopUpButton!
    private var checkUpdatesButton: NSButton!
    private var maxRecentFilesField: NSTextField!

    // Controls – AI Enhance
    private var enhanceVibranceField: NSTextField!
    private var enhanceVibranceStepper: NSStepper!
    private var enhanceContrastField: NSTextField!
    private var enhanceContrastStepper: NSStepper!
    private var enhanceSharpnessField: NSTextField!
    private var enhanceSharpnessStepper: NSStepper!

    // Controls – AI Upscale
    private var aiAutoUpscaleCheckbox: NSButton!
    private var smallImageThresholdField: NSTextField!
    private var smallImageThresholdStepper: NSStepper!

    // Controls – AI Dewatermark
    private var aiAutoDewatermarkCheckbox: NSButton!
    private var watermarkModePopup: NSPopUpButton!
    private var watermarkThresholdField: NSTextField!
    private var watermarkThresholdStepper: NSStepper!
    private var watermarkMinFractionField: NSTextField!
    private var watermarkMinFractionStepper: NSStepper!
    private var watermarkFeatherField: NSTextField!
    private var watermarkFeatherStepper: NSStepper!

    // Controls – AI One-click
    private var enhanceModePopup: NSPopUpButton!
    private var oneClickStatusLabel: NSTextField!

    // Controls – AI Dedup
    private var dedupAskContinueCheckbox: NSButton!
    private var dedupThresholdField: NSTextField!
    private var dedupThresholdStepper: NSStepper!

    // Controls – Advanced
    private var proxyEnabledCheckbox: NSButton!
    private var proxyTypePopup: NSPopUpButton!
    private var proxyHostField: NSTextField!
    private var proxyPortField: NSTextField!
    private var proxyPortStepper: NSStepper!
    private var cacheField: NSTextField!
    private var cacheStepper: NSStepper!
    private var logEnabledCheckbox: NSButton!
    private var logPathField: NSTextField!

    // Models
    private var modelRows: [(plugin: ModelPlugin, nameLabel: NSTextField, statusLabel: NSTextField, downloadButton: NSButton, enabledCheck: NSButton, uninstallButton: NSButton)] = []
    private var pluginObserver: NSObjectProtocol?
    private var changeObserver: NSObjectProtocol?
    private var l10nObserver: NSObjectProtocol?

    private override init() { super.init() }

    // MARK: - Public

    func show() {
        if window == nil { buildWindow() }
        syncControlsFromConfig()
        // If currently on About tab, switch to General
        if let selected = tabView.selectedTabViewItem,
           (selected.identifier as? String) == "about",
           tabView.numberOfTabViewItems > 0 {
            tabView.selectTabViewItem(at: 0)
        }
        presentWindow()
    }

    func showAboutTab() {
        if window == nil { buildWindow() }
        syncControlsFromConfig()
        selectTab("about")
        presentWindow()
    }

    func showAIModelsTab() {
        if window == nil { buildWindow() }
        syncControlsFromConfig()
        selectTab("ai")
        if let aiTab = aiTabView, aiTab.numberOfTabViewItems > 4 {
            aiTab.selectTabViewItem(at: 4)
        }
        presentWindow()
    }

    private func presentWindow() {
        guard let window = window else { return }
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func selectTab(_ identifier: String) {
        for item in tabView.tabViewItems {
            if (item.identifier as? String) == identifier {
                tabView.selectTabViewItem(item)
                return
            }
        }
    }

    // MARK: - Build Window

    private func buildWindow() {
        let width: CGFloat = 600
        let height: CGFloat = 640
        let screenFrame = NSScreen.main?.visibleFrame ?? .zero
        let frame = NSRect(
            x: screenFrame.midX - width / 2,
            y: screenFrame.midY - height / 2,
            width: width, height: height
        )

        let win = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = L10n.shared.t("Preferences")
        win.isReleasedWhenClosed = false
        win.minSize = NSSize(width: 600, height: 550)

        tabView = NSTabView()
        tabView.translatesAutoresizingMaskIntoConstraints = false
        win.contentView!.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: win.contentView!.topAnchor, constant: 10),
            tabView.bottomAnchor.constraint(equalTo: win.contentView!.bottomAnchor, constant: -10),
            tabView.leadingAnchor.constraint(equalTo: win.contentView!.leadingAnchor, constant: 10),
            tabView.trailingAnchor.constraint(equalTo: win.contentView!.trailingAnchor, constant: -10)
        ])

        rebuildTabs()

        changeObserver = NotificationCenter.default.addObserver(
            forName: AppConfig.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.syncControlsFromConfig() }

        l10nObserver = NotificationCenter.default.addObserver(
            forName: L10n.didChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let wasVisible = self.window?.isVisible ?? false
            self.window?.close()
            self.window = nil
            if wasVisible { self.show() }
        }

        pluginObserver = NotificationCenter.default.addObserver(
            forName: PluginManager.stateDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.syncModelRows() }

        tabView.delegate = self
        window = win
    }

    private func rebuildTabs() {
        while let tab = tabView.tabViewItems.first { tabView.removeTabViewItem(tab) }
        let t = L10n.shared.t

        let generalItem = NSTabViewItem(identifier: "general")
        generalItem.label = t("General")
        generalItem.view = buildGeneralTab()
        tabView.addTabViewItem(generalItem)

        let aiItem = NSTabViewItem(identifier: "ai")
        aiItem.label = t("AI")
        aiItem.view = buildAITab()
        tabView.addTabViewItem(aiItem)

        let advancedItem = NSTabViewItem(identifier: "advanced")
        advancedItem.label = t("Advanced")
        advancedItem.view = buildAdvancedTab()
        tabView.addTabViewItem(advancedItem)

        let aboutItem = NSTabViewItem(identifier: "about")
        aboutItem.label = t("About")
        aboutItem.view = buildAboutTab()
        tabView.addTabViewItem(aboutItem)
    }

    // MARK: - Layout Helpers

    private func makeRow(label: String, control: NSView) -> NSStackView {
        let labelField = NSTextField(labelWithString: label)
        labelField.alignment = .right
        labelField.translatesAutoresizingMaskIntoConstraints = false
        labelField.widthAnchor.constraint(equalToConstant: labelWidth).isActive = true
        control.translatesAutoresizingMaskIntoConstraints = false
        let row = NSStackView(views: [labelField, control])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        return row
    }

    private func makeVerticalStack() -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = rowSpacing
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        return stack
    }

    private func sectionHeader(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        return label
    }

    private func wrapInScroll(_ stack: NSStackView) -> NSView {
        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stack
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor)
        ])
        return scrollView
    }

    // MARK: - General Tab

    private func buildGeneralTab() -> NSView {
        let stack = makeVerticalStack()
        let t = L10n.shared.t

        quitCheckbox = NSButton(checkboxWithTitle: t("Quit app when the last window is closed"), target: self, action: #selector(toggleQuitOnLastClose(_:)))
        quitCheckbox.state = AppConfig.shared.quitOnLastWindowClosed ? .on : .off
        stack.addArrangedSubview(makeRow(label: "", control: quitCheckbox))

        deleteConfirmCheckbox = NSButton(checkboxWithTitle: t("Ask for confirmation before deleting a file"), target: self, action: #selector(toggleDeleteConfirm(_:)))
        deleteConfirmCheckbox.state = AppConfig.shared.deleteConfirmationEnabled ? .on : .off
        stack.addArrangedSubview(makeRow(label: "", control: deleteConfirmCheckbox))

        modelCheckPromptCheckbox = NSButton(checkboxWithTitle: t("Ask to download AI models at startup when missing"), target: self, action: #selector(toggleModelCheckPrompt(_:)))
        modelCheckPromptCheckbox.state = AppConfig.shared.modelCheckPromptEnabled ? .on : .off
        stack.addArrangedSubview(makeRow(label: "", control: modelCheckPromptCheckbox))

        cropLivePhotoConfirmCheckbox = NSButton(checkboxWithTitle: t("Confirm before cropping a Live Photo (result is a still image)"), target: self, action: #selector(toggleCropLivePhotoConfirm(_:)))
        cropLivePhotoConfirmCheckbox.state = AppConfig.shared.cropLivePhotoConfirm ? .on : .off
        stack.addArrangedSubview(makeRow(label: "", control: cropLivePhotoConfirmCheckbox))

        liveAutoPlayCheckbox = NSButton(checkboxWithTitle: t("Auto-play Live Photos when displayed"), target: self, action: #selector(toggleLiveAutoPlay(_:)))
        liveAutoPlayCheckbox.state = AppConfig.shared.livePhotoAutoPlay ? .on : .off
        stack.addArrangedSubview(makeRow(label: "", control: liveAutoPlayCheckbox))

        liveMutedCheckbox = NSButton(checkboxWithTitle: t("Mute Live Photo playback"), target: self, action: #selector(toggleLiveMuted(_:)))
        liveMutedCheckbox.state = AppConfig.shared.livePhotoMuted ? .on : .off
        stack.addArrangedSubview(makeRow(label: "", control: liveMutedCheckbox))

        let languagePopup = NSPopUpButton()
        for lang in ["English", "简体中文", "繁體中文"] { languagePopup.addItem(withTitle: lang) }
        let langIdx: Int
        switch AppConfig.shared.uiLanguage {
        case "zh": langIdx = 1
        case "zh-Hant": langIdx = 2
        default: langIdx = 0
        }
        languagePopup.selectItem(at: langIdx)
        languagePopup.target = self
        languagePopup.action = #selector(languageChanged(_:))
        self.languagePopup = languagePopup
        stack.addArrangedSubview(makeRow(label: t("Language"), control: languagePopup))

        let openDirModePopup = NSPopUpButton()
        openDirModePopup.addItem(withTitle: t("Last open"))
        openDirModePopup.addItem(withTitle: t("Choose..."))
        openDirModePopup.selectItem(at: AppConfig.shared.openPanelDirectoryMode == "custom" ? 1 : 0)
        openDirModePopup.target = self
        openDirModePopup.action = #selector(openDirModeChanged(_:))
        self.openDirModePopup = openDirModePopup

        let openDirField = NSTextField()
        openDirField.isEditable = false
        openDirField.isBezeled = true
        openDirField.bezelStyle = .roundedBezel
        openDirField.backgroundColor = .controlBackgroundColor
        openDirField.focusRingType = .none
        let currentDir = AppConfig.shared.getOpenPanelDirectory()
        openDirField.stringValue = currentDir?.lastPathComponent ?? ""
        openDirField.widthAnchor.constraint(equalToConstant: controlWidth).isActive = true
        self.openDirField = openDirField

        let dirRow = NSStackView(views: [openDirModePopup, openDirField])
        dirRow.orientation = .horizontal
        dirRow.spacing = 8
        dirRow.alignment = .centerY
        stack.addArrangedSubview(makeRow(label: t("Default directory"), control: dirRow))

        let transitionField = NSTextField()
        transitionField.alignment = .center
        transitionField.stringValue = String(format: "%.1f", AppConfig.shared.imageTransitionDuration)
        transitionField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        transitionField.target = self
        transitionField.action = #selector(transitionFieldChanged(_:))
        self.transitionField = transitionField
        let transitionStepper = NSStepper()
        transitionStepper.minValue = 0; transitionStepper.maxValue = 2; transitionStepper.increment = 0.1
        transitionStepper.valueWraps = false
        transitionStepper.doubleValue = AppConfig.shared.imageTransitionDuration
        transitionStepper.target = self
        transitionStepper.action = #selector(transitionStepperChanged(_:))
        self.transitionStepper = transitionStepper
        let transRow = NSStackView(views: [transitionField, transitionStepper])
        transRow.orientation = .horizontal; transRow.spacing = 4; transRow.alignment = .centerY
        stack.addArrangedSubview(makeRow(label: t("Image transition duration (0–2 s, 0 = off)"), control: transRow))

        let intervalField = NSTextField()
        intervalField.alignment = .center
        intervalField.stringValue = String(Int(AppConfig.shared.slideshowInterval))
        intervalField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        intervalField.target = self
        intervalField.action = #selector(intervalFieldChanged(_:))
        self.intervalField = intervalField
        let intervalStepper = NSStepper()
        intervalStepper.minValue = 1; intervalStepper.maxValue = 600; intervalStepper.increment = 1
        intervalStepper.valueWraps = false
        intervalStepper.integerValue = Int(AppConfig.shared.slideshowInterval)
        intervalStepper.target = self
        intervalStepper.action = #selector(intervalStepperChanged(_:))
        self.intervalStepper = intervalStepper
        let intRow = NSStackView(views: [intervalField, intervalStepper])
        intRow.orientation = .horizontal; intRow.spacing = 4; intRow.alignment = .centerY
        stack.addArrangedSubview(makeRow(label: t("Slideshow interval (1–600 s)"), control: intRow))

        let slideshowEndModePopup = NSPopUpButton()
        slideshowEndModePopup.addItem(withTitle: t("Stop at last image"))
        slideshowEndModePopup.addItem(withTitle: t("Return to first image"))
        slideshowEndModePopup.addItem(withTitle: t("Continuous loop"))
        switch AppConfig.shared.slideshowEndMode {
        case "first": slideshowEndModePopup.selectItem(at: 1)
        case "loop": slideshowEndModePopup.selectItem(at: 2)
        default: slideshowEndModePopup.selectItem(at: 0)
        }
        slideshowEndModePopup.target = self
        slideshowEndModePopup.action = #selector(slideshowEndModeChanged(_:))
        self.slideshowEndModePopup = slideshowEndModePopup
        stack.addArrangedSubview(makeRow(label: t("When slideshow ends"), control: slideshowEndModePopup))

        let cropModePopup = NSPopUpButton()
        cropModePopup.addItem(withTitle: t("Full image"))
        cropModePopup.addItem(withTitle: t("Drag to select"))
        cropModePopup.selectItem(at: AppConfig.shared.cropMode == "select" ? 1 : 0)
        cropModePopup.target = self
        cropModePopup.action = #selector(cropModeChanged(_:))
        self.cropModePopup = cropModePopup
        stack.addArrangedSubview(makeRow(label: t("Crop region selection"), control: cropModePopup))

        let toolbarAlphaField = NSTextField()
        toolbarAlphaField.alignment = .center
        toolbarAlphaField.stringValue = String(format: "%.1f", AppConfig.shared.toolbarHiddenAlpha)
        toolbarAlphaField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        toolbarAlphaField.target = self
        toolbarAlphaField.action = #selector(toolbarHiddenAlphaFieldChanged(_:))
        self.toolbarHiddenAlphaField = toolbarAlphaField
        let toolbarAlphaStepper = NSStepper()
        toolbarAlphaStepper.minValue = 0; toolbarAlphaStepper.maxValue = 1; toolbarAlphaStepper.increment = 0.1
        toolbarAlphaStepper.valueWraps = false
        toolbarAlphaStepper.doubleValue = AppConfig.shared.toolbarHiddenAlpha
        toolbarAlphaStepper.target = self
        toolbarAlphaStepper.action = #selector(toolbarHiddenAlphaStepperChanged(_:))
        self.toolbarHiddenAlphaStepper = toolbarAlphaStepper
        let alphaRow = NSStackView(views: [toolbarAlphaField, toolbarAlphaStepper])
        alphaRow.orientation = .horizontal; alphaRow.spacing = 4; alphaRow.alignment = .centerY
        stack.addArrangedSubview(makeRow(label: t("Toolbar hidden opacity (0–1)"), control: alphaRow))

        let updateFreqPopup = NSPopUpButton()
        for title in [t("On startup"), t("Daily"), t("Weekly"), t("Monthly"), t("Never")] {
            updateFreqPopup.addItem(withTitle: title)
        }
        let freqIdx: Int
        switch AppConfig.shared.updateCheckFrequency {
        case "daily": freqIdx = 1
        case "weekly": freqIdx = 2
        case "monthly": freqIdx = 3
        case "never": freqIdx = 4
        default: freqIdx = 0
        }
        updateFreqPopup.selectItem(at: freqIdx)
        updateFreqPopup.target = self
        updateFreqPopup.action = #selector(updateFrequencyChanged(_:))
        self.updateFrequencyPopup = updateFreqPopup

        let checkNowBtn = NSButton(title: t("Check Now"), target: self, action: #selector(checkForUpdatesNow(_:)))
        checkNowBtn.bezelStyle = .rounded
        self.checkUpdatesButton = checkNowBtn

        let updateRow = NSStackView(views: [updateFreqPopup, checkNowBtn])
        updateRow.orientation = .horizontal; updateRow.spacing = 12; updateRow.alignment = .centerY
        stack.addArrangedSubview(makeRow(label: t("Check for updates"), control: updateRow))

        let maxRecentField = NSTextField()
        maxRecentField.stringValue = String(AppConfig.shared.maxRecentFiles)
        maxRecentField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        maxRecentField.target = self
        maxRecentField.action = #selector(maxRecentFilesFieldChanged(_:))
        self.maxRecentFilesField = maxRecentField
        stack.addArrangedSubview(makeRow(label: t("Max recent files (0–50)"), control: maxRecentField))

        return wrapInScroll(stack)
    }

    // MARK: - AI Tab

    private func buildAITab() -> NSView {
        let container = NSView()
        let t = L10n.shared.t

        aiTabView = NSTabView()
        aiTabView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(aiTabView)
        NSLayoutConstraint.activate([
            aiTabView.topAnchor.constraint(equalTo: container.topAnchor, constant: 4),
            aiTabView.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -4),
            aiTabView.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 4),
            aiTabView.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4)
        ])

        let enhanceTab = NSTabViewItem(identifier: "enhance")
        enhanceTab.label = t("Quality Enhance")
        enhanceTab.view = buildEnhanceSubTab()
        aiTabView.addTabViewItem(enhanceTab)

        let upscaleTab = NSTabViewItem(identifier: "upscale")
        upscaleTab.label = t("Super Resolution")
        upscaleTab.view = buildUpscaleSubTab()
        aiTabView.addTabViewItem(upscaleTab)

        let dewatermarkTab = NSTabViewItem(identifier: "dewatermark")
        dewatermarkTab.label = t("Remove Watermark")
        dewatermarkTab.view = buildDewatermarkSubTab()
        aiTabView.addTabViewItem(dewatermarkTab)

        let dedupTab = NSTabViewItem(identifier: "dedup")
        dedupTab.label = t("AI Dedup")
        dedupTab.view = buildDedupSubTab()
        aiTabView.addTabViewItem(dedupTab)

        let oneClickTab = NSTabViewItem(identifier: "oneclick")
        oneClickTab.label = t("One-click Enhance")
        oneClickTab.view = buildOneClickSubTab()
        aiTabView.addTabViewItem(oneClickTab)

        let modelsTab = NSTabViewItem(identifier: "models")
        modelsTab.label = t("AI Models")
        modelsTab.view = buildModelsSubTab()
        aiTabView.addTabViewItem(modelsTab)

        aiTabView.delegate = self
        return container
    }

    private func buildEnhanceSubTab() -> NSView {
        let stack = makeVerticalStack()
        let t = L10n.shared.t

        addStepperRow(to: stack, label: t("Vibrance (0–1)"),
                      value: String(format: "%.2f", AppConfig.shared.enhanceVibrance),
                      min: 0, max: 1, increment: 0.05, format: "%.2f",
                      fieldAction: #selector(enhanceVibranceFieldChanged(_:)),
                      stepperAction: #selector(enhanceVibranceStepperChanged(_:)),
                      fieldOut: { self.enhanceVibranceField = $0 },
                      stepperOut: { self.enhanceVibranceStepper = $0 })

        addStepperRow(to: stack, label: t("Contrast (0.5–2.0, 1.0 = off)"),
                      value: String(format: "%.2f", AppConfig.shared.enhanceContrast),
                      min: 0.5, max: 2.0, increment: 0.05, format: "%.2f",
                      fieldAction: #selector(enhanceContrastFieldChanged(_:)),
                      stepperAction: #selector(enhanceContrastStepperChanged(_:)),
                      fieldOut: { self.enhanceContrastField = $0 },
                      stepperOut: { self.enhanceContrastStepper = $0 })

        addStepperRow(to: stack, label: t("Sharpness (0–1)"),
                      value: String(format: "%.2f", AppConfig.shared.enhanceSharpness),
                      min: 0, max: 1, increment: 0.05, format: "%.2f",
                      fieldAction: #selector(enhanceSharpnessFieldChanged(_:)),
                      stepperAction: #selector(enhanceSharpnessStepperChanged(_:)),
                      fieldOut: { self.enhanceSharpnessField = $0 },
                      stepperOut: { self.enhanceSharpnessStepper = $0 })

        let restoreBtn = NSButton(title: t("Restore This Page Defaults"), target: self, action: #selector(restoreEnhanceDefaults(_:)))
        restoreBtn.bezelStyle = .rounded
        stack.addArrangedSubview(makeRow(label: "", control: restoreBtn))

        return wrapInScroll(stack)
    }

    private func buildUpscaleSubTab() -> NSView {
        let stack = makeVerticalStack()
        let t = L10n.shared.t

        if PluginManager.shared.isReady(.realesrgan) {
            aiAutoUpscaleCheckbox = NSButton(checkboxWithTitle: t("Auto AI super-resolve small images on load"), target: self, action: #selector(toggleAutoUpscale(_:)))
            aiAutoUpscaleCheckbox.state = AppConfig.shared.aiAutoUpscaleEnabled ? .on : .off
            stack.addArrangedSubview(makeRow(label: "", control: aiAutoUpscaleCheckbox))

            addStepperRow(to: stack, label: t("Small image threshold (px, longest side)"),
                          value: String(AppConfig.shared.smallImageMaxSide),
                          min: 64, max: 8192, increment: 128, format: "%d",
                          fieldAction: #selector(smallImageThresholdFieldChanged(_:)),
                          stepperAction: #selector(smallImageThresholdStepperChanged(_:)),
                          fieldOut: { self.smallImageThresholdField = $0 },
                          stepperOut: { self.smallImageThresholdStepper = $0 })
        } else {
            let msg = NSTextField(labelWithString: t("Model not downloaded. Please download in AI Models tab."))
            msg.textColor = .secondaryLabelColor
            stack.addArrangedSubview(makeRow(label: "", control: msg))
        }

        let restoreBtn = NSButton(title: t("Restore This Page Defaults"), target: self, action: #selector(restoreUpscaleDefaults(_:)))
        restoreBtn.bezelStyle = .rounded
        stack.addArrangedSubview(makeRow(label: "", control: restoreBtn))

        return wrapInScroll(stack)
    }

    private func buildDewatermarkSubTab() -> NSView {
        let stack = makeVerticalStack()
        let t = L10n.shared.t

        let u2netReady = PluginManager.shared.isReady(.u2net)
        let lamaReady = PluginManager.shared.isReady(.lama)

        if u2netReady || lamaReady {
            let modePopup = NSPopUpButton()
            modePopup.addItem(withTitle: t("Auto (detect watermark automatically)"))
            modePopup.addItem(withTitle: t("Manual (select region manually)"))
            if AppConfig.shared.watermarkMode == "manual" { modePopup.selectItem(at: 1) }
            if !u2netReady {
                modePopup.item(at: 0)?.isEnabled = false
                modePopup.selectItem(at: 1)
            }
            modePopup.target = self
            modePopup.action = #selector(watermarkModeChanged(_:))
            self.watermarkModePopup = modePopup
            stack.addArrangedSubview(makeRow(label: t("Mode"), control: modePopup))

            aiAutoDewatermarkCheckbox = NSButton(checkboxWithTitle: t("Auto remove watermark on image load"), target: self, action: #selector(toggleAutoDewatermark(_:)))
            aiAutoDewatermarkCheckbox.state = AppConfig.shared.aiAutoDewatermarkEnabled ? .on : .off
            stack.addArrangedSubview(makeRow(label: "", control: aiAutoDewatermarkCheckbox))

            if u2netReady {
                addStepperRow(to: stack, label: t("Detection sensitivity (0.1–0.9)"),
                              value: String(format: "%.2f", AppConfig.shared.watermarkMaskThreshold),
                              min: 0.1, max: 0.9, increment: 0.05, format: "%.2f",
                              fieldAction: #selector(watermarkThresholdFieldChanged(_:)),
                              stepperAction: #selector(watermarkThresholdStepperChanged(_:)),
                              fieldOut: { self.watermarkThresholdField = $0 },
                              stepperOut: { self.watermarkThresholdStepper = $0 })

                addStepperRow(to: stack, label: t("Min. watermark size (0.0001–0.1)"),
                              value: String(format: "%.4f", AppConfig.shared.watermarkMinMaskFraction),
                              min: 0.0001, max: 0.1, increment: 0.0001, format: "%.4f",
                              fieldAction: #selector(watermarkMinFractionFieldChanged(_:)),
                              stepperAction: #selector(watermarkMinFractionStepperChanged(_:)),
                              fieldOut: { self.watermarkMinFractionField = $0 },
                              stepperOut: { self.watermarkMinFractionStepper = $0 })
            }

            addStepperRow(to: stack, label: t("Mask edge feather (0–10 px)"),
                          value: String(AppConfig.shared.watermarkFeatherRadius),
                          min: 0, max: 10, increment: 1, format: "%d",
                          fieldAction: #selector(watermarkFeatherFieldChanged(_:)),
                          stepperAction: #selector(watermarkFeatherStepperChanged(_:)),
                          fieldOut: { self.watermarkFeatherField = $0 },
                          stepperOut: { self.watermarkFeatherStepper = $0 })
        } else {
            let msg = lamaReady
                ? t("U2Net model required. Please download in AI Models tab.")
                : t("Models not downloaded. Please download in AI Models tab.")
            let label = NSTextField(labelWithString: msg)
            label.textColor = .secondaryLabelColor
            stack.addArrangedSubview(makeRow(label: "", control: label))
        }

        let restoreBtn = NSButton(title: t("Restore This Page Defaults"), target: self, action: #selector(restoreDewatermarkDefaults(_:)))
        restoreBtn.bezelStyle = .rounded
        stack.addArrangedSubview(makeRow(label: "", control: restoreBtn))

        return wrapInScroll(stack)
    }

    private func buildDedupSubTab() -> NSView {
        let stack = makeVerticalStack()
        let t = L10n.shared.t

        addStepperRow(to: stack, label: t("Similarity threshold (0.70–0.99, higher = stricter)"),
                      value: String(format: "%.2f", AppConfig.shared.dedupThreshold),
                      min: 0.70, max: 0.99, increment: 0.01, format: "%.2f",
                      fieldAction: #selector(dedupThresholdFieldChanged(_:)),
                      stepperAction: #selector(dedupThresholdStepperChanged(_:)),
                      fieldOut: { self.dedupThresholdField = $0 },
                      stepperOut: { self.dedupThresholdStepper = $0 })

        dedupAskContinueCheckbox = NSButton(checkboxWithTitle: t("Ask to continue between duplicate groups"), target: self, action: #selector(toggleDedupAskContinue(_:)))
        dedupAskContinueCheckbox.state = AppConfig.shared.dedupAskContinue ? .on : .off
        stack.addArrangedSubview(makeRow(label: "", control: dedupAskContinueCheckbox))

        let restoreBtn = NSButton(title: t("Restore This Page Defaults"), target: self, action: #selector(restoreDedupDefaults(_:)))
        restoreBtn.bezelStyle = .rounded
        stack.addArrangedSubview(makeRow(label: "", control: restoreBtn))

        return wrapInScroll(stack)
    }

    private func buildOneClickSubTab() -> NSView {
        let stack = makeVerticalStack()
        let t = L10n.shared.t

        let modePopup = NSPopUpButton()
        modePopup.addItem(withTitle: t("Both (dedup + dewatermark)"))
        modePopup.addItem(withTitle: t("Dedup only"))
        modePopup.addItem(withTitle: t("Dewatermark only"))
        switch AppConfig.shared.aiEnhanceMode {
        case "dedupOnly": modePopup.selectItem(at: 1)
        case "watermarkOnly": modePopup.selectItem(at: 2)
        default: modePopup.selectItem(at: 0)
        }
        modePopup.target = self
        modePopup.action = #selector(enhanceModeChanged(_:))
        self.enhanceModePopup = modePopup
        stack.addArrangedSubview(makeRow(label: t("One-click enhance"), control: modePopup))

        let statusLabel = NSTextField(labelWithString: "")
        statusLabel.textColor = .secondaryLabelColor
        self.oneClickStatusLabel = statusLabel
        stack.addArrangedSubview(makeRow(label: "", control: statusLabel))
        updateOneClickStatus()

        let restoreBtn = NSButton(title: t("Restore This Page Defaults"), target: self, action: #selector(restoreOneClickDefaults(_:)))
        restoreBtn.bezelStyle = .rounded
        stack.addArrangedSubview(makeRow(label: "", control: restoreBtn))

        return wrapInScroll(stack)
    }

    private func buildModelsSubTab() -> NSView {
        let stack = makeVerticalStack()
        let t = L10n.shared.t

        let header = NSTextField(labelWithString: t("Download third-party models for AI features:"))
        header.font = .systemFont(ofSize: 12)
        header.textColor = .secondaryLabelColor
        stack.addArrangedSubview(header)

        modelRows = []
        for plugin in ModelPlugin.all {
            let nameText: String
            switch plugin {
            case .realesrgan: nameText = "Real-ESRGAN 4x"
            case .u2net: nameText = "U2Net Saliency"
            case .lama: nameText = "LaMa"
            default: nameText = plugin.displayName
            }

            let nameLabel = NSTextField(labelWithString: nameText)
            nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
            nameLabel.toolTip = plugin.displayName

            let statusLabel = NSTextField(labelWithString: "")
            statusLabel.font = .systemFont(ofSize: 11)
            statusLabel.textColor = .secondaryLabelColor

            let downloadBtn = NSButton(title: t("Download"), target: self, action: #selector(modelDownloadTapped(_:)))
            downloadBtn.bezelStyle = .rounded

            let enabledCheck = NSButton(checkboxWithTitle: t("On"), target: self, action: #selector(modelEnableToggled(_:)))

            let uninstallBtn = NSButton(title: "", target: self, action: #selector(modelUninstallTapped(_:)))
            uninstallBtn.bezelStyle = .rounded
            uninstallBtn.image = NSImage(systemSymbolName: "trash", accessibilityDescription: t("Uninstall"))
            uninstallBtn.imagePosition = .imageOnly

            let controlRow = NSStackView(views: [statusLabel, downloadBtn, enabledCheck, uninstallBtn])
            controlRow.orientation = .horizontal
            controlRow.spacing = 8
            controlRow.alignment = .centerY

            let row = NSStackView(views: [nameLabel, controlRow])
            row.orientation = .horizontal
            row.spacing = 16
            row.alignment = .centerY
            stack.addArrangedSubview(row)

            modelRows.append((plugin: plugin, nameLabel: nameLabel, statusLabel: statusLabel,
                              downloadButton: downloadBtn, enabledCheck: enabledCheck, uninstallButton: uninstallBtn))
        }
        syncModelRows()

        return wrapInScroll(stack)
    }

    // MARK: - Advanced Tab

    private func buildAdvancedTab() -> NSView {
        let stack = makeVerticalStack()
        let t = L10n.shared.t

        stack.addArrangedSubview(sectionHeader(t("Proxy")))

        proxyEnabledCheckbox = NSButton(checkboxWithTitle: t("Enable proxy for model downloads"), target: self, action: #selector(toggleProxyEnabled(_:)))
        proxyEnabledCheckbox.state = AppConfig.shared.proxyEnabled ? .on : .off
        stack.addArrangedSubview(makeRow(label: "", control: proxyEnabledCheckbox))

        let proxyTypePopup = NSPopUpButton()
        proxyTypePopup.addItem(withTitle: "HTTP")
        proxyTypePopup.addItem(withTitle: "SOCKS")
        proxyTypePopup.selectItem(at: AppConfig.shared.proxyType == "socks" ? 1 : 0)
        proxyTypePopup.target = self
        proxyTypePopup.action = #selector(proxyTypeChanged(_:))
        self.proxyTypePopup = proxyTypePopup
        stack.addArrangedSubview(makeRow(label: t("Type"), control: proxyTypePopup))

        let proxyHostField = NSTextField()
        proxyHostField.placeholderString = "127.0.0.1"
        proxyHostField.stringValue = AppConfig.shared.proxyHost
        proxyHostField.widthAnchor.constraint(equalToConstant: controlWidth).isActive = true
        proxyHostField.target = self
        proxyHostField.action = #selector(proxyHostFieldChanged(_:))
        self.proxyHostField = proxyHostField
        stack.addArrangedSubview(makeRow(label: t("Host"), control: proxyHostField))

        let proxyPortField = NSTextField()
        proxyPortField.alignment = .center
        proxyPortField.stringValue = String(AppConfig.shared.proxyPort)
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        proxyPortField.formatter = formatter
        proxyPortField.widthAnchor.constraint(equalToConstant: 80).isActive = true
        proxyPortField.target = self
        proxyPortField.action = #selector(proxyPortFieldChanged(_:))
        self.proxyPortField = proxyPortField
        let proxyPortStepper = NSStepper()
        proxyPortStepper.minValue = 1; proxyPortStepper.maxValue = 65535; proxyPortStepper.increment = 1
        proxyPortStepper.valueWraps = false
        proxyPortStepper.integerValue = AppConfig.shared.proxyPort
        proxyPortStepper.target = self
        proxyPortStepper.action = #selector(proxyPortStepperChanged(_:))
        self.proxyPortStepper = proxyPortStepper
        let portRow = NSStackView(views: [proxyPortField, proxyPortStepper])
        portRow.orientation = .horizontal; portRow.spacing = 4; portRow.alignment = .centerY
        stack.addArrangedSubview(makeRow(label: t("Port"), control: portRow))

        stack.addArrangedSubview(sectionHeader(t("Image Cache")))

        let cacheField = NSTextField()
        cacheField.alignment = .center
        cacheField.stringValue = String(AppConfig.shared.imageCacheCount)
        cacheField.widthAnchor.constraint(equalToConstant: 60).isActive = true
        cacheField.target = self
        cacheField.action = #selector(cacheFieldChanged(_:))
        self.cacheField = cacheField
        let cacheStepper = NSStepper()
        cacheStepper.minValue = Double(AppConfig.cacheCountRange.lowerBound)
        cacheStepper.maxValue = Double(AppConfig.cacheCountRange.upperBound)
        cacheStepper.increment = 1; cacheStepper.valueWraps = false
        cacheStepper.integerValue = AppConfig.shared.imageCacheCount
        cacheStepper.target = self
        cacheStepper.action = #selector(cacheStepperChanged(_:))
        self.cacheStepper = cacheStepper
        let cacheRow = NSStackView(views: [cacheField, cacheStepper])
        cacheRow.orientation = .horizontal; cacheRow.spacing = 4; cacheRow.alignment = .centerY
        stack.addArrangedSubview(makeRow(label: t("Cached images (1–20)"), control: cacheRow))

        stack.addArrangedSubview(sectionHeader(t("Logging")))

        logEnabledCheckbox = NSButton(checkboxWithTitle: t("Enable logging (default: off)"), target: self, action: #selector(toggleLogEnabled(_:)))
        logEnabledCheckbox.state = AppConfig.shared.logEnabled ? .on : .off
        stack.addArrangedSubview(makeRow(label: "", control: logEnabledCheckbox))

        let logPathField = NSTextField()
        logPathField.stringValue = AppConfig.shared.logPath
        logPathField.placeholderString = AppConfig.Defaults.logPath()
        logPathField.widthAnchor.constraint(equalToConstant: 300).isActive = true
        logPathField.target = self
        logPathField.action = #selector(logPathFieldChanged(_:))
        self.logPathField = logPathField

        let browseBtn = NSButton(title: t("Browse..."), target: self, action: #selector(browseLogPath(_:)))
        browseBtn.bezelStyle = .rounded
        let logRow = NSStackView(views: [logPathField, browseBtn])
        logRow.orientation = .horizontal; logRow.spacing = 8; logRow.alignment = .centerY
        stack.addArrangedSubview(makeRow(label: t("Log file"), control: logRow))

        let restoreBtn = NSButton(title: t("Restore This Page Defaults"), target: self, action: #selector(restoreAdvancedDefaults(_:)))
        restoreBtn.bezelStyle = .rounded
        stack.addArrangedSubview(makeRow(label: "", control: restoreBtn))

        return wrapInScroll(stack)
    }

    // MARK: - About Tab

    private func buildAboutTab() -> NSView {
        let container = NSView()
        let t = L10n.shared.t

        let appIcon = NSImageView()
        if let icnsPath = Bundle.main.path(forResource: "PixAI", ofType: "icns"),
           let image = NSImage(contentsOfFile: icnsPath) {
            appIcon.image = image
        } else {
            appIcon.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
            appIcon.contentTintColor = .controlAccentColor
        }
        appIcon.translatesAutoresizingMaskIntoConstraints = false
        appIcon.widthAnchor.constraint(equalToConstant: 80).isActive = true
        appIcon.heightAnchor.constraint(equalToConstant: 80).isActive = true
        container.addSubview(appIcon)

        let nameLabel = NSTextField(labelWithString: "PixAI")
        nameLabel.font = .systemFont(ofSize: 22, weight: .semibold)
        nameLabel.alignment = .center
        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(nameLabel)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.alignment = .center
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(versionLabel)

        let copyrightLabel = NSTextField(labelWithString: "Copyright © 2026 Jia Liu")
        copyrightLabel.alignment = .center
        copyrightLabel.textColor = .secondaryLabelColor
        copyrightLabel.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(copyrightLabel)

        let githubButton = NSButton(title: "github.com/J-Liu/PixAI", target: self, action: #selector(openGitHub))
        githubButton.bezelStyle = .rounded
        githubButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(githubButton)

        let checkUpdatesButton = NSButton(title: t("Check for Updates..."), target: self, action: #selector(checkForUpdatesNow(_:)))
        checkUpdatesButton.bezelStyle = .rounded
        checkUpdatesButton.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(checkUpdatesButton)

        NSLayoutConstraint.activate([
            appIcon.topAnchor.constraint(equalTo: container.topAnchor, constant: 40),
            appIcon.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            nameLabel.topAnchor.constraint(equalTo: appIcon.bottomAnchor, constant: 16),
            nameLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            versionLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 8),
            versionLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            copyrightLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 8),
            copyrightLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            githubButton.topAnchor.constraint(equalTo: copyrightLabel.bottomAnchor, constant: 24),
            githubButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            checkUpdatesButton.topAnchor.constraint(equalTo: githubButton.bottomAnchor, constant: 12),
            checkUpdatesButton.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            checkUpdatesButton.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -20)
        ])

        return container
    }

    // MARK: - Stepper Row Helper

    private func addStepperRow(
        to stack: NSStackView, label: String, value: String,
        min: Double, max: Double, increment: Double, format: String,
        fieldAction: Selector, stepperAction: Selector,
        fieldOut: @escaping (NSTextField) -> Void,
        stepperOut: @escaping (NSStepper) -> Void
    ) {
        let field = NSTextField()
        field.alignment = .center
        field.stringValue = value
        field.widthAnchor.constraint(equalToConstant: 70).isActive = true
        field.target = self
        field.action = fieldAction
        fieldOut(field)

        let stepper = NSStepper()
        stepper.minValue = min; stepper.maxValue = max; stepper.increment = increment
        stepper.valueWraps = false
        stepper.doubleValue = Double(value) ?? min
        stepper.target = self
        stepper.action = stepperAction
        stepperOut(stepper)

        let row = NSStackView(views: [field, stepper])
        row.orientation = .horizontal; row.spacing = 4; row.alignment = .centerY
        stack.addArrangedSubview(makeRow(label: label, control: row))
    }

    // MARK: - Syncing

    private func syncControlsFromConfig() {
        guard window != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.quitCheckbox.state = AppConfig.shared.quitOnLastWindowClosed ? .on : .off
            self.deleteConfirmCheckbox.state = AppConfig.shared.deleteConfirmationEnabled ? .on : .off
            self.modelCheckPromptCheckbox.state = AppConfig.shared.modelCheckPromptEnabled ? .on : .off
            self.cropLivePhotoConfirmCheckbox.state = AppConfig.shared.cropLivePhotoConfirm ? .on : .off
            self.liveAutoPlayCheckbox.state = AppConfig.shared.livePhotoAutoPlay ? .on : .off
            self.liveMutedCheckbox.state = AppConfig.shared.livePhotoMuted ? .on : .off

            let langIdx: Int
            switch AppConfig.shared.uiLanguage {
            case "zh": langIdx = 1
            case "zh-Hant": langIdx = 2
            default: langIdx = 0
            }
            if self.languagePopup.indexOfSelectedItem != langIdx { self.languagePopup.selectItem(at: langIdx) }

            let openDirModeIdx = AppConfig.shared.openPanelDirectoryMode == "custom" ? 1 : 0
            if self.openDirModePopup.indexOfSelectedItem != openDirModeIdx { self.openDirModePopup.selectItem(at: openDirModeIdx) }
            let displayDir = AppConfig.shared.getOpenPanelDirectory()?.lastPathComponent ?? ""
            if self.openDirField.stringValue != displayDir { self.openDirField.stringValue = displayDir }

            let transitionStr = String(format: "%.1f", AppConfig.shared.imageTransitionDuration)
            if self.transitionField.stringValue != transitionStr { self.transitionField.stringValue = transitionStr }
            if abs(self.transitionStepper.doubleValue - AppConfig.shared.imageTransitionDuration) > 0.001 {
                self.transitionStepper.doubleValue = AppConfig.shared.imageTransitionDuration
            }

            let interval = Int(AppConfig.shared.slideshowInterval)
            if self.intervalField.integerValue != interval { self.intervalField.integerValue = interval }
            if self.intervalStepper.integerValue != interval { self.intervalStepper.integerValue = interval }

            let endIdx: Int
            switch AppConfig.shared.slideshowEndMode {
            case "first": endIdx = 1
            case "loop": endIdx = 2
            default: endIdx = 0
            }
            if self.slideshowEndModePopup.indexOfSelectedItem != endIdx { self.slideshowEndModePopup.selectItem(at: endIdx) }

            let cropIdx = AppConfig.shared.cropMode == "select" ? 1 : 0
            if self.cropModePopup.indexOfSelectedItem != cropIdx { self.cropModePopup.selectItem(at: cropIdx) }

            let alphaStr = String(format: "%.1f", AppConfig.shared.toolbarHiddenAlpha)
            if self.toolbarHiddenAlphaField.stringValue != alphaStr { self.toolbarHiddenAlphaField.stringValue = alphaStr }
            if abs(self.toolbarHiddenAlphaStepper.doubleValue - AppConfig.shared.toolbarHiddenAlpha) > 0.001 {
                self.toolbarHiddenAlphaStepper.doubleValue = AppConfig.shared.toolbarHiddenAlpha
            }

            let freqIdx: Int
            switch AppConfig.shared.updateCheckFrequency {
            case "daily": freqIdx = 1
            case "weekly": freqIdx = 2
            case "monthly": freqIdx = 3
            case "never": freqIdx = 4
            default: freqIdx = 0
            }
            if self.updateFrequencyPopup.indexOfSelectedItem != freqIdx { self.updateFrequencyPopup.selectItem(at: freqIdx) }

            let maxRecentStr = String(AppConfig.shared.maxRecentFiles)
            if self.maxRecentFilesField.stringValue != maxRecentStr { self.maxRecentFilesField.stringValue = maxRecentStr }

            let vibranceStr = String(format: "%.2f", AppConfig.shared.enhanceVibrance)
            if self.enhanceVibranceField.stringValue != vibranceStr { self.enhanceVibranceField.stringValue = vibranceStr }
            if abs(self.enhanceVibranceStepper.doubleValue - AppConfig.shared.enhanceVibrance) > 0.001 {
                self.enhanceVibranceStepper.doubleValue = AppConfig.shared.enhanceVibrance
            }
            let contrastStr = String(format: "%.2f", AppConfig.shared.enhanceContrast)
            if self.enhanceContrastField.stringValue != contrastStr { self.enhanceContrastField.stringValue = contrastStr }
            if abs(self.enhanceContrastStepper.doubleValue - AppConfig.shared.enhanceContrast) > 0.001 {
                self.enhanceContrastStepper.doubleValue = AppConfig.shared.enhanceContrast
            }
            let sharpnessStr = String(format: "%.2f", AppConfig.shared.enhanceSharpness)
            if self.enhanceSharpnessField.stringValue != sharpnessStr { self.enhanceSharpnessField.stringValue = sharpnessStr }
            if abs(self.enhanceSharpnessStepper.doubleValue - AppConfig.shared.enhanceSharpness) > 0.001 {
                self.enhanceSharpnessStepper.doubleValue = AppConfig.shared.enhanceSharpness
            }

            self.aiAutoUpscaleCheckbox?.state = AppConfig.shared.aiAutoUpscaleEnabled ? .on : .off
            let smallStr = String(AppConfig.shared.smallImageMaxSide)
            if let f = self.smallImageThresholdField, f.stringValue != smallStr { f.stringValue = smallStr }
            if let s = self.smallImageThresholdStepper, s.integerValue != AppConfig.shared.smallImageMaxSide {
                s.integerValue = AppConfig.shared.smallImageMaxSide
            }

            self.aiAutoDewatermarkCheckbox?.state = AppConfig.shared.aiAutoDewatermarkEnabled ? .on : .off
            let wmThreshStr = String(format: "%.2f", AppConfig.shared.watermarkMaskThreshold)
            if let f = self.watermarkThresholdField, f.stringValue != wmThreshStr { f.stringValue = wmThreshStr }
            if let s = self.watermarkThresholdStepper, abs(s.doubleValue - AppConfig.shared.watermarkMaskThreshold) > 0.001 {
                s.doubleValue = AppConfig.shared.watermarkMaskThreshold
            }
            let wmFracStr = String(format: "%.4f", AppConfig.shared.watermarkMinMaskFraction)
            if let f = self.watermarkMinFractionField, f.stringValue != wmFracStr { f.stringValue = wmFracStr }
            if let s = self.watermarkMinFractionStepper, abs(s.doubleValue - AppConfig.shared.watermarkMinMaskFraction) > 0.00001 {
                s.doubleValue = AppConfig.shared.watermarkMinMaskFraction
            }
            let wmModeIdx = AppConfig.shared.watermarkMode == "manual" ? 1 : 0
            if let p = self.watermarkModePopup, p.indexOfSelectedItem != wmModeIdx { p.selectItem(at: wmModeIdx) }
            let featherStr = String(AppConfig.shared.watermarkFeatherRadius)
            if let f = self.watermarkFeatherField, f.stringValue != featherStr { f.stringValue = featherStr }
            if let s = self.watermarkFeatherStepper, s.integerValue != AppConfig.shared.watermarkFeatherRadius {
                s.integerValue = AppConfig.shared.watermarkFeatherRadius
            }

            let modeIdx: Int
            switch AppConfig.shared.aiEnhanceMode {
            case "dedupOnly": modeIdx = 1
            case "watermarkOnly": modeIdx = 2
            default: modeIdx = 0
            }
            if self.enhanceModePopup.indexOfSelectedItem != modeIdx { self.enhanceModePopup.selectItem(at: modeIdx) }
            self.dedupAskContinueCheckbox.state = AppConfig.shared.dedupAskContinue ? .on : .off
            let dedupStr = String(format: "%.2f", AppConfig.shared.dedupThreshold)
            if let f = self.dedupThresholdField, f.stringValue != dedupStr { f.stringValue = dedupStr }
            if let s = self.dedupThresholdStepper, abs(s.doubleValue - AppConfig.shared.dedupThreshold) > 0.001 {
                s.doubleValue = AppConfig.shared.dedupThreshold
            }

            self.proxyEnabledCheckbox.state = AppConfig.shared.proxyEnabled ? .on : .off
            let typeIdx = AppConfig.shared.proxyType == "socks" ? 1 : 0
            if self.proxyTypePopup.indexOfSelectedItem != typeIdx { self.proxyTypePopup.selectItem(at: typeIdx) }
            if self.proxyHostField.stringValue != AppConfig.shared.proxyHost { self.proxyHostField.stringValue = AppConfig.shared.proxyHost }
            let portStr = String(AppConfig.shared.proxyPort)
            if self.proxyPortField.stringValue != portStr { self.proxyPortField.stringValue = portStr }
            if self.proxyPortStepper.integerValue != AppConfig.shared.proxyPort { self.proxyPortStepper.integerValue = AppConfig.shared.proxyPort }

            let cacheStr = String(AppConfig.shared.imageCacheCount)
            if self.cacheField.stringValue != cacheStr { self.cacheField.stringValue = cacheStr }
            if self.cacheStepper.integerValue != AppConfig.shared.imageCacheCount { self.cacheStepper.integerValue = AppConfig.shared.imageCacheCount }
            self.logEnabledCheckbox.state = AppConfig.shared.logEnabled ? .on : .off
            if self.logPathField.stringValue != AppConfig.shared.logPath { self.logPathField.stringValue = AppConfig.shared.logPath }

            self.syncModelRows()
        }
    }

    // MARK: - Actions – General

    @objc private func toggleQuitOnLastClose(_ sender: NSButton) {
        AppConfig.shared.quitOnLastWindowClosed = (sender.state == .on)
    }

    @objc private func toggleDeleteConfirm(_ sender: NSButton) {
        AppConfig.shared.deleteConfirmationEnabled = (sender.state == .on)
    }

    @objc private func toggleModelCheckPrompt(_ sender: NSButton) {
        AppConfig.shared.modelCheckPromptEnabled = (sender.state == .on)
    }

    @objc private func toggleCropLivePhotoConfirm(_ sender: NSButton) {
        AppConfig.shared.cropLivePhotoConfirm = (sender.state == .on)
    }

    @objc private func toggleLiveAutoPlay(_ sender: NSButton) {
        AppConfig.shared.livePhotoAutoPlay = (sender.state == .on)
    }

    @objc private func toggleLiveMuted(_ sender: NSButton) {
        AppConfig.shared.livePhotoMuted = (sender.state == .on)
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

    @objc private func openDirModeChanged(_ sender: NSPopUpButton) {
        if sender.indexOfSelectedItem == 1 {
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

    @objc private func transitionStepperChanged(_ sender: NSStepper) {
        let value = AppConfig.clampTransitionDuration(sender.doubleValue)
        if abs(transitionField.doubleValue - value) > 0.001 { transitionField.stringValue = String(format: "%.1f", value) }
        AppConfig.shared.imageTransitionDuration = value
    }

    @objc private func transitionFieldChanged(_ sender: NSTextField) {
        guard let value = Double(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig(); return
        }
        let clamped = AppConfig.clampTransitionDuration(value)
        sender.doubleValue = clamped
        transitionStepper.doubleValue = clamped
        AppConfig.shared.imageTransitionDuration = clamped
    }

    @objc private func intervalStepperChanged(_ sender: NSStepper) {
        intervalField.integerValue = sender.integerValue
        AppConfig.shared.slideshowInterval = Double(sender.integerValue)
    }

    @objc private func intervalFieldChanged(_ sender: NSTextField) {
        guard let value = Double(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig(); return
        }
        let clamped = Int(AppConfig.clampInterval(value))
        sender.integerValue = clamped
        intervalStepper.integerValue = clamped
        AppConfig.shared.slideshowInterval = Double(clamped)
    }

    @objc private func slideshowEndModeChanged(_ sender: NSPopUpButton) {
        let mode: String
        switch sender.indexOfSelectedItem {
        case 1: mode = "first"
        case 2: mode = "loop"
        default: mode = "stop"
        }
        AppConfig.shared.slideshowEndMode = mode
    }

    @objc private func cropModeChanged(_ sender: NSPopUpButton) {
        AppConfig.shared.cropMode = sender.indexOfSelectedItem == 1 ? "select" : "full"
    }

    @objc private func toolbarHiddenAlphaStepperChanged(_ sender: NSStepper) {
        toolbarHiddenAlphaField.stringValue = String(format: "%.1f", sender.doubleValue)
        AppConfig.shared.toolbarHiddenAlpha = sender.doubleValue
    }

    @objc private func toolbarHiddenAlphaFieldChanged(_ sender: NSTextField) {
        guard let value = Double(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig(); return
        }
        let clamped = min(max(value, 0), 1)
        sender.stringValue = String(format: "%.1f", clamped)
        toolbarHiddenAlphaStepper.doubleValue = clamped
        AppConfig.shared.toolbarHiddenAlpha = clamped
    }

    @objc private func updateFrequencyChanged(_ sender: NSPopUpButton) {
        let frequency: String
        switch sender.indexOfSelectedItem {
        case 1: frequency = "daily"
        case 2: frequency = "weekly"
        case 3: frequency = "monthly"
        case 4: frequency = "never"
        default: frequency = "startup"
        }
        AppConfig.shared.updateCheckFrequency = frequency
    }

    @objc private func checkForUpdatesNow(_ sender: Any?) {
        PixAIApp.checkForUpdatesFromPreferences()
    }

    @objc private func maxRecentFilesFieldChanged(_ sender: NSTextField) {
        guard let value = Int(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig(); return
        }
        let clamped = min(max(value, 0), 50)
        sender.integerValue = clamped
        AppConfig.shared.maxRecentFiles = clamped
    }

    // MARK: - Actions – AI Enhance

    @objc private func enhanceVibranceStepperChanged(_ sender: NSStepper) {
        enhanceVibranceField.stringValue = String(format: "%.2f", sender.doubleValue)
        AppConfig.shared.enhanceVibrance = sender.doubleValue
    }

    @objc private func enhanceVibranceFieldChanged(_ sender: NSTextField) {
        guard let value = Double(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig(); return
        }
        let clamped = min(max(value, 0), 1)
        sender.stringValue = String(format: "%.2f", clamped)
        enhanceVibranceStepper.doubleValue = clamped
        AppConfig.shared.enhanceVibrance = clamped
    }

    @objc private func enhanceContrastStepperChanged(_ sender: NSStepper) {
        enhanceContrastField.stringValue = String(format: "%.2f", sender.doubleValue)
        AppConfig.shared.enhanceContrast = sender.doubleValue
    }

    @objc private func enhanceContrastFieldChanged(_ sender: NSTextField) {
        guard let value = Double(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig(); return
        }
        let clamped = min(max(value, 0.5), 2.0)
        sender.stringValue = String(format: "%.2f", clamped)
        enhanceContrastStepper.doubleValue = clamped
        AppConfig.shared.enhanceContrast = clamped
    }

    @objc private func enhanceSharpnessStepperChanged(_ sender: NSStepper) {
        enhanceSharpnessField.stringValue = String(format: "%.2f", sender.doubleValue)
        AppConfig.shared.enhanceSharpness = sender.doubleValue
    }

    @objc private func enhanceSharpnessFieldChanged(_ sender: NSTextField) {
        guard let value = Double(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig(); return
        }
        let clamped = min(max(value, 0), 1)
        sender.stringValue = String(format: "%.2f", clamped)
        enhanceSharpnessStepper.doubleValue = clamped
        AppConfig.shared.enhanceSharpness = clamped
    }

    // MARK: - Actions – AI Upscale

    @objc private func toggleAutoUpscale(_ sender: NSButton) {
        AppConfig.shared.aiAutoUpscaleEnabled = (sender.state == .on)
    }

    @objc private func smallImageThresholdStepperChanged(_ sender: NSStepper) {
        smallImageThresholdField.stringValue = String(sender.integerValue)
        AppConfig.shared.smallImageMaxSide = sender.integerValue
    }

    @objc private func smallImageThresholdFieldChanged(_ sender: NSTextField) {
        guard let value = Int(sender.stringValue.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: ",", with: "")) else {
            syncControlsFromConfig(); return
        }
        let clamped = min(max(value, 64), 8192)
        sender.stringValue = String(clamped)
        smallImageThresholdStepper.integerValue = clamped
        AppConfig.shared.smallImageMaxSide = clamped
    }

    // MARK: - Actions – AI Dewatermark

    @objc private func toggleAutoDewatermark(_ sender: NSButton) {
        AppConfig.shared.aiAutoDewatermarkEnabled = (sender.state == .on)
    }

    @objc private func watermarkModeChanged(_ sender: NSPopUpButton) {
        AppConfig.shared.watermarkMode = sender.indexOfSelectedItem == 1 ? "manual" : "auto"
    }

    @objc private func watermarkThresholdStepperChanged(_ sender: NSStepper) {
        watermarkThresholdField.stringValue = String(format: "%.2f", sender.doubleValue)
        AppConfig.shared.watermarkMaskThreshold = sender.doubleValue
    }

    @objc private func watermarkThresholdFieldChanged(_ sender: NSTextField) {
        guard let value = Double(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig(); return
        }
        let clamped = min(max(value, 0.1), 0.9)
        sender.stringValue = String(format: "%.2f", clamped)
        watermarkThresholdStepper.doubleValue = clamped
        AppConfig.shared.watermarkMaskThreshold = clamped
    }

    @objc private func watermarkMinFractionStepperChanged(_ sender: NSStepper) {
        watermarkMinFractionField.stringValue = String(format: "%.4f", sender.doubleValue)
        AppConfig.shared.watermarkMinMaskFraction = sender.doubleValue
    }

    @objc private func watermarkMinFractionFieldChanged(_ sender: NSTextField) {
        guard let value = Double(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig(); return
        }
        let clamped = min(max(value, 0.0001), 0.1)
        sender.stringValue = String(format: "%.4f", clamped)
        watermarkMinFractionStepper.doubleValue = clamped
        AppConfig.shared.watermarkMinMaskFraction = clamped
    }

    @objc private func watermarkFeatherStepperChanged(_ sender: NSStepper) {
        watermarkFeatherField.stringValue = String(sender.integerValue)
        AppConfig.shared.watermarkFeatherRadius = sender.integerValue
    }

    @objc private func watermarkFeatherFieldChanged(_ sender: NSTextField) {
        guard let value = Int(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig(); return
        }
        let clamped = min(max(value, 0), 10)
        sender.stringValue = String(clamped)
        watermarkFeatherStepper.integerValue = clamped
        AppConfig.shared.watermarkFeatherRadius = clamped
    }

    // MARK: - Actions – AI Dedup

    @objc private func toggleDedupAskContinue(_ sender: NSButton) {
        AppConfig.shared.dedupAskContinue = (sender.state == .on)
    }

    @objc private func dedupThresholdStepperChanged(_ sender: NSStepper) {
        dedupThresholdField.stringValue = String(format: "%.2f", sender.doubleValue)
        AppConfig.shared.dedupThreshold = sender.doubleValue
    }

    @objc private func dedupThresholdFieldChanged(_ sender: NSTextField) {
        guard let value = Double(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig(); return
        }
        let clamped = min(max(value, 0.70), 0.99)
        sender.stringValue = String(format: "%.2f", clamped)
        dedupThresholdStepper.doubleValue = clamped
        AppConfig.shared.dedupThreshold = clamped
    }

    // MARK: - Actions – AI One-click

    @objc private func enhanceModeChanged(_ sender: NSPopUpButton) {
        switch sender.indexOfSelectedItem {
        case 1: AppConfig.shared.aiEnhanceMode = "dedupOnly"
        case 2: AppConfig.shared.aiEnhanceMode = "watermarkOnly"
        default: AppConfig.shared.aiEnhanceMode = "both"
        }
    }

    // MARK: - Actions – Advanced

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
            syncControlsFromConfig(); return
        }
        let clamped = min(max(value, 1), 65535)
        sender.integerValue = clamped
        proxyPortStepper.integerValue = clamped
        AppConfig.shared.proxyPort = clamped
    }

    @objc private func cacheStepperChanged(_ sender: NSStepper) {
        cacheField.integerValue = sender.integerValue
        AppConfig.shared.imageCacheCount = sender.integerValue
    }

    @objc private func cacheFieldChanged(_ sender: NSTextField) {
        guard let value = Int(sender.stringValue.replacingOccurrences(of: " ", with: "")) else {
            syncControlsFromConfig(); return
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
        var startDir = URL(fileURLWithPath: AppConfig.shared.logPath, isDirectory: false).deletingLastPathComponent()
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

    // MARK: - Actions – About

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/J-Liu/PixAI") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Restore Defaults

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

        if row.plugin.id == "realesrgan-x4" && ModelPlugin.isInChina && !AppConfig.shared.proxyEnabled {
            let t = L10n.shared.t
            let alert = NSAlert()
            alert.messageText = t("Proxy Recommended")
            alert.informativeText = t("Super-Resolution model is hosted on HuggingFace. Download may be slow or fail in mainland China. Enable proxy?")
            alert.addButton(withTitle: t("Enable Proxy"))
            alert.addButton(withTitle: t("Cancel"))
            alert.beginSheetModal(for: window!) { [weak self] response in
                if response == .alertFirstButtonReturn {
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

    private func switchToProxySettings() {
        selectTab("advanced")
        proxyEnabledCheckbox?.state = .on
        toggleProxyEnabled(proxyEnabledCheckbox!)
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
        case .realesrgan: nameText = L10n.shared.t("Super Resolution (Real-ESRGAN 4x)")
        case .u2net: nameText = L10n.shared.t("Watermark Detection (U2Net)")
        case .lama: nameText = L10n.shared.t("Watermark Inpainting (LaMa)")
        default: nameText = row.plugin.displayName
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
                modelRows[i].enabledCheck.isHidden = true
                modelRows[i].uninstallButton.isHidden = true
            case .downloading(let p):
                modelRows[i].statusLabel.stringValue = L10n.shared.tf("%.0f%%", p * 100)
                modelRows[i].downloadButton.title = L10n.shared.t("Downloading…")
                modelRows[i].downloadButton.isEnabled = false
                modelRows[i].enabledCheck.isHidden = true
                modelRows[i].uninstallButton.isHidden = true
            case .ready:
                modelRows[i].statusLabel.stringValue = ""
                modelRows[i].downloadButton.title = L10n.shared.t("Downloaded")
                modelRows[i].downloadButton.isEnabled = false
                modelRows[i].enabledCheck.isHidden = false
                modelRows[i].uninstallButton.isHidden = false
            case .error(let msg):
                modelRows[i].statusLabel.stringValue = L10n.shared.tf("Error: %@", msg)
                modelRows[i].downloadButton.title = L10n.shared.t("Download")
                modelRows[i].downloadButton.isEnabled = true
                modelRows[i].enabledCheck.isHidden = true
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

        if let menu = enhanceModePopup?.menu {
            menu.item(at: 0)?.isEnabled = watermarkReady
            menu.item(at: 1)?.isEnabled = true
            menu.item(at: 2)?.isEnabled = watermarkReady
        }

        let currentMode = AppConfig.shared.aiEnhanceMode
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
