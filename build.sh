#!/bin/bash
#
# # SPDX-License-Identifier: AGPL-3.0-or-later
# Copyright © 2026 Jia Liu
#
# PixAI - macOS App Packaging Script
# This script compiles the Swift project and packages it as a .app bundle.
# Usage: ./build.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_NAME="PixAI.app"
APP_BUNDLE="$SCRIPT_DIR/$APP_NAME"
BUILD_OUTPUT="$SCRIPT_DIR/.build/arm64-apple-macosx/release/PixAI"

echo "🔨 Building PixAI..."
cd "$SCRIPT_DIR"
rm -rf .build/module-cache
mkdir -p .build/arm64-apple-macosx/release

# CoreML-based build (no ExecuTorch dependencies)
SWIFT_PACKAGE_NO_SANDBOX=1 xcrun swiftc \
    -O \
    -whole-module-optimization \
    -enable-bare-slash-regex \
    -enable-testing \
    -parse-as-library \
    -module-name PixAI \
    -emit-executable \
    -o "$BUILD_OUTPUT" \
    -module-cache-path "$SCRIPT_DIR/.build/module-cache" \
    -Xcc -fmodules-cache-path="$SCRIPT_DIR/.build/module-cache" \
    -framework CoreML -framework Vision -framework Accelerate -framework CoreImage \
    -lsqlite3 -lc++ \
    $(find Sources -name "*.swift" | tr '\n' ' ')

echo "✅ Build successful: $BUILD_OUTPUT"

echo "📦 Packaging as $APP_NAME..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy the executable
cp "$BUILD_OUTPUT" "$APP_BUNDLE/Contents/MacOS/PixAI"
chmod +x "$APP_BUNDLE/Contents/MacOS/PixAI"

# Copy compiled icon (Assets.car from Resources/Compiled)
if [ -f "$SCRIPT_DIR/Resources/Compiled/Assets.car" ]; then
    cp "$SCRIPT_DIR/Resources/Compiled/Assets.car" "$APP_BUNDLE/Contents/Resources/Assets.car"
    echo "   📌 Icon copied: Assets.car"
else
    echo "   ⚠️ Warning: Compiled icon not found at Resources/Compiled/Assets.car"
    echo "      Run ./build_icon.sh locally to compile the icon, then commit the result."
fi

# Copy legacy .icns for older macOS versions
if [ -f "$SCRIPT_DIR/Resources/Compiled/PixAI.icns" ]; then
    cp "$SCRIPT_DIR/Resources/Compiled/PixAI.icns" "$APP_BUNDLE/Contents/Resources/PixAI.icns"
    echo "   📌 Legacy icon copied: PixAI.icns"
else
    echo "   ⚠️ Warning: PixAI.icns not found at Resources/Compiled/PixAI.icns"
    echo "      Older macOS versions may not display the app icon."
fi


# Copy Info.plist
if [ -f "$SCRIPT_DIR/Resources/Info.plist" ]; then
    cp "$SCRIPT_DIR/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
    echo "   📄 Info.plist copied"
else
    echo "   ⚠️ Warning: Info.plist not found at Resources/Info.plist"
fi
echo ""
echo "✅ Packaging complete: $APP_BUNDLE"
echo "   Run with: open \"$APP_BUNDLE\""
echo ""
