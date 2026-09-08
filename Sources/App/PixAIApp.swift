import AppKit
import UniformTypeIdentifiers

/// The application delegate. Sets the icon, menu bar, and creates the main window.
class PixAIApp: NSObject, NSApplicationDelegate {
    /// Paths passed from command-line arguments (files or folders).
    private let paths: [String]
    /// Whether to launch in fullscreen mode.
    private let isFullscreen: Bool
    
    /// The main image view that displays the current image.
    private var imageView: NSImageView?
    
    /// List of loaded image URLs.
    private var imageURLs: [URL] = []
    /// Current image index.
    private var currentIndex: Int = 0
    
    /// The auto-hide toolbar.
    private var toolbar: AutoHideToolbar?
    
    override init() {
        self.paths = commandPaths
        self.isFullscreen = isFullscreenMode
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.shared.log("applicationDidFinishLaunching")
        
        // Build and set the menu bar.
        NSApplication.shared.mainMenu = MenuBuilder.build()
        
        // Set up the openFile callback.
        MenuBuilder.openFileCallback = { [weak self] in
            guard let self = self else { return }
            self.openFile(nil)
        }

        // Create the main window with a transparent container view as content view.
        let windowRect = CGRect(x: 0, y: 0, width: 1200, height: 900)
        let window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        // Create a container view that will hold both the scroll view and toolbar.
        let containerView = NSView(frame: windowRect)
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        
        // Create a scroll view to hold the image view (for zooming and scrolling).
        let scrollView = DraggableScrollView(onDrop: { [weak self] urls in
            Logger.shared.log("DraggableScrollView callback: \(urls.count) URLs received")
            self?.loadImages(from: urls)
        })
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        // Create the image view.
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        self.imageView = imageView
        
        // Set the image view as the scroll view's document view.
        scrollView.documentView = imageView
        
        // Set the scroll view's frame to fill the container view (minus toolbar space).
        scrollView.frame = NSRect(x: 0, y: AutoHideToolbar.toolbarHeight, width: windowRect.width, height: windowRect.height - AutoHideToolbar.toolbarHeight)
        scrollView.autoresizingMask = [.width, .height]
        
        // Add the scroll view to the container view.
        containerView.addSubview(scrollView)
        
        // Create the auto-hide toolbar and add it to the container view.
        let toolbar = AutoHideToolbar(
            onLeftTap: { [weak self] in
                Logger.shared.log("Toolbar left button tapped")
                self?.goPrevious()
            },
            onRightTap: { [weak self] in
                Logger.shared.log("Toolbar right button tapped")
                self?.goNext()
            }
        )
        self.toolbar = toolbar
        
        // Position the toolbar at the bottom center of the window.
        let toolbarWidth: CGFloat = 120
        let toolbarHeight: CGFloat = AutoHideToolbar.toolbarHeight
        let toolbarX = (windowRect.width - toolbarWidth) / 2
        let toolbarY: CGFloat = 20
        
        toolbar.frame = NSRect(x: toolbarX, y: toolbarY, width: toolbarWidth, height: toolbarHeight)
        containerView.addSubview(toolbar)
        
        // Create the keyboard handler view and add it to the container view.
        let keyboardHandler = KeyboardHandlerView(
            onPrevious: { [weak self] in
                Logger.shared.log("Keyboard handler: previous")
                self?.goPrevious()
            },
            onNext: { [weak self] in
                Logger.shared.log("Keyboard handler: next")
                self?.goNext()
            }
        )
        keyboardHandler.frame = windowRect
        keyboardHandler.autoresizingMask = [.width, .height]
        containerView.addSubview(keyboardHandler)
        
        // Set the container view as the window's content view.
        window.contentView = containerView
        
        // Make sure the keyboard handler can receive key events.
        window.makeFirstResponder(keyboardHandler)
        
        // Center the window and show it.
        window.center()
        Logger.shared.log("Window created: \(window.frame)")
        window.makeKeyAndOrderFront(nil as NSResponder?)
        Logger.shared.log("Window shown")

        // If fullscreen flag is set, enter fullscreen immediately.
        if isFullscreen {
            window.toggleFullScreen(nil)
        }
        
        // Load images from command-line paths.
        let urlPaths = paths.compactMap { URL(fileURLWithPath: $0) }
        if !urlPaths.isEmpty {
            loadImages(from: urlPaths)
        }
        
        Logger.shared.log("PixAIApp initialized, imageURLs count: \(imageURLs.count)")
    }
    
    /// Load images from URLs (files and/or directories).
    private func loadImages(from urls: [URL]) {
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
        
        // Case 1: Single file → find all images in the same directory (non-recursive), dragged file first
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
        // Case 2: Multiple files (no directories) → use exactly those files
        else if files.count > 1, directories.isEmpty {
            imageUrls = FileScanner.scan(urls: files)
            Logger.shared.log("Multiple files opened: using exactly these \(files.count) files")
        }
        // Case 3: Directories (single or multiple) → scan recursively
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
        
        // Delegate to the ImageLoaderRegistry for format-agnostic loading.
        Task { @MainActor in
            if let nsImage = ImageLoaderRegistry.shared.loadImage(from: url) {
                self.imageView?.image = nsImage
                
                // Set the image view's frame to match the image size.
                self.imageView?.frame = NSRect(x: 0, y: 0, width: nsImage.size.width, height: nsImage.size.height)
                
                Logger.shared.log("Image loaded successfully: \(nsImage.size)")
            } else {
                Logger.shared.log("Failed to load image (unsupported format or decode error): \(url)")
            }
        }
    }
    
    /// Go to previous image with loop.
    private func goPrevious() {
        guard imageURLs.count > 0 else { return }
        
        if currentIndex == 0 {
            // At the first image: show a message and jump to the last image
            Logger.shared.log("At first image, showing wrap-around message")
            showStatusMessage("First image, wrapping to last")
            currentIndex = imageURLs.count - 1
        } else {
            currentIndex -= 1
        }
        
        loadImage(at: currentIndex)
    }
    
    /// Go to next image with loop.
    private func goNext() {
        guard imageURLs.count > 0 else { return }
        
        if currentIndex == imageURLs.count - 1 {
            // At the last image: show a message and jump to the first image
            Logger.shared.log("At last image, showing wrap-around message")
            showStatusMessage("Last image, wrapping to first")
            currentIndex = 0
        } else {
            currentIndex += 1
        }
        
        loadImage(at: currentIndex)
    }
    
    /// Show a status message at the bottom center of the window.
    private func showStatusMessage(_ message: String) {
        guard let window = NSApplication.shared.mainWindow else { return }
        
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
        let windowSize = window.frame.size
        let labelWidth: CGFloat = 300
        let labelHeight: CGFloat = 24
        let labelX = (windowSize.width - labelWidth) / 2
        let labelY: CGFloat = 60
        
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
    
    /// Open a file selection panel.
    @objc func openFile(_ sender: Any?) {
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
}
