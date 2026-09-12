#!/bin/bash
source "$(dirname "$0")/common.sh"
mac_only
[ -x "$ROOT/build/xmonad-engine" ] && [ -d "$ROOT/build/XMonadMac.app" ] || { echo "Run scripts/build.sh first." >&2; exit 1; }
if pgrep -x XMonadMac >/dev/null 2>&1; then
  echo "Quit XMonadMac from its menu before replacing the native app. Use xmonad --recompile for config-only updates." >&2; exit 1
fi
umask 077
mkdir -p "$HOME/Applications" "$SUPPORT" "$HOME/.config/xmonad-mac" "$HOME/.local/bin"
chmod 700 "$SUPPORT" "$HOME/.config/xmonad-mac"
# Install a self-contained source kit so xmonad.hs can be recompiled after the checkout moves.
KIT_NEW="$SUPPORT/build-kit.new"
rm -rf "$KIT_NEW"
mkdir -p "$KIT_NEW"
cp "$ROOT/xmonad-macos.cabal" "$ROOT/cabal.project" "$ROOT/LICENSE" "$ROOT/README.md" "$ROOT/CHANGELOG.md" "$KIT_NEW/"
for dir in src config docs native scripts tests .github; do cp -R "$ROOT/$dir" "$KIT_NEW/"; done
rm -rf "$KIT_NEW/build" "$KIT_NEW/dist-newstyle" "$KIT_NEW/tests/__pycache__"
rm -rf "$SUPPORT/build-kit.previous"
if [ -d "$SUPPORT/build-kit" ]; then mv "$SUPPORT/build-kit" "$SUPPORT/build-kit.previous"; fi
mv "$KIT_NEW" "$SUPPORT/build-kit"
rm -f "$SUPPORT/recompile.sh" "$SUPPORT/autostart.sh" "$SUPPORT/xmonadctl"
# The control commands live in the compiled config, as upstream's do, so both
# names are the engine binary itself.
ln -sfn "$SUPPORT/xmonad-engine" "$HOME/.local/bin/xmonadctl"
ln -sfn "$SUPPORT/xmonad-engine" "$HOME/.local/bin/xmonad"
requirement() { /usr/bin/codesign -d -r- "$1" 2>/dev/null | sed -n 's/^designated => //p'; }
OLD_REQ="$(requirement "$APP")"
if [ -d "$APP" ]; then
  rm -rf "$HOME/Applications/XMonadMac.previous.app"
  #mv "$APP" "$HOME/Applications/XMonadMac.previous.app"
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
