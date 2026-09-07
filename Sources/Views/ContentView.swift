import SwiftUI
import AppKit

/// The main content view. Displays images loaded from command-line arguments or dropped files.
struct ContentView: View {
    /// Paths passed from command-line arguments (files or folders).
    let paths: [String]

    @StateObject private var viewModel = ImageListViewModel()

    var body: some View {
        VStack(spacing: 0) {
            // Main image display area
            ZStack {
                if let currentImage = viewModel.currentImage {
                    ImageDisplayView(nsImage: currentImage)
                        .onTapGesture(count: 1) {
                            // Single click — do nothing for now
                        }
                } else if viewModel.isLoading {
                    // Loading indicator
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding(.bottom, 8)
                        Text("Loading...")
                            .foregroundColor(.secondary)
                    }
                } else if viewModel.images.isEmpty {
                    // Empty state
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 64))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.secondary)

                        Text("Drop images or use command line")
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(minWidth: 400, minHeight: 300)
            .background(Color(NSColor.windowBackgroundColor))

            // Status bar at the bottom
            HStack {
                // File name
                Text(viewModel.images.isEmpty ? "No images" : viewModel.images[viewModel.currentIndex].filename)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()

                // Image dimensions
                if let metadata = viewModel.currentMetadata {
                    Text("\(metadata.width)×\(metadata.height)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Status message (e.g. "→ First")
                if let statusBarMessage = viewModel.statusBarMessage {
                    Text(statusBarMessage)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.accentColor)
                } else {
                    Text("\(viewModel.currentIndex + 1)/\(viewModel.images.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(8)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.9))
        }
        .onAppear {
            // Load images from command-line paths
            let urlPaths = paths.compactMap { URL(fileURLWithPath: $0) }
            if !urlPaths.isEmpty {
                viewModel.loadImages(from: urlPaths)
            }
        }
        .onDrop(of: ["public.image", "public.folder"], isTargeted: nil) { providers in
            // Handle drag-and-drop
            let fileURLs = providers.compactMap { (provider: NSItemProvider) -> URL? in
                var url: URL?
                let semaphore = DispatchSemaphore(value: 0)
                provider.loadFileRepresentation(forTypeIdentifier: "public.image") { (fileURL: URL?, error: Error?) in
                    if let fileURL = fileURL {
                        url = fileURL
                    }
                    semaphore.signal()
                }
                _ = semaphore.wait(timeout: .now() + 1.0)
                return url
            }

            // Also handle dropped folders
            let folderURLs = providers.compactMap { (provider: NSItemProvider) -> URL? in
                var url: URL?
                let semaphore = DispatchSemaphore(value: 0)
                provider.loadFileRepresentation(forTypeIdentifier: "public.folder") { (fileURL: URL?, error: Error?) in
                    if let fileURL = fileURL {
                        url = fileURL
                    }
                    semaphore.signal()
                }
                _ = semaphore.wait(timeout: .now() + 1.0)
                return url
            }

            let allURLs = fileURLs + folderURLs
            if !allURLs.isEmpty {
                viewModel.loadImages(from: allURLs)
            }
            return true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            // Clean up on exit
        }
    }

    /// Handle keyboard events for navigation.
    private func handleKeypress(_ event: NSEvent) {
        switch event.keyCode {
        case 123: // Left arrow
            viewModel.goPrev()
        case 124: // Right arrow
            viewModel.goNext()
        default:
            break
        }
    }
}

/// A view modifier that intercepts keyDown events for custom navigation.
struct KeyDownModifier: ViewModifier {
    let onKeyPress: (NSEvent) -> Void

    func body(content: Content) -> some View {
        content
            .background(
                KeyboardListener(onKeyPress: onKeyPress)
                    .frame(width: 0, height: 0)
            )
    }
}

/// A SwiftUI view that listens for keyDown events.
struct KeyboardListener: NSViewRepresentable {
    let onKeyPress: (NSEvent) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = .clear
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // No-op
    }
}
