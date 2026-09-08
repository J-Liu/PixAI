import AppKit
import UniformTypeIdentifiers

/// A view that handles keyboard navigation for image browsing.
class KeyboardHandlerView: NSView {
    private let onPrevious: () -> Void
    private let onNext: () -> Void
    
    init(onPrevious: @escaping () -> Void, onNext: @escaping () -> Void) {
        self.onPrevious = onPrevious
        self.onNext = onNext
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
    
    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags
        let key = event.characters?.lowercased() ?? ""
        let keyCode = event.keyCode
        
        // Handle Cmd+W specifically: close THIS window only (the app keeps running).
        if mods.contains(.command) && (key == "w" || keyCode == 13) {
            self.window?.close()
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
        default:
            super.keyDown(with: event)
        }
    }
}
