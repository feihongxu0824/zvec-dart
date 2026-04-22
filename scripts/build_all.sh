#!/bin/bash
# =============================================================================
# build_all.sh — Build zvec native libraries for all platforms
#
# Usage:
#   bash scripts/build_all.sh [BUILD_TYPE]
#
# Build targets:
#   - Android: arm64-v8a, armeabi-v7a
#   - iOS:     arm64 device, arm64 simulator (Apple Silicon)
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_TYPE=${1:-"Release"}

echo "============================================"
echo "  Building zvec for all platforms"
echo "  Build Type: $BUILD_TYPE"
echo "============================================"

# ---------------------------------------------------------------------------
# Android
# ---------------------------------------------------------------------------
echo ""
echo ">>> Android arm64-v8a"
bash "$SCRIPT_DIR/build_android.sh" arm64-v8a 21 "$BUILD_TYPE"

echo ""
echo ">>> Android armeabi-v7a"
bash "$SCRIPT_DIR/build_android.sh" armeabi-v7a 21 "$BUILD_TYPE"

# ---------------------------------------------------------------------------
# iOS
# ---------------------------------------------------------------------------
echo ""
echo ">>> iOS arm64 (device)"
bash "$SCRIPT_DIR/build_ios.sh" OS "$BUILD_TYPE"

echo ""
echo ">>> iOS arm64 Simulator (Apple Silicon)"
bash "$SCRIPT_DIR/build_ios.sh" SIMULATORARM64 "$BUILD_TYPE"

echo ""
echo "============================================"
echo "  All builds complete!"
echo ""
echo "  Android artifacts:"
echo "    android/src/main/jniLibs/arm64-v8a/libzvec.so"
echo "    android/src/main/jniLibs/armeabi-v7a/libzvec.so"
echo ""
echo "  iOS artifacts:"
echo "    ios/zvec.framework/zvec"
echo ""
echo "  Release zips (for GitHub Releases):"
echo "    build/release/libzvec-android-arm64-v8a.zip"
echo "    build/release/libzvec-android-armeabi-v7a.zip"
echo "    build/release/zvec-framework-ios.zip"
echo "============================================"
