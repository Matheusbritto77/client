#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build/macos-release}"
APP_PATH="${APP_PATH:-$BUILD_DIR/bin/OTClient.app}"
OUT_PREFIX="${OUT_PREFIX:-$ROOT/dist/OTClient-macos-arm64}"

usage() {
  echo "Usage: $0 [build-dir] [output-prefix]" >&2
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ -n "${1:-}" ]; then
  BUILD_DIR="$1"
  APP_PATH="$BUILD_DIR/bin/OTClient.app"
fi

if [ -n "${2:-}" ]; then
  OUT_PREFIX="$2"
fi

if [ -z "${VCPKG_ROOT:-}" ] || [ ! -d "$VCPKG_ROOT" ]; then
  echo "VCPKG_ROOT must point to a valid vcpkg checkout." >&2
  exit 1
fi

cmake -S "$ROOT" -B "$BUILD_DIR" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$VCPKG_ROOT/scripts/buildsystems/vcpkg.cmake" \
  -DBUILD_STATIC_LIBRARY=ON \
  -DCMAKE_BUILD_TYPE=Release \
  -DOPTIONS_ENABLE_SCCACHE=ON \
  -DOPTIONS_ENABLE_IPO=OFF \
  -DCMAKE_CXX_FLAGS_RELEASE="-O2 -DNDEBUG" \
  -DCMAKE_C_FLAGS_RELEASE="-O2 -DNDEBUG" \
  -DVCPKG_TARGET_TRIPLET=arm64-osx \
  -DVCPKG_HOST_TRIPLET=arm64-osx \
  -DVCPKG_INSTALLED_DIR="$ROOT/vcpkg_installed/macos-release" \
  -DVCPKG_BUILD_TYPE=release \
  -DOTCLIENT_BUILD_TESTS=OFF \
  -DTOGGLE_BIN_FOLDER=ON \
  -DTOGGLE_BOT_PROTECTION=OFF

cmake --build "$BUILD_DIR" --target otclient

exec "$ROOT/tools/package_macos_release.sh" "$APP_PATH" "$OUT_PREFIX"
