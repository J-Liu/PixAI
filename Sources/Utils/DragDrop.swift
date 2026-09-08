import AppKit

/// Shared drag-and-drop helpers for accepting image files and folders.
enum DragDropHelper {
    /// All pasteboard types we accept (file URLs, folder URLs, common image types).
    static let draggedTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        NSPasteboard.PasteboardType("NSFilenamesPboardType"),
        NSPasteboard.PasteboardType("public.folder"),
        NSPasteboard.PasteboardType("public.image"),
        NSPasteboard.PasteboardType("public.png"),
        NSPasteboard.PasteboardType("public.jpeg"),
        NSPasteboard.PasteboardType("com.compuserve.gif"),
        NSPasteboard.PasteboardType("public.tiff"),
        NSPasteboard.PasteboardType("com.microsoft.bmp"),
        NSPasteboard.PasteboardType("public.heic"),
    ]
    
    /// Extract existing file/folder URLs from a drag pasteboard, trying several methods.
    static func extractURLs(from pasteboard: NSPasteboard) -> [URL] {
        var urls: [URL] = []
        
        // Method 1: modern URL reading API (works for Finder file/folder drags).
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        if let objects = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [NSURL] {
            urls = objects.map { $0 as URL }
        }
        
        // Method 2: legacy NSFilenamesPboardType property list.
        if urls.isEmpty, let fileURLs = pasteboard.propertyList(forType: .init("NSFilenamesPboardType")) as? [String] {
            urls = fileURLs.map { URL(fileURLWithPath: $0) }
        }
        
        // Method 3: string-based paths.
        if urls.isEmpty {
            for type in pasteboard.types ?? [] {
                if let string = pasteboard.string(forType: type) {
                    urls.append(URL(fileURLWithPath: string))
                }
            }
        }
        
        // Method 4: raw data URL representations.
        if urls.isEmpty {
            for type in pasteboard.types ?? [] {
                if let data = pasteboard.data(forType: type),
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    urls.append(url)
                }
            }
        }
        
        return urls.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
