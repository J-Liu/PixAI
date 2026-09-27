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
BUILD_OUTPUT="$SCRIPT_DIR/.build/release/PixAI"
SPARKLE_FRAMEWORK="$SCRIPT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

echo "🔨 Building PixAI..."
cd "$SCRIPT_DIR"

# Build with Swift Package Manager (downloads Sparkle automatically)
swift build -c release

echo "✅ Build successful: $BUILD_OUTPUT"

echo "📦 Packaging as $APP_NAME..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# Copy the executable
cp "$BUILD_OUTPUT" "$APP_BUNDLE/Contents/MacOS/PixAI"
chmod +x "$APP_BUNDLE/Contents/MacOS/PixAI"

# Add rpath for embedded frameworks
install_name_tool -add_rpath @executable_path/../Frameworks "$APP_BUNDLE/Contents/MacOS/PixAI"
echo "   🔧 Added rpath for frameworks"

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

# Copy Sparkle framework
if [ -d "$SPARKLE_FRAMEWORK" ]; then
    mkdir -p "$APP_BUNDLE/Contents/Frameworks"
    cp -R "$SPARKLE_FRAMEWORK" "$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
    echo "   📦 Sparkle framework copied"
else
    echo "   ⚠️ Warning: Sparkle framework not found at $SPARKLE_FRAMEWORK"
    echo "      Run 'swift build' first to download the framework."
fi

# Sign the app bundle (ad-hoc signature for distribution)
echo "🔏 Signing app bundle..."
codesign --force --deep --sign - --identifier com.jialiu.pixai "$APP_BUNDLE"
echo "   ✅ App signed"

echo ""
echo "✅ Packaging complete: $APP_BUNDLE"
echo "   Run with: open \"$APP_BUNDLE\""
echo ""
