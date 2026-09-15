// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import AVFoundation

/// A custom image view with full zoom/pan control (NSImageView has no built-in
/// zoom API — `imageScaling` only offers fixed scaling modes, so the image is
/// drawn manually here with an explicit transform).
///
/// Behavior (per spec):
///   - Mouse wheel: zoom centered on the cursor, 10% step per notch.
///     Per Apple's docs, `scrollingDeltaY` is the preferred delta property; when
///     `hasPreciseScrollingDeltas` is false the value is a coarse line count
///     (one notch = one 10% step). Precise trackpad deltas are accumulated in
///     points and converted to whole 10% steps.
///   - Trackpad pinch: zoom centered on the pinch location. Per Apple's docs,
///     `NSEvent.magnification` is the fractional delta since the previous event,
///     so `1 + magnification` is the multiplicative factor for this event.
///   - Double-click: toggle between "fit to window" and 100% — the first use
///     fits, the next switches to 100%, the next fits again, and so on.
///   - Drag: pan the view while zoomed in; clamped so the image always covers
///     the visible area (or stays centered when smaller than the view).
///   - Zoom range: 10% ~ 1000% of the original pixel size.
///
/// Drawing model (AppKit's default NON-flipped coordinates, origin bottom-left):
///   - `zoomScale`  : absolute scale, image pixels -> screen points (1.0 == 100%).
///   - `imageOrigin`: bottom-left corner of the drawn image rect in view coords.
/// Cursor-centered zoom keeps the image point under the cursor fixed:
///   origin' = cursor - ((cursor - origin) / oldScale) * newScale
class ZoomableImageView: NSView {
    // MARK: - State

    /// The displayed image. Setting it (including to nil) resets to fit mode.
    var image: NSImage? {
        didSet {
            guard oldValue !== image else { return }
            isFitMode = true
            nextToggleIsFit = true
            pendingPreciseDelta = 0
            resetToFit()
            startFade(from: oldValue)
        }
    }

    /// Absolute scale of image pixels to screen points (1.0 == 100% == 1:1).
    private(set) var zoomScale: CGFloat = 1

    /// Bottom-left corner of the drawn image rect in view coordinates.
    private var imageOrigin: NSPoint = .zero

    /// True while in "fit to window" mode (initial state / after a fit toggle);
    /// the image re-fits automatically on every resize.
    private var isFitMode: Bool = true

    /// True while the next fit/100% toggle (double-click or toolbar button)
    /// will "fit to window"; false means it will switch to 100%. Starts true so
    /// the first double-click after loading fits, per spec. Any manual zoom
    /// (wheel / pinch / drag / zoom buttons) resets this back to true.
    private(set) var nextToggleIsFit: Bool = true

    /// Called after any zoom change so the status bar can refresh in real time.
    var onZoomChange: (() -> Void)?

    // MARK: - Live Photo state

    /// The companion .MOV for the current image when it is a Live Photo pair
    /// (nil = plain still image). Setting it configures the badge and starts
    /// auto-playback when the "Auto-play Live Photos" setting is enabled.
    var livePhotoURL: URL? {
        didSet {
            guard oldValue != livePhotoURL else { return }
            configureLivePhoto()
        }
    }

    private var livePlayer: AVPlayer?
    /// The URL currently loaded into `livePlayer` (the player is recreated when
    /// the companion video changes).
    private var liveLoadedURL: URL?
    private let liveOverlay = LivePhotoOverlayView(frame: .zero)
    private let liveBadge = LivePhotoBadgeView(frame: NSRect(x: 0, y: 0, width: 28, height: 28))
    /// Tokens for the end/failure observers of the current AVPlayerItem.
    private var liveEventObservers: [NSObjectProtocol] = []
    private var configObserver: NSObjectProtocol?

    /// Fixed on-screen badge size and its inset from the drawn image corner.
    private static let liveBadgeSize: CGFloat = 28
    private static let liveBadgeInset: CGFloat = 10

    // MARK: - Limits (spec: 10% ~ 1000%, wheel step 10%)

    static let minZoom: CGFloat = 0.10
    static let maxZoom: CGFloat = 10.0
    /// Multiplicative factor per wheel notch (10% step).
    static let zoomStepFactor: CGFloat = 1.1
    /// Trackpad travel (points) that counts as one 10% step for precise deltas.
    private static let preciseScrollStepPoints: CGFloat = 12

    private var pendingPreciseDelta: CGFloat = 0

