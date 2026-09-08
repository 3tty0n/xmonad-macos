#!/bin/bash
source "$(dirname "$0")/common.sh"
mac_only
[ -x "$ROOT/build/xmonad-engine" ] && [ -d "$ROOT/build/XMonadMac.app" ] || { echo "Run scripts/build.sh first." >&2; exit 1; }
if pgrep -x XMonadMac >/dev/null 2>&1; then
  echo "Quit XMonadMac from its menu before replacing the native app. Use reload.sh for config-only updates." >&2; exit 1
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
cp "$ROOT/scripts/recompile-installed.sh" "$SUPPORT/recompile.sh"
cp "$ROOT/scripts/autostart.sh" "$SUPPORT/autostart.sh"
cp "$ROOT/scripts/xmonadctl.sh" "$SUPPORT/xmonadctl"
chmod 755 "$SUPPORT/recompile.sh" "$SUPPORT/autostart.sh" "$SUPPORT/xmonadctl"
ln -sfn "$SUPPORT/xmonadctl" "$HOME/.local/bin/xmonadctl"
# xmonad --recompile / --restart, for muscle memory from upstream xmonad.
ln -sfn "$SUPPORT/xmonadctl" "$HOME/.local/bin/xmonad"
if [ -d "$APP" ]; then
  rm -rf "$HOME/Applications/XMonadMac.previous.app"
  mv "$APP" "$HOME/Applications/XMonadMac.previous.app"
fi
/usr/bin/ditto "$ROOT/build/XMonadMac.app" "$APP"
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
echo "Control: $HOME/.local/bin/xmonadctl"
echo "Start a read-only preview: ./scripts/run.sh --dry-run"
