import AppKit
import UniformTypeIdentifiers
import ImageIO

/// A single image viewer window: light-gray image area with centered proportional
/// scaling, a bottom status bar (filename / size / zoom ratio / index-total),
/// a floating auto-hide toolbar, an empty-state placeholder, and keyboard navigation.
class ImageWindow {
    /// The underlying window.
    let window: NSWindow
    
    /// Called when this window is closed (used by the app delegate to drop its reference).
    var onClose: ((ImageWindow) -> Void)?
    
    private var container: ViewerContainerView?
    private var statusBarLabel: NSTextField?
    private var toolbar: AutoHideToolbar?
    /// Whether the fit/100% toggle button currently shows the "fit to window" icon
    /// (true) or the "100%" icon (false). Starts as true, so the first click fits.
    private var fitToggleShowsFitIcon = true
    
    /// List of loaded image URLs.
    private var imageURLs: [URL] = []
    /// Current image index.
    private var currentIndex: Int = 0
    /// Monotonic counter used to discard stale async image loads.
    private var loadGeneration: Int = 0
    /// The original (unrotated) image of the current file. Rotations are always
    /// computed from this, so repeated rotations never degrade quality.
    private var baseImage: NSImage?
    /// Cumulative 90° steps applied to the current image (+1 = clockwise, -1 =
    /// counterclockwise). Reset to 0 whenever a new image is loaded or a rotation
    /// is saved; discarded entirely when the window closes.
    private var rotationSteps: Int = 0
    
    private var closeObserver: NSObjectProtocol?
    
    init() {
        let windowRect = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "PixAI"
        self.window = window
        
        // Container (light gray background) that accepts dropped images/folders.
        let container = ViewerContainerView(onDrop: { [weak self] urls in
            Logger.shared.log("Container drop: \(urls.count) URLs")
            self?.loadImages(from: urls)
        })
        // Give the container its real size BEFORE it becomes the content view,
        // so every child frame computed below is already correct.
        container.frame = windowRect
        self.container = container
        
        // Image view: fills the area above the status bar. A custom NSView (NSImageView
        // has no zoom API) that draws the image itself, providing cursor-centered wheel
        // zoom (10% step, 10%~1000%), drag panning when zoomed in, and double-click
        // reset to "fit to window" mode.
        let imageView = ZoomableImageView()
        imageView.onZoomChange = { [weak self] in
            guard let self = self else { return }
            self.updateStatusBar()
            // Any manual zoom (wheel / drag / double-click) leaves fit mode: the next
            // toggle click should be "fit to window", so show the fit icon.
            if !(self.container?.imageView?.isInFitMode ?? false) {
                self.setFitToggleIcon(showsFit: true)
            }
        }
        container.imageView = imageView
        container.addSubview(imageView)
        
        // Bottom status bar: filename / size / zoom ratio / index-total.
        let statusBar = NSView()
        statusBar.wantsLayer = true
        statusBar.layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.9).cgColor
        
        let statusLabel = NSTextField(labelWithString: "Open or drag images here")
        statusLabel.font = NSFont.systemFont(ofSize: 12)
        statusLabel.textColor = NSColor(white: 0.92, alpha: 1)
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.attributedStringValue = Self.statusString("Open or drag images here")
        statusBar.addSubview(statusLabel)
        
        container.statusBar = statusBar
        container.statusLabel = statusLabel
        self.statusBarLabel = statusLabel
        container.addSubview(statusBar)
        
        // Floating auto-hide toolbar, bottom-center above the status bar.
        let toolbar = AutoHideToolbar(
            onLeftTap: { [weak self] in
                Logger.shared.log("Toolbar left button tapped")
                self?.goPrevious()
            },
            onRightTap: { [weak self] in
                Logger.shared.log("Toolbar right button tapped")
                self?.goNext()
            },
            onZoomInTap: { [weak self] in
                Logger.shared.log("Toolbar zoom-in button tapped")
                self?.container?.imageView?.zoomIn()
            },
            onZoomOutTap: { [weak self] in
                Logger.shared.log("Toolbar zoom-out button tapped")
                self?.container?.imageView?.zoomOut()
            },
            onFitToggleTap: { [weak self] in
                Logger.shared.log("Toolbar fit/100% toggle tapped")
                self?.toggleFitOr100Percent()
            },
            onRotateClockwiseTap: { [weak self] in
                Logger.shared.log("Toolbar rotate-clockwise button tapped")
                self?.rotateClockwise()
            },
            onRotateCounterclockwiseTap: { [weak self] in
                Logger.shared.log("Toolbar rotate-counterclockwise button tapped")
                self?.rotateCounterclockwise()
            },
            onSaveTap: { [weak self] in
                Logger.shared.log("Toolbar save button tapped")
                self?.saveCurrentRotation()
            }
        )
        container.toolbar = toolbar
        self.toolbar = toolbar
        container.addSubview(toolbar)
        
