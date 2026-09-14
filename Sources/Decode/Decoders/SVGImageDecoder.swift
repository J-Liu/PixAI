// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit
import Foundation
import WebKit

/// Decodes SVG documents.
///
/// Primary path: `NSImage(data:)` — recent macOS builds ship a native SVG
/// image rep (`_NSSVGImageRep`) that renders the document on demand and keeps
/// transparency. On systems without built-in SVG support it returns nil, and
/// the fallback renders the markup through an offscreen WKWebView (main-actor
/// bound) snapshotted at the document's intrinsic size.
final class SVGImageDecoder: ImageDecoder {
    let name = "svg"
    let supportedFormats: Set<ImageFormat> = [.svg]

    /// Clamp for the fallback render size (points) so a pathological SVG
    /// cannot allocate gigabytes of bitmap.
    private static let maxRenderSide: CGFloat = 8192
    private static let minRenderSide: CGFloat = 64
    private static let defaultRenderSide: CGFloat = 1024

    func canDecode(_ format: ImageFormat) -> Bool {
        return format == .svg
    }

    func decode(data: Data, url: URL?, format: ImageFormat) async throws -> DecodedImage {
        guard let html = String(data: data, encoding: .utf8), !html.isEmpty else {
            throw DecodeError.decodeFailed("SVGImageDecoder: not valid UTF-8 text")
        }

        // 1. Native NSImage SVG rep (macOS builds with built-in SVG support).
        if let image = NSImage(data: data), !image.representations.isEmpty {
            return DecodedImage(image: image, format: .svg,
                                pixelSize: image.decodedPixelSize, companionVideoURL: nil)
        }

        // 2. WebKit offscreen snapshot (main-actor bound).
        let size = Self.intrinsicSize(of: html)
        guard let cgImage = await WKSVGRenderer().render(html: html, size: size) else {
            throw DecodeError.decodeFailed("SVGImageDecoder: WebKit failed to render SVG")
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return DecodedImage(image: image, format: .svg,
                            pixelSize: NSSize(width: cgImage.width, height: cgImage.height),
                            companionVideoURL: nil)
    }

    // MARK: - Intrinsic size

    /// Intrinsic render size of an SVG document: explicit width/height on the
    /// root `<svg>` element, else viewBox dimensions, else 1024×1024.
    static func intrinsicSize(of svgText: String) -> NSSize {
        // Isolate the root <svg ...> tag.
        guard let openRange = svgText.range(of: "<svg", options: .caseInsensitive) else {
            return NSSize(width: defaultRenderSide, height: defaultRenderSide)
        }
        let afterOpen = svgText[openRange.upperBound...]
        let tagEnd = afterOpen.firstIndex(of: ">") ?? afterOpen.endIndex
        let tag = String(afterOpen[afterOpen.startIndex..<tagEnd])

        func attrValue(_ name: String) -> String? {
            guard let regex = try? NSRegularExpression(
                pattern: "\(name)\\s*=\\s*[\"']([^\"']+)[\"']", options: [.caseInsensitive]
            ) else { return nil }
            let nsTag = tag as NSString
            guard let match = regex.firstMatch(in: tag, options: [],
                                               range: NSRange(location: 0, length: nsTag.length)) else {
                return nil
            }
            return nsTag.substring(with: match.range(at: 1))
        }

        func numeric(_ value: String?) -> CGFloat? {
            guard let value = value else { return nil }
            let cleaned = value
                .replacingOccurrences(of: "px", with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespaces)
            guard let d = Double(cleaned), d.isFinite, d > 0 else { return nil }
            return CGFloat(d)
        }

        var width = numeric(attrValue("width"))
        var height = numeric(attrValue("height"))

        if (width == nil || height == nil), let viewBox = attrValue("viewBox") {
            let parts = viewBox
                .split { $0 == "," || $0 == " " }
                .compactMap { Double($0) }
            if parts.count == 4 {
                width = width ?? CGFloat(parts[2])
                height = height ?? CGFloat(parts[3])
            }
        }

        return NSSize(width: clampSide(width), height: clampSide(height))
    }

    private static func clampSide(_ side: CGFloat?) -> CGFloat {
        guard let side = side, side.isFinite, side > 0 else {
            return defaultRenderSide
        }
        return min(maxRenderSide, max(minRenderSide, side))
    }
}

// MARK: - WebKit fallback renderer (main-actor bound)

/// Offscreen WKWebView used to rasterize SVGs on systems without a native SVG
/// image rep. All WKWebView access happens on the main actor; the load and
/// snapshot steps are bridged with continuations.
@MainActor
private final class WKSVGRenderer: NSObject, WKNavigationDelegate {
    private var loadContinuation: CheckedContinuation<Bool, Never>?

    /// Render `html` into a CGImage at `size` (points), or nil on failure.
    func render(html: String, size: NSSize) async -> CGImage? {
        let webview = WKWebView(
            frame: NSRect(origin: .zero, size: size),
            configuration: WKWebViewConfiguration()
        )
        webview.navigationDelegate = self

        // Keep the page background transparent so the snapshot preserves the
        // SVG's alpha channel.
        let page = "<style>html,body{background:transparent !important;}</style>" + html

        let loaded = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            loadContinuation = continuation
            webview.loadHTMLString(page, baseURL: nil)
        }
        guard loaded else { return nil }

        let snapshot = await withCheckedContinuation { (continuation: CheckedContinuation<NSImage?, Never>) in
            webview.takeSnapshot(with: nil) { image, _ in
                continuation.resume(returning: image)
            }
        }
        return snapshot?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    // MARK: WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            loadContinuation?.resume(returning: true)
            loadContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            loadContinuation?.resume(returning: false)
            loadContinuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            loadContinuation?.resume(returning: false)
            loadContinuation = nil
        }
    }
}
