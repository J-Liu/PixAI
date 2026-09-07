import Foundation
import AppKit

/// Supported image file extensions (covers all formats handled by ImageLoaderRegistry).
let supportedExtensions = [
    "png", "jpg", "jpeg", "gif", "bmp", "tiff", "heic", "heif",
    "svg", "pdf", "webp"
]

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
                            // File: check extension
                            let ext = item.pathExtension.lowercased()
                            if !ext.isEmpty && supportedExtensions.contains(ext) {
                                results.append(item)
                            } else if ext.isEmpty {
                                // No extension - try to detect if it's an image using ImageLoaderRegistry
                                if let _ = ImageLoaderRegistry.shared.loadImage(from: item) {
                                    results.append(item)
                                }
                            }
                        }
                    }
                } else {
                    // File: check extension
                    let ext = url.pathExtension.lowercased()
                    if supportedExtensions.contains(ext) || ext.isEmpty {
                        // If no extension, try to detect using ImageLoaderRegistry
                        if ext.isEmpty {
                            if let _ = ImageLoaderRegistry.shared.loadImage(from: url) {
                                results.append(url)
                            }
                        } else {
                            results.append(url)
                        }
                    }
                }
            } catch {
                // Skip files that can't be accessed
                continue
            }
        }

        return results.sorted { $0.absoluteString < $1.absoluteString }
    }
}
