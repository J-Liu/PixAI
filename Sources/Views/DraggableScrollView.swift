import AppKit
import UniformTypeIdentifiers

/// A scroll view that accepts drag-and-drop of image files and folders.
class DraggableScrollView: NSScrollView {
    private let onDrop: ([URL]) -> Void
    
    init(onDrop: @escaping ([URL]) -> Void) {
        self.onDrop = onDrop
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        // Enable the scroll view to receive drag events.
        registerForDraggedTypes([
            NSPasteboard.PasteboardType("NSFilenamesPboardType"),
            NSPasteboard.PasteboardType("public.png"),
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("com.compuserve.gif"),
            NSPasteboard.PasteboardType("public.tiff"),
            NSPasteboard.PasteboardType("com.microsoft.bmp"),
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("public.image"),
            NSPasteboard.PasteboardType("public.folder"),
            NSPasteboard.PasteboardType("public.file-url"),
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var acceptsFirstResponder: Bool {
        return false
    }
    
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pasteboard = sender.draggingPasteboard
        if let types = pasteboard.types, !types.isEmpty {
            return .copy
        }
        return []
    }
    
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }
    
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        var urls: [URL] = []
        
        // Method 1: NSFilenamesPboardType (standard macOS drag type).
        if let fileURLs = pasteboard.propertyList(forType: .init("NSFilenamesPboardType")) as? [String] {
            urls = fileURLs.compactMap { path in
                let url = URL(fileURLWithPath: path)
                return FileManager.default.fileExists(atPath: url.path) ? url : nil
            }
        }
        
        // Method 2: Try individual image types as file URLs.
        if urls.isEmpty {
            for type in pasteboard.types ?? [] {
                if let string = pasteboard.string(forType: type) {
                    let url = URL(fileURLWithPath: string, isDirectory: false)
                    if FileManager.default.fileExists(atPath: url.path) {
                        urls.append(url)
                    }
                }
            }
        }
        
        // Method 3: Try from data.
        if urls.isEmpty {
            for type in pasteboard.types ?? [] {
                if let data = pasteboard.data(forType: type),
                   let url = URL(dataRepresentation: data, relativeTo: nil) {
                    if FileManager.default.fileExists(atPath: url.path) {
                        urls.append(url)
                    }
                }
            }
        }
        
        if !urls.isEmpty {
            onDrop(urls)
        }
        
        return true
    }
}
