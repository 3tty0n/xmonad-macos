# Changelog

## Unreleased

- The focus border no longer lags a workspace switch, and no longer jumps back
  onto the window that just lost focus. Only an explicit focus request pins the
  overlay; ordinary placement plans leave it alone, and a restore still reports
  `ownedHidden` until a later scan agrees. The panel stays ordered with
  `alphaValue` rather than leaving the window list.

- Finder windows stay on the workspace that owns them. A hide is journaled
  against the process instance that owns the window, so PID reuse cannot make
  a later process look like its owner, and the instance came from
  `NSRunningApplication.launchDate`. That is nil for the session's own
  launchd children, Finder among them, so every Finder hide was refused
  before it began and Finder stayed on every workspace. The instance now
  falls back to the BSD process start time, which is public and available for
  every process. The refusal names the window and the reason in the log.

- Quit no longer hangs. It replied to `terminateLater` from the main queue,
  which the nested event loop AppKit runs while waiting does not drain, so
  neither the reply nor its four-second timeout ever arrived and the app had
  to be killed. The wait for the final restore is bounded in place instead.

- Finder is minimized rather than parked. A position-only park is a no-op for
  it, and a size-position-size park clamps a large visible
  panel into the corner that admission then treats as hidden. Finder is
  therefore minimized, never parked. A still-visible window on a workspace
  that is not on a screen cannot pull the current tag back. The desktop
  scroll area is not counted as a same-PID peer. A hide that cannot park or
  minimize keeps its ownership token. Other apps still park first; if AX
  reports a parked frame while CG still shows the original on-display
  rectangle, a later scan minimizes that window. That check is not done in
  the parking call, or the window server's brief stale frame re-parks every
  scan.

- Chrome windows are tiled and traced. Chromium withholds on-screen CGWindow
  metadata, leaves system-wide AX focus empty, and animates geometry writes
  while `AXEnhancedUserInterface` is on; the helper now admits those AX
  windows, falls back to the frontmost app's focused window, writes geometry
  with that flag cleared, and re-raises the overlay on every scan.

- The focus border overlay uses the public overlay window level and
  `orderFrontRegardless`, so it stays visible on Electron apps whose content
  windows sit above `floatingWindow` (Claude Desktop, Codex). It remains
  click-through.

- Dialogs and floating panels (`AXDialog`, `AXSystemDialog`,
  `AXFloatingWindow`, `AXSystemFloatingWindow`) are managed as floats at the
  size the application chose, so they can take focus. Sheets and popovers
  remain unmanaged. `isDialog` matches those subroles; `doIgnore` still
  removes them.

- `borderWidth`, `focusedBorderColor` and `focusFollowsMouse` exist, with
  upstream's defaults. The border is a click-through overlay the helper draws
  around the focused window, since AX cannot give another application's window
  one; focus follows the mouse through a new `pointerFocus` event that policy
  is free to ignore.

- Focusing a screen with `M-w` / `M-e` / `M-r` moves the pointer to that
  display when it is elsewhere. The bindings existed, but with no window to
  focus on the target display nothing marked the change, and the observed
  focus pulled the current screen back a few ticks later. Plans now carry the
  current screen's display.

- The `xmonad` command is the compiled config binary itself, as upstream's is.
  Control arguments are handled before any engine starts, and both
  `~/.local/bin/xmonad` and `xmonadctl` are symlinks to it; the shell
  implementation is gone.
- The wait for a replacement element runs for its full 30 seconds from the
  moment the element died, and displays that sleep again do not spend it.
  Previously the wait was also cut off 30 seconds after the wake itself, which
  reset every workspace when a long sleep ended in a brief wake.
- A window closed with cmd-W is forgotten on the next scan instead of holding
  its place in the layout for 30 seconds. The grace for a destroyed element
  now applies only after a display wake, the one event that recycles them.

- Nothing is scanned for two seconds after the displays wake, and an
  application reported hidden has to be reported hidden twice before its
  windows leave management. The log marks both edges of the pause, so a wake
  that still loses state can be traced.
- A window whose element was destroyed stays in the snapshot, with its last
  known state, for up to 30 seconds while its replacement is awaited; the
  replacements were measured arriving about five seconds after wake.
- Windows keep their identity, and so their workspace, across display sleep.
  macOS destroys every window's AXUIElement on wake and issues new ones; the
  helper now adopts the replacement into the existing record, matched by
  AXIdentifier, or by title and frame. This was the actual cause of every
  window moving to one workspace after a wake.
- A window is forgotten only when the window server says its element is
  destroyed, or its process has exited. Previously a window missing from one
  scan of an application list was enough, and waking a display produces
  exactly that, which is what moved every window to one workspace.
- Fixed every window moving to one workspace after a display wake. macOS
  briefly reports an incomplete application list, which made the helper
  forget its windows; the engine then adopted them as new ones on the
  workspace in view. An application now has to be absent twice and be
  confirmed dead before its windows are dropped.

- More xmonad-contrib modules ported under their own module paths:
  `Layout.Grid`, `Layout.Simplest`, `Layout.ResizableTile`, `Layout.Renamed`,
  `Layout.Reflect`, `Layout.PerWorkspace`, `Layout.TwoPane`,
  `Layout.Accordion`, `Actions.CycleWS`, `Actions.WithAll`,
  `Actions.RotSlaves`, `Actions.SwapWorkspaces`, `Actions.DwmPromote`,
  `Actions.PhysicalScreens` and `Hooks.ManageHelpers`. See
  docs/COMPATIBILITY.md for the full list.
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
