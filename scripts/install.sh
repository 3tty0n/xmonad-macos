#!/bin/bash
source "$(dirname "$0")/common.sh"
mac_only
[ -x "$ROOT/build/xmonad-engine" ] && [ -d "$ROOT/build/XMonadMac.app" ] || { echo "Run scripts/build.sh first." >&2; exit 1; }
# A running app is quit (SIGTERM restores owned windows) and relaunched in the
# same mode once the new build is in place.
RELAUNCH=""
if pgrep -x XMonadMac >/dev/null 2>&1; then
  RELAUNCH=normal
  if pgrep -f 'XMonadMac.*--dry-run' >/dev/null 2>&1; then RELAUNCH=dry-run; fi
  echo "Stopping the running XMonadMac for the swap..."
  pkill -TERM -x XMonadMac || true
  for _ in $(seq 50); do pgrep -x XMonadMac >/dev/null 2>&1 || break; sleep 0.2; done
  if pgrep -x XMonadMac >/dev/null 2>&1; then
    echo "XMonadMac did not quit within 10s; quit it from its menu and retry." >&2; exit 1
  fi
fi
umask 077
mkdir -p "$HOME/Applications" "$SUPPORT" "$HOME/.config/xmonad-mac" "$HOME/.local/bin"
chmod 700 "$SUPPORT" "$HOME/.config/xmonad-mac"
# Install a self-contained source kit so xmonad.hs can be recompiled after the checkout moves.
KIT_NEW="$SUPPORT/build-kit.new"
rm -rf "$KIT_NEW"
stage_kit "$KIT_NEW"
if [ -d "$SUPPORT/build-kit/dist-newstyle" ]; then
  cp -Rp "$SUPPORT/build-kit/dist-newstyle" "$KIT_NEW/dist-newstyle"
fi
rm -rf "$SUPPORT/build-kit.previous"
if [ -d "$SUPPORT/build-kit" ]; then mv "$SUPPORT/build-kit" "$SUPPORT/build-kit.previous"; fi
mv "$KIT_NEW" "$SUPPORT/build-kit"
rm -f "$SUPPORT/recompile.sh" "$SUPPORT/autostart.sh" "$SUPPORT/xmonadctl"
# The control commands live in the compiled config, as upstream's do, so both
# names are the engine binary itself.
ln -sfn "$SUPPORT/xmonad-engine" "$HOME/.local/bin/xmonadctl"
ln -sfn "$SUPPORT/xmonad-engine" "$HOME/.local/bin/xmonad"
requirement() {
  # Missing or unsigned bundles make codesign fail; pipefail would otherwise
  # abort a first install with no message.
  /usr/bin/codesign -d -r- "$1" 2>/dev/null | sed -n 's/^designated => //p' || true
}
OLD_REQ=""
if [ -d "$APP" ]; then OLD_REQ="$(requirement "$APP")"; fi
if [ -d "$APP" ]; then
  rm -rf "$HOME/Applications/XMonadMac.previous.app"
  mv "$APP" "$HOME/Applications/XMonadMac.previous.app"
fi
/usr/bin/ditto "$ROOT/build/XMonadMac.app" "$APP"
# A changed designated requirement leaves a stale Accessibility entry that
# cannot be overridden by re-adding the app, so drop it and ask again.
NEW_REQ="$(requirement "$APP")"
if [ -n "$OLD_REQ" ] && [ "$OLD_REQ" != "$NEW_REQ" ]; then
  tccutil reset Accessibility org.xmonad.XMonadMac >/dev/null 2>&1 || true
  echo "The app signature changed; its Accessibility grant was reset."
  echo "Re-add $APP under Privacy & Security -> Accessibility."
fi
if [ -x "$SUPPORT/xmonad-engine" ]; then cp "$SUPPORT/xmonad-engine" "$SUPPORT/xmonad-engine.previous"; fi
cp "$ROOT/build/xmonad-engine" "$SUPPORT/xmonad-engine.new"
chmod 755 "$SUPPORT/xmonad-engine.new"
mv -f "$SUPPORT/xmonad-engine.new" "$SUPPORT/xmonad-engine"
if [ ! -e "$HOME/.config/xmonad-mac/xmonad.hs" ] && [ ! -e "$HOME/.xmonad/xmonad.hs" ]; then
  cp "$ROOT/build/config/Main.hs" "$HOME/.config/xmonad-mac/xmonad.hs"
  if [ -d "$ROOT/build/config/lib" ]; then cp -R "$ROOT/build/config/lib" "$HOME/.config/xmonad-mac/"; fi
fi
echo "Installed: $APP"
echo "Config: $HOME/.config/xmonad-mac/xmonad.hs"
echo "Control: $HOME/.local/bin/xmonad (and xmonadctl)"
echo "Start a read-only preview: xmonad start --dry-run"
case "$RELAUNCH" in
  normal) /usr/bin/open "$APP"; echo "Relaunched XMonadMac." ;;
  dry-run) /usr/bin/open "$APP" --args --dry-run; echo "Relaunched XMonadMac (dry-run)." ;;
esac
