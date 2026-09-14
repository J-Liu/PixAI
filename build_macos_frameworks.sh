#!/bin/bash
# Build ExecuTorch xcframeworks for macOS only
# Usage: ./build_macos_frameworks.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_ROOT_DIR="$SCRIPT_DIR/.executorch_build/executorch"
OUTPUT="cmake-out"
PYTHON=/opt/homebrew/bin/python3.11
TOOLCHAIN="$SOURCE_ROOT_DIR/third-party/ios-cmake/ios.toolchain.cmake"

cd "$SOURCE_ROOT_DIR"

echo "=== Building ExecuTorch for macOS arm64 ==="

rm -rf "$OUTPUT" && mkdir -p "$OUTPUT" && cd "$OUTPUT" || exit 1

mkdir -p macos && cd macos || exit 1

cmake "$SOURCE_ROOT_DIR" -G Xcode \
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

cmake --build . --config Release -j$(sysctl -n hw.ncpu)

echo "✅ Build complete"
cd "$OUTPUT"

# Export headers
echo "Exporting headers..."
mkdir -p include/executorch
cp -r "$SOURCE_ROOT_DIR/extension/apple/ExecuTorch/Exported/"* include/executorch/

# Create xcframeworks using create_frameworks.sh
echo "Creating xcframeworks..."

mkdir -p "$SCRIPT_DIR/Vendor/ExecuTorch"

# Use create_frameworks.sh to create proper xcframeworks
"$SOURCE_ROOT_DIR/scripts/create_frameworks.sh" \
    --directory=macos \
    --framework="executorch:libexecutorch.a,libexecutorch_core.a,libextension_apple.a,libextension_data_loader.a,libextension_module.a,libextension_tensor.a:include/executorch" \
    --output="$SCRIPT_DIR/Vendor/ExecuTorch"

"$SOURCE_ROOT_DIR/scripts/create_frameworks.sh" \
    --directory=macos/backends/apple/coreml \
    --framework="backend_coreml:libcoreml_util.a,libcoreml_inmemoryfs.a,libcoremldelegate.a:" \
    --output="$SCRIPT_DIR/Vendor/ExecuTorch"

"$SOURCE_ROOT_DIR/scripts/create_frameworks.sh" \
    --directory=macos/kernels/optimized \
    --framework="kernels_optimized:libcpublas.a,liboptimized_kernels.a,liboptimized_native_cpu_ops_lib.a:" \
    --output="$SCRIPT_DIR/Vendor/ExecuTorch"

"$SOURCE_ROOT_DIR/scripts/create_frameworks.sh" \
    --directory=macos/extension/threadpool \
    --framework="threadpool:libextension_threadpool.a:" \
    --output="$SCRIPT_DIR/Vendor/ExecuTorch"

echo ""
echo "✅ xcframeworks created:"
ls -la "$SCRIPT_DIR/Vendor/ExecuTorch/"