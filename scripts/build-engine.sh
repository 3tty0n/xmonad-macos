#!/bin/bash
source "$(dirname "$0")/common.sh"
need ghc; need cabal
"$ROOT/scripts/prepare-config.sh" "$@"
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
