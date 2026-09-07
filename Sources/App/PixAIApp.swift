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

        // Create the main window with explicit size (1200x900 for comfortable viewing).
        let window = NSWindow(
            contentRect: CGRect(x: 0, y: 0, width: 1200, height: 900),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PixAI"
        window.center()
        Logger.shared.log("Window created: \(window.frame)")
        
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
        
        // Add the scroll view to the window.
        window.contentView = scrollView
        
        window.makeKeyAndOrderFront(nil)
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
        
        // Case 1: Single file → find all images in the same directory (non-recursive)
        if files.count == 1, directories.isEmpty {
            let file = files[0]
            let parentDir = file.deletingLastPathComponent()
            if FileManager.default.fileExists(atPath: parentDir.path) {
                imageUrls = scanDirectoryOnly(parentDir)
                Logger.shared.log("Single file opened: found \(imageUrls.count) images in parent directory")
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
                if !ext.isEmpty && supportedExtensions.contains(ext) {
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
