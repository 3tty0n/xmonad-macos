#!/bin/bash
set -euo pipefail
SUPPORT="$HOME/Library/Application Support/XMonadMac"
KIT="$SUPPORT/build-kit"
APP="$HOME/Applications/XMonadMac.app"
HELPER="$APP/Contents/MacOS/XMonadMac"
# Config search order: explicit argument, XMONAD_CONFIG, then the first of
# ~/.xmonad/xmonad.hs (upstream layout) and the XDG location that exists.
resolve_config() {
  local explicit="${1:-${XMONAD_CONFIG:-}}" c
  if [ -n "$explicit" ]; then printf '%s\n' "$explicit"; return 0; fi
  for c in "$HOME/.xmonad/xmonad.hs" "$HOME/.config/xmonad-mac/xmonad.hs"; do
    if [ -f "$c" ]; then printf '%s\n' "$c"; return 0; fi
  done
  printf '%s\n' "$HOME/.config/xmonad-mac/xmonad.hs"
}
CONFIG="$(resolve_config "${1:-}")"
# Only fall back to the Homebrew locations when the toolchain is not already
# on PATH, so a caller-supplied ghc/cabal (tests, custom installs) still wins.
command -v ghc >/dev/null 2>&1 && command -v cabal >/dev/null 2>&1 ||
  export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! command -v ghc >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then
  GHC_PREFIX="$(brew --prefix ghc@9.12 2>/dev/null || true)"
  [ -z "$GHC_PREFIX" ] || export PATH="$GHC_PREFIX/bin:$PATH"
fi
for cmd in ghc cabal; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "Missing command: $cmd" >&2; exit 1; }
done
[ -d "$KIT/src" ] && [ -f "$KIT/xmonad-macos.cabal" ] || {
  echo "Installed build kit is missing. Re-run scripts/install.sh from the XMonadMac source tree." >&2
  exit 1
}
[ -f "$CONFIG" ] || { echo "Config not found: $CONFIG" >&2; exit 1; }
mkdir -p "$KIT/build/config/lib"
rm -rf "$KIT/build/config/lib"
mkdir -p "$KIT/build/config/lib"
cp "$CONFIG" "$KIT/build/config/Main.hs"
if [ -d "$(dirname "$CONFIG")/lib" ]; then
  cp -R "$(dirname "$CONFIG")/lib/." "$KIT/build/config/lib/"
fi
printf '%s\n' "$CONFIG" > "$KIT/build/config-source.txt"
cd "$KIT"
cabal build exe:xmonad-engine
ENGINE="$(cabal list-bin exe:xmonad-engine)"
TMP="$SUPPORT/xmonad-engine.new.$$"
CONF="$SUPPORT/configure.new.$$.json"
cleanup() { rm -f "$TMP" "$CONF"; }
trap cleanup EXIT
cp "$ENGINE" "$TMP"
chmod 755 "$TMP"
"$TMP" --check-config > "$CONF"
if [ -x "$HELPER" ]; then "$HELPER" --validate-config "$CONF"; fi
if [ -x "$SUPPORT/xmonad-engine" ]; then cp "$SUPPORT/xmonad-engine" "$SUPPORT/xmonad-engine.previous"; fi
mv -f "$TMP" "$SUPPORT/xmonad-engine"
cp "$CONF" "$SUPPORT/configure.json"
trap - EXIT
rm -f "$CONF"
echo "Installed compiled config: $CONFIG"