    // MARK: - Crossfade transition (config: imageTransitionDuration; 0 = off)

    /// The previously displayed image while a fade-in of the new one runs.
    private var fadePreviousImage: NSImage?
    /// 0 → old image fully visible, 1 → new image fully visible (no fade).
    private var fadeProgress: CGFloat = 1
    private var fadeTimer: Timer?

    /// Begin fading the old image out / the new one in over the configured
    /// duration. No animation when the setting is 0 or there is nothing to
    /// fade from (first load, cleared image).
    private func startFade(from old: NSImage?) {
        fadeTimer?.invalidate()
        fadeTimer = nil
        guard let old, image != nil else {
            fadePreviousImage = nil
            fadeProgress = 1
            return
        }
        let duration = AppConfig.shared.imageTransitionDuration
        guard duration > 0 else {
            fadePreviousImage = nil
            fadeProgress = 1
            return
        }
        fadePreviousImage = old
        fadeProgress = 0
        let step = 1.0 / 60.0
        fadeTimer = Timer.scheduledTimer(withTimeInterval: step, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            self.fadeProgress += CGFloat(step) / CGFloat(duration)
            if self.fadeProgress >= 1 {
                self.fadeProgress = 1
                self.fadePreviousImage = nil
                timer.invalidate()
                self.fadeTimer = nil
            }
            self.needsDisplay = true
        }
    }

