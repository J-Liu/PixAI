import Foundation
import AppKit
import Combine

/// Main view model for the image list.
@MainActor
class ImageListViewModel: ObservableObject {
    @Published var images: [ImageInfo] = []
    @Published var currentIndex: Int = 0
    @Published var currentImage: NSImage?
    @Published var isLoading: Bool = false
    @Published var currentMetadata: ImageMetadata?
    @Published var statusBarMessage: String?

    private let imageLoader = ImageLoader()
    private var cancellables = Set<AnyCancellable>()

    /// Load images from a list of URLs (files and/or directories).
    func loadImages(from urls: [URL]) {
        let scanned = FileScanner.scan(urls: urls)
        images = scanned.map { url in
            ImageInfo(id: url.absoluteString, url: url)
        }
        currentIndex = 0

        // Load the first image
        if !images.isEmpty {
            loadCurrentImage()
        }
    }

    /// Go to the next image (circular).
    func goNext() {
        guard !images.isEmpty else { return }
        currentIndex = (currentIndex + 1) % images.count
        loadCurrentImage()
        showStatusMessage("→ \(currentIndex == 0 ? "First" : "\(currentIndex + 1)/\(images.count)")")
    }

    /// Go to the previous image (circular).
    func goPrev() {
        guard !images.isEmpty else { return }
        currentIndex = (currentIndex - 1 + images.count) % images.count
        loadCurrentImage()
        showStatusMessage("← \(currentIndex == 0 ? "First" : "\(currentIndex + 1)/\(images.count)")")
    }

    /// Go to a specific index.
    func goTo(index: Int) {
        guard !images.isEmpty, index >= 0, index < images.count else { return }
        currentIndex = index
        loadCurrentImage()
    }

    /// Load the image at the current index.
    func loadCurrentImage() {
        guard !images.isEmpty else { return }
        isLoading = true
        let url = images[currentIndex].url

        Task {
            let image = await imageLoader.load(url: url)
            let metadata = await fetchMetadata(for: url)
            self.currentImage = image
            self.currentMetadata = metadata
            self.isLoading = false
        }
    }

    /// Fetch metadata for an image.
    private func fetchMetadata(for url: URL) async -> ImageMetadata? {
        do {
            let data = try Data(contentsOf: url)
            return try ImageDecoderManager.shared.metadata(from: data)
        } catch {
            print("Failed to extract metadata from \(url): \(error)")
            return nil
        }
    }

    /// Show a status bar message that auto-clears after 2 seconds.
    private func showStatusMessage(_ message: String) {
        statusBarMessage = message
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.statusBarMessage = nil
            }
        }
    }
}
