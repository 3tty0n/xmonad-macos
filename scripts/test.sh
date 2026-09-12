#!/bin/bash
source "$(dirname "$0")/common.sh"
need ghc; need cabal; need python3
mkdir -p "$ROOT/build/config/lib"
rm -rf "$ROOT/build/config/lib"
mkdir -p "$ROOT/build/config/lib"
cp "$ROOT/config/xmonad.hs" "$ROOT/build/config/Main.hs"
printf '%s\n' "$ROOT/config/xmonad.hs" > "$ROOT/build/config-source.txt"
cd "$ROOT"
cabal test core-tests --test-show-details=direct
cabal build exe:xmonad-engine
python3 tests/integration.py "$(cabal list-bin exe:xmonad-engine)"
# Native SDK compilation is deliberately a separate build-native.sh step.
