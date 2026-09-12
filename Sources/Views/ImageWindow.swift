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
    /// Files already shown the >50 MB warning for (once per file per window).
    private var largeFileWarned: Set<URL> = []
    /// True while the displayed image is a downscaled thumbnail of a huge file.
    private var currentImageIsScaled = false

    /// Per-image AI state (transform results + applied flags), keyed by URL.
    private var aiStates: [URL: ImageAIState] = [:]
    /// True while the AI one-click batch is running (UI locked).
    private var batchRunning = false
    /// Progress overlay shown during the AI one-click batch.
    private var batchOverlay: NSView?
    /// URLs with an in-flight async AI computation (toggle re-entry guard).
    private var aiBusy: Set<URL> = []
    /// URLs for which auto-AI has already been attempted this session.
    private var autoAIDone: Set<URL> = []
    /// Progress indicator + label inside the batch overlay.
    private var batchProgressIndicator: NSProgressIndicator?
    private var batchStatusLabel: NSTextField?

    private var pluginObserver: NSObjectProtocol?

    /// Drives slideshow playback (P / Space keys, toolbar play-pause button).
    /// The slide interval defaults to 3 s and will later be configurable via
    /// a config file / settings UI.
    private let slideshow = SlideshowController()

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
        // zoom (10% step, 10%~1000%), trackpad pinch zoom, drag panning when zoomed
        // in, and a double-click toggle between "fit to window" and 100%.
        let imageView = ZoomableImageView()
        imageView.onZoomChange = { [weak self] in
            guard let self = self else { return }
            self.updateStatusBar()
            // Keep the toolbar fit/100% icon in sync with the view's toggle state:
            // the icon always depicts what the next double-click / click will do.
            if let imageView = self.container?.imageView {
                self.setFitToggleIcon(showsFit: imageView.nextToggleIsFit)
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
                // Same alternating toggle as double-click; the view owns the state
                // and onZoomChange syncs the toolbar icon afterwards.
                self?.container?.imageView?.toggleFitOr100Percent()
            },
            onAIEnhanceQualityTap: { [weak self] in
                Logger.shared.log("Toolbar AI quality-enhance button tapped")
                self?.toggleAIEnhance()
            },
            onAIDewatermarkTap: { [weak self] in
                Logger.shared.log("Toolbar AI dewatermark button tapped")
                self?.toggleAIDewatermark()
            },
            onAIUpscaleTap: { [weak self] in
                Logger.shared.log("Toolbar AI upscale button tapped")
                self?.toggleAIUpscale()
            },
            onAIOneClickTap: { [weak self] in
                Logger.shared.log("Toolbar AI one-click enhance button tapped")
                self?.runAIOneClickEnhance()
            },
            onPlayPauseTap: { [weak self] in
                Logger.shared.log("Toolbar play/pause button tapped")
                self?.togglePlayPause()
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
            },
            onDeleteTap: { [weak self] in
                Logger.shared.log("Toolbar delete button tapped")
                self?.deleteCurrentImage()
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
            onSaveAs: { [weak self] in
                Logger.shared.log("Keyboard handler: save as (Cmd+Shift+S)")
                self?.saveAsImage()
            },
            onDelete: { [weak self] in
                Logger.shared.log("Keyboard handler: delete current image (Cmd+Delete)")
                self?.deleteCurrentImage()
            },
            onToggleFullscreen: { [weak self] in
                Logger.shared.log("Keyboard handler: toggle full screen (F)")
                self?.toggleFullScreen()
            },
            onExitFullscreen: { [weak self] in
                Logger.shared.log("Keyboard handler: exit full screen (Esc/Enter)")
                self?.exitFullScreen()
            },
            onPlayPause: { [weak self] in
                Logger.shared.log("Keyboard handler: play/pause (Space)")
                self?.togglePlayPause()
            },
            onStartOrStopSlideshow: { [weak self] in
                Logger.shared.log("Keyboard handler: start/stop slideshow (P)")
                self?.startOrStopSlideshow()
            },
            isSlideshowActive: { [weak self] in
                self?.slideshow.isActive ?? false
            }
        )
        container.keyboardHandler = keyboardHandler
        container.addSubview(keyboardHandler)

        // Slideshow controller: owns the countdown; this window reacts to ticks.
        slideshow.onTick = { [weak self] in
            self?.slideshowTick()
        }

        // Refresh AI toolbar button states when model plugin states change
        // (download finished, enabled/disabled, uninstalled).
        self.pluginObserver = NotificationCenter.default.addObserver(
            forName: PluginManager.stateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateAIToolbarState()
        }

        // Set the container as content view (same size, so nothing jumps),
        // then lay out all children explicitly.
        window.contentView = container
        container.layoutChildren()
        window.makeFirstResponder(keyboardHandler)
        updateAIToolbarState()

        // Notify the app delegate when this window closes.
        self.closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // Never leave a running slideshow timer or Live Photo playback behind.
            self.slideshow.stop()
            self.container?.imageView?.stopLivePlayback()
            if let token = self.closeObserver {
                NotificationCenter.default.removeObserver(token)
                self.closeObserver = nil
            }
            if let token = self.pluginObserver {
                NotificationCenter.default.removeObserver(token)
                self.pluginObserver = nil
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
        // A new image set invalidates any running slideshow.
        if slideshow.isActive {
            Logger.shared.log("Slideshow stopped (new images loaded)")
            endSlideshow(finished: false)
        }

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
                } else if ext.isEmpty, DecoderManager.shared.isSupportedImage(at: item) {
                    // No extension - identify by magic numbers (header only).
                    results.append(item)
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

        // Large-file warning (spec: 大图警告): a single image over 50 MB shows
        // a warning, once per file per window session.
        warnIfLargeFile(url)

        // Bump the generation so stale loads from rapid navigation are discarded.
        let generation = loadGeneration + 1
        loadGeneration = generation

        // Cache hit: show the decoded image immediately, no re-decode.
        if let cached = ImageCache.shared.image(for: url) {
            self.baseImage = cached
            self.rotationSteps = 0
            // The cache remembers whether this entry is a huge-image thumbnail.
            self.currentImageIsScaled = ImageCache.shared.isScaled(url)
            self.displayImage(cached, at: url)
            self.updateWindowTitle()
            self.container?.placeholder?.isHidden = true
            Logger.shared.log("Image cache hit for index \(index)")
            self.updateStatusBar()
            self.updateAIToolbarState()
            self.applyAutoAIIfNeeded(url: url)
            return
        }

        // Delegate to the decode abstraction layer: magic-number format
        // detection (Live Photo before HEIC) + auto-selected decoder. The
        // nonisolated async decode runs off the main actor, so heavy files
        // (RAW, large TIFFs) don't block the UI; the SVG WebKit fallback hops
        // back to the main actor internally only for its render pass.
        // The huge-image memory policy (spec: 超大图缩略) is applied here:
        // files ≥ 10 000 px on any side are decoded only as a downscaled
        // thumbnail so the full bitmap never enters memory.
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            do {
                let (decoded, scaled) = try await self.decodeWithHugeImagePolicy(url: url)
                // Discard out-of-order loads so the newest press always wins.
                guard generation == self.loadGeneration else {
                    Logger.shared.log("Discarding stale image load for index \(index)")
                    return
                }

                // A newly loaded image is always shown unrotated: any unsaved
                // rotation of the previous image is discarded here (per spec).
                self.baseImage = decoded.image
                self.rotationSteps = 0
                self.currentImageIsScaled = scaled

                // Keep the decoded image in the NSCache (size follows the
                // "Cached images" setting, 1–20, read live on insert).
                ImageCache.shared.insert(decoded.image, for: url, scaled: scaled)

                // The image view fills the window area; setting the image resets it to
                // "fit to window" mode (proportional fit, centered). Live Photo
                // support is configured alongside the new still.
                self.displayImage(decoded.image, at: url)

                // Window title shows the current file name (+ active AI mark).
                self.updateWindowTitle()

                // Hide the empty-state placeholder once an image is shown.
                self.container?.placeholder?.isHidden = true

                if scaled {
                    Logger.shared.log("Huge image shown as scaled thumbnail: \(url)")
                    self.showStatusBarHint("已缩放显示（超大图缩略）", for: 3.0)
                } else {
                    Logger.shared.log("Image loaded successfully (\(decoded.format.displayName)): \(decoded.image.size)")
                }

                // Refresh status bar (filename / size / zoom / index).
                self.updateStatusBar()
                self.updateAIToolbarState()
                self.applyAutoAIIfNeeded(url: url)
            } catch {
                Logger.shared.log("Failed to load image (unsupported format or decode error): \(url) — \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Memory management (large-file warning + huge-image thumbnails)

    /// Show a warning for image files over 50 MB (spec: 大图警告), once per
    /// file per window session. A non-blocking sheet is used so slideshow
    /// playback and rapid navigation are never frozen by a modal dialog.
    private func warnIfLargeFile(_ url: URL) {
        guard largeFileWarned.insert(url).inserted else { return }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64,
              size > ImageLimits.largeFileWarningBytes else { return }

        Logger.shared.log("Large file warning: \(url.lastPathComponent) is \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) (> 50 MB)")

        let alert = NSAlert()
        alert.messageText = "Large image warning"
        alert.informativeText = "“\(url.lastPathComponent)” is \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)), larger than 50 MB. Displaying it may use a lot of memory."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in }
    }

    /// Decode `url` applying the huge-image memory policy (spec: 超大图缩略):
    /// if ImageIO can read the pixel dimensions and any side is ≥ 10 000 px,
    /// only a downscaled thumbnail is decoded (the full bitmap never enters
    /// memory); otherwise the normal decode runs and — if its result turns out
    /// huge anyway (formats the dimension probe cannot read) — it is downscaled
    /// after the fact as a fallback.
    private func decodeWithHugeImagePolicy(url: URL) async throws -> (image: DecodedImage, scaled: Bool) {
        // 1) Cheap dimension probe (file header only, no full decode).
        if let probed = Self.probePixelSize(url),
           max(probed.width, probed.height) >= ImageLimits.hugeImagePixelThreshold {
            if let thumb = try? await DecoderManager.shared.decodeThumbnail(
                url: url, maxPixelSize: ImageLimits.thumbnailMaxPixels) {
                return (thumb, true)
            }
            // Thumbnail generation failed — fall through to the full decode.
        }

        // 2) Normal decode via the decoder registry.
        let decoded = try await DecoderManager.shared.decode(url: url)

        // 3) Fallback for formats the probe could not read: downscale in place.
        if Self.isHugePixelSize(decoded.pixelSize),
           let small = Self.downscale(decoded.image, toMaxPixels: ImageLimits.thumbnailMaxPixels) {
            return (DecodedImage(image: small, format: decoded.format,
                                 pixelSize: small.decodedPixelSize,
                                 companionVideoURL: decoded.companionVideoURL), true)
        }
        return (decoded, false)
    }

    /// Pixel dimensions read from the file header only (no full decode).
    private static func probePixelSize(_ url: URL) -> NSSize? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              w > 0, h > 0 else { return nil }
        return NSSize(width: w, height: h)
    }

    /// Whether any side of `size` reaches the huge-image threshold (10 000 px).
    private static func isHugePixelSize(_ size: NSSize?) -> Bool {
        guard let size = size else { return false }
        return max(size.width, size.height) >= ImageLimits.hugeImagePixelThreshold
    }

    /// Downscale an already-decoded image so its longest side is ≤ `maxPixels`.
    private static func downscale(_ image: NSImage, toMaxPixels maxPixels: Int) -> NSImage? {
        guard let src = image.sourceCGImage else { return nil }
        let longest = CGFloat(max(src.width, src.height))
        guard longest > 0 else { return nil }
        let factor = CGFloat(maxPixels) / longest
        let w = max(1, Int((CGFloat(src.width) * factor).rounded()))
        let h = max(1, Int((CGFloat(src.height) * factor).rounded()))
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let cg = ctx.makeImage() else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: w, height: h))
    }

    /// Swap in a new displayed image and (re)configure Live Photo support for it:
    /// stop any running playback, show the still, then attach the companion video
    /// (if any) — which auto-plays per the "Auto-play Live Photos" setting.
    private func displayImage(_ nsImage: NSImage, at url: URL) {
        guard let imageView = container?.imageView else { return }
        imageView.livePhotoURL = nil   // stop playback of the previous image first
        // Show the active AI transform (if any) instead of the base image.
        var shown = nsImage
        if let state = aiStates[url], let kind = state.activeKind, let aiImage = state.image(for: kind) {
            shown = aiImage
        }
        imageView.image = shown
        attachLivePhoto(for: url)
    }

    /// The image the current rotation/save operates on: the active AI result
    /// when a transform is applied, otherwise the original base image.
    private var currentSourceImage: NSImage? {
        guard !imageURLs.isEmpty, imageURLs.indices.contains(currentIndex) else { return nil }
        let url = imageURLs[currentIndex]
        if let state = aiStates[url], let kind = state.activeKind {
            return state.image(for: kind) ?? baseImage
        }
        return baseImage
    }

    /// Window title with the active AI mark (e.g. "photo.jpg — AI Super-Resolved").
    private func updateWindowTitle() {
        guard !imageURLs.isEmpty, imageURLs.indices.contains(currentIndex) else {
            window.title = "PixAI"
            return
        }
        let name = imageURLs[currentIndex].lastPathComponent
        if let mark = aiStates[imageURLs[currentIndex]]?.activeMark {
            window.title = "\(name) — \(mark)"
        } else {
            window.title = name
        }
    }

    /// Detect the companion .MOV for `url` (async, cached per URL) and attach it
    /// to the image view — but only if this image is still current when the
    /// detection completes (rapid navigation discards stale results).
    private func attachLivePhoto(for url: URL) {
        let generation = loadGeneration
        Task { @MainActor [weak self] in
            guard let self = self, self.loadGeneration == generation,
                  self.imageURLs.indices.contains(self.currentIndex),
                  self.imageURLs[self.currentIndex] == url else { return }
            self.container?.imageView?.livePhotoURL =
                await LivePhotoDetector.shared.companionVideoURL(for: url)
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
            var sizeText = "\(Int(size.width.rounded()))x\(Int(size.height.rounded())) px"
            if currentImageIsScaled {
                // Huge-image thumbnail: mark that the display is scaled down.
                sizeText += " (已缩放)"
            }
            parts.append(sizeText)
            parts.append(String(format: "%.0f%%", currentZoomRatio() * 100))
        }
        
        if let mark = aiStates[url]?.activeMark {
            parts.append(mark)
        }
        parts.append("\(currentIndex + 1) / \(imageURLs.count)")
        label.attributedStringValue = Self.statusString(parts.joined(separator: "\t"))
    }
    
    /// Update the toolbar's fit toggle icon (true = depicts "fit to window").
    /// The toggle state itself lives in ZoomableImageView; this only mirrors it.
    private func setFitToggleIcon(showsFit: Bool) {
        toolbar?.setFitToggleShowsFitIcon(showsFit)
    }

    // MARK: - Rotation & save

    /// Rotate the current image 90° clockwise (temporary; not written to disk).
    func rotateClockwise() {
        guard !batchRunning, baseImage != nil else { return }
        rotationSteps += 1
        applyRotation()
    }

    /// Rotate the current image 90° counterclockwise (temporary; not written to disk).
    func rotateCounterclockwise() {
        guard !batchRunning, baseImage != nil else { return }
        rotationSteps -= 1
        applyRotation()
    }

    /// Redraw the displayed image from the ORIGINAL image at the accumulated
    /// angle, so quality never degrades no matter how many times it is rotated.
    private func applyRotation() {
        guard let base = currentSourceImage else { return }
        let displayed = base.rotatedClockwise(by: rotationSteps * 90) ?? base

        // A temporary rotation desynchronizes the still from its companion video,
        // so suppress Live Photo playback until the rotation is undone or saved.
        if (rotationSteps * 90) % 360 != 0 {
            container?.imageView?.livePhotoURL = nil
        }

        container?.imageView?.image = displayed

        if (rotationSteps * 90) % 360 == 0, imageURLs.indices.contains(currentIndex) {
            // Back to the original orientation: restore Live Photo support.
            attachLivePhoto(for: imageURLs[currentIndex])
        }
        updateStatusBar()
    }

    /// Save the rotated image over the original file (overwrite). If the
    /// accumulated rotation is a multiple of 360° (in either direction), the
    /// image is back to its original orientation: the save is ignored so the
    /// original file data is never re-encoded.
    func saveCurrentRotation() {
        guard !batchRunning, !imageURLs.isEmpty, imageURLs.indices.contains(currentIndex), let source = currentSourceImage else { return }
        let url = imageURLs[currentIndex]

        let netDegrees = rotationSteps * 90
        let hasRotation = (netDegrees % 360) != 0
        let hasAITransform = aiStates[url]?.activeKind != nil

        if !hasRotation && !hasAITransform {
            Logger.shared.log("Save ignored: no rotation and no AI transform")
            showStatusMessage("Nothing to save")
            return
        }

        let toSave = hasRotation ? (source.rotatedClockwise(by: netDegrees) ?? source) : source
        guard let cgImage = toSave.sourceCGImage else {
            Logger.shared.log("Save failed: could not produce image for \(url)")
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
            // The file now matches the displayed image.
            if hasRotation {
                baseImage = toSave
                rotationSteps = 0
            }
            // Restore Live Photo support (suppressed while rotated).
            attachLivePhoto(for: url)
            Logger.shared.log("Saved image to \(url)")
            showStatusMessage("Saved")
        } catch {
            Logger.shared.log("Save failed for \(url): \(error)")
            showStatusMessage("Save failed: \(error.localizedDescription)")
        }
    }

    /// Save the current image (rotation + active AI transform) to a new file.
    func saveAsImage() {
        guard !imageURLs.isEmpty, imageURLs.indices.contains(currentIndex), let source = currentSourceImage else { return }
        let url = imageURLs[currentIndex]

        let netDegrees = rotationSteps * 90
        let hasRotation = (netDegrees % 360) != 0
        let toSave = hasRotation ? (source.rotatedClockwise(by: netDegrees) ?? source) : source
        guard let cgImage = toSave.sourceCGImage else {
            showStatusMessage("Save failed")
            return
        }

        let panel = NSSavePanel()
        panel.nameFieldStringValue = url.lastPathComponent
        panel.canCreateDirectories = true
        panel.message = "Save the current image (including any AI transform)"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self, response == .OK, let dest = panel.url else { return }
            let ext = dest.pathExtension.lowercased()
            guard let data = Self.encodeImage(cgImage, fileExtension: ext) else {
                self.showStatusMessage("Save failed: unsupported format")
                return
            }
            do {
                try data.write(to: dest, options: .atomic)
                Logger.shared.log("Saved As to \(dest.path)")
                self.showStatusMessage("Saved as \(dest.lastPathComponent)")
            } catch {
                Logger.shared.log("Save As failed for \(dest.path): \(error)")
                self.showStatusMessage("Save failed: \(error.localizedDescription)")
            }
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

    // MARK: - AI (toggles + one-click batch)

    /// Get or create the per-image AI state for `url`.
    private func aiState(for url: URL) -> ImageAIState {
        if let existing = aiStates[url] { return existing }
        let fresh = ImageAIState()
        aiStates[url] = fresh
        return fresh
    }

    /// Wrap a CGImage result into an NSImage sized in pixels.
    private static func nsImage(from cg: CGImage) -> NSImage {
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    /// Refresh the display + title + status bar + toolbar for the current image.
    private func refreshCurrentDisplay() {
        guard imageURLs.indices.contains(currentIndex), let base = baseImage else { return }
        let url = imageURLs[currentIndex]
        displayImage(base, at: url)
        updateWindowTitle()
        updateStatusBar()
        updateAIToolbarState()
    }

    /// Sync the AI toolbar buttons with model availability + current image state.
    private func updateAIToolbarState() {
        let state: ImageAIState? = imageURLs.indices.contains(currentIndex) ? aiStates[imageURLs[currentIndex]] : nil
        toolbar?.setAIModelButtonsEnabled(
            upscaleAvailable: RealESRGANEngine.shared.isAvailable,
            dewatermarkAvailable: U2NetEngine.shared.isAvailable
        )
        toolbar?.setAIEnhanceQualityApplied(state?.isEnhanced ?? false)
        toolbar?.setAIDewatermarkApplied(state?.isDewatermarked ?? false)
        toolbar?.setAIUpscaleApplied(state?.isUpscaled ?? false)
    }

    /// Auto-AI on load (config: auto upscale small images / auto dewatermark).
    /// Runs at most once per URL per window session; results are memory-only.
    private func applyAutoAIIfNeeded(url: URL) {
        guard autoAIDone.insert(url).inserted else { return }
        let cfg = AppConfig.shared
        var wantUpscale = false
        var wantDewatermark = false
        if cfg.aiAutoUpscaleEnabled, RealESRGANEngine.shared.isAvailable,
           let cg = baseImage?.sourceCGImage, max(cg.width, cg.height) <= cfg.smallImageMaxSide {
            wantUpscale = true
        }
        if cfg.aiAutoDewatermarkEnabled, U2NetEngine.shared.isAvailable {
            wantDewatermark = true
        }
        guard wantUpscale || wantDewatermark, let cg = baseImage?.sourceCGImage else { return }
        aiBusy.insert(url)
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            defer { self.aiBusy.remove(url) }
            if wantUpscale {
                let out = await Task.detached(priority: .userInitiated) { () -> CGImage? in
                    guard (try? await RealESRGANEngine.shared.ensureLoaded()) != nil else { return nil }
                    return try? RealESRGANEngine.shared.upscale(cg, progress: nil)
                }.value
                if let out = out {
                    let state = self.aiState(for: url)
                    state.upscaledImage = Self.nsImage(from: out)
                    state.isUpscaled = true
                    state.lastApplied = .upscale
                    self.aiStates[url] = state
                } else {
                    Logger.shared.log("Auto upscale failed for \(url.lastPathComponent)")
                }
            }
            if wantDewatermark {
                let result = await Task.detached(priority: .userInitiated) { () -> (CGImage, Double)? in
                    guard (try? U2NetEngine.shared.ensureLoaded()) != nil else { return nil }
                    return try? U2NetEngine.shared.removeWatermark(from: cg)
                }.value
                if let (out, fraction) = result, fraction > 0 {
                    let state = self.aiState(for: url)
                    state.dewatermarkedImage = Self.nsImage(from: out)
                    state.isDewatermarked = true
                    state.lastApplied = .dewatermark
                    self.aiStates[url] = state
                }
            }
            if self.imageURLs.indices.contains(self.currentIndex), self.imageURLs[self.currentIndex] == url {
                self.refreshCurrentDisplay()
            }
        }
    }

    /// Toggle CIAutoEnhance quality enhancement on the current image.
    func toggleAIEnhance() {
        guard !batchRunning, imageURLs.indices.contains(currentIndex) else { return }
        let url = imageURLs[currentIndex]
        let state = aiState(for: url)
        if state.isEnhanced {
            // Already on → turn off instantly (no recompute).
            state.isEnhanced = false
            if state.lastApplied == .enhance {
                state.lastApplied = state.isUpscaled ? .upscale : (state.isDewatermarked ? .dewatermark : nil)
            }
            aiStates[url] = state
            refreshCurrentDisplay()
            return
        }
        guard let cg = baseImage?.sourceCGImage else { return }
        aiBusy.insert(url)
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            defer { self.aiBusy.remove(url) }
            // Fast, but still kept off the main thread.
            let out = await Task.detached(priority: .userInitiated) {
                AutoEnhance.enhance(cg)
            }.value
            if let out = out {
                let state = self.aiState(for: url)
                state.enhancedImage = Self.nsImage(from: out)
                state.isEnhanced = true
                state.lastApplied = .enhance
                self.aiStates[url] = state
            } else {
                self.showStatusMessage("AI enhance failed")
            }
            if self.imageURLs.indices.contains(self.currentIndex), self.imageURLs[self.currentIndex] == url {
                self.refreshCurrentDisplay()
            }
        }
    }

    /// Toggle Real-ESRGAN 4x super-resolution on the current image.
    func toggleAIUpscale() {
        guard !batchRunning, imageURLs.indices.contains(currentIndex) else { return }
        let url = imageURLs[currentIndex]
        let state = aiState(for: url)
        if state.isUpscaled {
            // Already on → restore the original instantly.
            state.isUpscaled = false
            if state.lastApplied == .upscale {
                state.lastApplied = state.isDewatermarked ? .dewatermark : (state.isEnhanced ? .enhance : nil)
            }
            aiStates[url] = state
            refreshCurrentDisplay()
            return
        }
        guard RealESRGANEngine.shared.isAvailable else {
            showStatusMessage("Real-ESRGAN model not downloaded — see Preferences ▸ AI Models")
            return
        }
        guard let cg = baseImage?.sourceCGImage else { return }
        aiBusy.insert(url)
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            defer { self.aiBusy.remove(url) }
            self.showStatusBarHint("AI upscaling…", for: 2.0)
            // Synchronous heavy work: run off the main thread.
            let out = await Task.detached(priority: .userInitiated) { [weak self] () -> CGImage? in
                guard (try? await RealESRGANEngine.shared.ensureLoaded()) != nil else { return nil }
                return try? RealESRGANEngine.shared.upscale(cg) { p in
                    DispatchQueue.main.async {
                        self?.showStatusBarHint(String(format: "AI upscaling… %.0f%%", p * 100), for: 1.0)
                    }
                }
            }.value
            if let out = out {
                let state = self.aiState(for: url)
                state.upscaledImage = Self.nsImage(from: out)
                state.isUpscaled = true
                state.lastApplied = .upscale
                self.aiStates[url] = state
            } else {
                self.showStatusMessage("AI upscale failed")
            }
            if self.imageURLs.indices.contains(self.currentIndex), self.imageURLs[self.currentIndex] == url {
                self.refreshCurrentDisplay()
            }
        }
    }

    /// Toggle U2Net watermark removal on the current image.
    func toggleAIDewatermark() {
        guard !batchRunning, imageURLs.indices.contains(currentIndex) else { return }
        let url = imageURLs[currentIndex]
        let state = aiState(for: url)
        if state.isDewatermarked {
            // Already on → restore the original instantly.
            state.isDewatermarked = false
            if state.lastApplied == .dewatermark {
                state.lastApplied = state.isUpscaled ? .upscale : (state.isEnhanced ? .enhance : nil)
            }
            aiStates[url] = state
            refreshCurrentDisplay()
            return
        }
        guard U2NetEngine.shared.isAvailable else {
            showStatusMessage("U2Net model not downloaded — see Preferences ▸ AI Models")
            return
        }
        guard let cg = baseImage?.sourceCGImage else { return }
        aiBusy.insert(url)
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            defer { self.aiBusy.remove(url) }
            self.showStatusBarHint("AI dewatermarking…", for: 2.0)
            // Synchronous heavy work: run off the main thread.
            let result = await Task.detached(priority: .userInitiated) { () -> (CGImage, Double)? in
                guard (try? U2NetEngine.shared.ensureLoaded()) != nil else { return nil }
                return try? U2NetEngine.shared.removeWatermark(from: cg)
            }.value
            if let (out, fraction) = result {
                if fraction <= 0 {
                    self.showStatusMessage("No watermark detected")
                } else {
                    let state = self.aiState(for: url)
                    state.dewatermarkedImage = Self.nsImage(from: out)
                    state.isDewatermarked = true
                    state.lastApplied = .dewatermark
                    self.aiStates[url] = state
                }
            } else {
                self.showStatusMessage("AI dewatermark failed")
            }
            if self.imageURLs.indices.contains(self.currentIndex), self.imageURLs[self.currentIndex] == url {
                self.refreshCurrentDisplay()
            }
        }
    }

    /// AI one-click enhance: confirm, then run the batch (dedup + dewatermark)
    /// over the whole queue with the UI locked behind a progress overlay.
    func runAIOneClickEnhance() {
        guard !batchRunning, !imageURLs.isEmpty else { return }
        let alert = NSAlert()
        alert.messageText = "AI One-Click Enhance"
        alert.informativeText = "Run AI dedup and dewatermark on the current image queue? Duplicate files will be moved to the Trash."
        alert.addButton(withTitle: "Run")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        batchRunning = true
        showBatchOverlay()
        let urls = imageURLs
        let mode = AppConfig.shared.aiEnhanceMode
        Task { @MainActor [weak self] in
            await self?.runAIBatch(urls: urls, mode: mode)
        }
    }

    /// The batch itself (main actor; heavy work hops to detached tasks).
    @MainActor
    private func runAIBatch(urls: [URL], mode: String) async {
        var trashed: Set<URL> = []

        // ── Phase 1: dedup (skipped when mode == "watermarkOnly") ─────────
        if mode != "watermarkOnly" {
            setBatchProgress(0, indeterminate: true)
            let observations = await DuplicateDetector.featurePrints(for: urls) { p in
                DispatchQueue.main.async { [weak self] in
                    self?.setBatchProgress(p * 0.4, indeterminate: false)
                }
            }
            let groups = DuplicateDetector.findGroups(urls: urls, observations: observations, threshold: DuplicateDetector.defaultThreshold)
            for (gi, group) in groups.enumerated() {
                setBatchProgress(0.4, indeterminate: true)
                // Resolve the group to live URLs (groups are disjoint, so all
                // members of an unprocessed group still exist).
                let live = group.indices.compactMap { i in urls.indices.contains(i) ? urls[i] : nil }
                guard live.count >= 2 else { continue }

                var toTrash: [URL] = []
                if live.count == 2 {
                    // Side-by-side comparison; default selection = best image.
                    let best = DuplicateDetector.bestIndex(in: group, urls: urls, dewatermarkedFlags: [:])
                    let defaultSide: Int = (group.indices[1] == best) ? 1 : 0
                    let keepURL: URL? = await withCheckedContinuation { cont in
                        DedupComparisonWindow.present(
                            over: self.window,
                            leftURL: live[0],
                            rightURL: live[1],
                            initialSelection: defaultSide,
                            onConfirm: { side in
                                cont.resume(returning: side == 0 ? live[0] : live[1])
                            },
                            onCancel: {
                                cont.resume(returning: nil)   // keep both
                            }
                        )
                    }
                    if let keep = keepURL {
                        toTrash = live.filter { $0 != keep }
                    }
                } else {
                    // >2 members: keep the best, trash the rest.
                    let best = DuplicateDetector.bestIndex(in: group, urls: urls, dewatermarkedFlags: [:])
                    toTrash = live.filter { $0 != urls[best] }
                }

                for u in toTrash {
                    do {
                        try FileManager.default.trashItem(at: u, resultingItemURL: nil)
                        trashed.insert(u)
                        Logger.shared.log("AI batch dedup: moved \(u.lastPathComponent) to Trash")
                    } catch {
                        Logger.shared.log("AI batch dedup: trash failed for \(u.lastPathComponent): \(error.localizedDescription)")
                    }
                }

                // Ask before the next group (config: ask to continue).
                if gi < groups.count - 1, AppConfig.shared.dedupAskContinue {
                    let cont = NSAlert()
                    cont.messageText = "Continue?"
                    cont.informativeText = "More duplicate groups remain. Continue deduplicating?"
                    cont.addButton(withTitle: "Yes")
                    cont.addButton(withTitle: "No")
                    if cont.runModal() != .alertFirstButtonReturn { break }
                }
            }

            // Apply the removals to the queue (keep the current image stable).
            if !trashed.isEmpty {
                let currentURL = imageURLs.indices.contains(currentIndex) ? imageURLs[currentIndex] : nil
                imageURLs.removeAll { trashed.contains($0) }
                for u in trashed { aiStates.removeValue(forKey: u) }
                ImageCache.shared.removeAll()
                if let cur = currentURL, let idx = imageURLs.firstIndex(of: cur) {
                    currentIndex = idx
                } else if !imageURLs.isEmpty {
                    currentIndex = min(currentIndex, imageURLs.count - 1)
                }
            }
        }

        // ── Phase 2: dewatermark (skipped when mode == "dedupOnly") ───────
        if mode != "dedupOnly" {
            if U2NetEngine.shared.isAvailable {
                let queue = imageURLs
                for (i, u) in queue.enumerated() {
                    setBatchProgress(0.4 + 0.6 * Double(i + 1) / Double(max(queue.count, 1)), indeterminate: false)
                    guard let decoded = try? await DecoderManager.shared.decode(url: u),
                          let cg = decoded.image.sourceCGImage else { continue }
                    if let (out, fraction) = await Task.detached(priority: .userInitiated, operation: { () -> (CGImage, Double)? in
                        guard (try? U2NetEngine.shared.ensureLoaded()) != nil else { return nil }
                        return try? U2NetEngine.shared.removeWatermark(from: cg)
                    }).value, fraction > 0 {
                        let state = aiState(for: u)
                        state.dewatermarkedImage = Self.nsImage(from: out)
                        state.isDewatermarked = true
                        state.lastApplied = .dewatermark
                        aiStates[u] = state
                    }
                }
            } else {
                setBatchProgress(1, indeterminate: false)
                Logger.shared.log("AI batch: U2Net not downloaded — dewatermark phase skipped")
            }
        }

        // ── Finish: refresh display, unlock the UI ────────────────────────
        if !imageURLs.isEmpty {
            currentIndex = min(currentIndex, imageURLs.count - 1)
            loadImage(at: currentIndex)
        } else {
            baseImage = nil
            rotationSteps = 0
            window.title = "PixAI"
            container?.imageView?.image = nil
            container?.imageView?.livePhotoURL = nil
            container?.placeholder?.isHidden = false
            updateStatusBar()
        }
        window.makeKeyAndOrderFront(nil)
        hideBatchOverlay()
        batchRunning = false
        showStatusMessage("AI one-click enhance complete")
        updateAIToolbarState()
    }

    /// Full-window progress overlay shown while the AI batch runs.
    private func showBatchOverlay() {
        guard let contentView = window.contentView else { return }
        let overlay = NSView(frame: contentView.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor(white: 0, alpha: 0.55).cgColor

        let barW = min(420, max(200, contentView.bounds.width - 80))
        let bar = NSProgressIndicator(frame: NSRect(x: (contentView.bounds.width - barW) / 2,
                                                    y: contentView.bounds.midY - 20,
                                                    width: barW, height: 20))
        bar.style = .bar
        bar.minValue = 0
        bar.maxValue = 1
        bar.isIndeterminate = false

        let label = NSTextField(labelWithString: "This operation takes time, please wait")
        label.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.sizeToFit()
        let labelW = max(label.frame.width, barW)
        label.frame = NSRect(x: (contentView.bounds.width - labelW) / 2,
                             y: contentView.bounds.midY + 16,
                             width: labelW, height: label.frame.height)

        overlay.addSubview(bar)
        overlay.addSubview(label)
        contentView.addSubview(overlay, positioned: .above, relativeTo: nil)
        batchOverlay = overlay
        batchProgressIndicator = bar
        batchStatusLabel = label
    }

    private func hideBatchOverlay() {
        batchProgressIndicator?.stopAnimation(nil)
        batchOverlay?.removeFromSuperview()
        batchOverlay = nil
        batchProgressIndicator = nil
        batchStatusLabel = nil
    }

    private func setBatchProgress(_ value: Double, indeterminate: Bool) {
        guard let bar = batchProgressIndicator else { return }
        if indeterminate {
            bar.isIndeterminate = true
            bar.startAnimation(nil)
        } else {
            bar.isIndeterminate = false
            bar.stopAnimation(nil)
            bar.doubleValue = min(max(value, 0), 1)
        }
    }

    // MARK: - Delete (move to Trash)

    /// Delete the current image: move it to the Trash (per Apple's
    /// `FileManager.trashItem(at:resultingItemURL:)`), optionally after a
    /// confirmation dialog, then switch to the next / previous image or the
    /// empty state when the last one is removed.
    func deleteCurrentImage() {
        guard !batchRunning, !imageURLs.isEmpty, imageURLs.indices.contains(currentIndex) else { return }
        let url = imageURLs[currentIndex]

        // Confirmation dialog (skipped when the user disabled it via the
        // "don't ask again" checkbox or the Preferences window).
        if AppConfig.shared.deleteConfirmationEnabled {
            let alert = NSAlert()
            alert.messageText = "Delete “\(url.lastPathComponent)”?"
            alert.informativeText = "The file will be moved to the Trash.\nSize: \(Self.fileSizeString(for: url))"
            alert.alertStyle = .warning
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Don't ask again"
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")

            let response = alert.runModal()
            if alert.suppressionButton?.state == .on {
                // Persist "don't ask again" to ~/.pixai/config.json.
                AppConfig.shared.deleteConfirmationEnabled = false
            }
            guard response == .alertFirstButtonReturn else { return }
        }

        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            Logger.shared.log("Move to Trash failed for \(url): \(error)")
            showStatusMessage("Delete failed: \(error.localizedDescription)")
            return
        }

        // Remove from the list; drop any unsaved rotation of this image.
        let wasIndex = currentIndex
        imageURLs.remove(at: wasIndex)
        baseImage = nil
        rotationSteps = 0

        if imageURLs.isEmpty {
            // All files deleted → empty state.
            if slideshow.isActive {
                endSlideshow(finished: false)
            }
            currentIndex = 0
            window.title = "PixAI"
            container?.imageView?.livePhotoURL = nil
            container?.imageView?.image = nil
            container?.placeholder?.isHidden = false
            updateStatusBar()
        } else {
            // Switch to the image that shifted into this slot (the next one),
            // or the previous one when the last image was deleted.
            let newIndex = min(wasIndex, imageURLs.count - 1)
            loadImage(at: newIndex)
        }

        Logger.shared.log("Deleted \(url) (moved to Trash)")
        showStatusMessage("Moved to Trash")
    }

    /// Human-readable file size for the delete confirmation dialog.
    private static func fileSizeString(for url: URL) -> String {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
        return "unknown"
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

    // MARK: - Slideshow

    /// Start the slideshow: auto full screen, then advance every `interval` seconds.
    private func startSlideshow() {
        guard !imageURLs.isEmpty else { return }
        // Read the configured interval (Preferences ▸ Slideshow) at start time.
        slideshow.interval = AppConfig.shared.slideshowInterval
        Logger.shared.log("Slideshow started: \(imageURLs.count) images, \(slideshow.interval)s each")
        slideshow.start()
        updatePlayPauseIcon()
        window.toggleFullScreen(nil)   // auto full screen on start
    }

    /// Pause the running slideshow (Space key / toolbar button).
    private func pauseSlideshow() {
        guard slideshow.isPlaying else { return }
        Logger.shared.log("Slideshow paused at index \(currentIndex)")
        slideshow.pause()
        updatePlayPauseIcon()
    }

    /// Resume a paused slideshow (Space key / toolbar button).
    private func resumeSlideshow() {
        guard slideshow.state == .paused else { return }
        Logger.shared.log("Slideshow resumed at index \(currentIndex)")
        slideshow.resume()
        updatePlayPauseIcon()
    }

    /// Stop the slideshow and return to window mode (P / Enter / Esc keys).
    private func stopSlideshow() {
        guard slideshow.isActive else { return }
        Logger.shared.log("Slideshow stopped")
        endSlideshow(finished: false)
    }

    /// Toggle play/pause (Space key, toolbar play-pause button).
    /// Starts the slideshow when it is not running yet.
    func togglePlayPause() {
        guard !batchRunning, !imageURLs.isEmpty else { return }
        switch slideshow.state {
        case .stopped: startSlideshow()
        case .playing: pauseSlideshow()
        case .paused: resumeSlideshow()
        }
    }

    /// P key: start the slideshow when stopped, exit it (back to window mode) otherwise.
    func startOrStopSlideshow() {
        if slideshow.isActive {
            stopSlideshow()
        } else {
            startSlideshow()
        }
    }

    /// Called by the controller after a full interval elapses while playing:
    /// advance to the next image, or finish at the last one.
    private func slideshowTick() {
        guard slideshow.isPlaying else { return }
        if currentIndex < imageURLs.count - 1 {
            loadImage(at: currentIndex + 1)
        } else {
            endSlideshow(finished: true)
        }
    }

    /// Finish the slideshow: stop playback, exit full screen (back to window
    /// mode), and — when the whole list was played — hint in the status bar.
    private func endSlideshow(finished: Bool) {
        slideshow.stop()
        updatePlayPauseIcon()
        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
        if finished {
            Logger.shared.log("Slideshow finished at the last image")
            showStatusBarHint("播放结束 (playback ended)", for: 3.0)
        }
    }

    /// Mirror the play state onto the toolbar button icon: pause icon while
    /// playing, play icon when stopped or paused.
    private func updatePlayPauseIcon() {
        toolbar?.setPlayPauseShowsPauseIcon(slideshow.isPlaying)
    }

    /// Temporarily show a hint in the bottom status bar; the normal
    /// filename/size/zoom/index content is restored after `duration` seconds
    /// (navigation rewrites it earlier anyway).
    private func showStatusBarHint(_ message: String, for duration: TimeInterval) {
        guard let label = statusBarLabel else { return }
        label.attributedStringValue = Self.statusString(message)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.updateStatusBar()
        }
    }

    /// Go to previous image with loop.
    /// One press at the first image shows the hint AND jumps to the last image immediately.
    private func goPrevious() {
        guard !batchRunning, imageURLs.count > 1 else { return }

        if currentIndex == 0 {
            Logger.shared.log("At first image, showing wrap-around message")
            showStatusMessage("First image, wrapping to last")
        }

        currentIndex = (currentIndex - 1 + imageURLs.count) % imageURLs.count
        loadImage(at: currentIndex)
        // Manual jump during playback: keep playing with a fresh interval.
        if slideshow.isPlaying {
            slideshow.restartCountdown()
        }
    }

    /// Go to next image with loop.
    /// One press at the last image shows the hint AND jumps to the first image immediately.
    private func goNext() {
        guard !batchRunning, imageURLs.count > 1 else { return }

        if currentIndex == imageURLs.count - 1 {
            Logger.shared.log("At last image, showing wrap-around message")
            showStatusMessage("Last image, wrapping to first")
        }

        currentIndex = (currentIndex + 1) % imageURLs.count
        loadImage(at: currentIndex)
        // Manual jump during playback: keep playing with a fresh interval.
        if slideshow.isPlaying {
            slideshow.restartCountdown()
        }
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
