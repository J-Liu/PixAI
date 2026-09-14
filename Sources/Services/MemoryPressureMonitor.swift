// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

/// Watches system memory pressure and clears the shared image cache when the
/// OS signals a memory warning.
///
/// macOS has no direct equivalent of iOS's
/// `UIApplication.didReceiveMemoryWarningNotification`; per Apple's documentation
/// the documented mechanism on AppKit is a Dispatch memory-pressure source
/// (`DispatchSource.makeMemoryPressureSource(eventMask:queue:)`) reacting to
/// the `.warning` / `.critical` events (DISPATCH_MEMORYPRESSURE_WARN /
/// DISPATCH_MEMORYPRESSURE_CRITICAL).
final class MemoryPressureMonitor {
    static let shared = MemoryPressureMonitor()

    private var source: DispatchSourceMemoryPressure?

    private init() {}

    /// Install the handler. Idempotent; call once at launch.
    func start() {
        guard source == nil else { return }
        let src = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        src.setEventHandler { [weak self] in
            guard let self, let event = self.source?.data else { return }
            Logger.shared.log("Memory pressure \(event.contains(.critical) ? "CRITICAL" : "warning") — clearing image cache")
            ImageCache.shared.removeAll()
        }
        src.activate()
        source = src
    }
}
