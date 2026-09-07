import SwiftUI
import AppKit

/// The main content view. Displays an empty state when no images are loaded,
/// or shows the image(s) passed from the command line.
struct ContentView: View {
    /// Paths passed from command-line arguments (files or folders).
    let paths: [String]

    var body: some View {
        ZStack {
            // Background color matching macOS window style
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()

            if paths.isEmpty {
                // Empty state — centered text with drop hint
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 64))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundColor(.secondary)

                    Text("Drop images or use command line")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
            } else {
                // Show the first path's content (placeholder for now).
                // In a future version this would render the image.
                VStack(spacing: 12) {
                    Image(systemName: "photo")
                        .font(.system(size: 48))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.secondary, .primary)

                    Text("Loading: \(paths[0])")
                        .font(.body)
                        .foregroundColor(.secondary)

                    // Show all paths as a list
                    List(paths, id: \.self) { path in
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.accentColor)
                            Text(path)
                                .font(.subheadline)
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 200)
                }
            }
        }
        .onDrop(of: ["public.image", "public.folder"], isTargeted: nil) { providers in
            // Handle drag-and-drop — collect file URLs from item providers.
            // On macOS, the perform closure receives [NSItemProvider].
            let fileURLs = providers.compactMap { (provider: NSItemProvider) -> URL? in
                // Use loadFileRepresentation to get the local file path synchronously.
                // The completionHandler is called on a background thread, so we need
                // to dispatch back to the main queue if we want to update UI immediately.
                // However, since we're just collecting URLs here and returning true,
                // we can't block — instead, we'll collect the URLs asynchronously.
                // For now, we'll just print the count and handle URLs in a background task.
                var url: URL?
                let semaphore = DispatchSemaphore(value: 0)
                provider.loadFileRepresentation(forTypeIdentifier: "public.image") { (fileURL: URL?, error: Error?) in
                    if let fileURL = fileURL {
                        url = fileURL
                    }
                    semaphore.signal()
                }
                // Wait briefly for the result (up to 1 second)
                _ = semaphore.wait(timeout: .now() + 1.0)
                return url
            }
            print("Dropped \(fileURLs.count) items")
            return true
        }
    }
}
