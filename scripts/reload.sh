#!/bin/bash
source "$(dirname "$0")/common.sh"
mac_only; installed
# Prefer the installed, self-contained build kit. A failed compile never replaces
# the current engine, and this keeps reload working even if this checkout moves.
if [ -x "$SUPPORT/recompile.sh" ]; then
  "$SUPPORT/recompile.sh" "$@"
else
  "$ROOT/scripts/build-engine.sh" "$@"
  "$HELPER" --validate-config "$ROOT/build/configure.json"
  umask 077
  cp "$ROOT/build/xmonad-engine" "$SUPPORT/xmonad-engine.new"
  chmod 755 "$SUPPORT/xmonad-engine.new"
  if [ -x "$SUPPORT/xmonad-engine" ]; then cp "$SUPPORT/xmonad-engine" "$SUPPORT/xmonad-engine.previous"; fi
  mv -f "$SUPPORT/xmonad-engine.new" "$SUPPORT/xmonad-engine"
fi
if pgrep -x XMonadMac >/dev/null 2>&1; then "$HELPER" --reload; else echo "Installed config. Start with ./scripts/run.sh"; fi
