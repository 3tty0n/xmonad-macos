#!/bin/bash
source "$(dirname "$0")/common.sh"
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
