import AppKit
import Foundation

/// Renders the first page of a PDF document as an image (2× for quality).
final class PDFImageDecoder: ImageDecoder {
    let name = "pdf"
    let supportedFormats: Set<ImageFormat> = [.pdf]

    func canDecode(_ format: ImageFormat) -> Bool {
        return format == .pdf
    }

    func decode(data: Data, url: URL?, format: ImageFormat) async throws -> DecodedImage {
        guard let provider = CGDataProvider(data: data as CFData),
              let document = CGPDFDocument(provider) else {
            throw DecodeError.decodeFailed("PDFImageDecoder: not a valid PDF document")
        }
        guard let page = document.page(at: 1) else {
            throw DecodeError.decodeFailed("PDFImageDecoder: PDF has no pages")
        }

        let pageRect = page.getBoxRect(.mediaBox)
        let scale: CGFloat = 2.0 // Render at 2x for better quality.
        let width = max(1, Int(pageRect.width * scale))
        let height = max(1, Int(pageRect.height * scale))

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else {
            throw DecodeError.decodeFailed("PDFImageDecoder: cannot create bitmap context")
        }

        // Scale and translate the context, then draw the page.
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: pageRect.height)
        context.concatenate(page.getDrawingTransform(.mediaBox, rect: pageRect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)

        guard let cgImage = context.makeImage() else {
            throw DecodeError.decodeFailed("PDFImageDecoder: rendering produced no image")
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        return DecodedImage(image: image, format: .pdf,
                            pixelSize: NSSize(width: cgImage.width, height: cgImage.height),
                            companionVideoURL: nil)
    }
}
