// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import Foundation

/// A downloadable AI model "plugin". The main app has zero hard dependency on
/// the model binaries: when a plugin is not downloaded, its features are simply
/// disabled and everything else works normally.
struct ModelPlugin: Equatable {
    /// Stable unique identifier (used in config / state).
    let id: String
    /// Human-readable display name.
    let displayName: String
    /// Hugging Face repository (for the download UI).
    let repo: String
    /// ModelScope repository (for China mainland users). Nil means HF only.
    let mirrorRepo: String?
    /// Files to download: (repo-relative path, expected SHA256 hex).
    let files: [(path: String, sha256: String)]
    /// Local files to verify after download/extraction (path relative to subDir, empty SHA256 = just check existence).
    let verifyFiles: [(path: String, sha256: String)]
    /// Directory under `~/.pixai/models` where this plugin's files live.
    let subDir: String

    static let all: [ModelPlugin] = [realesrgan, u2net, lama]

    /// True if the current user is in mainland China (for mirror selection).
    private static var _isInChina: Bool?
    static var isInChina: Bool {
        if let cached = _isInChina { return cached }
        // Quick check: try a China-specific endpoint
        let semaphore = DispatchSemaphore(value: 0)
        var result = false
        let task = URLSession.shared.dataTask(with: URL(string: "https://myip.ipip.net/json")!) { data, _, _ in
            defer { semaphore.signal() }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let info = json["data"] as? [String: Any] else {
                Logger.shared.log("IP detection: failed to parse response")
                result = false
                return
            }
            // location can be either a String or an Array [String]
            if let locationStr = info["location"] as? String {
                result = locationStr.contains("中国") || locationStr.contains("China")
                Logger.shared.log("IP detection: location=\(locationStr), isInChina=\(result)")
            } else if let locationArr = info["location"] as? [String] {
                let locationStr = locationArr.joined(separator: " ")
                result = locationArr.contains("中国") || locationStr.contains("China")
                Logger.shared.log("IP detection: location=\(locationStr), isInChina=\(result)")
            } else {
                Logger.shared.log("IP detection: location format unknown")
                result = false
            }
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 2)
        _isInChina = result
        return result
    }

    /// Download base URL: ModelScope for China, HuggingFace for others.
    var downloadBaseURL: String {
        if let mirrorRepo, Self.isInChina {
            let url = "https://modelscope.cn/models/\(mirrorRepo)/resolve/master"
            Logger.shared.log("Using ModelScope mirror: \(url)")
            return url
        }
        let url = "https://huggingface.co/\(repo)/resolve/main"
        Logger.shared.log("Using HuggingFace: \(url)")
        return url
    }

    // ── Real-ESRGAN x4 (Core ML) ─────────────────────────────────────
    static let realesrgan = ModelPlugin(
        id: "realesrgan-x4",
        displayName: "Real-ESRGAN x4 (Core ML)",
        repo: "mlboydaisuke/Real-ESRGAN-x4-CoreML",
        mirrorRepo: nil,
        files: [
            ("RealESRGAN_x4.mlpackage/Manifest.json",
             "4faf3700dad0497c6efd622ca031cb04d17ad8b685477403c8cd573effdb4a1a"),
            ("RealESRGAN_x4.mlpackage/Data/com.apple.CoreML/model.mlmodel",
             "6107dc417de87bf974e5b225a2632e2c78f2849265dc897981f482e922050ec9")
        ],
        verifyFiles: [
            ("RealESRGAN_x4.mlpackage/Manifest.json",
             "4faf3700dad0497c6efd622ca031cb04d17ad8b685477403c8cd573effdb4a1a"),
            ("RealESRGAN_x4.mlpackage/Data/com.apple.CoreML/model.mlmodel",
             "6107dc417de87bf974e5b225a2632e2c78f2849265dc897981f482e922050ec9")
        ],
        subDir: "realesrgan"
    )

    // ── U2Net (Core ML, salient object detection) ────────────────────
    static let u2net = ModelPlugin(
        id: "u2net",
        displayName: "U2Net Saliency (Core ML)",
        repo: "Jia-Liu/U2Net-CoreML",
        mirrorRepo: "JiaLiuModel/U2Net-CoreML",
        files: [
            // Download zip file
            ("U2Net-CoreML.zip",
             "040a3b466bba867607cbb1e40e8dd2b6e275f9f71c1b81a498aec08199d503cb")
        ],
        verifyFiles: [
            // After extraction, check for mlpackage (empty SHA256 = just check existence)
            ("U2NET.mlpackage/Manifest.json", "")
        ],
        subDir: "u2net"
    )

    // ── LaMa (Core ML, Large Mask Inpainting) ────────────────────────
    static let lama = ModelPlugin(
        id: "lama",
        displayName: "LaMa Inpainting (Core ML)",
        repo: "Jia-Liu/big-lama-coreml",
        mirrorRepo: "JiaLiuModel/big-lama-coreml",
        files: [
            // Download zip file
            ("big-lama-coreml.zip",
             "8e1fb17d1f21233c350524453a6f58fe986f919eead26067afb2f3814f5e5adf")
        ],
        verifyFiles: [
            // After extraction, check for mlpackage (empty SHA256 = just check existence)
            ("LaMa.mlpackage/Manifest.json", "")
        ],
        subDir: "lama"
    )

    /// Root directory for all downloaded models: `~/.pixai/models`.
    static var modelsRoot: URL {
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".pixai/models")
    }

    /// This plugin's local directory.
    var localDir: URL {
        return ModelPlugin.modelsRoot.appendingPathComponent(subDir)
    }

    /// Local URL of one downloaded file (by repo-relative path).
    func localURL(forPath path: String) -> URL {
        return localDir.appendingPathComponent(path)
    }

    // Tuples in `files` are not Equatable, so compare by stable id.
    static func == (lhs: ModelPlugin, rhs: ModelPlugin) -> Bool {
        return lhs.id == rhs.id
    }
}

/// Runtime state of a plugin as seen by the UI / engines.
enum PluginState: Equatable {
    case notDownloaded
    case downloading(progress: Double)   // 0.0 ... 1.0
    case ready
    case error(String)
}
