# Usage reference

Everything the README leaves out. See [Design](DESIGN.md) for why any of it
works the way it does.

## Config search order

1. an explicit path argument
2. `$XMONAD_CONFIG`
3. `~/.xmonad/xmonad.hs`
4. `~/.config/xmonad-mac/xmonad.hs`

A `lib/` directory beside the config is staged with it, so a config split
across modules compiles.

## All default key bindings

`M` is Option (`mod1Mask`); use `mod4Mask` for Command. `S` is Shift.
Bindings follow physical key positions on a US layout. AZERTY/QWERTZ
character resolution and multi-stroke chords are not implemented.

| Key | Action |
|---|---|
| `M-j` / `M-k` / `M-Tab` | Focus next / previous / next |
| `M-m` | Focus the master window |
| `M-S-j` / `M-S-k` | Swap position in the stack |
| `M-Return` / `M-S-Return` | Make focused window master / launch terminal |
| `M-h` / `M-l` | Shrink / expand the master area, Circle's centre included |
| `M-,` / `M-.` | More / fewer master windows |
| `M-Space` / `M-S-Space` | Next layout / reset to the default layout |
| `M-n` | Refresh (a no-op: every action re-lays out already) |
| `M-1...9`, `M-0` | View that workspace |
| `M-S-1...9`, `M-S-0` | Move the focused window to that workspace |
| `M-w` / `M-e` / `M-r` | Focus screen 0 / 1 / 2 |
| `M-S-w` / `M-S-e` / `M-S-r` | Move to the workspace on that screen |
| `M-f` / `M-t` | Toggle float / sink back into the tiling |
| `M-S-c` | Press the window's Close button; never force-quits |
| `M-q` / `M-S-q` | Recompile and reload / quit |
| `M-S-p` | Pause and restore hidden windows |
| `M` + left / right drag | Float and move / float and resize (`mouseBindings`) |
| `Ctrl-Opt-Cmd-Esc` | Emergency stop and restore, bypassing Haskell |

A drag sets `StackSet.floating` and suspends tiling for that window until
release. Dragged to another display, the window joins the workspace visible
there. Replace the gestures from `xmonad.hs`:

```haskell
import qualified Data.Map.Strict as M

main = xmonad $ def
  { mouseBindings = \c -> M.fromList
      [ ((modMask c, button1), MouseMove)
      , ((modMask c, button3), MouseResize)
      , ((modMask c, button2), MouseRaise)
      ]
  }
  `additionalMouseBindings` [ ((mod4Mask, button1), MouseMove) ]
```

`MouseRaise` reports the window under the pointer as `pointerFocus`; it does
not start a drag. A binding whose modifier mask is 0 is rejected.

## Dialogs and popups

Save panels, alerts and other `AXDialog` / `AXFloatingWindow` windows are
floated at the size the app chose, so they can take focus with `M-j` / `M-k`
and the mouse. `isDialog --> doIgnore` leaves one alone; `doSink` tiles it.
Sheets and popovers are not managed.

## Focus border and the mouse

`borderWidth`, `focusedBorderColor` and `normalBorderColor` trace the focused
window and the other visible ones; `borderWidth = 0` turns both off.
`focusFollowsMouse` is on by default, as upstream:

```haskell
main = xmonad $ def
  { borderWidth = 2
  , focusedBorderColor = "#61afef"
  , normalBorderColor = "#dddddd"
  , focusFollowsMouse = False
  }
```

The border is an overlay window of the helper's own, because AX cannot give
another application's window a border. It is click-through, sits at the
public overlay window level so Electron content windows (Claude Desktop,
Codex) do not cover it, is raised when a focus request is applied and on
every later scan so Chrome cannot bury it, and follows the window as the
helper observes it move, so it lags a fast drag slightly. Unfocused
(`normalBorderColor`) frames are clipped where they overlap the focused
window, so an active floating window stays above those white borders.

## Several displays

