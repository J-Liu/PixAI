// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation
import Vision
import CoreGraphics

/// Duplicate detection via Vision FeaturePrint + cosine similarity, and a
/// "best image" heuristic for choosing which duplicate to keep.
struct DuplicateGroup: Equatable {
    /// Indices into the scanned URL list.
    let indices: [Int]
}

enum DuplicateDetector {
    /// Cosine-similarity threshold above which two images count as duplicates.
    static let defaultThreshold: Float = 0.85

    /// Returns the configured threshold from AppConfig.
    static var threshold: Float {
        return Float(AppConfig.shared.dedupThreshold)
    }

    // MARK: - Feature prints

    /// Extract a FeaturePrint observation for each URL (nil for failures).
    /// Runs off the main thread.
    static func featurePrints(for urls: [URL],
                              progress: ((Double) -> Void)? = nil) async -> [Int: VNFeaturePrintObservation] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var result: [Int: VNFeaturePrintObservation] = [:]
                for (i, url) in urls.enumerated() {
                    do {
                        let request = VNGenerateImageFeaturePrintRequest()
                        let handler = VNImageRequestHandler(url: url, options: [:])
                        try handler.perform([request])
                        if let obs = request.results?.first {
                            result[i] = obs
                        }
                    } catch {
                        Logger.shared.log("DuplicateDetector: feature print failed for \(url.lastPathComponent): \(error.localizedDescription)")
                    }
                    progress?(Double(i + 1) / Double(urls.count))
                }
                continuation.resume(returning: result)
            }
        }
    }

    /// Cosine similarity (0...1) between two feature prints, computed from the
    /// raw observation data (the SDK's built-in similarity method is gone in
    /// recent macOS versions).
    static func cosineSimilarity(_ a: VNFeaturePrintObservation, _ b: VNFeaturePrintObservation) -> Float {
        guard let va = Self.floatVector(of: a), let vb = Self.floatVector(of: b),
              va.count == vb.count, !va.isEmpty else { return 0 }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in 0..<va.count {
            dot += va[i] * vb[i]
            na += va[i] * va[i]
            nb += vb[i] * vb[i]
        }
        let denom = (na.squareRoot()) * (nb.squareRoot())
        guard denom > 0 else { return 0 }
        return dot / denom
    }

    /// Decode the observation's raw data into a [Float] vector.
    private static func floatVector(of obs: VNFeaturePrintObservation) -> [Float]? {
        let data = obs.data
        switch obs.elementType {
        case .float:
            guard data.count >= 4 else { return nil }
            var v = [Float](repeating: 0, count: data.count / 4)
            let n = v.count
            data.withUnsafeBytes { raw in
                let src = raw.bindMemory(to: Float.self)
                v.withUnsafeMutableBufferPointer { dst in
                    _ = dst.update(from: src[0..<n])
                }
            }
            return v
        case .double:
            guard data.count >= 8 else { return nil }
            let n = data.count / 8
            var v = [Float](repeating: 0, count: n)
            data.withUnsafeBytes { raw in
                let src = raw.bindMemory(to: Double.self)
                for i in 0..<n { v[i] = Float(src[i]) }
            }
            return v
        default:
            return nil
        }
    }

    /// Group indices whose pairwise cosine similarity ≥ threshold (union-find).
    static func findGroups(urls: [URL],
                           observations: [Int: VNFeaturePrintObservation],
                           threshold: Float? = nil) -> [DuplicateGroup] {
        let threshold = threshold ?? Self.threshold
        let keys = observations.keys.sorted()
        var parent = Array(repeating: 0, count: urls.count)
        for i in 0..<urls.count { parent[i] = i }

        func find(_ a: Int) -> Int {
            var root = a
            while parent[root] != root { root = parent[root] }
            // Path compression.
            var cur = a
            while parent[cur] != root {
                let next = parent[cur]
                parent[cur] = root
                cur = next
            }
            return root
        }

        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }

        for x in 0..<keys.count {
            let ia = keys[x]
            guard let oa = observations[ia] else { continue }
            for y in (x + 1)..<keys.count {
                let ib = keys[y]
                guard let ob = observations[ib] else { continue }
                let sim = Self.cosineSimilarity(oa, ob)
                if sim >= threshold {
                    union(ia, ib)
                }
            }
        }

        var byRoot: [Int: [Int]] = [:]
        for i in keys {
            byRoot[find(i), default: []].append(i)
        }
        // Only groups with ≥2 members are duplicates; sort each group.
        return byRoot.values
            .filter { $0.count >= 2 }
            .map { DuplicateGroup(indices: $0.sorted()) }
            .sorted { $0.indices[0] < $1.indices[0] }
    }

    // MARK: - Best-image heuristic

    /// Score one image for "which duplicate to keep" (higher = better):
    /// resolution (pixel count) dominates, then file size as a quality proxy,
    /// plus a bonus when the session already de-watermarked it.
    static func keepScore(url: URL, dewatermarked: Bool) -> Double {
        var score = 0.0
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            let size = (attrs[.size] as? Int64) ?? 0
            score += Double(size) / 1_000_000          // MB, quality proxy
        }
        if let probed = pixelSize(of: url) {
            let px = Double(probed.width * probed.height) / 1_000_000   // MP
            score += px * 10                              // resolution dominates
        }
        if dewatermarked {
            score += 1000                                 // already cleaned wins
        }
        return score
    }

    /// The index (into `group.indices`) of the best image to keep.
    static func bestIndex(in group: DuplicateGroup, urls: [URL], dewatermarkedFlags: [Int: Bool]) -> Int {
        var best = group.indices[0]
        var bestScore = -Double.greatestFiniteMagnitude
        for i in group.indices {
            let s = keepScore(url: urls[i], dewatermarked: dewatermarkedFlags[i] ?? false)
            if s > bestScore {
                bestScore = s
                best = i
            }
        }
        return best
    }

    // MARK: - Helpers

    /// Pixel dimensions from the file header only (no full decode).
    static func pixelSize(of url: URL) -> NSSize? {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, options),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              w > 0, h > 0 else { return nil }
        return NSSize(width: w, height: h)
    }
}
