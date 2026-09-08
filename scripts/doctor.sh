#!/bin/bash
source "$(dirname "$0")/common.sh"
mac_only; installed
sw_vers
"$HELPER" --diagnose
if [ -f "$SUPPORT/status.json" ]; then cat "$SUPPORT/status.json"; printf '\n'; fi
printf '\nPotential conflicting processes:\n'
pgrep -fl '(^|/)(yabai|skhd)( |$)' || true
printf '\nSignature:\n'
codesign -dv "$APP" 2>&1
printf '\nRecent log (may contain application names/window titles):\n'
tail -n 30 "$HOME/Library/Logs/XMonadMac/bridge.log" 2>/dev/null || true
