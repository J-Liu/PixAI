import AppKit
import UniformTypeIdentifiers

/// A view that accepts drag-and-drop of image files and folders.
class DragDestinationView: NSView {
    private let onDrop: ([URL]) -> Void
    
    init(onDrop: @escaping ([URL]) -> Void) {
        self.onDrop = onDrop
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var acceptsFirstResponder: Bool {
        return false
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        Logger.shared.log("draggingEntered - types: \(pasteboard.types ?? [])")
        for type in pasteboard.types ?? [] {
            if type.rawValue.contains("image") || type.rawValue.contains("folder") || type.rawValue.contains("fileURL") {
                return .copy
            }
        }
        return []
    }
    
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        Logger.shared.log("performDragOperation - types: \(pasteboard.types ?? [])")
        var urls: [URL] = []
        
        // Method 1: Try to get file URLs using NSFilenamesPboardType (standard macOS drag type).
        let filenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        Logger.shared.log("Trying NSFilenamesPboardType (\(filenamesType.rawValue))")
        if let fileURLs = pasteboard.propertyList(forType: filenamesType) as? [String] {
            urls = fileURLs.compactMap { path in
                let url = URL(fileURLWithPath: path)
                if FileManager.default.fileExists(atPath: url.path) {
                    return url
                } else {
                    Logger.shared.log("File does NOT exist: \(url.path)")
                    return nil
                }
            }
            Logger.shared.log("Method 1: extracted \(urls.count) URLs from NSFilenamesPboardType")
        } else {
            Logger.shared.log("Method 1: failed to get property list for NSFilenamesPboardType")
        }
        
        // Method 2: Fallback — try to extract file paths from the pasteboard as strings.
        if urls.isEmpty {
            Logger.shared.log("Method 2: trying string extraction")
            for type in pasteboard.types ?? [] {
                if let string = pasteboard.string(forType: type) {
                    let url = URL(fileURLWithPath: string, isDirectory: false)
                    Logger.shared.log("   Found string URL: \(url)")
                    if FileManager.default.fileExists(atPath: url.path) {
                        urls.append(url)
                        Logger.shared.log("   File exists: \(url.path)")
                    } else {
                        Logger.shared.log("   File does NOT exist: \(url.path)")
                    }
                }
            }
        }
        
        // Method 3: Try to extract from the pasteboard data.
        if urls.isEmpty {
            Logger.shared.log("Method 3: trying data extraction")
            for type in pasteboard.types ?? [] {
                if let data = pasteboard.data(forType: type),
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    Logger.shared.log("   Data URL: \(url)")
                    if FileManager.default.fileExists(atPath: url.path) {
                        urls.append(url)
                        Logger.shared.log("   File exists: \(url.path)")
                    } else {
                        Logger.shared.log("   File does NOT exist: \(url.path)")
                    }
                }
            }
        }
        
        Logger.shared.log("Final extracted URLs: \(urls.map { $0.absoluteString })")
        if !urls.isEmpty {
            onDrop(urls)
        } else {
            Logger.shared.log("ERROR: No valid URLs extracted from drag operation!")
        }
        
        return true
    }
}
