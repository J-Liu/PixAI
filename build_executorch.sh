#!/bin/bash
# Build ExecuTorch xcframeworks from source for macOS
# This script downloads and builds the ExecuTorch xcframeworks required by PixAI.
# 
# Prerequisites:
#   - CMake 3.20+
#   - Python 3.10+
#   - Xcode Command Line Tools
#   - buck2 (will be downloaded automatically)
# 
# Usage: ./build_executorch.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENDOR_DIR="$SCRIPT_DIR/Vendor/ExecuTorch"
BUILD_DIR="$SCRIPT_DIR/.executorch_build"
EXECUTORCH_VERSION="v0.6.0"
PYTHON=/opt/homebrew/bin/python3.11

echo "=== ExecuTorch xcframework Build Script (macOS only) ==="
echo ""

# Check prerequisites
check_prerequisites() {
    echo "Checking prerequisites..."
    
    if ! command -v cmake &> /dev/null; then
        echo "❌ CMake not found. Please install CMake 3.20+"
        echo "   brew install cmake"
        exit 1
    fi
    
    if ! command -v $PYTHON &> /dev/null; then
        echo "❌ Python 3.11 not found at $PYTHON"
        echo "   brew install python@3.11"
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

# Build xcframeworks for macOS
build_xcframeworks() {
    echo ""
    echo "Building ExecuTorch xcframeworks for macOS arm64..."
    echo "   This may take 15-30 minutes depending on your machine."
    echo ""
    
    cd "$BUILD_DIR/executorch"
    
    # Use official build script but only for macOS
    local TOOLCHAIN="$BUILD_DIR/executorch/third-party/ios-cmake/ios.toolchain.cmake"
    
    if [ ! -f "$TOOLCHAIN" ]; then
        echo "❌ iOS CMake toolchain not found at $TOOLCHAIN"
        exit 1
    fi
    
    # Build only for macOS (skip iOS and simulator)
    rm -rf cmake-out && mkdir -p cmake-out && cd cmake-out
    mkdir -p macos && cd macos
    
    echo "   Configuring CMake..."
    cmake "$BUILD_DIR/executorch" -G Xcode \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_TOOLCHAIN_FILE="$TOOLCHAIN" \
        -DPLATFORM=MAC_ARM64 \
        -DDEPLOYMENT_TARGET=14.0 \
        -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LANGUAGE_STANDARD="c++17" \
        -DCMAKE_XCODE_ATTRIBUTE_CLANG_CXX_LIBRARY="libc++" \
        -DPYTHON_EXECUTABLE="$PYTHON" \
        -DEXECUTORCH_BUILD_COREML=ON \
        -DEXECUTORCH_BUILD_XNNPACK=OFF \
        -DEXECUTORCH_BUILD_EXTENSION_APPLE=ON \
        -DEXECUTORCH_BUILD_EXTENSION_DATA_LOADER=ON \
        -DEXECUTORCH_BUILD_EXTENSION_MODULE=ON \
        -DEXECUTORCH_BUILD_EXTENSION_TENSOR=ON \
        -DEXECUTORCH_BUILD_KERNELS_OPTIMIZED=ON \
        -DCMAKE_ARCHIVE_OUTPUT_DIRECTORY="$(pwd)"
    
    echo "   Building..."
    cmake --build . --config Release -j$(sysctl -n hw.ncpu)
    
    echo "✅ Build complete"
}

# Package xcframeworks
package_xcframeworks() {
    echo ""
    echo "Packaging xcframeworks..."
    
    cd "$BUILD_DIR/executorch/cmake-out"
    
    # Export headers
    echo "   Exporting headers..."
    mkdir -p include/executorch
    cp -r "$BUILD_DIR/executorch/extension/apple/ExecuTorch/Exported/"* include/executorch/
    
    mkdir -p "$VENDOR_DIR"
    
    # Create xcframeworks using official script
    echo "   Creating executorch.xcframework..."
    "$BUILD_DIR/executorch/scripts/create_frameworks.sh" \
        --directory=macos \
        --framework="executorch:libexecutorch.a,libexecutorch_core.a,libextension_apple.a,libextension_data_loader.a,libextension_module.a,libextension_tensor.a:include/executorch" \
        --output="$VENDOR_DIR"
    
    echo "   Creating backend_coreml.xcframework..."
    "$BUILD_DIR/executorch/scripts/create_frameworks.sh" \
        --directory=macos/backends/apple/coreml \
        --framework="backend_coreml:libcoreml_util.a,libcoreml_inmemoryfs.a,libcoremldelegate.a:" \
        --output="$VENDOR_DIR"
    
    echo "   Creating kernels_optimized.xcframework..."
    "$BUILD_DIR/executorch/scripts/create_frameworks.sh" \
        --directory=macos/kernels/optimized \
        --framework="kernels_optimized:libcpublas.a,liboptimized_kernels.a,liboptimized_native_cpu_ops_lib.a:" \
        --output="$VENDOR_DIR"
    
    echo "   Creating threadpool.xcframework..."
    "$BUILD_DIR/executorch/scripts/create_frameworks.sh" \
        --directory=macos/extension/threadpool \
        --framework="threadpool:libextension_threadpool.a:" \
        --output="$VENDOR_DIR"
    
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