#!/bin/bash
source "$(dirname "$0")/common.sh"
need git; need tar
if [ $# -ne 1 ] || [ -e "$1" ]; then echo "Usage: $0 NEW_LOCAL_DIRECTORY (must not exist)" >&2; exit 1; fi
PIN=a9a8b5c1b91b63b0836f5810634c9b28ec0af788
DEST="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
case "$DEST/" in "$ROOT/"*) echo "Destination must be outside the prototype directory." >&2; exit 1;; esac
git clone https://github.com/xmonad/xmonad.git "$DEST"
git -C "$DEST" checkout -b macos-native "$PIN"
mkdir -p "$DEST/macos"
# Keep upstream X11 implementation untouched. This port is a separate Cabal package.
tar -C "$ROOT" --exclude=.git --exclude=build --exclude=dist-newstyle --exclude=__pycache__ -cf - . \
  | tar -C "$DEST/macos" -xf -
mkdir -p "$DEST/.github/workflows"
printf 'defaults:\n  run:\n    working-directory: macos\n' > "$DEST/.github/workflows/macos-native.yml"
cat "$ROOT/.github/workflows/ci.yml" >> "$DEST/.github/workflows/macos-native.yml"
git -C "$DEST" add macos .github/workflows/macos-native.yml
echo "Local fork prepared at $DEST, branch macos-native, base $PIN"
echo "Changes are staged, not committed or pushed. Build from its macos/ subdirectory."
