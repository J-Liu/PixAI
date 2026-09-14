// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation
import AVFoundation

/// Detects Apple Live Photo pairs on disk.
///
/// A Live Photo exported from an iPhone is a PAIR of files with the same base
/// name in the same directory: the still image (e.g. `IMG_0001.HEIC`) and a
/// companion QuickTime movie (e.g. `IMG_0001.MOV`). Per Apple's documentation,
/// the two files share a "content identifier" UUID in their metadata, and the
/// movie carries Live-Photo-specific movie-level QuickTime metadata items
/// (`com.apple.quicktime.livephoto`, `com.apple.quicktime.autolivephoto` —
/// see `AVMetadataIdentifier` / `PHLivePhoto.request(withResourceFileURLs:)`).
final class LivePhotoDetector {
    static let shared = LivePhotoDetector()

    /// Movie-level metadata keys that mark a MOV as a Live Photo video.
    private static let livePhotoMetadataKeys: Set<String> = [
        "com.apple.quicktime.livephoto",
        "com.apple.quicktime.content.identifier"
    ]

    private var cache: [URL: URL?] = [:]
    private let lock = NSLock()

    /// Returns the companion .MOV for `imageURL` if the two files form a Live
    /// Photo pair; nil otherwise. Results are cached per image URL.
    func companionVideoURL(for imageURL: URL) async -> URL? {
        // Synchronous cache check (no suspension point while the lock is held).
        if let cached = cachedVideoURL(for: imageURL) {
            return cached
        }
        let result = await Self.detect(imageURL)
        storeVideoURL(result, for: imageURL)
        return result
    }

    /// `nil` = not cached yet; `.some(nil)` = cached as "not a Live Photo".
    private func cachedVideoURL(for url: URL) -> URL?? {
        lock.lock(); defer { lock.unlock() }
        return cache[url]
    }

    private func storeVideoURL(_ result: URL?, for url: URL) {
        lock.lock(); defer { lock.unlock() }
        cache[url] = result
    }

    /// Nonisolated so the directory scan and metadata load run off the main
    /// thread while `await`ed from the UI.
    private static func detect(_ imageURL: URL) async -> URL? {
        // 1. Find a same-base-name .MOV in the same directory (case-insensitive).
        let dir = imageURL.deletingLastPathComponent()
        let baseName = imageURL.deletingPathExtension().lastPathComponent
        guard !baseName.isEmpty else { return nil }

        do {
            let items = try FileManager.default.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
            let candidates = items.filter { item in
                guard item.pathExtension.lowercased() == "mov" else { return false }
                let candidateBase = item.deletingPathExtension().lastPathComponent
                return candidateBase.caseInsensitiveCompare(baseName) == .orderedSame
            }
            guard let movURL = candidates.first else { return nil }

            // 2. Verify the MOV carries Live Photo movie-level metadata via the
            //    modern async AVAsset API (`asset.metadata` is deprecated).
            let asset = AVURLAsset(url: movURL)
            guard let metadata = try? await asset.load(.metadata), !metadata.isEmpty else {
                // Metadata unreadable (locked file, unusual container): fall
                // back to Apple's file-naming convention.
                return movURL
            }
            for item in metadata {
                let keys = [item.identifier?.rawValue, item.commonKey?.rawValue]
                    .compactMap { $0 }
                if keys.contains(where: { livePhotoMetadataKeys.contains($0) }) {
                    return movURL
                }
            }
            // Readable metadata with no Live Photo marker: a regular video that
            // merely shares the file name — not a Live Photo.
            return nil
        } catch {
            Logger.shared.log("LivePhotoDetector: failed to scan \(dir.path): \(error)")
            return nil
        }
    }
}
