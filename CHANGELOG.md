# Changelog

## Unreleased

- More xmonad-contrib modules ported under their own module paths:
  `Layout.Grid`, `Layout.Simplest`, `Layout.ResizableTile`, `Actions.CycleWS`
  and `Actions.WithAll`. See docs/COMPATIBILITY.md for the full list.
- `Circle` resizes its centred master with `M-h` / `M-l`, which upstream
  cannot do; plain `Circle` keeps upstream's proportions.
- `ThreeCol`, `ThreeColMid` and `Circle` layouts, ported from xmonad-contrib,
  reachable both from `XMonad` and from their contrib module paths
  `XMonad.Layout.ThreeColumns` and `XMonad.Layout.Circle`.
- `M-Return` makes the focused window the master and `M-S-Return` launches the
  terminal, as upstream xmonad binds them. This swaps the two defaults.
- The menu bar shows an xmobar-style workspace row, and `xmonad status`
  publishes the same data for an external bar.
- Menu bar items are grouped under Settings and Diagnostics.

- Windows on another workspace are parked off-screen instead of minimized. No
  Dock animation, no apps refusing or delaying `AXMinimized`, and no restore
  race on switching back. A window whose app clamps the position back onto a
  display is minimized instead. Mapping workspaces onto macOS Desktops was
  investigated and is not possible from an ordinary process: the window server
  ignores a Space move for windows another process owns.
- Fixed windows losing their identity on a Space switch: an app can return an
  incomplete AX window list, and a known window whose frame is briefly
  unreadable is no longer treated as closed and re-adopted as a new one.
- `make` builds and installs; `xmonad --recompile` and `xmonad --restart` are
  the primary commands for a running XMonadMac. The make targets that
  duplicated them (`reload`, `recompile`, `doctor`, `recover`, `status`,
  `autostart-on/off`, `engine`, `native`, `test`, `test-portable`) are gone.
- Fixed send-to-workspace losing windows: a transient `AXMinimized` read
  failure, or a window missing from the window-server list while it animates,
  dropped it from the snapshot, and the engine then treated it as a new window
  on the workspace in view.
- The app is signed with a persistent local certificate, so rebuilding no
  longer invalidates the Accessibility grant.

- Fixed the engine handshake: the helper read the engine's stdout with
  `FileHandle.read(upToCount:)`, which blocks until the full count arrives, so
  the `configure` line was never consumed and the watchdog paused every start.
- Fixed the executable build: the staged config is now `Main.hs`, so
  `import XMonad` no longer resolves to the config itself on a
  case-insensitive filesystem.
- `Full` now stacks every window at the full frame and raises the focused one,
  instead of minimizing the others into the Dock.
- Default `modMask` is `mod1Mask` (Option).
- Added a tenth workspace: `M-0` and `M-S-0`.
- Added `xmonad --recompile` and `xmonad --restart`, installed as
  `~/.local/bin/xmonad` alongside `xmonadctl`.
- Added `~/.xmonad/xmonad.hs` to the config search order.
- Added a Makefile front end over `scripts/`.
- Added app and menu bar icons derived from the xmonad logo.
- Added an opt-in menu toggle that suppresses macOS window shortcuts
  (`Cmd-Tab`, `` Cmd-` ``, `Ctrl-arrows`, `Cmd-H`, `Cmd-M`) while tiling.
- Added an opt-in menu toggle that logs modified key presses to `bridge.log`.
- Toolchain fallback no longer prepends Homebrew paths when `ghc` and `cabal`
  are already on `PATH`.
- Documentation translated to English and reorganized.

## 0.3.0 - 2026-09-07

- Added built-in `modMask` + left-drag move and right-drag resize using a native pointer event tap.
- Kept mouse policy in Haskell: drag start emits `mouseFloat`, which updates `StackSet.floating` and focus intent.
- Suppress stale/native layout moves for the active drag target until mouse-up to prevent snap-back races.
- Added cross-display floating drag semantics: the window follows the visible logical workspace on the destination display.
- Added `xmonadctl self-test` and menu AX self-test with same-frame write/read-back and public CGWindow correlation checks.
- Added pointer protocol/config validation and expanded portable/static tests.

## 0.2.0 - 2026-09-07

- Added safe in-app `xmonad.hs` recompilation. The old engine remains installed until build and native key validation both succeed.
- Changed the default `M-q` to recompile and reload, closer to upstream xmonad behavior.
- Added a self-contained installed build kit under Application Support, so config rebuilds do not depend on the original checkout remaining in place.
- Added `xmonadctl` for status, pause/resume, reload/recompile, recovery, diagnostics, logs and config access.
- Added opt-in LaunchAgent management for login startup.
- Added menu entries to recompile and open `xmonad.hs`.
- Added a portable atomic-recompile smoke test and expanded static checks.