        // Empty-state placeholder (big icon + hint), centered in the image area.
        let placeholder = PlaceholderView(
            onOpen: { [weak self] in
                Logger.shared.log("Placeholder tapped, opening file panel")
                self?.presentOpenPanel()
            },
            onDrop: { [weak self] urls in
                Logger.shared.log("Placeholder drop: \(urls.count) URLs")
                self?.loadImages(from: urls)
            }
        )
        container.placeholder = placeholder
        container.addSubview(placeholder)
        
        // Keyboard handler on top (mouse events pass through to the views below).
        let keyboardHandler = KeyboardHandlerView(
            onPrevious: { [weak self] in
                Logger.shared.log("Keyboard handler: previous")
                self?.goPrevious()
            },
            onNext: { [weak self] in
                Logger.shared.log("Keyboard handler: next")
                self?.goNext()
            },
            onRotateClockwise: { [weak self] in
                Logger.shared.log("Keyboard handler: rotate clockwise (R)")
                self?.rotateClockwise()
            },
            onRotateCounterclockwise: { [weak self] in
                Logger.shared.log("Keyboard handler: rotate counterclockwise (Cmd+R)")
                self?.rotateCounterclockwise()
            },
            onSave: { [weak self] in
                Logger.shared.log("Keyboard handler: save rotation (Cmd+S)")
                self?.saveCurrentRotation()
            },
            onToggleFullscreen: { [weak self] in
                Logger.shared.log("Keyboard handler: toggle full screen (F)")
                self?.toggleFullScreen()
            },
            onExitFullscreen: { [weak self] in
                Logger.shared.log("Keyboard handler: exit full screen (Esc/Enter)")
                self?.exitFullScreen()
            }
        )
        container.keyboardHandler = keyboardHandler
        container.addSubview(keyboardHandler)
        
        // Set the container as content view (same size, so nothing jumps),
        // then lay out all children explicitly.
        window.contentView = container
        container.layoutChildren()
        window.makeFirstResponder(keyboardHandler)
        
