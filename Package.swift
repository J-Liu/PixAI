// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PixAI",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "PixAI",
            path: "Sources",
            resources: [
                .process("Resources/PixAI.icns")
            ]
        )
    ]
)
