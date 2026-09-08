import AppKit
import UniformTypeIdentifiers

/// A semi-transparent toolbar that auto-hides when not hovered.
class AutoHideToolbar: NSView {
    let leftButton: NSButton
    let rightButton: NSButton
    private var isHovered = false
    
    /// The color for the toolbar buttons (bright orange).
    static let buttonColor = NSColor(red: 1.0, green: 0.55, blue: 0.0, alpha: 1.0) // Bright orange
    
    /// The background color of the toolbar (semi-transparent dark).
    static let toolbarColor = NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.6)
    
    /// The height of the toolbar.
    static let toolbarHeight: CGFloat = 36
    
    init(onLeftTap: @escaping () -> Void, onRightTap: @escaping () -> Void) {
        leftButton = NSButton()
        rightButton = NSButton()
        super.init(frame: .zero)
        
        wantsLayer = true
        layer?.backgroundColor = AutoHideToolbar.toolbarColor.cgColor
        
        // Configure left button with SF Symbol
        configureButton(leftButton, symbolName: "chevron.left", action: onLeftTap)
        
        // Configure right button with SF Symbol
        configureButton(rightButton, symbolName: "chevron.right", action: onRightTap)
        
        addSubview(leftButton)
        addSubview(rightButton)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func configureButton(_ button: NSButton, symbolName: String, action: @escaping () -> Void) {
        button.bezelStyle = .rounded
        button.isBordered = false
        button.wantsLayer = true
        
        // Create an image view with SF Symbol
        let sfImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        sfImage?.size = NSSize(width: 20, height: 20)
        sfImage?.isTemplate = true
        
        // Set button image color to orange using a graphics context
        if let cgImage = sfImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let width = cgImage.width
            let height = cgImage.height
            
            // Create an orange-colored version of the image
            let coloredImage = NSImage(size: NSSize(width: width, height: height))
            coloredImage.lockFocus()
            AutoHideToolbar.buttonColor.set()
            let rect = NSRect(x: 0, y: 0, width: width, height: height)
            let context = NSGraphicsContext.current?.cgContext
            context?.draw(cgImage, in: rect)
            coloredImage.unlockFocus()
            
            button.image = coloredImage
        } else if let sfImage = sfImage {
            button.image = sfImage
        }
        
        // Set up the action
        button.target = self
        button.action = #selector(buttonTapped(_:))
        button.title = ""
    }
    
    override func mouseDown(with event: NSEvent) {
        // Prevent the window from closing when clicking toolbar
        super.mouseDown(with: event)
    }
    
    @objc private func buttonTapped(_ sender: NSButton) {
        if sender == leftButton {
            leftButton.performClick(nil)
        } else if sender == rightButton {
            rightButton.performClick(nil)
        }
    }
    
    override func updateTrackingAreas() {
        // Remove old tracking areas
        for area in self.trackingAreas {
            self.removeTrackingArea(area)
        }
        
        // Add a new tracking area that tracks mouse enter/exit
        let trackingArea = NSTrackingArea(
            rect: self.bounds,
            options: [.activeAlways, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        self.addTrackingArea(trackingArea)
    }
    
    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        self.alphaValue = 0.9
    }
    
    override func mouseExited(with event: NSEvent) {
        isHovered = false
        self.alphaValue = 0.3
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
