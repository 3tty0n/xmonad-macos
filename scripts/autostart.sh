#!/bin/bash
set -euo pipefail
LABEL="org.xmonad.XMonadMac.autostart"
APP="$HOME/Applications/XMonadMac.app"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
DOMAIN="gui/$(id -u)"
xml_escape() { printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g' -e "s/'/\&apos;/g"; }
case "${1:-status}" in
  on|install|enable)
    [ -d "$APP" ] || { echo "XMonadMac is not installed at $APP" >&2; exit 1; }
    mkdir -p "$HOME/Library/LaunchAgents"
    APP_XML="$(xml_escape "$APP")"
    cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-g</string><string>$APP_XML</string></array>
  <key>RunAtLoad</key><true/>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
PLIST
    chmod 600 "$PLIST"
    /bin/launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
    /bin/launchctl bootstrap "$DOMAIN" "$PLIST"
    echo "XMonadMac will start at login."
    ;;
  off|uninstall|disable)
    /bin/launchctl bootout "$DOMAIN/$LABEL" >/dev/null 2>&1 || true
    rm -f "$PLIST"
    echo "XMonadMac login start disabled."
    ;;
  status)
    if [ -f "$PLIST" ]; then
      echo "enabled: $PLIST"
      /bin/launchctl print "$DOMAIN/$LABEL" 2>/dev/null | sed -n '1,20p' || echo "not currently loaded"
    else
      echo "disabled"
    fi
    ;;
  *) echo "Usage: $0 {on|off|status}" >&2; exit 2 ;;
esac
