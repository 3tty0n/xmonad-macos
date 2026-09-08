# XMonadMac

A native macOS port of xmonad's policy core. `xmonad.hs` is compiled as real
Haskell and drives a signed Swift helper over NDJSON.

Source-compatible subset, not a drop-in replacement: existing configurations
do not run unchanged. The xmonad-contrib package cannot be a dependency, but
modules whose logic is pure `StackSet` or geometry are ported under their own
module paths - `ThreeColumns`, `Circle`, `Grid`, `Simplest`, `ResizableTile`,
`CycleWS`, `WithAll`. [Compatibility](docs/COMPATIBILITY.md) has the list and
states the exact boundary.

## Requirements

| | |
|---|---|
| OS | macOS 13 or later, single display, Stage Manager off |
| Tools | Xcode Command Line Tools, Homebrew |
| Toolchain | `ghc@9.12` and `cabal-install`, installed by `make bootstrap` |
| Network | Hackage access for the first build |

## Install

```sh
git clone <this-repo> xmonad-macos
cd xmonad-macos
make bootstrap        # test, build, sign, install
```

Then grant Accessibility to `~/Applications/XMonadMac.app` in System Settings
-> Privacy & Security -> Accessibility, and restart the app.

The app is ad-hoc signed by default, so every rebuild changes its identity and
the grant has to be given again. To sign with a stable identity instead, once:

```sh
./scripts/signing-identity.sh   # asks for your login password
```

`CODESIGN_IDENTITY=...` uses your own identity. A changed identity invalidates
the grant, and macOS ignores a re-add while the stale entry stands, so
`make install` clears it with `tccutil` and asks you to add the app again.

## Run

```sh
make dry-run          # read-only: logs plans, moves nothing, grabs no keys
make run
```

`--dry-run` skips `startupHook`, but `manageHook` and `logHook` are your own
Haskell and still run. Stop yabai or skhd first; `run.sh` refuses to start
rather than touching your services. Try it with throwaway windows first.

## Workspaces

Workspaces are XMonadMac's own; macOS Desktops are unrelated and cannot be
used, because the window server refuses to let an ordinary process move
another app's window to another Desktop.

| | |
|---|---|
| Hiding | The window is parked past the bottom-right corner of the displays |
| Fallback | AppKit keeps ~40 points of a window on screen; an app that enforces that has its window minimized instead |
| Restore | Both kinds return to the frame recorded before hiding |
| `Full` | Hides nothing: every window keeps the full frame, focused one raised |
| Your own minimizing | Never managed and never undone |

Keep macOS on one Desktop. `Control-N`, a swipe or Mission Control switches
the native Desktop, which resets workspace assignments and unhides windows.

Before hiding a window, an ownership record is written atomically to
`~/Library/Application Support/XMonadMac/recovery.json`. A normal quit, engine
failure, emergency stop or watchdog restores owned windows; after a `SIGKILL`
or an OS crash run `xmonad recover`. A window that cannot be identified
unambiguously keeps its record and is left alone - deleting the record is not
a restore. Tiling pauses while a native full-screen window is frontmost.

## Configuration

Config search order: explicit path argument, `$XMONAD_CONFIG`,
`~/.xmonad/xmonad.hs`, `~/.config/xmonad-mac/xmonad.hs`. A `lib/` directory
beside the config is staged with it.

```haskell
import XMonad
import qualified XMonad.StackSet as W
import XMonad.Util.EZConfig
import XMonad.Layout.Spacing
import XMonad.MacOS

main :: IO ()
main = xmonad $
  def
    { terminal = "open -a Terminal"
    , modMask = mod1Mask
    , workspaces = map show [1..9] ++ ["0"]
    , layoutHook = spacing 4 $
        Tall 1 (3/100) (1/2)
        ||| ThreeCol 1 (3/100) (1/2)   -- ThreeColMid centres the master
        ||| Circle                     -- centred master, M-h/M-l resize it
        ||| Mirror (Tall 1 (3/100) (1/2))
        ||| Full
    , manageHook = composeAll
        [ bundleId =? "com.apple.systempreferences" --> doFloat ]
    }
  `additionalKeysP`
    [ ("M-f", toggleFloat)
    , ("M-S-p", pause)
    , ("M-S-m", windows W.shiftMaster)
    ]
```

Matchers map onto macOS: `className` is the app's display name; `resource`,
`appName` and `bundleId` are the bundle identifier; `title` is `AXTitle`.
Prefer `bundleId`, because display names are localized. Native tabs count as
one window unless the app exposes each tab as an AX window.

```sh
xmonad --recompile    # compile and install; running engine untouched
xmonad --restart      # run the compiled config, starting the app if needed
xmonad recompile      # both
```

