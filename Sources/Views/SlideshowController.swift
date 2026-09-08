import Foundation

/// Drives slideshow playback (timer + play state) for one viewer window.
///
/// The controller only owns the countdown; the owning window decides what
/// happens on each tick (advance to the next image or finish at the last one).
/// All methods must be called on the main thread.
final class SlideshowController {
    enum State {
        case stopped
        case playing
        case paused
    }

    /// Seconds shown per slide. Default 3; will later be overridable from a
    /// config file / settings UI (set before starting the slideshow).
    var interval: TimeInterval = 3.0

    private(set) var state: State = .stopped

    /// Called on the main thread after a full interval elapses while playing.
    var onTick: (() -> Void)?

    private var timer: Timer?

    /// True while playing or paused (the slideshow has been started but not exited).
    var isActive: Bool { state != .stopped }
    var isPlaying: Bool { state == .playing }

    /// Start playback (no-op if already active).
    func start() {
        guard !isActive else { return }
        state = .playing
        scheduleTick()
    }

    /// Pause playback (no-op unless playing).
    func pause() {
        guard isPlaying else { return }
        cancelTimer()
        state = .paused
    }

    /// Resume playback after a pause (no-op unless paused).
    func resume() {
        guard state == .paused else { return }
        state = .playing
        scheduleTick()
    }

    /// Restart the countdown from now. Used after a manual jump (arrow keys)
    /// so the newly shown image gets a full interval before advancing.
    func restartCountdown() {
        guard isPlaying else { return }
        cancelTimer()
        scheduleTick()
    }

    /// Stop playback and drop back to the stopped state.
    func stop() {
        guard isActive else { return }
        cancelTimer()
        state = .stopped
    }

    private func cancelTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleTick() {
        let t = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            self?.onTick?()
        }
        // .common mode keeps the tick firing while the run loop is busy with
        // event tracking (mouse down, menu tracking, ...).
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}
