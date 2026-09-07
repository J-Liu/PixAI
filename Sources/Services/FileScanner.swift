import Foundation

/// Scans files and directories to find supported image files.
class FileScanner {
    /// Scan a list of URLs (files or directories), return only supported image files.
    static func scan(urls: [URL]) -> [URL] {
        let supportedExtensions = ImageDecoderManager.shared.supportedExtensions()
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
                        let itemResourceValues = try? item.resourceValues(
                            forKeys: [.isDirectoryKey]
                        )
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
                                // No extension - try to detect if it's an image
                                if let data = try? Data(contentsOf: item),
                                   ImageIODecoder.canDecode(data) {
                                    results.append(item)
                                }
                            }
                        }
                    }
                } else {
                    // File: check extension
                    let ext = url.pathExtension.lowercased()
                    if supportedExtensions.contains(ext) || ext.isEmpty {
                        // If no extension, try to detect
                        if ext.isEmpty {
                            if let data = try? Data(contentsOf: url),
                               ImageIODecoder.canDecode(data) {
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
