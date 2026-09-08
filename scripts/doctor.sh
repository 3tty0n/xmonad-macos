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
REQ="$(codesign -d -r- "$APP" 2>/dev/null | grep '^designated' || true)"
printf '%s\n' "$REQ"
case "$REQ" in
  *"certificate leaf"*) ;;
  *) printf 'Ad-hoc signed: rebuilding invalidates the Accessibility grant.\n';;
esac
printf '\nRecent log (may contain application names/window titles):\n'
tail -n 30 "$HOME/Library/Logs/XMonadMac/bridge.log" 2>/dev/null || true
