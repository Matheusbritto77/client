#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 /path/to/source.zip-or-dir /path/to/output.zip [runtime-dir ...]" >&2
}

SOURCE_PATH="${1:-}"
OUTPUT_ZIP="${2:-}"
shift 2 || true

if [ -z "$SOURCE_PATH" ] || [ -z "$OUTPUT_ZIP" ]; then
  usage
  exit 1
fi

if [ ! -e "$SOURCE_PATH" ]; then
  echo "Source path not found: $SOURCE_PATH" >&2
  exit 1
fi

TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/otclient-winpkg.XXXXXX")"
WORK_DIR="$TMP_ROOT/work"
mkdir -p "$WORK_DIR"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

copy_runtime_dll() {
  local dll_name="$1"
  shift

  for runtime_dir in "$@"; do
    [ -n "$runtime_dir" ] || continue
    if [ -f "$runtime_dir/$dll_name" ]; then
      cp -f "$runtime_dir/$dll_name" "$WORK_DIR/$dll_name"
      return 0
    fi
  done

  return 1
}

extract_source() {
  if [ -d "$SOURCE_PATH" ]; then
    cp -R "$SOURCE_PATH"/. "$WORK_DIR"/
    return 0
  fi

  unzip -q "$SOURCE_PATH" -d "$WORK_DIR"
}

extract_source

require_path() {
  local path="$1"
  local message="$2"

  if [ ! -e "$path" ]; then
    echo "$message" >&2
    exit 1
  fi
}

require_directory() {
  local path="$1"
  local label="$2"

  if [ ! -d "$path" ]; then
    echo "Required ${label} directory not found: $path" >&2
    exit 1
  fi
}

require_path "$WORK_DIR/init.lua" "Required runtime file not found: init.lua"
require_path "$WORK_DIR/otclientrc.lua" "Required runtime file not found: otclientrc.lua"
require_directory "$WORK_DIR/data" "data"
require_directory "$WORK_DIR/modules" "modules"
require_directory "$WORK_DIR/mods" "mods"
require_path "$WORK_DIR/mods/README.txt" "Required runtime file not found: mods/README.txt"
require_path "$WORK_DIR/mods/client_mods/mods.otmod" "Required runtime file not found: mods/client_mods/mods.otmod"

RUNTIME_DIRS=()
if [ "$#" -gt 0 ]; then
  RUNTIME_DIRS+=("$@")
fi

if command -v x86_64-w64-mingw32-gcc >/dev/null 2>&1; then
  gcc_bin="$(command -v x86_64-w64-mingw32-gcc)"
  gcc_root="$(cd "$(dirname "$gcc_bin")/.." && pwd)"
  RUNTIME_DIRS+=("$gcc_root/bin" "$gcc_root/lib")
fi

RUNTIME_DIRS+=(
  "/opt/homebrew/Cellar/mingw-w64/14.0.0_1/toolchain-x86_64/x86_64-w64-mingw32/bin"
  "/opt/homebrew/Cellar/mingw-w64/14.0.0_1/toolchain-x86_64/x86_64-w64-mingw32/lib"
  "/usr/x86_64-w64-mingw32/bin"
  "/usr/x86_64-w64-mingw32/lib"
)

for dll in libwinpthread-1.dll libgcc_s_seh-1.dll libstdc++-6.dll; do
  if [ -f "$WORK_DIR/$dll" ]; then
    continue
  fi

  if ! copy_runtime_dll "$dll" "${RUNTIME_DIRS[@]}"; then
    echo "Required runtime DLL not found: $dll" >&2
    exit 1
  fi
done

for required_runtime in libwinpthread-1.dll libgcc_s_seh-1.dll libstdc++-6.dll; do
  require_path "$WORK_DIR/$required_runtime" "Required runtime DLL not found after lookup: $required_runtime"
done

rm -f "$OUTPUT_ZIP"
(cd "$WORK_DIR" && zip -9 -qr -X "$OUTPUT_ZIP" .)

echo "$OUTPUT_ZIP"
