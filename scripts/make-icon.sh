#!/bin/bash
# Regenerates the app and menu bar icons from the SVGs. Needs rsvg-convert
# (brew install librsvg); the generated files are committed so builds do not.
source "$(dirname "$0")/common.sh"
mac_only; need rsvg-convert; need iconutil
SET="$ROOT/build/AppIcon.iconset"
rm -rf "$SET"; mkdir -p "$SET"
for size in 16 32 128 256 512; do
  rsvg-convert -w "$size" -h "$size" "$ROOT/native/icon.svg" \
    -o "$SET/icon_${size}x${size}.png"
  rsvg-convert -w "$((size * 2))" -h "$((size * 2))" "$ROOT/native/icon.svg" \
    -o "$SET/icon_${size}x${size}@2x.png"
done
iconutil -c icns "$SET" -o "$ROOT/native/AppIcon.icns"
rm -rf "$SET"
# Vector PDF so the menu bar template scales on any display.
rsvg-convert -f pdf "$ROOT/native/menubar.svg" -o "$ROOT/native/MenuBarIcon.pdf"
echo "Wrote $ROOT/native/AppIcon.icns and $ROOT/native/MenuBarIcon.pdf"
