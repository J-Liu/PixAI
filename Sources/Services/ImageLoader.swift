import AppKit
import UniformTypeIdentifiers

/// Protocol for loading images from URLs.
/// Each concrete loader handles specific file formats.
protocol ImageLoader {
    /// Whether this loader can handle the given URL based on its extension or content type.
    func canLoad(url: URL) -> Bool
    
    /// Load an image from the given URL.
    /// Returns nil if loading fails or the format is not supported.
    func loadImage(from url: URL) -> NSImage?
}

/// Abstracts image loading into a single entry point that dispatches to
/// the appropriate concrete loader based on file extension.
class ImageLoaderRegistry {
    private var loaders: [ImageLoader] = []
    
    static let shared = ImageLoaderRegistry()
    
    private init() {
        // Register all supported loaders in priority order (more specific first)
        loaders.append(HEICImageLoader())
        loaders.append(WebPImageLoader())   // macOS 15+ native
        loaders.append(SVGImageLoader())
        loaders.append(PDFImageLoader())
        loaders.append(GenericImageLoader()) // Fallback for PNG, JPEG, GIF, BMP, TIFF
    }
    
    func loadImage(from url: URL) -> NSImage? {
        for loader in loaders {
            if loader.canLoad(url: url) {
                return loader.loadImage(from: url)
            }
        }
        // Last resort: try generic loader
        return GenericImageLoader().loadImage(from: url)
    }
}

// MARK: - Generic Image Loader (PNG, JPEG, GIF, BMP, TIFF)
/// Loads images using NSImage(data:) which supports PNG, JPEG, GIF, BMP, TIFF natively.
class GenericImageLoader: ImageLoader {
    private let supportedExtensions = ["png", "jpg", "jpeg", "gif", "bmp", "tiff"]
    
    func canLoad(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return supportedExtensions.contains(ext) || ext.isEmpty
    }
    
    func loadImage(from url: URL) -> NSImage? {
        do {
            let data = try Data(contentsOf: url)
            // Try NSImage first (supports PNG, JPEG, GIF, BMP, TIFF)
            if let nsImage = NSImage(data: data) {
                return nsImage
            }
            // Fallback: try to detect image format from data
            return nil
        } catch {
            Logger.shared.log("GenericImageLoader failed for \(url): \(error)")
            return nil
        }
    }
}

// MARK: - HEIC Image Loader
/// Loads HEIC images using NSImage(data:) which supports HEIC on macOS.
class HEICImageLoader: ImageLoader {
    func canLoad(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "heic" || ext == "heif"
    }
    
    func loadImage(from url: URL) -> NSImage? {
        do {
            let data = try Data(contentsOf: url)
            if let nsImage = NSImage(data: data) {
                return nsImage
            }
            // Fallback: try using CGImageSource for HEIC
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return nil
            }
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return nil
            }
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            Logger.shared.log("HEICImageLoader failed for \(url): \(error)")
            return nil
        }
    }
}

// MARK: - WebP Image Loader
/// Loads WebP images. On macOS 15+, NSImage supports WebP natively.
/// On earlier versions, returns nil (future implementation needed).
class WebPImageLoader: ImageLoader {
    func canLoad(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "webp"
    }
    
    func loadImage(from url: URL) -> NSImage? {
        #if canImport(UniformTypeIdentifiers)
        // Check if we're on macOS 15+ (WebP support added in macOS 15 Sequoia)
        if #available(macOS 15.0, *) {
            do {
                let data = try Data(contentsOf: url)
                return NSImage(data: data)
            } catch {
                Logger.shared.log("WebPImageLoader failed for \(url): \(error)")
                return nil
            }
        } else {
            // Not supported on this macOS version — try CGImageSource with a WebP plugin
            // This is a placeholder; actual WebP decoding requires a third-party library
            Logger.shared.log("WebP not supported on macOS < 15: \(url)")
            return nil
        }
        #else
        return nil
        #endif
    }
}

// MARK: - SVG Image Loader
/// Loads SVG files by rendering them to a bitmap image.
class SVGImageLoader: ImageLoader {
    func canLoad(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "svg"
    }
    
    func loadImage(from url: URL) -> NSImage? {
        do {
            let data = try Data(contentsOf: url)
            // Try using CGImageSource with SVG MIME type
            if let source = CGImageSourceCreateWithData(data as CFData, [
                kCGImageSourceTypeIdentifierHint: "public.svg-image"
            ] as CFDictionary) {
                guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    return nil
                }
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            }
            
            // Fallback: use NSBitmapImageRep from data (may not work for all SVGs)
            if let bitmapRep = NSBitmapImageRep(data: data) {
                let nsImage = NSImage()
                nsImage.addRepresentation(bitmapRep)
                return nsImage
            }
            
            Logger.shared.log("SVGImageLoader failed to decode SVG: \(url)")
            return nil
        } catch {
            Logger.shared.log("SVGImageLoader failed for \(url): \(error)")
            return nil
        }
    }
}

// MARK: - PDF Image Loader
/// Loads PDF files by rendering the first page as an image.
class PDFImageLoader: ImageLoader {
    func canLoad(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "pdf"
    }
    
    func loadImage(from url: URL) -> NSImage? {
        do {
            let data = try Data(contentsOf: url)
            // Create a CGDataProvider from the data
            guard let provider = CGDataProvider(data: data as CFData) else {
                Logger.shared.log("PDFImageLoader failed to create data provider")
                return nil
            }
            guard let document = CGPDFDocument(provider) else {
                Logger.shared.log("PDFImageLoader failed to create PDF document")
                return nil
            }
            
            guard let page = document.page(at: 1) else {
                Logger.shared.log("PDFImageLoader failed to get first page")
                return nil
            }
            
            let pageRect = page.getBoxRect(.mediaBox)
            let scale: CGFloat = 2.0 // Render at 2x for better quality
            
            // Create a graphics context
            let width = Int(pageRect.width * scale)
            let height = Int(pageRect.height * scale)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            ) else {
                Logger.shared.log("PDFImageLoader failed to create graphics context")
                return nil
            }
            
            // Scale and translate the context
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: 0, y: pageRect.height)
            context.concatenate(page.getDrawingTransform(.mediaBox, rect: pageRect, rotate: 0, preserveAspectRatio: true))
            
            // Draw the page
            context.drawPDFPage(page)
            
            // Create image from context
            guard let cgImage = context.makeImage() else {
                Logger.shared.log("PDFImageLoader failed to create CGImage")
                return nil
            }
            
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            return nsImage
            
        } catch {
            Logger.shared.log("PDFImageLoader failed for \(url): \(error)")
            return nil
        }
    }
}
