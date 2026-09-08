#!/bin/bash
source "$(dirname "$0")/common.sh"
need ghc; need cabal; need python3
"$ROOT/scripts/prepare-config.sh" "$ROOT/config/xmonad.hs"
cd "$ROOT"
cabal test core-tests --test-show-details=direct
cabal build exe:xmonad-engine
python3 tests/integration.py "$(cabal list-bin exe:xmonad-engine)"
# Native SDK compilation is deliberately a separate build-native.sh step.
