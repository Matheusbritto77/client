#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_SRC="${1:-$ROOT/dist/macos-prod-app/OTClient.app}"
OUT_DMG="${2:-$ROOT/dist/OTClient-macos-prod.dmg}"
TEMP_DMG="$ROOT/dist/OTClient-macos-prod-temp.dmg"

if [ ! -d "$APP_SRC" ]; then
  echo "App bundle not found: $APP_SRC" >&2
  exit 1
fi

STAMP="$(date +%Y%m%d%H%M%S)"
STAGE="$(mktemp -d "$ROOT/dist/macos-dmg-stage.XXXXXX")"
MOUNT_POINT="$ROOT/dist/macos-dmg-mount"
BG_DIR="$STAGE/.background"
BG_PNG="$BG_DIR/background.png"

cleanup() {
  if mount | grep -q "on $MOUNT_POINT "; then
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

if [ -e "$OUT_DMG" ]; then
  mv "$OUT_DMG" "$OUT_DMG.bak-$STAMP"
fi
if [ -e "$TEMP_DMG" ]; then
  mv "$TEMP_DMG" "$TEMP_DMG.bak-$STAMP"
fi

mkdir -p "$BG_DIR"
cp -R "$APP_SRC" "$STAGE/OTClient.app"
ln -s /Applications "$STAGE/Applications"
chflags hidden "$BG_DIR"

ICON_SRC="$ROOT/cmake/OTClient.icns"
ICON_PNG="$STAGE/.background/app-icon.png"
if command -v sips >/dev/null 2>&1; then
  sips -s format png "$ICON_SRC" --out "$ICON_PNG" >/dev/null
else
  echo "sips is required to convert the app icon." >&2
  exit 1
fi

python3 - "$ICON_PNG" "$BG_PNG" <<'PY'
from pathlib import Path
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

icon_path = Path(sys.argv[1])
bg_path = Path(sys.argv[2])

W, H = 900, 540
img = Image.new("RGBA", (W, H), "#ffffff")
draw = ImageDraw.Draw(img)

# soft frame
draw.rounded_rectangle((22, 22, W - 23, H - 23), radius=28, outline="#e7e7e7", width=2)
draw.rounded_rectangle((42, 42, W - 43, H - 43), radius=24, fill="#fbfbfb", outline="#f0f0f0", width=1)

# central card
shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
shadow_draw = ImageDraw.Draw(shadow)
shadow_draw.rounded_rectangle((150, 150, 750, 390), radius=28, fill=(0, 0, 0, 64))
shadow = shadow.filter(ImageFilter.GaussianBlur(18))
img = Image.alpha_composite(img, shadow)
draw = ImageDraw.Draw(img)
draw.rounded_rectangle((144, 144, 744, 384), radius=28, fill="#ffffff", outline="#e8e8e8", width=2)

def font(paths, size):
    for path in paths:
        if Path(path).exists():
            try:
                return ImageFont.truetype(path, size=size)
            except Exception:
                pass
    return ImageFont.load_default()

title_font = font([
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
], 34)
body_font = font([
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
], 22)
small_font = font([
    "/System/Library/Fonts/Supplemental/Arial.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
], 18)

# app icon
icon = Image.open(icon_path).convert("RGBA").resize((116, 116), Image.LANCZOS)
icon_bg = Image.new("RGBA", (138, 138), (0, 0, 0, 0))
icon_shadow = Image.new("RGBA", (138, 138), (0, 0, 0, 0))
ImageDraw.Draw(icon_shadow).ellipse((10, 12, 128, 130), fill=(0, 0, 0, 40))
icon_shadow = icon_shadow.filter(ImageFilter.GaussianBlur(10))
icon_bg = Image.alpha_composite(icon_bg, icon_shadow)
icon_bg.alpha_composite(icon, (11, 11))
img.alpha_composite(icon_bg, (182, 182))

# arrow
arrow_color = "#c0c0c0"
draw.rounded_rectangle((410, 245, 520, 255), radius=5, fill=arrow_color)
draw.polygon([(520, 250), (492, 230), (492, 270)], fill=arrow_color)

# Applications badge
badge_x1, badge_y1, badge_x2, badge_y2 = 548, 194, 676, 322
draw.rounded_rectangle((badge_x1, badge_y1, badge_x2, badge_y2), radius=22, fill="#f7f7f7", outline="#e2e2e2", width=2)
draw.text((612, 348), "Applications", fill="#3d3d3d", font=body_font, anchor="mm")
draw.text((330, 164), "Arraste o app para instalar", fill="#1f1f1f", font=title_font, anchor="ma")
draw.text((330, 424), "Depois solte em Applications para concluir a instalação.", fill="#6d6d6d", font=small_font, anchor="ma")

bg_path.parent.mkdir(parents=True, exist_ok=True)
img.save(bg_path)
PY

hdiutil create -volname "OTClient" -srcfolder "$STAGE" -ov -format UDRW "$TEMP_DMG"

hdiutil attach "$TEMP_DMG" -nobrowse -mountpoint "$MOUNT_POINT"
chflags hidden "$MOUNT_POINT/.background"
SetFile -a V "$MOUNT_POINT/.background" || true

osascript <<EOF
tell application "Finder"
  tell disk "OTClient"
    set bgPath to POSIX file "$MOUNT_POINT/.background/background.png" as alias
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 1010, 620}
    set arrangement of icon view options of container window to not arranged
    set icon size of icon view options of container window to 128
    set background picture of icon view options of container window to bgPath
    set position of item "OTClient.app" of container window to {260, 290}
    set position of item "Applications" of container window to {640, 290}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
EOF

hdiutil detach "$MOUNT_POINT"

hdiutil convert "$TEMP_DMG" -ov -format UDZO -o "$OUT_DMG"

echo "$OUT_DMG"