    /// Draw `img` proportionally fitted (centered) inside `containerRect`
    /// with the given alpha — used for the outgoing image of a crossfade.
    private func drawFitted(_ img: NSImage, in containerRect: NSRect, fraction: CGFloat) {
        guard fraction > 0 else { return }
        var size = NSSize(width: 0, height: 0)
        if let rep = img.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            size = NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        } else {
            size = img.size
        }
        guard size.width > 0, size.height > 0 else { return }
        let scale = min(containerRect.width / size.width, containerRect.height / size.height)
        let w = size.width * scale
        let h = size.height * scale
        let r = NSRect(x: containerRect.midX - w / 2, y: containerRect.midY - h / 2, width: w, height: h)
        img.draw(in: r, from: .zero, operation: .sourceOver, fraction: fraction,
                 respectFlipped: false, hints: [.interpolation: NSImageInterpolation.high])
    }

    private var isPanning = false
    private var panStartPoint: NSPoint = .zero
    private var panStartOrigin: NSPoint = .zero

    private var trackingArea: NSTrackingArea?

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        // Live Photo chrome: the video overlay sits directly above the drawn
        // image, and the badge (bottom-left corner of the image) above that.
        liveOverlay.isHidden = true
        addSubview(liveOverlay)
        liveBadge.isHidden = true
        liveBadge.onTap = { [weak self] in
            self?.toggleLivePlayback()
        }
        addSubview(liveBadge)

        // Keep a running Live Photo's mute state in sync with the setting.
        configObserver = NotificationCenter.default.addObserver(
            forName: AppConfig.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self, let player = self.livePlayer else { return }
            player.isMuted = AppConfig.shared.livePhotoMuted
        }
    }

    deinit {
        for observer in liveEventObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        fadeTimer?.invalidate()
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Let a click in the image area start panning even when activating the window.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }

    // MARK: - Geometry helpers

    /// Pixel dimensions of the current image (first rep's pixelsWide/High preferred,
    /// falling back to NSImage.size).
    private func imagePixelSize() -> NSSize? {
        guard let image else { return nil }
        if let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 {
            return NSSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        if image.size.width > 0, image.size.height > 0 {
            return image.size
        }
        return nil
    }

    /// Size of the image at the current `zoomScale`.
    private func drawnSize() -> NSSize? {
        guard let size = imagePixelSize() else { return nil }
        return NSSize(width: size.width * zoomScale, height: size.height * zoomScale)
    }

    /// Scale that fits the entire image inside the view, preserving aspect ratio.
    func fitScale() -> CGFloat {
        guard let size = imagePixelSize(), bounds.width > 0, bounds.height > 0 else { return 1 }
        return min(bounds.width / size.width, bounds.height / size.height)
    }

    /// True when the image is larger than its fit size (panning is meaningful).
    var isZoomedIn: Bool {
        guard image != nil else { return false }
        return zoomScale > fitScale() * 1.001
    }

    /// True while in "fit to window" mode (initial state / after double-click).
    var isInFitMode: Bool {
        return isFitMode
    }

    // MARK: - Zoom / pan actions

    /// Return to "fit to window" mode: proportional fit, centered.
    func resetToFit() {
        guard image != nil else { return }
        isFitMode = true
        zoomScale = fitScale()
        centerImage()
        needsDisplay = true
        layoutLivePhotoChrome()
        onZoomChange?()
    }

    /// Zoom by a multiplicative factor, keeping the image point under `cursor` fixed.
    func zoom(by factor: CGFloat, centeredOn cursor: NSPoint) {
        guard image != nil, factor > 0 else { return }
        setZoom(to: zoomScale * factor, centeredOn: cursor)
    }

    /// Set an absolute scale (clamped to 10%~1000%), keeping the image point under
    /// `cursor` fixed. Used by the toolbar buttons (centered on the view midpoint).
    func setZoom(to newScale: CGFloat, centeredOn cursor: NSPoint) {
        guard image != nil else { return }
        let clamped = min(Self.maxZoom, max(Self.minZoom, newScale))
        guard abs(clamped - zoomScale) > .ulpOfOne else { return }

        // Image-space point under the cursor — it must stay under the cursor.
        let qx = (cursor.x - imageOrigin.x) / zoomScale
        let qy = (cursor.y - imageOrigin.y) / zoomScale

        zoomScale = clamped
        isFitMode = false
        // Any manual zoom leaves the toggle alternation back at "fit": the next
        // double-click / toolbar click will fit to window.
        nextToggleIsFit = true
        imageOrigin = NSPoint(x: cursor.x - qx * zoomScale, y: cursor.y - qy * zoomScale)
        clampOrigin()
        needsDisplay = true
        layoutLivePhotoChrome()
        onZoomChange?()
    }

    /// Zoom in by one 10% step (same factor as the wheel), centered on the view.
    func zoomIn() {
        setZoom(to: zoomScale * Self.zoomStepFactor, centeredOn: NSPoint(x: bounds.midX, y: bounds.midY))
    }

    /// Zoom out by one 10% step (same factor as the wheel), centered on the view.
    func zoomOut() {
        setZoom(to: zoomScale / Self.zoomStepFactor, centeredOn: NSPoint(x: bounds.midX, y: bounds.midY))
    }

    /// Switch to exactly 100% (1:1 pixels), keeping the view center fixed.
    func zoomTo100Percent() {
        setZoom(to: 1.0, centeredOn: NSPoint(x: bounds.midX, y: bounds.midY))
    }

    /// Toggle between "fit to window" and 100% (double-click or toolbar button).
    /// The action ALTERNATES regardless of the current mode: the first use fits,
    /// the next switches to 100%, the next fits again, and so on. Any manual
    /// zoom resets the alternation back to "fit".
    func toggleFitOr100Percent() {
        guard image != nil else { return }
        let willFit = nextToggleIsFit
        nextToggleIsFit = !willFit
        if willFit {
            resetToFit()
        } else {
            zoomTo100Percent()
        }
        // zoomTo100Percent is a no-op when already at exactly 100% (no callback),
        // so report the state change explicitly to keep the toolbar icon in sync.
        onZoomChange?()
    }

    private func centerImage() {
        guard let size = drawnSize() else { return }
        imageOrigin = NSPoint(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2
        )
    }

    /// Constrain the pan so the image covers the view when larger than it,
    /// and stays centered when smaller.
    private func clampOrigin() {
        guard let size = drawnSize(), bounds.width > 0, bounds.height > 0 else { return }
        var x = imageOrigin.x
        var y = imageOrigin.y
        if size.width >= bounds.width {
            x = min(0, max(bounds.width - size.width, x))
        } else {
            x = (bounds.width - size.width) / 2
        }
        if size.height >= bounds.height {
            y = min(0, max(bounds.height - size.height, y))
        } else {
            y = (bounds.height - size.height) / 2
        }
        imageOrigin = NSPoint(x: x, y: y)
    }

    // MARK: - Resize

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        guard image != nil else { return }
        if isFitMode {
            // "Fit to window" mode: recompute the fit on every resize.
            zoomScale = fitScale()
            centerImage()
        } else {
            clampOrigin()
        }
        needsDisplay = true
        layoutLivePhotoChrome()
        onZoomChange?()
    }

    // MARK: - Mouse / wheel / pinch events

    /// Trackpad pinch: zoom centered on the pinch location. Per Apple's docs,
    /// `event.magnification` is the fractional delta since the previous event,
    /// so `1 + magnification` is the multiplicative factor for this event.
    override func magnify(with event: NSEvent) {
        guard image != nil else { return }
        let factor = 1.0 + event.magnification
        let cursor = convert(event.locationInWindow, from: nil)
        zoom(by: factor, centeredOn: cursor)
    }

    override func scrollWheel(with event: NSEvent) {
        guard image != nil else { return }
        let cursor = convert(event.locationInWindow, from: nil)

        if event.hasPreciseScrollingDeltas {
            // Trackpad / precise mouse: accumulate points; one 10% step per threshold.
            pendingPreciseDelta += event.scrollingDeltaY
            let steps = Int((pendingPreciseDelta / Self.preciseScrollStepPoints).rounded())
            if steps != 0 {
                zoom(by: pow(Self.zoomStepFactor, CGFloat(steps)), centeredOn: cursor)
                pendingPreciseDelta -= CGFloat(steps) * Self.preciseScrollStepPoints
            }
        } else {
            // Generic wheel (coarse line deltas per Apple's docs): one notch = one 10% step.
            let steps = event.scrollingDeltaY > 0 ? 1 : (event.scrollingDeltaY < 0 ? -1 : 0)
            if steps != 0 {
                zoom(by: pow(Self.zoomStepFactor, CGFloat(steps)), centeredOn: cursor)
            }
        }
    }

    override func mouseDown(with event: NSEvent) {
        guard image != nil else { return }

        // Double-click: toggle between "fit to window" and 100% (first use fits,
        // next switches to 100%, alternating).
        if event.clickCount == 2 {
            toggleFitOr100Percent()
            updateCursor()
            return
        }

        // Begin panning (clamped to center when the image is smaller than the view).
        isPanning = true
        panStartPoint = convert(event.locationInWindow, from: nil)
        panStartOrigin = imageOrigin
        updateCursor()
    }

    override func mouseDragged(with event: NSEvent) {
        guard isPanning else { return }
        let point = convert(event.locationInWindow, from: nil)
        imageOrigin = NSPoint(
            x: panStartOrigin.x + (point.x - panStartPoint.x),
            y: panStartOrigin.y + (point.y - panStartPoint.y)
        )
        clampOrigin()
        needsDisplay = true
        layoutLivePhotoChrome()
    }

    override func mouseUp(with event: NSEvent) {
        if isPanning {
            isPanning = false
            updateCursor()
        }
    }

    // MARK: - Cursor feedback (hand when zoomed in, closed hand while dragging)

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        refreshTrackingArea()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshTrackingArea()
    }

    private func refreshTrackingArea() {
        if let area = trackingArea {
            removeTrackingArea(area)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        updateCursor()
    }

    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    private func updateCursor() {
        if isPanning {
            NSCursor.closedHand.set()
        } else if isZoomedIn {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    // MARK: - Live Photo playback

    /// The drawn image rect in this view's coordinates (what `draw(_:)` paints).
    private func drawnImageRect() -> NSRect? {
        guard let size = drawnSize() else { return nil }
        return NSRect(origin: imageOrigin, size: size)
    }

    /// Called when `livePhotoURL` changes: stop any running playback, show or
    /// hide the badge, and auto-play when the setting is enabled.
    private func configureLivePhoto() {
        stopLivePlayback()
        guard livePhotoURL != nil else {
            liveBadge.isHidden = true
            return
        }
        liveBadge.isHidden = false
        layoutLivePhotoChrome()
        if AppConfig.shared.livePhotoAutoPlay {
            startLivePlayback()
        }
    }

    /// Start (or restart) playback of the companion video: muted per the
    /// current setting, playing once over the still image.
    private func startLivePlayback() {
        guard let url = livePhotoURL, image != nil else { return }
        if livePlayer == nil || liveLoadedURL != url {
            let player = AVPlayer(url: url)
            player.isMuted = AppConfig.shared.livePhotoMuted
            player.volume = 1.0
            player.actionAtItemEnd = .none
            observeLivePlaybackEvents(for: player.currentItem)
            livePlayer = player
            liveLoadedURL = url
            liveOverlay.player = player
        }
        // Seek to zero first; AVFoundation delays `play()` until the seek finishes.
        livePlayer?.seek(to: .zero)
        livePlayer?.play()
        layoutLivePhotoChrome()
        liveOverlay.isHidden = false
    }

    /// Stop playback and fall back to the still image (navigation, rotation
    /// changes, window close, and the end of a play-through all call this).
    func stopLivePlayback() {
        livePlayer?.pause()
        liveOverlay.isHidden = true
    }

    /// Badge click: play when idle, stop while playing. Mute follows the
    /// current setting at playback time.
    private func toggleLivePlayback() {
        guard livePhotoURL != nil else { return }
        if livePlayer?.timeControlStatus == .playing {
            stopLivePlayback()
        } else {
            startLivePlayback()
        }
    }

    /// Reposition the video overlay (exactly over the drawn image) and the badge
    /// (bottom-left corner of the drawn image). Called on every zoom/pan/resize.
    private func layoutLivePhotoChrome() {
        guard livePhotoURL != nil, let rect = drawnImageRect() else { return }
        liveOverlay.frame = rect
        let side = Self.liveBadgeSize
        let inset = Self.liveBadgeInset
        liveBadge.frame = NSRect(
            x: rect.minX + inset,
            y: rect.maxY - side - inset,
            width: side,
            height: side
        )
    }

    /// Observe the end (and failure) of the current item so playback falls back
    /// to the still image when it finishes or cannot play.
    private func observeLivePlaybackEvents(for item: AVPlayerItem?) {
        for old in liveEventObservers {
            NotificationCenter.default.removeObserver(old)
        }
        liveEventObservers.removeAll()
        guard let item else { return }
        liveEventObservers.append(NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.stopLivePlayback()
        })
        liveEventObservers.append(NotificationCenter.default.addObserver(
            forName: AVPlayerItem.failedToPlayToEndTimeNotification,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Logger.shared.log("Live Photo playback failed")
            self?.stopLivePlayback()
        })
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }

        // Light-gray background (matches the container).
        NSColor(white: 0.92, alpha: 1).setFill()
        bounds.fill()

        guard let size = drawnSize(), let context = NSGraphicsContext.current else { return }
        let rect = NSRect(origin: imageOrigin, size: size)

        // Clip to the view so a zoomed/panned image never overdraws the status bar.
        context.saveGraphicsState()
        bounds.clip()

        // Nearest-neighbor at ~1:1 and above (crisp pixels), smooth when downscaled.
        let hints: [NSImageRep.HintKey: Any] = [
            .interpolation: zoomScale >= 0.95 ? NSImageInterpolation.none : NSImageInterpolation.high
        ]

        // Crossfade: the outgoing image fades out while the new one fades in.
        if let previous = fadePreviousImage {
            drawFitted(previous, in: rect, fraction: max(0, 1 - fadeProgress))
            image.draw(in: rect, from: .zero, operation: .sourceOver,
                       fraction: min(1, fadeProgress), respectFlipped: false, hints: hints)
        } else {
            image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0, respectFlipped: false, hints: hints)
        }

        context.restoreGraphicsState()
    }

    // MARK: - Coordinate mapping (used by the crop overlay)

    /// Pixel dimensions of the current image in CGImage conventions
    /// (origin top-left, y down) — same space as `CGImage.cropping(to:)`.
    var cgPixelSize: NSSize? {
        return imagePixelSize()
    }

    /// Convert an image-pixel rect (CG coords, y from the TOP) to this view's
    /// coordinates (non-flipped, y up).
    func viewRect(forPixelRect r: CGRect) -> NSRect {
        guard let psize = cgPixelSize else { return .zero }
        let x = imageOrigin.x + r.minX * zoomScale
        // r.maxY is the distance of the rect's BOTTOM edge from the image top;
        // the view-space y of that edge is measured from the image bottom.
        let yView = imageOrigin.y + (psize.height - r.maxY) * zoomScale
        return NSRect(x: x, y: yView, width: r.width * zoomScale, height: r.height * zoomScale)
    }

    /// Convert a point in this view's coordinates to an image-pixel point
    /// (CG coords, y from the TOP).
    func pixelPoint(forViewPoint p: NSPoint) -> CGPoint {
        guard let psize = cgPixelSize else { return .zero }
        let x = (p.x - imageOrigin.x) / zoomScale
        let yTop = psize.height - (p.y - imageOrigin.y) / zoomScale
        return CGPoint(x: x, y: yTop)
    }

    // MARK: - Context menu (right-click)

    /// Set by the host to supply the right-click context menu.
    var contextMenuProvider: (() -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        return contextMenuProvider?()
    }
}
