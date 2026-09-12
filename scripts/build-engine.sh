#!/bin/bash
source "$(dirname "$0")/common.sh"
need ghc; need cabal
CONFIG="$(resolve_config "${1:-}")"
if [ ! -f "$CONFIG" ]; then
  if [ $# -gt 0 ] || [ -n "${XMONAD_CONFIG:-}" ]; then echo "Config not found: $CONFIG" >&2; exit 1; fi
  CONFIG="$ROOT/config/xmonad.hs"
fi
# Never edit the user's original config; compile a staged copy.
mkdir -p "$ROOT/build/config"
rm -rf "$ROOT/build/config/lib"
mkdir -p "$ROOT/build/config/lib"
cp "$CONFIG" "$ROOT/build/config/Main.hs"
if [ -d "$(dirname "$CONFIG")/lib" ]; then cp -R "$(dirname "$CONFIG")/lib/." "$ROOT/build/config/lib/"; fi
printf '%s\n' "$CONFIG" > "$ROOT/build/config-source.txt"
echo "Config: $CONFIG"
cd "$ROOT"
cabal test core-tests --test-show-details=direct
cabal build exe:xmonad-engine
ENGINE="$(cabal list-bin exe:xmonad-engine)"
cp "$ENGINE" "$ROOT/build/xmonad-engine.new"
chmod 755 "$ROOT/build/xmonad-engine.new"
# Config evaluation is checked without executing startupHook.
"$ROOT/build/xmonad-engine.new" --check-config > "$ROOT/build/configure.json"
if [ -x "$ROOT/build/XMonadMac" ] && [ "$(uname -s)" = Darwin ]; then
  "$ROOT/build/XMonadMac" --validate-config "$ROOT/build/configure.json"
elif [ -x "$HELPER" ] && [ "$(uname -s)" = Darwin ]; then
  "$HELPER" --validate-config "$ROOT/build/configure.json"
fi
mv -f "$ROOT/build/xmonad-engine.new" "$ROOT/build/xmonad-engine"
echo "Built $ROOT/build/xmonad-engine"
