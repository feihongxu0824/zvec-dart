#!/bin/bash
# =============================================================================
# build_ios.sh — Build zvec iOS dynamic framework
#
# Usage:
#   bash scripts/build_ios.sh [PLATFORM] [BUILD_TYPE]
#
# Parameters:
#   PLATFORM   - OS (default, arm64 device) | SIMULATORARM64 | SIMULATOR64
#   BUILD_TYPE - Release (default) | Debug
#
# Examples:
#   bash scripts/build_ios.sh                    # arm64 device Release
#   bash scripts/build_ios.sh SIMULATORARM64     # Apple Silicon simulator
#   bash scripts/build_ios.sh OS Debug           # arm64 device Debug
#
# Output:
#   ios/zvec.framework/          — dynamic framework (vendored_framework)
#     zvec                       — FAT dylib (all deps + factory registrations)
#     Headers/c_api.h            — C API public header
#
# Notes:
#   The upstream zvec CMake defines a zvec_c_api SHARED target. On Apple
#   platforms it uses -Wl,-force_load to embed all internal static libs into
#   the dylib, including factory registrations. No extra force-load archives
#   or manual static lib merging needed.
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ZVEC_SRC="$PROJECT_ROOT/third_party/zvec"

PLATFORM=${1:-"OS"}
BUILD_TYPE=${2:-"Release"}
IOS_DEPLOYMENT_TARGET="14.0"

# ---------------------------------------------------------------------------
# Check prerequisites
# ---------------------------------------------------------------------------
if [ ! -d "$ZVEC_SRC/src" ]; then
    echo "Error: third_party/zvec does not exist or is not initialized"
    echo "Run: git submodule update --init --recursive"
    exit 1
fi

if ! command -v xcrun &> /dev/null; then
    echo "Error: xcrun not found, please install Xcode Command Line Tools"
    exit 1
fi

# Determine architecture
case "$PLATFORM" in
    "OS")           ARCH="arm64" ;;
    "SIMULATOR64")  ARCH="x86_64" ;;
    "SIMULATORARM64") ARCH="arm64" ;;
    *)
        echo "Error: Unknown platform '$PLATFORM'"
        echo "Options: OS | SIMULATORARM64 | SIMULATOR64"
        exit 1 ;;
esac

echo "============================================"
echo "  Zvec iOS Build (Dynamic Framework)"
echo "  Platform:   $PLATFORM ($ARCH)"
echo "  Build Type: $BUILD_TYPE"
echo "  Target:     iOS $IOS_DEPLOYMENT_TARGET"
echo "============================================"

# ---------------------------------------------------------------------------
# Step 1: Build host protoc
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
# Step 2: Cross-compile zvec_c_api dynamic library for iOS
# ---------------------------------------------------------------------------
echo ""
echo "[2/3] Cross-compiling zvec_c_api for iOS ($PLATFORM)..."

# Reset thirdparty (patches may conflict)
pushd "$ZVEC_SRC" > /dev/null
git submodule foreach --recursive 'git stash --include-untracked 2>/dev/null || true' > /dev/null 2>&1
popd > /dev/null

if [ "$PLATFORM" = "OS" ]; then
    SDK_NAME="iphoneos"
else
    SDK_NAME="iphonesimulator"
fi
SDK_PATH=$(xcrun --sdk "$SDK_NAME" --show-sdk-path)

IOS_BUILD_DIR="$PROJECT_ROOT/build/ios_$PLATFORM"
mkdir -p "$IOS_BUILD_DIR"
pushd "$IOS_BUILD_DIR" > /dev/null

cmake \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$IOS_DEPLOYMENT_TARGET" \
    -DCMAKE_OSX_ARCHITECTURES="$ARCH" \
    -DCMAKE_OSX_SYSROOT="$SDK_PATH" \
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE" \
    -DBUILD_C_BINDINGS=ON \
    -DBUILD_PYTHON_BINDINGS=OFF \
    -DBUILD_TOOLS=OFF \
    -DCMAKE_INSTALL_PREFIX="./install" \
    -DGLOBAL_CC_PROTOBUF_PROTOC="$PROTOC_EXECUTABLE" \
    -DIOS=ON \
    "$ZVEC_SRC"

# Build only the zvec_c_api target (compiles all deps and links into a single dylib)
make -j"$(sysctl -n hw.ncpu)" zvec_c_api
popd > /dev/null

echo "[2/3] Done"

# ---------------------------------------------------------------------------
# Step 3: Package as .framework
# ---------------------------------------------------------------------------
echo ""
echo "[3/3] Packaging as zvec.framework ..."

IOS_DIR="$PROJECT_ROOT/ios"
FRAMEWORK_DIR="$IOS_DIR/zvec.framework"

# Find the CMake output dylib
DYLIB_PATH=$(find "$IOS_BUILD_DIR" -name "libzvec_c_api.dylib" -o -name "libzvec_c_api.so" | head -1)
if [ -z "$DYLIB_PATH" ]; then
    echo "Error: build artifact libzvec_c_api.dylib not found"
    echo "CMake build directory contents:"
    find "$IOS_BUILD_DIR/lib" -type f 2>/dev/null || true
    find "$IOS_BUILD_DIR/src/binding/c" -type f -name "*.dylib" 2>/dev/null || true
    exit 1
fi
echo "  Found dylib: $DYLIB_PATH"

# Create framework directory structure
rm -rf "$FRAMEWORK_DIR"
mkdir -p "$FRAMEWORK_DIR/Headers"

# Copy dylib and rename to framework binary name
cp "$DYLIB_PATH" "$FRAMEWORK_DIR/zvec"

# Fix install_name — CocoaPods loads via @rpath after embedding
install_name_tool -id @rpath/zvec.framework/zvec "$FRAMEWORK_DIR/zvec"

# Copy generated c_api.h (contains version info)
GENERATED_HEADER="$IOS_BUILD_DIR/src/generated/zvec/c_api.h"
if [ -f "$GENERATED_HEADER" ]; then
    cp "$GENERATED_HEADER" "$FRAMEWORK_DIR/Headers/"
else
    # Fallback: use source header
    cp "$ZVEC_SRC/src/include/zvec/c_api.h" "$FRAMEWORK_DIR/Headers/"
fi

# Generate Info.plist — required for App Store submission
FRAMEWORK_VERSION="0.1.0"
cat > "$FRAMEWORK_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>zvec</string>
    <key>CFBundleIdentifier</key>
    <string>com.alibaba.zvec</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>zvec</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>${FRAMEWORK_VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${FRAMEWORK_VERSION}</string>
    <key>MinimumOSVersion</key>
    <string>${IOS_DEPLOYMENT_TARGET}</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>iPhoneOS</string>
    </array>
</dict>
</plist>
EOF

echo "[3/3] Done"

# Verify artifacts
echo ""  
echo "============================================"
echo "  Build successful!"
echo "  Output: ios/zvec.framework/zvec"
echo "  Size:   $(du -h "$FRAMEWORK_DIR/zvec" | cut -f1)"
echo "  Type:   $(file "$FRAMEWORK_DIR/zvec" | sed 's|.*: ||')"
echo "============================================"

# ---------------------------------------------------------------------------
# Step 4: Package as zip (for uploading to GitHub Releases)
# ---------------------------------------------------------------------------
RELEASE_DIR="$PROJECT_ROOT/build/release"
mkdir -p "$RELEASE_DIR"
ZIP_NAME="zvec-framework-ios.zip"
cd "$IOS_DIR" && zip -r "$RELEASE_DIR/$ZIP_NAME" zvec.framework/
echo "  Release zip: build/release/$ZIP_NAME"
