// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Bottom status bar with left-to-right layout: filename | gap | file size | gap | resolution | gap | zoom controls | gap | index
class StatusBarView: NSView {
    let filenameLabel: NSTextField
    let fileSizeLabel: NSTextField
    let resolutionLabel: NSTextField
    let zoomOutButton: NSButton
    let zoomField: NSTextField
    let zoomInButton: NSButton
    let fitButton: NSButton
    let indexLabel: NSTextField
    let aiMarkLabel: NSTextField

    private let onZoomIn: () -> Void
    private let onZoomOut: () -> Void
    private let onFitToggle: () -> Void
    var onZoomValueChange: ((Int) -> Void)?

    // Character widths (monospaced font, ~7px per char)
    private static let charWidth: CGFloat = 7
    private static let filenameChars: CGFloat = 30
    private static let gapChars: CGFloat = 5
    private static let fileSizeChars: CGFloat = 10
    private static let resolutionChars: CGFloat = 18
    private static let zoomGroupChars: CGFloat = 17  // [-] [100%] [+] [fit]
    private static let indexChars: CGFloat = 10
    private static let aiMarkChars: CGFloat = 15

    init(onZoomIn: @escaping () -> Void,
         onZoomOut: @escaping () -> Void,
         onFitToggle: @escaping () -> Void) {
        self.onZoomIn = onZoomIn
        self.onZoomOut = onZoomOut
        self.onFitToggle = onFitToggle

        // Create all labels with monospaced font
        filenameLabel = Self.createLabel()
        fileSizeLabel = Self.createLabel()
        resolutionLabel = Self.createLabel()
        zoomField = Self.createEditableField(width: 50, alignment: .center)
        indexLabel = Self.createLabel()
        aiMarkLabel = Self.createLabel()

        zoomOutButton = NSButton()
        zoomInButton = NSButton()
        fitButton = NSButton()

        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.9).cgColor

        configureButton(zoomOutButton, symbolName: "minus")
        configureButton(zoomInButton, symbolName: "plus")
        configureButton(fitButton, symbolName: "arrow.down.left.and.arrow.up.right")

        // Set up zoom field delegate
        zoomField.delegate = self

        addSubview(filenameLabel)
        addSubview(fileSizeLabel)
        addSubview(resolutionLabel)
        addSubview(zoomOutButton)
        addSubview(zoomField)
        addSubview(zoomInButton)
        addSubview(fitButton)
        addSubview(indexLabel)
        addSubview(aiMarkLabel)
    }

    private static func createLabel(width: CGFloat? = nil, alignment: NSTextAlignment = .left) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = NSColor(white: 0.92, alpha: 1)
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingTail
        label.isEditable = false
        label.isBezeled = false
        label.isBordered = false
        return label
    }

    private static func createEditableField(width: CGFloat, alignment: NSTextAlignment = .center) -> NSTextField {
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: width, height: 20))
        field.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        field.textColor = NSColor(white: 0.92, alpha: 1)
        field.alignment = alignment
        field.isEditable = true
        field.isBezeled = false
        field.isBordered = false
        field.drawsBackground = false
        field.stringValue = "100%"
        return field
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureButton(_ button: NSButton, symbolName: String) {
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.title = ""

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            image.isTemplate = true
            button.image = image
        }
        button.contentTintColor = AutoHideToolbar.buttonColor

        button.target = self
        button.action = #selector(buttonTapped(_:))
    }

    @objc private func buttonTapped(_ sender: NSButton) {
        if sender == zoomInButton {
            onZoomIn()
        } else if sender == zoomOutButton {
            onZoomOut()
        } else if sender == fitButton {
            onFitToggle()
        }
    }

    override func layout() {
        super.layout()

        let buttonSize: CGFloat = 24
        let y = (bounds.height - 16) / 2
        let buttonY = (bounds.height - buttonSize) / 2
        let gap = Self.gapChars * Self.charWidth
        let startX: CGFloat = 12

        var x = startX

        // Filename (30 chars)
        let filenameWidth = Self.filenameChars * Self.charWidth
        filenameLabel.frame = NSRect(x: x, y: y, width: filenameWidth, height: 16)
        x += filenameWidth + gap

        // File size (10 chars)
        let fileSizeWidth = Self.fileSizeChars * Self.charWidth
        fileSizeLabel.frame = NSRect(x: x, y: y, width: fileSizeWidth, height: 16)
        x += fileSizeWidth + gap

        // Resolution (18 chars)
        let resolutionWidth = Self.resolutionChars * Self.charWidth
        resolutionLabel.frame = NSRect(x: x, y: y, width: resolutionWidth, height: 16)
        x += resolutionWidth + gap

        // Zoom controls: [-] [100%] [+] [fit]
        let zoomGap: CGFloat = 4
        zoomOutButton.frame = NSRect(x: x, y: buttonY, width: buttonSize, height: buttonSize)
        x += buttonSize + zoomGap
        zoomField.frame = NSRect(x: x, y: (bounds.height - 20) / 2, width: 50, height: 20)
        x += 50 + zoomGap
        zoomInButton.frame = NSRect(x: x, y: buttonY, width: buttonSize, height: buttonSize)
        x += buttonSize + zoomGap
        fitButton.frame = NSRect(x: x, y: buttonY, width: buttonSize, height: buttonSize)
        x += buttonSize + gap

        // AI mark (optional, 15 chars)
        if !aiMarkLabel.stringValue.isEmpty {
            let aiWidth = Self.aiMarkChars * Self.charWidth
            aiMarkLabel.frame = NSRect(x: x, y: y, width: aiWidth, height: 16)
            x += aiWidth + gap
        } else {
            aiMarkLabel.frame = .zero
        }

        // Index (10 chars)
        let indexWidth = Self.indexChars * Self.charWidth
        indexLabel.frame = NSRect(x: x, y: y, width: indexWidth, height: 16)
    }

    /// Update the fit button icon (fit vs 100%).
    func setFitButtonShowsFitIcon(_ showsFit: Bool) {
        let name = showsFit ? "arrow.down.left.and.arrow.up.right" : "1.square"
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            image.isTemplate = true
            fitButton.image = image
        }
    }

    /// Update the zoom percentage display.
    func setZoomPercentage(_ percent: Int) {
        zoomField.stringValue = "\(percent)%"
    }
}

// MARK: - NSTextFieldDelegate for zoom field

extension StatusBarView: NSTextFieldDelegate {
    func controlTextDidEndEditing(_ obj: Notification) {
        guard obj.object as? NSTextField == zoomField else { return }
        parseAndApplyZoom()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)) {
            // Enter key: apply zoom and end editing
            parseAndApplyZoom()
            window?.makeFirstResponder(nil)
            return true
        }
        return false
    }

    private func parseAndApplyZoom() {
        let text = zoomField.stringValue

        // Remove % if present and parse number
        let cleaned = text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
        guard let percent = Int(cleaned), percent > 0, percent <= 1000 else {
            // Invalid input, restore current value
            return
        }

        onZoomValueChange?(percent)
    }
}
