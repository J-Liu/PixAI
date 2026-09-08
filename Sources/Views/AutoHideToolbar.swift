import AppKit
import UniformTypeIdentifiers

/// A semi-transparent toolbar that auto-hides (dims) when not hovered.
class AutoHideToolbar: NSView {
    let leftButton: NSButton
    let rightButton: NSButton
    private var isHovered = false
    private let onLeftTap: () -> Void
    private let onRightTap: () -> Void
    
    /// The color for the toolbar buttons (bright orange).
    static let buttonColor = NSColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1.0) // Bright orange
    
    /// The background color of the toolbar (semi-transparent dark).
    static let toolbarColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.6)
    
    /// The height of the toolbar.
    static let toolbarHeight: CGFloat = 56
    
    init(onLeftTap: @escaping () -> Void, onRightTap: @escaping () -> Void) {
        self.onLeftTap = onLeftTap
        self.onRightTap = onRightTap
        leftButton = NSButton()
        rightButton = NSButton()
        super.init(frame: .zero)
        
        wantsLayer = true
        layer?.backgroundColor = AutoHideToolbar.toolbarColor.cgColor
        layer?.cornerRadius = 14
        
        // Configure buttons with orange SF Symbols.
        configureButton(leftButton, symbolName: "chevron.left")
        configureButton(rightButton, symbolName: "chevron.right")
        
        addSubview(leftButton)
        addSubview(rightButton)
        
        // Start in the visible (hovered) state.
        self.alphaValue = 0.9
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func configureButton(_ button: NSButton, symbolName: String) {
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imagePosition = .imageOnly
        button.title = ""
        
        // Orange-tinted template SF Symbol.
        let config = NSImage.SymbolConfiguration(pointSize: 24, weight: .semibold)
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            image.isTemplate = true
            button.image = image
        }
        button.contentTintColor = AutoHideToolbar.buttonColor
        
        // Set up the action.
        button.target = self
        button.action = #selector(buttonTapped(_:))
    }
    
    /// Position the two buttons side by side, centered in the toolbar.
    override func layout() {
        super.layout()
        
        let buttonSize: CGFloat = 42
        let gap: CGFloat = 12
        let totalWidth = buttonSize * 2 + gap
        let startX = (bounds.width - totalWidth) / 2
        let y = (bounds.height - buttonSize) / 2
        
        leftButton.frame = NSRect(x: startX, y: y, width: buttonSize, height: buttonSize)
        rightButton.frame = NSRect(x: startX + buttonSize + gap, y: y, width: buttonSize, height: buttonSize)
    }
    
    override func mouseDown(with event: NSEvent) {
        // Prevent the window from closing when clicking toolbar
        super.mouseDown(with: event)
    }
    
    @objc private func buttonTapped(_ sender: NSButton) {
        if sender == leftButton {
            onLeftTap()
        } else if sender == rightButton {
            onRightTap()
        }
    }
    
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshTrackingArea()
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshTrackingArea()
    }
    
    private func refreshTrackingArea() {
        for area in self.trackingAreas {
            self.removeTrackingArea(area)
        }
        
        // Track mouse enter/exit over the whole visible rect.
        let trackingArea = NSTrackingArea(
            rect: self.bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        self.addTrackingArea(trackingArea)
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.animator().alphaValue = 0.9
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            self.animator().alphaValue = 0.3
        }
    }
    
    /// Show the toolbar with animation.
    func show() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            self.animator().alphaValue = 0.9
        }
    }
    
    /// Hide the toolbar with animation.
    func hide() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            self.animator().alphaValue = 0.3
        }
    }
}
