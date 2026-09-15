// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Which AI transformation is currently applied (for display) to an image.
enum AIKind: String {
    case upscale
    case dewatermark
    case enhance
}

/// Per-image, per-window AI state. Each transform result is derived from the
/// ORIGINAL base image (never chained), so toggling back and forth never
/// degrades quality. At most one transform is displayed at a time: the most
/// recently applied one (`lastApplied`).
final class ImageAIState {
    /// 4x super-resolution result (Real-ESRGAN).
    var upscaledImage: NSImage?
    /// Watermark-removed result (U2Net + inpaint).
    var dewatermarkedImage: NSImage?
    /// CIAutoEnhance result.
    var enhancedImage: NSImage?

    /// Toggle flags (a transform is "on" when its flag is set).
    var isUpscaled = false
    var isDewatermarked = false
    var isEnhanced = false

    /// The transform currently shown (most recently applied wins).
    var lastApplied: AIKind?

    /// History of applied transforms (for Cmd+Z undo).
    private var appliedHistory: [AIKind] = []

    /// The image to display for the given kind, if computed.
    func image(for kind: AIKind) -> NSImage? {
        switch kind {
        case .upscale: return upscaledImage
        case .dewatermark: return dewatermarkedImage
        case .enhance: return enhancedImage
        }
    }

    /// The currently displayed transform, if any.
    var activeKind: AIKind? {
        guard let kind = lastApplied else { return nil }
        switch kind {
        case .upscale: return isUpscaled ? kind : nil
        case .dewatermark: return isDewatermarked ? kind : nil
        case .enhance: return isEnhanced ? kind : nil
        }
    }

    /// English title/status-bar mark for the active transform (spec wording).
    var activeMark: String? {
        switch activeKind {
        case .upscale: return "AI Super-Resolved"
        case .dewatermark: return "AI Watermark Removed"
        case .enhance: return "AI Enhanced"
        case nil: return nil
        }
    }

    /// Whether any transform has been computed (used to decide save behavior).
    var hasAnyResult: Bool {
        return isUpscaled || isDewatermarked || isEnhanced
    }

    /// Whether undo is possible.
    var canUndo: Bool {
        return !appliedHistory.isEmpty
    }

    /// Record that a transform was applied (for undo history).
    func recordApplied(_ kind: AIKind) {
        appliedHistory.append(kind)
    }

    /// Undo the most recently applied transform. Returns the kind that was undone, or nil.
    @discardableResult
    func undo() -> AIKind? {
        guard let last = appliedHistory.popLast() else { return nil }
        switch last {
        case .upscale: isUpscaled = false
        case .dewatermark: isDewatermarked = false
        case .enhance: isEnhanced = false
        }
        // Update lastApplied to the previous one in history
        lastApplied = appliedHistory.last
        return last
    }
}
