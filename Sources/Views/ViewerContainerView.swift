import AppKit
import UniformTypeIdentifiers

/// Content container for a viewer window (light gray background).
///
/// All children are positioned EXPLICITLY in `layoutChildren()`, which is called
/// from both `layout()` and `setFrameSize(_:)`. No autoresizing masks are used:
/// per Apple's documentation, autoresizing recomputes subview frames relative to
/// the superview's OLD size, so a container that starts at zero size produces
/// undefined (broken) layouts. Explicit re-layout on every resize is deterministic.
///
/// AppKit's default coordinate system is NON-flipped: origin at the bottom-left
/// corner, y increases upward (see NSView.isFlipped).
class ViewerContainerView: NSView {
    var imageView: ZoomableImageView?
    var statusBar: NSView?
    var statusLabel: NSTextField?
    var toolbar: AutoHideToolbar?
    var placeholder: PlaceholderView?
    var keyboardHandler: KeyboardHandlerView?
    /// Shown centered in the image area when the current file cannot be decoded.
    var unsupportedView: NSView?
    /// Interactive crop rectangle overlay (exactly over the image view).
    var cropOverlay: NSView?
    private let onDrop: ([URL]) -> Void
    
    /// Height of the bottom status bar.
    static let statusBarHeight: CGFloat = 28
    /// Width of the floating toolbar (14 buttons + 6 dividers, incl. the AI group).
    static let toolbarWidth: CGFloat = 920
    /// Distance of the toolbar above the status bar.
    static let toolbarBottomInset: CGFloat = 16
    
    init(onDrop: @escaping ([URL]) -> Void) {
        self.onDrop = onDrop
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.92, alpha: 1).cgColor
        registerForDraggedTypes(DragDropHelper.draggedTypes)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layout() {
        super.layout()
        layoutChildren()
    }
    
    /// Runs on every resize (including the initial sizing when this view becomes
    /// the window's content view).
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutChildren()
    }
    
    /// Position all children based on the current bounds.
    func layoutChildren() {
        let b = bounds.size
        guard b.width > 0, b.height > 0 else { return }
        let statusH = Self.statusBarHeight
        
        // Image area: everything above the status bar.
        if let imageView {
            imageView.frame = NSRect(x: 0, y: statusH, width: b.width, height: max(0, b.height - statusH))
        }
        
        // Status bar: full width along the bottom edge (y = 0 in non-flipped coords).
        if let statusBar {
            statusBar.frame = NSRect(x: 0, y: 0, width: b.width, height: statusH)
        }
        if let statusLabel {
            statusLabel.frame = NSRect(x: 12, y: (statusH - 16) / 2, width: max(0, b.width - 24), height: 16)
        }
        
        // Floating toolbar: horizontally centered, fixed distance above the status bar.
        if let toolbar {
            let w = Self.toolbarWidth
            let h = AutoHideToolbar.toolbarHeight
            toolbar.frame = NSRect(x: (b.width - w) / 2, y: statusH + Self.toolbarBottomInset, width: w, height: h)
        }
        
        // Placeholder: centered in the image area.
        if let placeholder {
            let size = PlaceholderView.preferredSize
            let areaHeight = max(0, b.height - statusH)
            placeholder.frame = NSRect(
                x: (b.width - size.width) / 2,
                y: statusH + (areaHeight - size.height) / 2,
                width: size.width,
                height: size.height
            )
        }
        // Unsupported-format placeholder: centered in the image area.
        if let unsupportedView {
            let size = unsupportedView.frame.size
            let areaHeight = max(0, b.height - statusH)
            unsupportedView.frame = NSRect(
                x: (b.width - size.width) / 2,
                y: statusH + (areaHeight - size.height) / 2,
                width: size.width,
                height: size.height
            )
        }
        
        // Crop overlay: exactly over the image view.
        if let cropOverlay, let imageView {
            cropOverlay.frame = imageView.frame
        }
        
        // Keyboard handler: covers the whole content area (mouse passes through).
        if let keyboardHandler {
            keyboardHandler.frame = bounds
        }
    }
    
    // MARK: - Drag and drop
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }
    
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = DragDropHelper.extractURLs(from: sender.draggingPasteboard)
        if !urls.isEmpty {
            Logger.shared.log("Container drop: \(urls.count) URLs")
            onDrop(urls)
            return true
        }
        return false
    }
}
