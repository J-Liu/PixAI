// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation
import AppKit

/// Extensions that are treated as photo/image files for automatic scanning.
let photoExtensions = [
    "png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "heif", "webp",
    // Camera RAW (decoded via Core Image)
    "cr2", "cr3", "nef", "nrw", "arw", "sr2", "dng", "rw2", "srw", "orf", "raf", "x3f"
]

/// All supported extensions (including document formats like SVG/PDF).
let supportedExtensions = photoExtensions + ["svg", "pdf"]

/// Scans files and directories to find supported image files.
class FileScanner {
    /// Scan a list of URLs (files or directories), return only supported image files.
    static func scan(urls: [URL]) -> [URL] {
        var results: [URL] = []

        for url in urls {
            do {
                let resourceValues = try url.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues.isDirectory == true {
                    // Directory: recursively scan
                    let directoryContents = try FileManager.default.contentsOfDirectory(
                        at: url,
                        includingPropertiesForKeys: nil,
                        options: .skipsHiddenFiles
                    )

                    for item in directoryContents {
                        let itemResourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey])
                        if itemResourceValues?.isDirectory == true {
                            // Recursively scan subdirectories
                            let nested = scan(urls: [item])
                            results.append(contentsOf: nested)
                        } else {
                            // File: known photo extensions match directly; files
                            // without an extension are identified by magic numbers.
                            let ext = item.pathExtension.lowercased()
                            if !ext.isEmpty && photoExtensions.contains(ext) {
                                results.append(item)
                            } else if ext.isEmpty, DecoderManager.shared.isSupportedImage(at: item) {
                                results.append(item)
                            }
                        }
                    }
                } else {
                    // File: known extensions match directly; anything else is
                    // identified by magic-number detection on the header bytes.
                    let ext = url.pathExtension.lowercased()
                    if !ext.isEmpty && supportedExtensions.contains(ext) {
                        results.append(url)
                    } else if DecoderManager.shared.isSupportedImage(at: url) {
                        results.append(url)
                    }
                }
            } catch {
                // Skip files that can't be accessed
                continue
            }
        }

        return results.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}
