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
PACKAGE_DIR="$TMP_ROOT/package"
mkdir -p "$WORK_DIR" "$PACKAGE_DIR"

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
      cp -f "$runtime_dir/$dll_name" "$PACKAGE_DIR/$dll_name"
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

copy_required_file() {
  local source_path="$1"
  local target_path="$2"

  require_path "$source_path" "Required runtime file not found: ${source_path#$WORK_DIR/}"
  cp -f "$source_path" "$target_path"
}

copy_optional_file() {
  local source_path="$1"
  local target_path="$2"

  if [ -e "$source_path" ]; then
    cp -f "$source_path" "$target_path"
  fi
}

copy_required_directory() {
  local source_path="$1"
  local target_path="$2"

  require_directory "$source_path" "${source_path#$WORK_DIR/}"
  rm -rf "$target_path"
  cp -R "$source_path" "$target_path"
}

copy_runtime_tree() {
  copy_required_file "$WORK_DIR/init.lua" "$PACKAGE_DIR/init.lua"
  copy_required_file "$WORK_DIR/otclientrc.lua" "$PACKAGE_DIR/otclientrc.lua"
  copy_optional_file "$WORK_DIR/meta.lua" "$PACKAGE_DIR/meta.lua"
  copy_optional_file "$WORK_DIR/config.ini" "$PACKAGE_DIR/config.ini"
  copy_optional_file "$WORK_DIR/cacert.pem" "$PACKAGE_DIR/cacert.pem"

  copy_required_directory "$WORK_DIR/data" "$PACKAGE_DIR/data"
  copy_required_directory "$WORK_DIR/modules" "$PACKAGE_DIR/modules"
  copy_required_directory "$WORK_DIR/mods" "$PACKAGE_DIR/mods"

  for candidate in OTClient.exe otclient_x64.exe otclient.exe; do
    if [ -f "$WORK_DIR/$candidate" ]; then
      cp -f "$WORK_DIR/$candidate" "$PACKAGE_DIR/$candidate"
      return 0
    fi
  done

  echo "Required client executable not found in package source." >&2
  exit 1
}

prune_debug_artifacts() {
  find "$PACKAGE_DIR" -type f \( \
    -name '*.pdb' -o \
    -name '*.ilk' -o \
    -name '*.exp' -o \
    -name '*.lib' -o \
    -name '*.idb' -o \
    -name '*.obj' -o \
    -name '*.o' -o \
    -name '*.ipdb' -o \
    -name '*.iobj' -o \
    -name '*.tlog' -o \
    -name '*.log' -o \
    -name '.ninja_log' -o \
    -name '.ninja_deps' -o \
    -name 'CMakeCache.txt' -o \
    -name 'build.ninja' -o \
    -name 'compile_commands.json' -o \
    -name 'cmake_install.cmake' -o \
    -name 'InstallScripts.json' -o \
    -name 'TargetDirectories.txt' -o \
    -name 'rules.ninja' \
  \) -delete

  find "$PACKAGE_DIR" -type d \( \
    -name 'CMakeFiles' -o \
    -name '.vs' -o \
    -name 'Testing' -o \
    -name '.git' \
  \) -prune -exec rm -rf {} +
}

copy_runtime_tree
prune_debug_artifacts

require_path "$PACKAGE_DIR/init.lua" "Required runtime file not found: init.lua"
require_path "$PACKAGE_DIR/otclientrc.lua" "Required runtime file not found: otclientrc.lua"
require_directory "$PACKAGE_DIR/data" "data"
require_directory "$PACKAGE_DIR/modules" "modules"
require_directory "$PACKAGE_DIR/mods" "mods"
require_path "$PACKAGE_DIR/mods/README.txt" "Required runtime file not found: mods/README.txt"
require_path "$PACKAGE_DIR/mods/client_mods/mods.otmod" "Required runtime file not found: mods/client_mods/mods.otmod"

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
  if [ -f "$PACKAGE_DIR/$dll" ]; then
    continue
  fi

  if ! copy_runtime_dll "$dll" "${RUNTIME_DIRS[@]}"; then
    echo "Required runtime DLL not found: $dll" >&2
    exit 1
  fi
done

for required_runtime in libwinpthread-1.dll libgcc_s_seh-1.dll libstdc++-6.dll; do
  require_path "$PACKAGE_DIR/$required_runtime" "Required runtime DLL not found after lookup: $required_runtime"
done

rm -f "$OUTPUT_ZIP"
(cd "$PACKAGE_DIR" && zip -9 -qr -X "$OUTPUT_ZIP" .)

echo "$OUTPUT_ZIP"
