// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation
import IOKit.pwr_mgt

/// Manages a power assertion to prevent system sleep and display idle.
/// Used during fullscreen slideshow playback to keep the system awake.
final class PowerAssertion {
    static let shared = PowerAssertion()

    private var assertionID: IOPMAssertionID = 0
    private var isActive = false
    private let lock = NSLock()

    private init() {}

    /// Enable the power assertion (prevent sleep and display idle).
    /// Safe to call multiple times; only creates one assertion.
    func enable(reason: String = "Slideshow playback") {
        lock.lock()
        defer { lock.unlock() }

        guard !isActive else { return }

        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &assertionID
        )

        if result == kIOReturnSuccess {
            isActive = true
            Logger.shared.log("PowerAssertion: enabled (\(reason))")
        } else {
            Logger.shared.log("PowerAssertion: failed to enable (error: \(result))")
        }
    }

    /// Disable the power assertion.
    /// Safe to call when not active.
    func disable() {
        lock.lock()
        defer { lock.unlock() }

        guard isActive else { return }

        let result = IOPMAssertionRelease(assertionID)
        if result == kIOReturnSuccess {
            isActive = false
            Logger.shared.log("PowerAssertion: disabled")
        } else {
            Logger.shared.log("PowerAssertion: failed to disable (error: \(result))")
        }
    }

    deinit {
        if isActive {
            IOPMAssertionRelease(assertionID)
        }
    }
}
