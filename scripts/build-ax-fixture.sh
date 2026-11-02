#!/bin/bash
# Build the test-only AppKit fixture. It is intentionally not part of the
# signed XMonadMac bundle; the helper treats it as an ordinary client app.
source "$(dirname "$0")/common.sh"
mac_only; need xcrun
SDK="$(xcrun --sdk macosx --show-sdk-path)"
APP="$ROOT/build/AXFixture.app"
BIN="$APP/Contents/MacOS/AXFixture"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -swift-version 5 -O -sdk "$SDK" \
  -target "$(uname -m)-apple-macosx13.0" \
  "$ROOT/tests/AXFixture.swift" -framework AppKit -o "$BIN"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleExecutable</key><string>AXFixture</string>
  <key>CFBundleIdentifier</key><string>org.xmonad.AXFixture</string>
  <key>CFBundleName</key><string>AXFixture</string>
  <key>CFBundleDisplayName</key><string>AXFixture</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST
/usr/bin/codesign --force --sign - --identifier org.xmonad.AXFixture "$APP" >/dev/null
echo "Built $APP"
