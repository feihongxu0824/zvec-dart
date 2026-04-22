#!/bin/bash
# =============================================================================
# run_tests.sh — Run Dart unit tests with the macOS native library
#
# Usage:
#   bash scripts/run_tests.sh [ARGS...]
#
# Examples:
#   bash scripts/run_tests.sh                                # run all tests
#   bash scripts/run_tests.sh test/zvec_native_test.dart     # specific file
#   bash scripts/run_tests.sh --name "Doc"                   # filter by name
#   bash scripts/run_tests.sh test/zvec_test.dart            # pure-Dart only
#
# Notes:
#   This script sets ZVEC_LIBRARY_PATH to an absolute path so that
#   ZvecLibrary._openLibrary() can locate the macOS-built native library.
#   (DYLD_LIBRARY_PATH is stripped by macOS SIP in child processes.)
#   If the dylib does not exist, it will prompt you to build it first.
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DYLIB_DIR="$PROJECT_ROOT/build/macos"
DYLIB_PATH="$DYLIB_DIR/libzvec.dylib"

# ---------------------------------------------------------------------------
# Check that the native library exists
# ---------------------------------------------------------------------------
if [ ! -f "$DYLIB_PATH" ]; then
    echo "Error: $DYLIB_PATH not found"
    echo ""
    echo "Build the macOS native library first:"
    echo "  bash scripts/build_macos.sh"
    exit 1
fi

echo "Using native library: $DYLIB_PATH"
echo "  Type: $(file "$DYLIB_PATH" | sed 's|.*: ||')"
echo ""

# ---------------------------------------------------------------------------
# Run tests
# ---------------------------------------------------------------------------
cd "$PROJECT_ROOT"
ZVEC_LIBRARY_PATH="$DYLIB_PATH" flutter test "$@"
