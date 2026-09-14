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
    /// Files to download: (repo-relative path, expected SHA256 hex).
    let files: [(path: String, sha256: String)]
    /// Directory under `~/.pixai/models` where this plugin's files live.
    let subDir: String

    static let all: [ModelPlugin] = [realesrgan, u2net]

    // ── Real-ESRGAN x4 (Core ML) ─────────────────────────────────────
    static let realesrgan = ModelPlugin(
        id: "realesrgan-x4",
        displayName: "Real-ESRGAN x4 (Core ML)",
        repo: "mlboydaisuke/Real-ESRGAN-x4-CoreML",
        files: [
            ("RealESRGAN_x4.mlpackage/Manifest.json",
             "4faf3700dad0497c6efd622ca031cb04d17ad8b685477403c8cd573effdb4a1a"),
            ("RealESRGAN_x4.mlpackage/Data/com.apple.CoreML/model.mlmodel",
             "6107dc417de87bf974e5b225a2632e2c78f2849265dc897981f482e922050ec9")
        ],
        subDir: "realesrgan"
    )

    // ── U2Net (ExecuTorch, Core ML delegate) ─────────────────────────
    static let u2net = ModelPlugin(
        id: "u2net",
        displayName: "U2Net Watermark (ExecuTorch)",
        repo: "mlboydaisuke/U2Net-ExecuTorch",
        files: [
            ("u2net_coreml_all.pte",
             "2a0e1588ed0883862c6fa7bfd2c28d97c57d0280d9c78a09ac953713ed6047d8")
        ],
        subDir: "u2net"
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