Each display shows one workspace and is laid out in its own frame, as upstream
xmonad does with Xinerama. `M-w` / `M-e` / `M-r` focus screens 0, 1 and 2;
`M-S-w` and friends send the focused window to the workspace showing there.
Screen 0 is the display macOS calls primary; the rest follow in display-ID
order. Focusing a screen moves the pointer there when it is on another
display, because macOS has nothing else that says which screen is current.

- A display that comes back with the same display ID reclaims the workspace it
  showed last, including across an unplug that lasted the whole session.
- A disconnected display's workspaces become hidden rather than losing
  windows.
- A window hidden by a workspace switch parks past the right edge of the
  whole arrangement, so it never lands on another display. Finder cannot be
  parked that way, so it is minimized instead of remaining painted, including
  as a clamped strip in the corner.
- macOS gives every display its own Mission Control Desktops. Those are still
  not workspaces, and switching them still resets assignments.

## Menu bar

The status item shows the workspace row and the current layout, xmobar style:
`[2] 1 3 - Tall`. The current workspace is in brackets, one visible on another
screen is in parentheses, and empty workspaces are omitted.

Its menu holds Pause, Recompile and Open xmonad.hs, with the rest under two
submenus:

- **Settings → Disable macOS window shortcuts** swallows `Cmd-Tab`,
  ``Cmd-` ``, the Mission Control arrows, `Cmd-H` and `Cmd-M` while tiling.
  Nothing is written to system preferences, so quitting gives them all back.
- **Settings → Log key events** logs every modified key press as
  `key code=... mask=... bound=... consumed=...`. Turn it on when a binding
  looks dead: the mask says which modifier actually arrived, where Shift is 1,
  Control is 4, Option is 8 and Command is 64.
- **Diagnostics** holds reload, open log, write diagnostic snapshot and the AX
  self-test.

## Status for an external bar

`xmonad status` is JSON, and its `workspaces` array has one entry per
workspace with `tag`, `windows`, `current` and `visible`:

```sh
xmonad status | jq -r '[.workspaces[] | select(.windows > 0 or .current)
  | if .current then "[\(.tag)]" else .tag end] | join(" ")'
```

## Where things are installed

| Path | Contents |
|---|---|
| `~/Applications/XMonadMac.app` | The signed helper |
| `~/.local/bin/xmonad` | The control command: a symlink to the compiled config (`xmonadctl` is the same file). `start`, `--recompile`, `autostart`, `doctor` and `recover` all live here, not as copied shell scripts |
| `~/Library/Application Support/XMonadMac/xmonad-engine` | Compiled config |
| `~/Library/Application Support/XMonadMac/build-kit` | Self-contained sources, so `xmonad --recompile` keeps working after the checkout moves |
| `~/Library/Application Support/XMonadMac/recovery.json` | Windows currently hidden, for recovery after a crash |
| `~/Library/Application Support/XMonadMac/session.json` | Last checkpoint plus window fingerprints, for a helper restart |
| `~/Library/Logs/XMonadMac/bridge.log` | The log |

## Signing and the Accessibility grant

The app is ad-hoc signed by default, so every rebuild changes its identity and
macOS asks for the Accessibility grant again.

`./scripts/signing-identity.sh` creates `XMonadMac Local Signing` in your login
keychain and trusts it for code signing, once, with a password prompt. The
grant then follows the certificate instead of the build.

`CODESIGN_IDENTITY=...` signs with your own identity. Changing identity
invalidates the grant, and macOS ignores a re-add while the stale entry
stands, so `make install` clears it with `tccutil` and asks you to add the app
again.

## Recovery

Before hiding a window, an ownership record is written atomically to
`recovery.json`. A normal quit, engine failure, emergency stop or the response
watchdog restores hidden windows. A `SIGKILL` or an OS crash cannot, so run
`xmonad recover`.

A window that cannot be identified unambiguously keeps its record and is left
alone; restore it by hand. Deleting the record is not a restore.

## Working as an upstream fork

`./scripts/make-upstream-fork.sh ../xmonad-native-fork` grafts this tree under
`macos/` onto xmonad's real history, at base commit `a9a8b5c1`, branch
`macos-native`. The X11 tree stays intact, and because this port is a separate
Haskell package it cannot break the existing build.
