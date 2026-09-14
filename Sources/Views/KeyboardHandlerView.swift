// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import UniformTypeIdentifiers

/// A view that handles keyboard navigation for image browsing.
class KeyboardHandlerView: NSView {
    private let onPrevious: () -> Void
    private let onNext: () -> Void
    private let onRotateClockwise: () -> Void
    private let onRotateCounterclockwise: () -> Void
    private let onSave: () -> Void
    private let onSaveAs: () -> Void
    private let onToggleFullscreen: () -> Void
    private let onExitFullscreen: () -> Void
    private let onPlayPause: () -> Void
    private let onStartOrStopSlideshow: () -> Void
    private let onDelete: () -> Void
    /// Live query so Esc/Enter can exit the slideshow before falling back to
    /// exiting plain full screen.
    private let isSlideshowActive: () -> Bool
    /// Live query for whether the AI one-click batch (dedup / dewatermark)
    /// is running; Esc then cancels it and returns to browse mode.
    private let isBatchActive: () -> Bool
    /// Called on Esc while the AI batch runs: cancel and return to browse mode.
    private let onCancelBatch: () -> Void
    /// Live query for whether crop mode is active.
    private let isCropModeActive: () -> Bool
    /// Called on Esc while cropping: exit crop mode without saving.
    private let onCancelCrop: () -> Void
    /// Called when "?" is pressed: show the keyboard-shortcuts help window.
    private let onShowShortcuts: () -> Void
    init(onPrevious: @escaping () -> Void,
         onNext: @escaping () -> Void,
         onRotateClockwise: @escaping () -> Void,
         onRotateCounterclockwise: @escaping () -> Void,
         onSave: @escaping () -> Void,
         onSaveAs: @escaping () -> Void,
         onDelete: @escaping () -> Void,
         onToggleFullscreen: @escaping () -> Void,
         onExitFullscreen: @escaping () -> Void,
         onPlayPause: @escaping () -> Void,
         onStartOrStopSlideshow: @escaping () -> Void,
         isSlideshowActive: @escaping () -> Bool,
         isBatchActive: @escaping () -> Bool,
         onCancelBatch: @escaping () -> Void,
         isCropModeActive: @escaping () -> Bool,
         onCancelCrop: @escaping () -> Void,
         onShowShortcuts: @escaping () -> Void) {
        self.onPrevious = onPrevious
        self.onNext = onNext
        self.onRotateClockwise = onRotateClockwise
        self.onRotateCounterclockwise = onRotateCounterclockwise
        self.onSave = onSave
        self.onSaveAs = onSaveAs
        self.onDelete = onDelete
        self.onToggleFullscreen = onToggleFullscreen
        self.onExitFullscreen = onExitFullscreen
        self.onPlayPause = onPlayPause
        self.onStartOrStopSlideshow = onStartOrStopSlideshow
        self.isSlideshowActive = isSlideshowActive
        self.isBatchActive = isBatchActive
        self.onCancelBatch = onCancelBatch
        self.isCropModeActive = isCropModeActive
        self.onCancelCrop = onCancelCrop
        self.onShowShortcuts = onShowShortcuts
        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        focusRingType = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool {
        return true
    }

    /// Pass mouse events through to the views below (toolbar buttons, placeholder).
    /// Key events are still delivered because this view is the first responder.
    override func hitTest(_ point: NSPoint) -> NSView? {
        return nil
    }

    /// True while the window is in native full-screen mode.
    private var isWindowInFullScreen: Bool {
        return self.window?.styleMask.contains(.fullScreen) ?? false
    }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags
        let key = event.characters?.lowercased() ?? ""
        let keyCode = event.keyCode

        // Handle Cmd+W specifically: close THIS window only (the app keeps running).
        if mods.contains(.command) && (key == "w" || keyCode == 13) {
            self.window?.close()
            return
        }

        // Cmd+R: rotate the current image 90° counterclockwise (temporary, not saved).
        if mods.contains(.command), !mods.contains(.control), !mods.contains(.option),
           (key == "r" || keyCode == 15) {
            onRotateCounterclockwise()
            return
        }

        // Cmd+Shift+S: Save As (new file).
        if mods.contains(.command), mods.contains(.shift), !mods.contains(.control), !mods.contains(.option),
           (key == "s" || keyCode == 1) {
            onSaveAs()
            return
        }

        // Cmd+S: save the rotated image back to the file.
        if mods.contains(.command), !mods.contains(.shift), !mods.contains(.control), !mods.contains(.option),
           (key == "s" || keyCode == 1) {
            onSave()
            return
        }

        // Cmd+Delete: move the current image to the Trash (keyCode 51 = Delete,
        // 117 = Forward Delete; both carry the 0x7F character).
        if mods.contains(.command), !mods.contains(.control), !mods.contains(.option),
           (keyCode == 51 || keyCode == 117) {
            onDelete()
            return
        }

        // Don't intercept if Cmd/Control/Option is pressed
        if mods.contains([.command, .control, .option]) {
            super.keyDown(with: event)
            return
        }

        switch (key, keyCode) {
        // Arrow keys (use key code to detect them reliably)
        case ("leftarrow", _), (_, 123):
            onPrevious()
            return
        case ("rightarrow", _), (_, 124):
            onNext()
            return
        case ("uparrow", _), (_, 126):
            onPrevious()
            return
        case ("downarrow", _), (_, 125):
            onNext()
            return
        // Gaming style (WASD)
        case ("w", _):
            onPrevious()
            return
        case ("s", _):
            onNext()
            return
        case ("a", _):
            onPrevious()
            return
        case ("d", _):
            onNext()
            return
        // Vim style (HJKL)
        case ("h", _):
            onPrevious()
            return
        case ("j", _):
            onNext()
            return
        case ("k", _):
            onPrevious()
            return
        case ("l", _):
            onNext()
            return
        // R: rotate 90° clockwise (temporary, not saved)
        case ("r", _), (_, 15):
            onRotateClockwise()
            return
        // F: toggle full screen mode
        case ("f", _), (_, 3):
            onToggleFullscreen()
            return
        // Space: toggle play/pause of the slideshow (starts it when stopped).
        case (" ", _), (_, 49):
            onPlayPause()
            return
        // P: start the slideshow (auto full screen) or exit it to window mode.
        case ("p", _), (_, 35):
            onStartOrStopSlideshow()
            return
        // Esc / Enter: exit the slideshow if active, otherwise exit full screen
        // (only while in full screen).
        case ("\u{1b}", _), (_, 53), ("\r", _), (_, 36):
            if isCropModeActive() {
                onCancelCrop()
            } else if isBatchActive() {
                onCancelBatch()
            } else if isSlideshowActive() {
                onStartOrStopSlideshow()
            } else if isWindowInFullScreen {
                onExitFullscreen()
            } else {
                super.keyDown(with: event)
            }
            return
        // ?: show the keyboard-shortcuts help window.
        case ("?", _):
            onShowShortcuts()
            return
        default:
            super.keyDown(with: event)
        }
    }
}
