#!/bin/bash
# Build ExecuTorch xcframeworks from source
# This script downloads and builds the ExecuTorch xcframeworks required by PixAI.
# 
# Prerequisites:
#   - CMake 3.20+
#   - Python 3.8+
#   - Xcode Command Line Tools
# 
# Usage: ./build_executorch.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR_DIR="$SCRIPT_DIR/Vendor/ExecuTorch"
BUILD_DIR="$SCRIPT_DIR/.executorch_build"
EXECUTORCH_VERSION="v0.6.0"

echo "=== ExecuTorch xcframework Build Script ==="
echo ""

# Check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."
    
    if ! command -v cmake &> /dev/null; then
        echo "❌ CMake not found. Please install CMake 3.20+"
        echo "   brew install cmake"
        exit 1
    fi
    
    if ! command -v python3 &> /dev/null; then
        echo "❌ Python 3 not found. Please install Python 3.8+"
        exit 1
    fi
    
    if ! command -v xcrun &> /dev/null; then
        echo "❌ Xcode Command Line Tools not found. Please install:"
        echo "   xcode-select --install"
        exit 1
    fi
    
    echo "✅ Prerequisites OK"
}

# Download ExecuTorch repository
download_executorch() {
    echo ""
    echo "Downloading ExecuTorch $EXECUTORCH_VERSION release..."
    
    if [ -d "$BUILD_DIR/executorch" ]; then
        echo "   Using existing directory at $BUILD_DIR/executorch"
        return
    fi
    
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    
    # Clone specific release tag with submodules
    echo "   Cloning release $EXECUTORCH_VERSION (depth 1)..."
    git clone --depth 1 --branch $EXECUTORCH_VERSION --recursive https://github.com/pytorch/executorch.git
    
    echo "✅ Download complete"
}

# Build xcframeworks
build_xcframeworks() {
    echo ""
    echo "Building ExecuTorch xcframeworks..."
    echo "   This may take 15-30 minutes depending on your machine."
    echo ""
    
    cd "$BUILD_DIR/executorch"
    
    # Install Python dependencies
    echo "Installing Python dependencies..."
    if [ -f "requirements.txt" ]; then
        pip3 install --user -r requirements.txt
    elif [ -f "requirements-dev.txt" ]; then
        pip3 install --user -r requirements-dev.txt
    else
        echo "   Note: No requirements file found, continuing without Python deps"
    fi
    
    # Set up build directories
    local CMAKE_BUILD_DIR="$BUILD_DIR/cmake_build"
    local FRAMEWORKS_DIR="$BUILD_DIR/frameworks"
    mkdir -p "$CMAKE_BUILD_DIR"
    mkdir -p "$FRAMEWORKS_DIR"
    
    # Build for macOS arm64
    local MACOS_ARCH="arm64"
    local MACOS_MIN_VERSION="14.0"
    
    echo ""
    echo "Building for macOS $MACOS_ARCH..."
    
    # Configure CMake
    cmake \
        -B "$CMAKE_BUILD_DIR" \
        -G Xcode \
        -DCMAKE_SYSTEM_NAME=Darwin \
        -DCMAKE_OSX_ARCHITECTURES=$MACOS_ARCH \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=$MACOS_MIN_VERSION \
        -DCMAKE_BUILD_TYPE=Release \
        -DEXECUTORCH_BUILD_XCFRAMEWORK=ON \
        -DEXECUTORCH_BUILD_COREML=ON \
        -S .
    
    # Build
    cmake --build "$CMAKE_BUILD_DIR" --config Release -j$(sysctl -n hw.ncpu)
    
    echo "✅ Build complete"
}

# Package xcframeworks
package_xcframeworks() {
    echo ""
    echo "Packaging xcframeworks..."
    
    mkdir -p "$VENDOR_DIR"
    
    local FRAMEWORKS_DIR="$BUILD_DIR/cmake_build"
    
    # Copy and verify xcframeworks
    for fw in "executorch" "backend_coreml" "kernels_optimized" "threadpool"; do
        local SRC="$FRAMEWORKS_DIR/$fw.xcframework"
        local DST="$VENDOR_DIR/$fw.xcframework"
        local ZIP="$VENDOR_DIR/$fw.zip"
        
        if [ -d "$SRC" ]; then
            echo "   Copying $fw.xcframework..."
            cp -R "$SRC" "$DST"
            
            # Create zip for distribution
            echo "   Creating $fw.zip..."
            cd "$VENDOR_DIR"
            zip -rq "$fw.zip" "$fw.xcframework"
        else
            echo "⚠️  Warning: $fw.xcframework not found in build output"
        fi
    done
    
    echo ""
    echo "✅ Packaging complete"
    echo ""
    echo "xcframeworks location: $VENDOR_DIR"
    ls -la "$VENDOR_DIR"
}

# Main
main() {
    check_prerequisites
    download_executorch
    build_xcframeworks
    package_xcframeworks
    
    echo ""
    echo "=== Build Successful ==="
    echo ""
    echo "ExecuTorch xcframeworks have been built and placed in:"
    echo "  $VENDOR_DIR"
    echo ""
    echo "You can now run ./build.sh to build PixAI."
    echo ""
    echo "To clean up build artifacts and free disk space (~2GB):"
    echo "  rm -rf $BUILD_DIR"
}

main "$@"