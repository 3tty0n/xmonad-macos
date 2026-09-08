#!/bin/bash
source "$(dirname "$0")/common.sh"
mac_only; need brew; need xcrun
xcode-select -p >/dev/null || { echo "Run xcode-select --install, then rerun this script." >&2; exit 1; }
if ! command -v ghc >/dev/null 2>&1; then
  brew install ghc@9.12
  export PATH="$(brew --prefix ghc@9.12)/bin:$PATH"
fi
if ! command -v cabal >/dev/null 2>&1; then brew install cabal-install; fi
cabal update
"$ROOT/scripts/build.sh" "$@"
"$ROOT/scripts/install.sh"
