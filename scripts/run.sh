#!/bin/bash
source "$(dirname "$0")/common.sh"
mac_only; installed
if [ $# -gt 1 ] || { [ $# -eq 1 ] && [ "$1" != --dry-run ]; }; then echo "Usage: $0 [--dry-run]" >&2; exit 1; fi
if pgrep -x XMonadMac >/dev/null 2>&1; then echo "XMonadMac is already running; quit it before changing startup mode." >&2; exit 1; fi
if [ "${1:-}" != --dry-run ]; then
  for process in yabai skhd; do
    if pgrep -x "$process" >/dev/null 2>&1; then
      echo "$process is running. Stop its service explicitly before starting XMonadMac." >&2; exit 1
    fi
  done
fi
open "$APP" --args "$@"
