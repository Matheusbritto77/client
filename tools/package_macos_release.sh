#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SRC="${1:-}"
OUT_PREFIX="${2:-}"
DMG_TOOL="${3:-$ROOT/tools/make_macos_dmg.sh}"

usage() {
  echo "Usage: $0 /path/to/OTClient.app /path/to/output-prefix [make_macos_dmg.sh]" >&2
}

if [ -z "$APP_SRC" ] || [ -z "$OUT_PREFIX" ]; then
  usage
  exit 1
fi

if [ ! -d "$APP_SRC" ]; then
  echo "App bundle not found: $APP_SRC" >&2
  exit 1
fi

if [ ! -f "$DMG_TOOL" ]; then
  echo "DMG helper not found: $DMG_TOOL" >&2
  exit 1
fi

ZIP_OUT="${OUT_PREFIX}.zip"
DMG_OUT="${OUT_PREFIX}.dmg"
mkdir -p "$(dirname "$ZIP_OUT")" "$(dirname "$DMG_OUT")"

NOTARY_ARGS=()
HAS_NOTARY_CREDENTIALS=0
HAS_DEVELOPER_ID_SIGNING=0

if [ -n "${MACOS_NOTARY_KEYCHAIN_PROFILE:-}" ]; then
  NOTARY_ARGS=(--keychain-profile "$MACOS_NOTARY_KEYCHAIN_PROFILE")
  HAS_NOTARY_CREDENTIALS=1
elif [ -n "${MACOS_NOTARY_APPLE_ID:-}" ] && [ -n "${MACOS_NOTARY_TEAM_ID:-}" ] && [ -n "${MACOS_NOTARY_PASSWORD:-}" ]; then
  NOTARY_ARGS=(--apple-id "$MACOS_NOTARY_APPLE_ID" --team-id "$MACOS_NOTARY_TEAM_ID" --password "$MACOS_NOTARY_PASSWORD")
  HAS_NOTARY_CREDENTIALS=1
fi

sign_app() {
  local sign_identity="${MACOS_CODESIGN_IDENTITY:-}"
  local sign_args=(
    --force
    --deep
    --sign
  )

  xattr -cr "$APP_SRC"

  if [ -n "$sign_identity" ] && [ "$sign_identity" != "-" ]; then
    sign_args+=( "$sign_identity" "--options" "runtime" "--timestamp" )
    HAS_DEVELOPER_ID_SIGNING=1
  else
    sign_args+=( "-" )
    echo "MACOS_CODESIGN_IDENTITY is not set; using ad hoc signing." >&2
  fi

  codesign "${sign_args[@]}" "$APP_SRC"
  codesign --verify --deep --strict --verbose=4 "$APP_SRC"
}

submit_for_notarization() {
  local archive_path="$1"
  if [ "$HAS_NOTARY_CREDENTIALS" -eq 0 ] || [ "$HAS_DEVELOPER_ID_SIGNING" -eq 0 ]; then
    echo "Skipping notarization for ${archive_path}: no notarization credentials configured." >&2
    return 0
  fi

  echo "Submitting for notarization: ${archive_path}" >&2
  xcrun notarytool submit "$archive_path" --wait "${NOTARY_ARGS[@]}"
}

sign_app

ditto -c -k --keepParent "$APP_SRC" "$ZIP_OUT"
submit_for_notarization "$ZIP_OUT"

bash "$DMG_TOOL" "$APP_SRC" "$DMG_OUT"
submit_for_notarization "$DMG_OUT"

if [ -n "${MACOS_CODESIGN_IDENTITY:-}" ] && [ "${MACOS_CODESIGN_IDENTITY:-}" != "-" ] && [ "$HAS_NOTARY_CREDENTIALS" -eq 1 ]; then
  xcrun stapler staple "$DMG_OUT"
  xcrun stapler validate "$DMG_OUT"
fi

echo "$ZIP_OUT"
echo "$DMG_OUT"
