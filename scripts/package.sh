#!/bin/bash
# Build the release bundle: the app carrying the source kit and an engine
# compiled from the shipped config, which it installs on first launch.
#
# CODESIGN_IDENTITY selects the signing identity (a Developer ID for a public
# release). With NOTARY_APPLE_ID, NOTARY_TEAM_ID and NOTARY_PASSWORD set, the
# bundle is also notarized and stapled.
source "$(dirname "$0")/common.sh"
mac_only; need ghc; need cabal
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/native/Info.plist")"
CABAL_VERSION="$(sed -n 's/^version:[[:space:]]*//p' "$ROOT/xmonad-macos.cabal")"
[ "$VERSION" = "$CABAL_VERSION" ] || {
  echo "Info.plist says $VERSION but xmonad-macos.cabal says $CABAL_VERSION." >&2; exit 1; }
"$ROOT/scripts/build.sh" "$ROOT/config/xmonad.hs"

OUT="$ROOT/build/release"
BUNDLE="$OUT/XMonadMac.app"
HELPERS="$BUNDLE/Contents/Helpers"
rm -rf "$OUT"
mkdir -p "$OUT"
/usr/bin/ditto "$ROOT/build/XMonadMac.app" "$BUNDLE"
mkdir -p "$HELPERS"
cp "$ROOT/build/xmonad-engine" "$HELPERS/xmonad-engine"
chmod 755 "$HELPERS/xmonad-engine"

# The engine is installed outside the bundle, so every library it needs
# beyond the OS travels beside it and is found through @loader_path.
foreign_libs() {
  /usr/bin/otool -L "$1" | tail -n +2 | awk '{print $1}' |
    grep -v -e '^/usr/lib/' -e '^/System/' -e '^@loader_path/' || true
}
for lib in $(foreign_libs "$HELPERS/xmonad-engine"); do
  case "$lib" in
    /*) ;;
    *) echo "Cannot bundle $lib: only absolute install names are handled." >&2; exit 1 ;;
  esac
  name="$(basename "$lib")"
  cp "$lib" "$HELPERS/$name"
  chmod 644 "$HELPERS/$name"
  /usr/bin/install_name_tool -id "@loader_path/$name" "$HELPERS/$name"
  /usr/bin/install_name_tool -change "$lib" "@loader_path/$name" "$HELPERS/xmonad-engine"
  nested="$(foreign_libs "$HELPERS/$name" | grep -v -F "$lib" || true)"
  [ -z "$nested" ] || { echo "$name needs $nested, which is not bundled." >&2; exit 1; }
done
stage_kit "$BUNDLE/Contents/Resources/build-kit"

IDENTITY="${CODESIGN_IDENTITY:-$("$ROOT/scripts/signing-identity.sh" --if-ready || echo -)}"
SIGN=(/usr/bin/codesign --force --sign "$IDENTITY")
if [ "$IDENTITY" != - ]; then SIGN+=(--options runtime --timestamp); fi
for code in "$HELPERS"/*.dylib "$HELPERS/xmonad-engine"; do
  [ -e "$code" ] && "${SIGN[@]}" "$code"
done
"${SIGN[@]}" "$BUNDLE"
/usr/bin/codesign --verify --strict --deep "$BUNDLE"
"$HELPERS/xmonad-engine" --version

ZIP="$OUT/XMonadMac-$VERSION-$(uname -m).zip"
/usr/bin/ditto -c -k --keepParent "$BUNDLE" "$ZIP"
if [ -n "${NOTARY_APPLE_ID:-}" ]; then
  xcrun notarytool submit "$ZIP" --apple-id "$NOTARY_APPLE_ID" \
    --team-id "$NOTARY_TEAM_ID" --password "$NOTARY_PASSWORD" --wait
  xcrun stapler staple "$BUNDLE"
  rm -f "$ZIP"
  /usr/bin/ditto -c -k --keepParent "$BUNDLE" "$ZIP"
fi
echo "Packaged $ZIP"
