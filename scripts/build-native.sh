#!/bin/bash
source "$(dirname "$0")/common.sh"
mac_only; need xcrun
xcode-select -p >/dev/null || { echo "Install Xcode Command Line Tools with xcode-select --install." >&2; exit 1; }
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MAJOR" -ge 13 ] || { echo "macOS 13 or later is required." >&2; exit 1; }
SDK="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$ROOT/build"
xcrun swiftc -swift-version 5 -O -parse-as-library \
  -sdk "$SDK" -target "$(uname -m)-apple-macosx13.0" \
  "$ROOT/native/Wire.swift" "$ROOT/native/Keyboard.swift" "$ROOT/native/Pointer.swift" \
  "$ROOT/native/Accessibility.swift" "$ROOT/native/App.swift" \
  -framework AppKit -framework ApplicationServices -framework CoreGraphics \
  -o "$ROOT/build/XMonadMac"
BUNDLE="$ROOT/build/XMonadMac.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$ROOT/build/XMonadMac" "$BUNDLE/Contents/MacOS/"
cp "$ROOT/native/Info.plist" "$BUNDLE/Contents/Info.plist"
cp "$ROOT/native/AppIcon.icns" "$ROOT/native/MenuBarIcon.pdf" "$BUNDLE/Contents/Resources/"
cp "$ROOT/LICENSE" "$BUNDLE/Contents/Resources/LICENSE"
# A stable identity keeps the Accessibility grant across rebuilds. Creating
# one needs a password prompt, so the build only uses one that already exists:
# run scripts/signing-identity.sh once to set it up.
IDENTITY="${CODESIGN_IDENTITY:-$("$ROOT/scripts/signing-identity.sh" --if-ready || echo -)}"
if [ "$IDENTITY" = - ]; then
  echo "Ad-hoc signing: run scripts/signing-identity.sh once to keep the" >&2
  echo "Accessibility grant across rebuilds." >&2
fi
/usr/bin/codesign --force --sign "$IDENTITY" \
  --identifier org.xmonad.XMonadMac "$BUNDLE"
/usr/bin/codesign --verify --strict --verbose=2 "$BUNDLE"
echo "Built and signed $BUNDLE"
