// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright © 2026 Jia Liu

import AppKit

/// Global variables to pass parsed arguments to the AppKit app.
var commandPaths: [String] = []
var isFullscreenMode = false


// Parse command-line arguments
let args = CommandLine.arguments.dropFirst() // skip executable path
var skippedNonexistent = 0
for arg in args {
    if arg == "--fullscreen" {
        isFullscreenMode = true
    } else {
        let url = URL(fileURLWithPath: arg)
        if FileManager.default.fileExists(atPath: url.path) {
            commandPaths.append(arg)
        } else {
            skippedNonexistent += 1
        }
    }
}

// Create the AppKit app delegate instance
let pixaiApp = PixAIApp()

// Set up the application
let app = NSApplication.shared
app.delegate = pixaiApp
app.run()
