import SwiftUI
import AppKit

/// A SwiftUI view that displays an NSImage using NSViewRepresentable.
struct ImageDisplayView: NSViewRepresentable {
    let nsImage: NSImage

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = nsImage
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        nsView.image = nsImage
    }
}
