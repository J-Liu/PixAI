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
    private var intervalField: NSTextField!
    private var intervalStepper: NSStepper!
    private var cacheField: NSTextField!
    private var cacheStepper: NSStepper!
    private var logEnabledCheckbox: NSButton!
    private var logPathField: NSTextField!

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
        let contentSize = NSSize(width: 520, height: 460)
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
            let interval = Int(AppConfig.shared.slideshowInterval)
            if self.intervalField.integerValue != interval { self.intervalField.integerValue = interval }
            if self.intervalStepper.integerValue != interval { self.intervalStepper.integerValue = interval }
            let cache = AppConfig.shared.imageCacheCount
            if self.cacheField.integerValue != cache { self.cacheField.integerValue = cache }
            if self.cacheStepper.integerValue != cache { self.cacheStepper.integerValue = cache }
            self.logEnabledCheckbox.state = AppConfig.shared.logEnabled ? .on : .off
            let path = AppConfig.shared.logPath
            if self.logPathField.stringValue != path { self.logPathField.stringValue = path }
        }
    }

    // MARK: - Actions (each writes to AppConfig → instant effect + persist)

    @objc private func toggleQuitOnLastClose(_ sender: NSButton) {
        AppConfig.shared.quitOnLastWindowClosed = (sender.state == .on)
    }

    @objc private func toggleDeleteConfirm(_ sender: NSButton) {
        AppConfig.shared.deleteConfirmationEnabled = (sender.state == .on)
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
