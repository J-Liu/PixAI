// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

/// Identifies image formats from file content.
///
/// Detection priority (per spec):
///   1. **Magic numbers** — the file header bytes are authoritative.
///   2. **Live Photo before HEIC** — a HEIF still (recognized by magic or by
///      a `.heic`/`.heif` extension) that has a same-basename companion .MOV
///      in the same directory is classified as `.livePhoto`, never `.heic`.
///   3. **Extension fallback** — used only when the magic number is
///      unrecognized (or no data was supplied).
enum MagicNumberDetector {

    // MARK: - Public API

    /// Detect the format of a file on disk by reading its header bytes only
    /// (no full-file load — cheap enough for directory scans).
    static func detect(url: URL) -> ImageFormat {
        let data = readHeader(of: url)
        return detect(data: data, url: url)
    }

    /// Detect the format of in-memory data. `url` (when available) supplies
    /// the extension fallback and the Live Photo companion check.
    static func detect(data: Data?, url: URL?) -> ImageFormat {
        if let data = data, !data.isEmpty, let magic = detectMagic(in: data, url: url) {
            return magic
        }
        return detectByExtension(url: url)
    }

    /// Synchronous, O(1) existence check for an Apple Live Photo companion
    /// .MOV (same base name, same directory). The UI's playback badge still
    /// verifies the MOV's QuickTime metadata asynchronously (LivePhotoDetector);
    /// this check only needs to classify the still's format.
    static func livePhotoCompanion(for imageURL: URL) -> URL? {
        let dir = imageURL.deletingLastPathComponent()
        let baseName = imageURL.deletingPathExtension().lastPathComponent
        guard !baseName.isEmpty else { return nil }
        for ext in ["mov", "MOV"] {
            let candidate = dir.appendingPathComponent(baseName + "." + ext)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    // MARK: - Magic numbers

    private static func detectMagic(in data: Data, url: URL?) -> ImageFormat? {
        func has(_ prefix: [UInt8], at offset: Int = 0) -> Bool {
            guard data.count >= offset + prefix.count else { return false }
            for (i, byte) in prefix.enumerated() where data[offset + i] != byte {
                return false
            }
            return true
        }
        func ascii(_ s: String, at offset: Int) -> Bool {
            has(Array(s.utf8), at: offset)
        }

        // PNG — 89 50 4E 47 0D 0A 1A 0A
        if has([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        // JPEG — FF D8 FF
        if has([0xFF, 0xD8, 0xFF]) { return .jpeg }
        // GIF — "GIF8"
        if ascii("GIF8", at: 0) { return .gif }
        // BMP — "BM"
        if has([0x42, 0x4D]) { return .bmp }
        // PDF — "%PDF-"
        if ascii("%PDF-", at: 0) { return .pdf }

        // RIFF container — WebP ("WEBP" @8) vs. Olympus ORF RAW ("ORF " @8).
        if ascii("RIFF", at: 0), data.count >= 12 {
            if ascii("WEBP", at: 8) { return .webp }
            if ascii("ORF", at: 8) { return .raw }
        }

        // ISO-BMFF (HEIF/HEIC) — "ftyp" @4, major brand @8.
        // Live Photo is resolved BEFORE plain HEIC (per spec).
        if ascii("ftyp", at: 4), data.count >= 12 {
            let brand = String(bytes: data[8..<12], encoding: .ascii)?.lowercased() ?? ""
            switch brand {
            case "heic", "heix", "hevc", "hevx", "mif1", "msf1", "heis":
                if let url = url, livePhotoCompanion(for: url) != nil { return .livePhoto }
                return .heic
            default:
                break // mp4/mov (qt, isom, …) and other BMFF containers
            }
        }

        // Fuji RAF — "FUJIFILMCCD-RAW"
        if ascii("FUJIFILMCCD-RAW", at: 0) { return .raw }
        // Sigma X3F — 00 C2 D4 9E
        if has([0x00, 0xC2, 0xD4, 0x9E]) { return .raw }

        // TIFF and TIFF-based camera RAWs — II* (little-endian) / MM* (big-endian).
        // The magic cannot distinguish RAW from plain TIFF; refine by extension.
        if has([0x49, 0x49, 0x2A, 0x00]) || has([0x4D, 0x4D, 0x00, 0x2A]) {
            if let url = url, rawExtensions.contains(url.pathExtension.lowercased()) {
                return .raw
            }
            return .tiff
        }

        // SVG — XML document containing an <svg> element (BOM/whitespace tolerated).
        if looksLikeSVG(data) { return .svg }

        return nil
    }

    private static func looksLikeSVG(_ data: Data) -> Bool {
        let limit = min(data.count, 1024)
        guard limit > 0 else { return false }
        let prefix = data[0..<limit]
        guard prefix.contains(0x3C) else { return false } // '<'
        for encoding in [String.Encoding.utf8, String.Encoding.utf16] {
            if let text = String(data: Data(prefix), encoding: encoding)?.lowercased(),
               text.contains("<svg") {
                return true
            }
        }
        return false
    }

    // MARK: - Extension fallback (Live Photo before HEIC)

    private static func detectByExtension(url: URL?) -> ImageFormat {
        guard let url = url else { return .unknown }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "heic", "heif":
            // Live Photo BEFORE the plain HEIC extension (per spec).
            if livePhotoCompanion(for: url) != nil { return .livePhoto }
            return .heic
        case "jpg", "jpeg":  return .jpeg
        case "png":          return .png
        case "gif":          return .gif
        case "bmp":          return .bmp
        case "tif", "tiff":  return .tiff
        case "webp":         return .webp
        case "svg":          return .svg
        case "pdf":          return .pdf
        default:
            if rawExtensions.contains(ext) { return .raw }
            return .unknown
        }
    }

    // MARK: - Header reading

    private static func readHeader(of url: URL, maxBytes: Int = 4096) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        return (try? handle.read(upToCount: maxBytes)) ?? Data()
    }
}
