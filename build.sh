#!/bin/bash
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

# ─── ExecuTorch (U2Net watermark model) binary targets ──────────────────────
VENDOR="$SCRIPT_DIR/Vendor/ExecuTorch"
for name in executorch backend_coreml kernels_optimized threadpool; do
    if [ ! -d "$VENDOR/$name.xcframework" ] && [ -f "$VENDOR/$name.zip" ]; then
        echo "   📦 Extracting $name.xcframework..."
        unzip -qo "$VENDOR/$name.zip" -d "$VENDOR"
    fi
done

ET_SLICE="$VENDOR/executorch.xcframework/macos-arm64"
BC_SLICE="$VENDOR/backend_coreml.xcframework/macos-arm64"
KO_SLICE="$VENDOR/kernels_optimized.xcframework/macos-arm64"
TP_SLICE="$VENDOR/threadpool.xcframework/macos-arm64"

if [ ! -f "$ET_SLICE/ExecuTorch.swiftinterface" ]; then
    echo "❌ ExecuTorch xcframework missing (run the unzip step / check Vendor/ExecuTorch)"
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
    -L "$ET_SLICE" -lexecutorch_macos \
    -Xlinker -force_load -Xlinker "$BC_SLICE/libbackend_coreml_macos.a" \
    -Xlinker -force_load -Xlinker "$KO_SLICE/libkernels_optimized_macos.a" \
    -L "$TP_SLICE" -lthreadpool_macos \
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
