// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

/// Image formats PixAI can decode, as identified by the decode abstraction
/// layer. Detection prefers magic numbers (file header bytes) and falls back
/// to the file extension; Live Photo is always resolved BEFORE plain HEIC.
enum ImageFormat: String, CaseIterable {
    case jpeg
    case png
    case gif
    case bmp
    case tiff
    /// HEIF/HEIC still image without a Live Photo companion video.
    case heic
    /// Apple Live Photo: a HEIF/HEIC still with a same-basename companion
    /// .MOV in the same directory. Classified before `.heic` by design.
    case livePhoto
    case webp
    case svg
    case pdf
    /// Camera RAW (CR2/CR3, NEF/NRW, ARW/SR2, DNG, RW2, SRW, ORF, RAF, X3F, …)
    /// — decoded through Core Image.
    case raw
    case unknown

    /// Whether files of this format are displayable by the viewer.
    var isDisplayable: Bool {
        return self != .unknown
    }

    var displayName: String {
        switch self {
        case .jpeg:      return "JPEG"
        case .png:       return "PNG"
        case .gif:       return "GIF"
        case .bmp:       return "BMP"
        case .tiff:      return "TIFF"
        case .heic:      return "HEIC"
        case .livePhoto: return "Live Photo (HEIC)"
        case .webp:      return "WebP"
        case .svg:       return "SVG"
        case .pdf:       return "PDF"
        case .raw:       return "RAW"
        case .unknown:   return "Unknown"
        }
    }
}

/// File extensions that identify camera RAW files.
///
/// Most of these (CR2, CR3, NEF, NRW, ARW, SR2, DNG, RW2, SRW, PEF, RWL, ERF,
/// KDC, GPR) are TIFF-based and share the plain-TIFF magic number, so the
/// TIFF magic alone cannot distinguish them — the extension refines the
/// classification. ORF (RIFF container), RAF ("FUJIFILMCCD-RAW") and X3F have
/// distinct magics of their own.
let rawExtensions: Set<String> = [
    "cr2", "cr3", "nef", "nrw", "arw", "sr2", "dng", "rw2", "srw",
    "orf", "raf", "x3f", "pef", "rwl", "erf", "kdc", "gpr"
]
