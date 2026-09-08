#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SUPPORT="$HOME/Library/Application Support/XMonadMac"
APP="$HOME/Applications/XMonadMac.app"
HELPER="$APP/Contents/MacOS/XMonadMac"
# Only fall back to the Homebrew locations when the toolchain is not already
# on PATH, so a caller-supplied ghc/cabal (tests, custom installs) still wins.
command -v ghc >/dev/null 2>&1 && command -v cabal >/dev/null 2>&1 ||
  export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
if ! command -v ghc >/dev/null 2>&1 && command -v brew >/dev/null 2>&1; then
  GHC_PREFIX="$(brew --prefix ghc@9.12 2>/dev/null || true)"
  if [ -n "$GHC_PREFIX" ] && [ -x "$GHC_PREFIX/bin/ghc" ]; then
    export PATH="$GHC_PREFIX/bin:$PATH"
  fi
fi
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
need() { command -v "$1" >/dev/null 2>&1 || { echo "Missing command: $1" >&2; exit 1; }; }
mac_only() { [ "$(uname -s)" = Darwin ] || { echo "This command requires macOS." >&2; exit 1; }; }
installed() { [ -x "$HELPER" ] || { echo "Run scripts/bootstrap.sh first." >&2; exit 1; }; }