A compile failure never replaces the running engine.

## Default keys

`M` is Option (`mod1Mask`); use `mod4Mask` for Command. `S` is Shift.
Bindings follow physical key positions on a US layout; AZERTY/QWERTZ
character resolution and multi-stroke chords are not implemented.

| Key | Action |
|---|---|
| `M-j` / `M-k` | Focus next / previous |
| `M-S-j` / `M-S-k` | Swap position in the stack |
| `M-Return` / `M-S-Return` | Make focused window master / launch terminal |
| `M-h` / `M-l` | Shrink / expand the master area, including Circle's centre |
| `M-Space` / `M-S-Space` | Next layout / reset to the default layout |
| `M-1...9`, `M-0` | View that workspace |
| `M-S-1...9`, `M-S-0` | Move the focused window to that workspace |
| `M-w` / `M-e` / `M-r` | Focus screen 0 / 1 / 2 |
| `M-S-w` / `M-S-e` / `M-S-r` | Move to the workspace on that screen |
| `M-f` / `M-t` | Toggle float / sink back into the tiling |
| `M-S-c` | Press the window's Close button; never force-quits |
| `M-q` / `M-S-q` | Recompile and reload / quit |
| `M-S-p` | Pause and restore hidden windows |
| `M` + left / right drag | Float and move / float and resize |
| `Ctrl-Opt-Cmd-Esc` | Emergency stop and restore, bypassing Haskell |

A drag sets `StackSet.floating` and suspends tiling for that window until
release. Dragged to another display, the window joins the workspace visible
there.

## Commands

`make` builds; `xmonad` drives a running instance. `make install` creates
`~/.local/bin/xmonad` and copies a self-contained build kit to
`~/Library/Application Support/XMonadMac/build-kit`, so recompiling keeps
working after the checkout moves.

| Command | Purpose |
|---|---|
| `make bootstrap` | Toolchain, build, install |
| `make build` | Engine and native app (`CONFIG=` overrides the config) |
| `make install` | App, engine and the `xmonad` command |
| `make run` / `make dry-run` | Launch normally / read-only |
| `make check` | Swift, Haskell, integration and packaging tests |
| `make icon` / `make clean` | Icons from SVG / remove build output |
| `xmonad --recompile` / `--restart` | Compile the config / run it |
| `xmonad status` / `doctor` / `log` | JSON status / diagnostics / follow log |
| `xmonad pause` / `resume` / `quit` | Suspend, resume, quit |
| `xmonad recover` | Restore windows XMonadMac hid |
| `xmonad config` / `self-test` / `dump` | Open config / AX check / snapshot |
| `xmonad autostart on\|off\|status` | Login item |

Each make target is a thin wrapper over the matching script in `scripts/`.

## Status bar

The menu bar shows the workspace row and layout, xmobar style:
`[2] 1 3 - Tall`. Current in brackets, visible on another screen in
parentheses, empty workspaces omitted. Its menu holds Pause, Recompile and
Open, with the rest under Settings and Diagnostics.

`xmonad status` publishes the same data under `workspaces`, one entry per
workspace with `tag`, `windows`, `current` and `visible`, for sketchybar,
Übersicht or a shell loop:

```sh
xmonad status | jq -r '[.workspaces[] | select(.windows > 0 or .current)
  | if .current then "[\(.tag)]" else .tag end] | join(" ")'
```

Settings -> *Disable macOS window shortcuts* swallows `Cmd-Tab`, ``Cmd-` ``,
the Mission Control arrows, `Cmd-H` and `Cmd-M` while tiling, without writing
to system preferences. Settings -> *Log key events* logs every modified key as
`key code=... mask=... bound=... consumed=...`; the mask is Shift 1,
Control 4, Option 8, Command 64.

## Upstream fork

`./scripts/make-upstream-fork.sh ../xmonad-native-fork` grafts this tree under
`macos/` onto xmonad's real history at base commit `a9a8b5c1`, branch
`macos-native`. The X11 tree stays intact; this port is a separate Haskell
package and cannot break its build.

## Documentation

| Document | Contents |
|---|---|
| [Design](docs/DESIGN.md) | Architecture and the reasoning behind it |
| [Compatibility](docs/COMPATIBILITY.md) | What of xmonad's API works |
| [Protocol](docs/PROTOCOL.md) | The NDJSON contract between the two halves |
| [Testing](docs/TESTING.md) | Automated checks and the manual matrix |
| [Upstream](docs/UPSTREAM.md) | Attribution and primary sources |

## License

BSD-3-Clause, preserving xmonad's original copyright. See [LICENSE](LICENSE).
