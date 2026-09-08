#!/bin/bash
set -euo pipefail
SUPPORT="$HOME/Library/Application Support/XMonadMac"
APP="$HOME/Applications/XMonadMac.app"
HELPER="$APP/Contents/MacOS/XMonadMac"
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
CONFIG="$(resolve_config)"
usage() {
  cat <<USAGE
Usage: xmonad --FLAG | COMMAND [ARGS]

  --recompile [xmonad.hs]  compile the config; leave the running engine alone
  --restart                run the compiled config, starting the app if needed

  status                   show current bridge status
  doctor                   print native diagnostics
  log                      follow bridge.log
  config                   open xmonad.hs
  pause|resume             pause/resume tiling
  recover                  restore windows minimized by XMonadMac
  quit                     quit XMonadMac
  autostart on|off|status  manage login startup
  self-test                verify focused-window AX read/write and read-back
  dump                     write diagnostic snapshot

  recompile [xmonad.hs]    --recompile, then --restart
  reload                   reload the already-compiled engine

The app itself is built from the source tree with make; see make help.
USAGE
}
[ $# -gt 0 ] || { usage; exit 2; }
cmd="$1"; shift
case "$cmd" in
  status)
    if [ -f "$SUPPORT/status.json" ]; then cat "$SUPPORT/status.json"; printf '\n'; else echo "XMonadMac is not running."; fi
    ;;
  pause|resume|reload|dump|quit)
    [ -x "$HELPER" ] || { echo "XMonadMac is not installed." >&2; exit 1; }
    "$HELPER" "--$cmd"
    ;;
  recover)
    [ -x "$HELPER" ] || { echo "XMonadMac is not installed." >&2; exit 1; }
    "$HELPER" --recover
    ;;
  recompile|--recompile)
    [ -x "$SUPPORT/recompile.sh" ] || { echo "Installed recompiler missing; re-run scripts/install.sh." >&2; exit 1; }
    "$SUPPORT/recompile.sh" "${1:-$CONFIG}"
    # Upstream --recompile only builds; the bare command also restarts.
    if [ "$cmd" = recompile ]; then
      if pgrep -x XMonadMac >/dev/null 2>&1; then "$HELPER" --reload; else /usr/bin/open -g "$APP"; fi
    fi
    ;;
  --restart)
    [ -x "$HELPER" ] || { echo "XMonadMac is not installed." >&2; exit 1; }
    if pgrep -x XMonadMac >/dev/null 2>&1; then "$HELPER" --reload; else /usr/bin/open -g "$APP"; fi
    ;;
  doctor)
    [ -x "$HELPER" ] || { echo "XMonadMac is not installed." >&2; exit 1; }
    "$HELPER" --diagnose
    ;;
  self-test)
    [ -x "$HELPER" ] || { echo "XMonadMac is not installed." >&2; exit 1; }
    "$HELPER" --self-test
    ;;
  config)
    [ -f "$CONFIG" ] || { echo "Config not found: $CONFIG" >&2; exit 1; }
    /usr/bin/open "$CONFIG"
    ;;
  log)
    exec /usr/bin/tail -f "$HOME/Library/Logs/XMonadMac/bridge.log"
    ;;
  autostart)
    [ -x "$SUPPORT/autostart.sh" ] || { echo "Installed autostart helper missing; re-run scripts/install.sh." >&2; exit 1; }
    exec "$SUPPORT/autostart.sh" "${1:-status}"
    ;;
  help|-h|--help) usage ;;
  *) usage >&2; exit 2 ;;
esac
