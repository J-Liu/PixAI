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

# ExecuTorch version for build script reference
EXECUTORCH_VERSION="v0.6.0"

echo "🔨 Building PixAI..."
cd "$SCRIPT_DIR"
rm -rf .build/module-cache
mkdir -p .build/arm64-apple-macosx/release

# ─── ExecuTorch (U2Net watermark model) binary targets ──────────────────────
VENDOR="$SCRIPT_DIR/Vendor/ExecuTorch"
mkdir -p "$VENDOR"

# Define the xcframeworks needed
FRAMEWORKS=("executorch" "backend_coreml" "kernels_optimized" "threadpool")

# Check if all frameworks already exist
ALL_EXIST=true
for name in "${FRAMEWORKS[@]}"; do
    if [ ! -d "$VENDOR/$name.xcframework" ]; then
        ALL_EXIST=false
        break
    fi
done

# Download missing frameworks
if [ "$ALL_EXIST" = false ]; then
    echo "   🔍 Checking ExecuTorch dependencies..."
    for name in "${FRAMEWORKS[@]}"; do
        if [ ! -d "$VENDOR/$name.xcframework" ]; then
            if [ -f "$VENDOR/$name.zip" ]; then
                echo "   📦 Extracting $name.xcframework from local zip..."
                unzip -qo "$VENDOR/$name.zip" -d "$VENDOR"
            else
                echo ""
                echo "   ⚠️  ExecuTorch xcframeworks not found. Building from source..."
                echo "   This will download and build ExecuTorch $EXECUTORCH_VERSION (15-30 min)."
                echo ""

                # Check if build_executorch.sh exists
                if [ -f "$SCRIPT_DIR/build_executorch.sh" ]; then
                    # Run build_executorch.sh
                    cd "$SCRIPT_DIR"
                    bash build_executorch.sh

                    # Verify build succeeded
                    if [ ! -d "$VENDOR/$name.xcframework" ]; then
                        echo ""
                        echo "❌ Failed to build ExecuTorch xcframeworks"
                        exit 1
                    fi
                else
                    echo "❌ Missing ExecuTorch dependency: $name.xcframework"
                    echo "   build_executorch.sh not found."
                    echo ""
                    echo "   ExecuTorch xcframeworks are required for AI features (watermark removal)."
                    echo "   PyTorch does not provide pre-built macOS xcframeworks."
                    echo ""
                    echo "   To build from source, get build_executorch.sh and run:"
                    echo "     ./build_executorch.sh"
                    echo ""
                    exit 1
                fi
            fi
        fi
    done
fi

ET_SLICE="$VENDOR/executorch.xcframework/macos-arm64"
BC_SLICE="$VENDOR/backend_coreml.xcframework/macos-arm64"
KO_SLICE="$VENDOR/kernels_optimized.xcframework/macos-arm64"
TP_SLICE="$VENDOR/threadpool.xcframework/macos-arm64"

# Check if xcframeworks exist (Headers for executorch, .a files for others)
if [ ! -d "$ET_SLICE" ] || [ ! -d "$ET_SLICE/Headers" ]; then
    echo "❌ ExecuTorch xcframework missing or incomplete"
    echo "   Please ensure all xcframeworks are present in Vendor/ExecuTorch/"
    exit 1
fi

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
    -I "$ET_SLICE" \
    -I "$ET_SLICE/Headers" \
    -Xcc -I"$ET_SLICE/Headers" \
    -Xlinker -force_load -Xlinker "$ET_SLICE/libexecutorch_macos.a" \
    -Xlinker -force_load -Xlinker "$BC_SLICE/libbackend_coreml_macos.a" \
    -Xlinker -force_load -Xlinker "$KO_SLICE/libkernels_optimized_macos.a" \
    -Xlinker -force_load -Xlinker "$TP_SLICE/libthreadpool_macos.a" \
    -framework CoreML -framework Accelerate -framework CoreImage -framework Vision \
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

# Copy the icon
if [ -f "$SCRIPT_DIR/Resources/PixAI.icns" ]; then
    cp "$SCRIPT_DIR/Resources/PixAI.icns" "$APP_BUNDLE/Contents/Resources/PixAI.icns"
    echo "   📌 Icon copied: PixAI.icns"
else
    echo "   ⚠️ Warning: Icon not found at Resources/PixAI.icns"
fi

# Create Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>PixAI</string>
    <key>CFBundleDisplayName</key>
    <string>PixAI</string>
    <key>CFBundleIdentifier</key>
    <string>com.pixai.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleExecutable</key>
    <string>PixAI</string>
    <key>CFBundleIconFile</key>
    <string>PixAI.icns</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
    <key>NSMainNibFile</key>
    <string></string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
</dict>
</plist>
EOF

echo "   📄 Info.plist created"
echo ""
echo "✅ Packaging complete: $APP_BUNDLE"
echo "   Run with: open \"$APP_BUNDLE\""
echo ""
