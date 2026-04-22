#!/bin/bash
# =============================================================================
# build_macos.sh — Build zvec native dynamic library for macOS (testing)
#
# Usage:
#   bash scripts/build_macos.sh [BUILD_TYPE]
#
# Parameters:
#   BUILD_TYPE - Release (default) | Debug
#
# Examples:
#   bash scripts/build_macos.sh            # Release build
#   bash scripts/build_macos.sh Debug      # Debug build
#
# Output:
#   build/macos/libzvec.dylib
#
# Notes:
#   This builds the native zvec_c_api shared library for the host macOS
#   platform (Apple Silicon arm64). It is NOT shipped with the Flutter
#   package — it is only used for running Dart FFI unit tests locally
#   without an iOS/Android emulator.
#
#   Run tests with:
#     DYLD_LIBRARY_PATH=build/macos flutter test
#   or use the convenience script:
#     bash scripts/run_tests.sh
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ZVEC_SRC="$PROJECT_ROOT/third_party/zvec"

BUILD_TYPE=${1:-"Release"}

# ---------------------------------------------------------------------------
# Check prerequisites
# ---------------------------------------------------------------------------
if [ ! -d "$ZVEC_SRC/src" ]; then
    echo "Error: third_party/zvec does not exist or is not initialized"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

echo "============================================"
echo "  Zvec macOS Build (for testing)"
echo "  Build Type: $BUILD_TYPE"
echo "  Arch:       $(uname -m)"
echo "============================================"

# ---------------------------------------------------------------------------
# Step 1: Build host protoc (required for protobuf compilation)
# ---------------------------------------------------------------------------
echo ""
echo "[1/3] Building host protoc..."

HOST_BUILD_DIR="$PROJECT_ROOT/build/host"
PROTOC_EXECUTABLE="$HOST_BUILD_DIR/bin/protoc"

if [ -x "$PROTOC_EXECUTABLE" ]; then
    echo "  Already exists, skipping: $PROTOC_EXECUTABLE"
else
    # Reset thirdparty submodules
    pushd "$ZVEC_SRC" > /dev/null
    git submodule foreach --recursive 'git stash --include-untracked 2>/dev/null || true' > /dev/null 2>&1
    popd > /dev/null

    mkdir -p "$HOST_BUILD_DIR"
    pushd "$HOST_BUILD_DIR" > /dev/null
    cmake -DCMAKE_BUILD_TYPE="$BUILD_TYPE" "$ZVEC_SRC"
    make -j"$(sysctl -n hw.ncpu)" protoc
    popd > /dev/null
fi

echo "[1/3] Done"

# ---------------------------------------------------------------------------
# Step 2: Build zvec_c_api shared library for macOS
# ---------------------------------------------------------------------------
echo ""
echo "[2/3] Building zvec_c_api for macOS..."

# Reset thirdparty submodules (patches may conflict)
pushd "$ZVEC_SRC" > /dev/null
git submodule foreach --recursive 'git stash --include-untracked 2>/dev/null || true' > /dev/null 2>&1
popd > /dev/null

MACOS_BUILD_DIR="$PROJECT_ROOT/build/macos_build"
mkdir -p "$MACOS_BUILD_DIR"
pushd "$MACOS_BUILD_DIR" > /dev/null

cmake \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DBUILD_C_BINDINGS=ON \
    -DBUILD_PYTHON_BINDINGS=OFF \
    -DBUILD_TOOLS=OFF \
    -DCMAKE_INSTALL_PREFIX="./install" \
    -DGLOBAL_CC_PROTOBUF_PROTOC="$PROTOC_EXECUTABLE" \
    "$ZVEC_SRC"

# Build only the zvec_c_api target
make -j"$(sysctl -n hw.ncpu)" zvec_c_api
popd > /dev/null

echo "[2/3] Done"

# ---------------------------------------------------------------------------
# Step 3: Copy artifact to build/macos/
# ---------------------------------------------------------------------------
echo ""
echo "[3/3] Copying libzvec.dylib to build/macos/ ..."

MACOS_OUTPUT_DIR="$PROJECT_ROOT/build/macos"
mkdir -p "$MACOS_OUTPUT_DIR"

# Find build artifact
DYLIB_FILE=$(find "$MACOS_BUILD_DIR" -name "libzvec_c_api.dylib" -type f | head -1)

if [ -z "$DYLIB_FILE" ]; then
    echo "Error: libzvec_c_api.dylib build artifact not found"
    echo "CMake build directory contents:"
    find "$MACOS_BUILD_DIR" -name "*.dylib" -type f 2>/dev/null || true
    exit 1
fi

# Rename to libzvec.dylib (Dart loads via DynamicLibrary.open('libzvec.dylib'))
cp "$DYLIB_FILE" "$MACOS_OUTPUT_DIR/libzvec.dylib"

echo "[3/3] Done"

echo ""
echo "============================================"
echo "  Build successful!"
echo "  Output: build/macos/libzvec.dylib"
echo "  Size:   $(du -h "$MACOS_OUTPUT_DIR/libzvec.dylib" | cut -f1)"
echo "  Type:   $(file "$MACOS_OUTPUT_DIR/libzvec.dylib" | sed 's|.*: ||')"
echo "============================================"
echo ""
echo "  Run tests with:"
echo "    DYLD_LIBRARY_PATH=build/macos flutter test"
echo "  or:"
echo "    bash scripts/run_tests.sh"
