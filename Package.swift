// swift-tools-version: 5.9
//
// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import PackageDescription

let package = Package(
    name: "PixAI",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "PixAI",
            path: "Sources"
        )
    ]
)