        // Notify the app delegate when this window closes.
        self.closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            if let token = self.closeObserver {
                NotificationCenter.default.removeObserver(token)
                self.closeObserver = nil
            }
            self.onClose?(self)
        }
        
        // Refresh the status bar (zoom ratio) whenever the window resizes.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResize),
            name: NSWindow.didResizeNotification,
            object: window
        )
    }
    
    /// Center the window and show it.
    func show() {
        window.center()
        Logger.shared.log("Window shown: \(window.frame)")
        window.makeKeyAndOrderFront(nil)
    }
    
    /// Refresh the status bar when the window is resized (zoom ratio changes).
    @objc private func windowDidResize() {
        updateStatusBar()
    }
    
    /// Open a file selection panel and load the chosen items.
    func presentOpenPanel() {
        Logger.shared.log("openFile action triggered")
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.image, .folder]
        panel.begin { response in
            if response == .OK {
                Logger.shared.log("Open panel selected \(panel.urls.count) items")
                self.loadImages(from: panel.urls)
            } else {
                Logger.shared.log("Open panel cancelled")
            }
        }
    }
    
    /// Load images from URLs (files and/or directories).
    func loadImages(from urls: [URL]) {
        var imageUrls: [URL] = []
        
        // Separate files and directories from the input
        var files: [URL] = []
        var directories: [URL] = []
        
        for url in urls {
            do {
                let isDir = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
                if isDir == true {
                    directories.append(url)
                } else {
                    files.append(url)
                }
            } catch {
                // Treat as file if we can't determine
                files.append(url)
            }
        }
        
        Logger.shared.log("loadImages: \(files.count) files, \(directories.count) directories")
        
        // Case 1: Single file -> find all images in the same directory (non-recursive), dragged file first
        if files.count == 1, directories.isEmpty {
            let file = files[0]
            let parentDir = file.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parentDir.path) {
                // Scan the directory for all photo files (excluding the dragged file)
                let allImages = scanDirectoryOnly(parentDir)
                var otherImages: [URL] = []
                for img in allImages {
                    if img != file {
                        otherImages.append(img)
                    }
                }
                
                Logger.shared.log("Single file case: parentDir=\(parentDir), allImages.count=\(allImages.count), otherImages.count=\(otherImages.count)")
                
                // Put the dragged file first, then other images
                imageUrls = [file] + otherImages
                
                Logger.shared.log("Single file opened: dragged file first, then \(otherImages.count) other images")
            } else {
                // Parent doesn't exist, use the single file
                imageUrls = FileScanner.scan(urls: [file])
            }
        }
        // Case 2: Multiple files (no directories) -> use exactly those files
        else if files.count > 1, directories.isEmpty {
            imageUrls = FileScanner.scan(urls: files)
            Logger.shared.log("Multiple files opened: using exactly these \(files.count) files")
        }
        // Case 3: Directories (single or multiple) -> scan recursively
        else if !directories.isEmpty {
            let scanned = FileScanner.scan(urls: directories)
            imageUrls = scanned
            Logger.shared.log("Directory/ies opened: scanned \(scanned.count) files from \(directories.count) directory(ies)")
        }
        
        // Edge case: mix of files and directories (shouldn't happen in normal usage)
        if !files.isEmpty, !directories.isEmpty {
            let dirScans = FileScanner.scan(urls: directories)
            imageUrls = dirScans + FileScanner.scan(urls: files)
        }
        
        Logger.shared.log("loadImages: total \(imageUrls.count) files in array")
        
        imageURLs = imageUrls
        currentIndex = 0
        
        if !imageURLs.isEmpty {
            loadImage(at: 0)
        } else {
            window.title = "PixAI"
            container?.placeholder?.isHidden = false
            updateStatusBar()
        }
    }
    
    /// Scan only the immediate directory contents (no recursion).
    private func scanDirectoryOnly(_ directory: URL) -> [URL] {
        var results: [URL] = []
        do {
            let items = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            for item in items {
                let isDir = try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory
                if isDir == true {
                    // Skip subdirectories (no recursion)
                    continue
                }
                let ext = item.pathExtension.lowercased()
                if !ext.isEmpty && photoExtensions.contains(ext) {
                    results.append(item)
                } else if ext.isEmpty {
                    // No extension - try to detect
                    do {
                        _ = try Data(contentsOf: item)
                        if ImageLoaderRegistry.shared.loadImage(from: item) != nil {
                            results.append(item)
                        }
                    } catch {
                        // Not an image, skip
                    }
                }
            }
        } catch {
            Logger.shared.log("Failed to scan directory \(directory): \(error)")
        }
        return results.sorted { $0.absoluteString < $1.absoluteString }
    }
    
    /// Load and display the image at the given index.
    private func loadImage(at index: Int) {
        guard index >= 0, index < imageURLs.count else { return }
        currentIndex = index
        let url = imageURLs[index]
        
        Logger.shared.log("Loading image at index \(index): \(url)")
        
        // Bump the generation so stale loads from rapid navigation are discarded.
        let generation = loadGeneration + 1
        loadGeneration = generation
        
        // Delegate to the ImageLoaderRegistry for format-agnostic loading.
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let nsImage = ImageLoaderRegistry.shared.loadImage(from: url) {
                // Discard out-of-order loads so the newest press always wins.
                guard generation == self.loadGeneration else {
                    Logger.shared.log("Discarding stale image load for index \(index)")
                    return
                }
                
                // A newly loaded image is always shown unrotated: any unsaved
                // rotation of the previous image is discarded here (per spec).
                self.baseImage = nsImage
                self.rotationSteps = 0

                // The image view fills the window area; setting the image resets it to
                // "fit to window" mode (proportional fit, centered).
                self.container?.imageView?.image = nsImage
                
                // Window title shows the current file name.
                self.window.title = url.lastPathComponent
                
                // Hide the empty-state placeholder once an image is shown.
                self.container?.placeholder?.isHidden = true
                
                Logger.shared.log("Image loaded successfully: \(nsImage.size)")
                
                // Refresh status bar (filename / size / zoom / index).
                self.updateStatusBar()
            } else {
                Logger.shared.log("Failed to load image (unsupported format or decode error): \(url)")
            }
        }
    }
    
    /// Pixel dimensions of the current image, if determinable.
    private func currentPixelSize() -> NSSize? {
        guard let image = container?.imageView?.image else { return nil }
        // Prefer the actual pixel size of the first representation.
        if let rep = image.representations.first {
            if rep.pixelsWide > 0, rep.pixelsHigh > 0 {
                return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
            }
        }
        if image.size.width > 0, image.size.height > 0 {
            return image.size
        }
        return nil
    }
    
    /// The actual on-screen scale of the current image relative to its original size
    /// (1.0 == 100% == 1:1 pixels). Read live from the zoomable view so the status
    /// bar reflects wheel zoom / pan state in real time.
    private func currentZoomRatio() -> CGFloat {
        return container?.imageView?.zoomScale ?? 1
    }
    
    /// Build a tab-separated attributed string (fixed tab interval for aligned columns).
    private static func statusString(_ text: String) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.defaultTabInterval = 96
        return NSAttributedString(string: text, attributes: [.paragraphStyle: paragraph])
    }
    
    /// Update the bottom status bar: filename / size / zoom ratio / index-total.
    private func updateStatusBar() {
        guard let label = statusBarLabel else { return }
        
        if imageURLs.isEmpty || currentIndex < 0 || currentIndex >= imageURLs.count {
            label.attributedStringValue = Self.statusString("Open or drag images here")
            return
        }
        
        let url = imageURLs[currentIndex]
        var parts: [String] = [url.lastPathComponent]
        
        if let size = currentPixelSize() {
            parts.append("\(Int(size.width.rounded()))x\(Int(size.height.rounded())) px")
            parts.append(String(format: "%.0f%%", currentZoomRatio() * 100))
        }
        
        parts.append("\(currentIndex + 1) / \(imageURLs.count)")
        label.attributedStringValue = Self.statusString(parts.joined(separator: "\t"))
    }
    
    /// Fit/100% toggle button: first click fits to window (icon then shows 100%),
    /// next click switches to 100% (icon then shows fit). The icon always depicts
    /// what the NEXT click will do.
    private func toggleFitOr100Percent() {
        guard let imageView = container?.imageView, imageView.image != nil else { return }
        if fitToggleShowsFitIcon {
            imageView.resetToFit()
            setFitToggleIcon(showsFit: false)
        } else {
            imageView.zoomTo100Percent()
            setFitToggleIcon(showsFit: true)
        }
    }
    
    /// Update the toolbar's fit toggle icon and remember which mode it depicts.
    private func setFitToggleIcon(showsFit: Bool) {
        fitToggleShowsFitIcon = showsFit
        toolbar?.setFitToggleShowsFitIcon(showsFit)
    }

    // MARK: - Rotation & save

    /// Rotate the current image 90° clockwise (temporary; not written to disk).
    func rotateClockwise() {
        guard baseImage != nil else { return }
        rotationSteps += 1
        applyRotation()
    }

    /// Rotate the current image 90° counterclockwise (temporary; not written to disk).
    func rotateCounterclockwise() {
        guard baseImage != nil else { return }
        rotationSteps -= 1
        applyRotation()
    }

    /// Redraw the displayed image from the ORIGINAL image at the accumulated
    /// angle, so quality never degrades no matter how many times it is rotated.
    private func applyRotation() {
        guard let base = baseImage else { return }
        let displayed = base.rotatedClockwise(by: rotationSteps * 90) ?? base
        container?.imageView?.image = displayed
        updateStatusBar()
    }

    /// Save the rotated image over the original file (overwrite). If the
    /// accumulated rotation is a multiple of 360° (in either direction), the
    /// image is back to its original orientation: the save is ignored so the
    /// original file data is never re-encoded.
    func saveCurrentRotation() {
        guard !imageURLs.isEmpty, imageURLs.indices.contains(currentIndex), let base = baseImage else { return }
        let url = imageURLs[currentIndex]

        let netDegrees = rotationSteps * 90
        if netDegrees % 360 == 0 {
            Logger.shared.log("Save ignored: rotation (\(netDegrees)°) is a multiple of 360°")
            showStatusMessage("Rotation is a multiple of 360°, nothing to save")
            return
        }

        guard let rotated = base.rotatedClockwise(by: netDegrees),
              let cgImage = rotated.sourceCGImage else {
            Logger.shared.log("Save failed: could not produce rotated image for \(url)")
            showStatusMessage("Save failed")
            return
        }

        let ext = url.pathExtension.lowercased()
        guard let data = Self.encodeImage(cgImage, fileExtension: ext) else {
            Logger.shared.log("Save failed: unsupported format '\(ext)' for \(url)")
            showStatusMessage("Save failed: unsupported format")
            return
        }

        do {
            try data.write(to: url, options: .atomic)
            // The file now matches the displayed image: adopt it as the new base.
            baseImage = rotated
            rotationSteps = 0
            Logger.shared.log("Saved \(netDegrees)°-rotated image to \(url)")
            showStatusMessage("Saved")
        } catch {
            Logger.shared.log("Save failed for \(url): \(error)")
            showStatusMessage("Save failed: \(error.localizedDescription)")
        }
    }

    /// Encode a CGImage to file data in the format suggested by the extension.
    /// Lossy formats are written at 95% quality to preserve image fidelity.
    private static func encodeImage(_ cgImage: CGImage, fileExtension ext: String) -> Data? {
        let lossyQuality: CGFloat = 0.95

        switch ext {
        case "jpg", "jpeg", "png", "gif", "bmp", "tiff":
            let fileType: NSBitmapImageRep.FileType
            switch ext {
            case "jpg", "jpeg": fileType = .jpeg
            case "png": fileType = .png
            case "gif": fileType = .gif
            case "bmp": fileType = .bmp
            default: fileType = .tiff
            }
            let rep = NSBitmapImageRep(cgImage: cgImage)
            var properties: [NSBitmapImageRep.PropertyKey: Any] = [:]
            if fileType == .jpeg {
                properties[.compressionFactor] = lossyQuality
            }
            return rep.representation(using: fileType, properties: properties)
        default:
            // HEIC/HEIF/WebP/anything else: go through ImageIO with the UTI.
            let type = UTType(filenameExtension: ext) ?? .png
            let mutableData = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(mutableData, type.identifier as CFString, 1, nil) else {
                return nil
            }
            let properties = [kCGImageDestinationLossyCompressionQuality: lossyQuality]
            CGImageDestinationAddImage(dest, cgImage, properties as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { return nil }
            return mutableData as Data
        }
    }

    // MARK: - Full screen

    /// Enter or exit native full-screen mode (F key). Native full screen
    /// remembers the previous window frame and restores it on exit.
    func toggleFullScreen() {
        window.toggleFullScreen(nil)
    }

    /// Exit full screen and restore the previous window frame (Esc / Enter keys).
    func exitFullScreen() {
        guard window.styleMask.contains(.fullScreen) else { return }
        window.toggleFullScreen(nil)
    }
    
    /// Go to previous image with loop.
    /// One press at the first image shows the hint AND jumps to the last image immediately.
    private func goPrevious() {
        guard imageURLs.count > 1 else { return }
        
        if currentIndex == 0 {
            Logger.shared.log("At first image, showing wrap-around message")
            showStatusMessage("First image, wrapping to last")
        }
        
        currentIndex = (currentIndex - 1 + imageURLs.count) % imageURLs.count
        loadImage(at: currentIndex)
    }
    
    /// Go to next image with loop.
    /// One press at the last image shows the hint AND jumps to the first image immediately.
    private func goNext() {
        guard imageURLs.count > 1 else { return }
        
        if currentIndex == imageURLs.count - 1 {
            Logger.shared.log("At last image, showing wrap-around message")
            showStatusMessage("Last image, wrapping to first")
        }
        
        currentIndex = (currentIndex + 1) % imageURLs.count
        loadImage(at: currentIndex)
    }
    
    /// Show a status message at the bottom center of the window.
    private func showStatusMessage(_ message: String) {
        // Create a temporary label for the status message.
        let label = NSTextField(labelWithString: message)
        label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.isEditable = false
        label.isBezeled = false
        label.isBordered = false
        label.alignment = .center
        label.backgroundColor = NSColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.6)
        
        // Position it at the bottom center of the window (above the toolbar).
        let windowSize = window.contentView?.bounds.size ?? window.frame.size
        let labelWidth: CGFloat = 300
        let labelHeight: CGFloat = 24
        let labelX = (windowSize.width - labelWidth) / 2
        let labelY: CGFloat = ViewerContainerView.statusBarHeight + 60
        
        label.frame = NSRect(x: labelX, y: labelY, width: labelWidth, height: labelHeight)
        
        // Add the label to the window's content view.
        if let contentView = window.contentView {
            contentView.addSubview(label)
            
            // Animate in.
            label.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                label.animator().alphaValue = 1
            }
            
            // Remove after 2 seconds.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    label.animator().alphaValue = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    label.removeFromSuperview()
                }
            }
        }
    }
}
