# XMonadMac

A native macOS port of xmonad's policy core. Your `xmonad.hs` is compiled as
real Haskell.

> **Scope.** This is a source-compatible subset of xmonad, not a drop-in
> replacement. Existing configurations do not run unchanged, and
> xmonad-contrib is not supported. [Compatibility](docs/COMPATIBILITY.md) has
> the exact boundary.

## Requirements

- macOS 13 or later
- Xcode Command Line Tools (`xcode-select --install`)
- Homebrew. Bootstrap installs `ghc@9.12` and `cabal-install` if they are
  missing
- Network access to Hackage for the first build

## Install

```sh
git clone <this-repo> xmonad-macos
cd xmonad-macos
                # runs tests, compiles your config,
                # builds and sign the native app,
make bootstrap  # and installs it
```

### Permissions

In System Settings, under Privacy & Security -> Accessibility, add
`~/Applications/XMonadMac.app`, quit the app, and start it
again.

Rebuilding the native app changes its code signature, and that invalidates the
Accessibility grant. Re-add the app after `make native`, or sign with a stable
identity through `CODESIGN_IDENTITY=...`.

## First run

Start read-only.
It logs a layout plan without moving windows or intercepting keys:

```sh
make dry-run
xmonadctl log        # follow ~/Library/Logs/XMonadMac/bridge.log
```

Quit XMonadMac from its menu. If you run yabai or skhd, stop them yourself:
`run.sh` refuses to start rather than editing your services. Then:

```sh
make run
```

Try it first with two or three throwaway windows, such as Terminal and
Finder, holding no unsaved work. The tested setup is one native Space per
display with Stage Manager off.

`--dry-run` skips `startupHook` and changes nothing natively, but your config
is an ordinary Haskell program. Any IO you wrote in `manageHook` or `logHook`
still runs, so treat it as your own code rather than a sandbox.

## Configuration

XMonadMac looks for your config in this order:

1. an explicit path argument
2. `$XMONAD_CONFIG`
3. `~/.xmonad/xmonad.hs`
4. `~/.config/xmonad-mac/xmonad.hs`

A `lib/` directory beside the config is staged alongside it.

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

Window matchers map onto macOS concepts. `className` is the app's display
name, `resource`, `appName`, and `bundleId` are all the bundle identifier, and
`title` is `AXTitle`. Prefer `bundleId`, because display names are localized.
Native tabs count as one window unless the app exposes each tab as its own AX
window.

Apply changes:

```sh
xmonad --recompile      # compile and install; leave the running engine alone
xmonad --restart        # restart the engine with the compiled config
make reload             # compile, install, and reload in one step
```

A compile failure never replaces the running engine.

## Default keys

`M` is **Option** (`mod1Mask`). Use `mod4Mask` for Command, or
`controlMask .|. mod4Mask` for both. `S` is Shift.

| Key | Action |
|---|---|
| `M-j` / `M-k` | Focus next / previous |
| `M-S-j` / `M-S-k` | Swap position in the stack |
| `M-Return` / `M-S-Return` | Launch terminal / swap with master |
| `M-h` / `M-l` | Shrink / expand the master area |
| `M-Space` / `M-S-Space` | Next layout / reset to the default layout |
| `M-1…9`, `M-0` | View that workspace |
| `M-S-1…9`, `M-S-0` | Move the focused window to that workspace |
| `M-w` / `M-e` / `M-r` | Focus screen 0 / 1 / 2 |
| `M-S-w` / `M-S-e` / `M-S-r` | Move to the workspace on that screen |
| `M-f` / `M-t` | Toggle float / sink back into the tiling |
| `M` + left drag | Float the window and move it |
| `M` + right drag | Float the window and resize it |
| `M-S-c` | Press the window's Close button (never force-quits) |
| `M-q` / `M-S-q` | Recompile and reload / quit XMonadMac |
| `M-S-p` | Pause and restore WM-minimized windows |
| `Ctrl-Opt-Cmd-Esc` | Emergency stop and restore, bypassing Haskell |

Bindings match physical key positions on a US layout. Character-based
resolution for AZERTY and QWERTZ, and multi-stroke chords, are not
implemented.

Mouse drag uses the same modifier as `modMask`. Starting a drag updates
`StackSet.floating` in Haskell and stops tiling that window until you release
the button. A floating window dragged onto another display joins the logical
workspace visible there.

## Daily use

`make install` creates `~/.local/bin/xmonadctl` and `~/.local/bin/xmonad`. It
also copies a self-contained build kit to
`~/Library/Application Support/XMonadMac/build-kit`, so recompiling your
config keeps working after you move or delete the checkout.

```sh
xmonadctl status         # bridge status as JSON
xmonadctl pause          # and resume
xmonadctl reload         # restart the compiled engine
xmonadctl recompile      # compile, then reload
xmonadctl config         # open xmonad.hs
xmonadctl log            # follow the log
xmonadctl self-test      # AX read/write/read-back on the focused window
xmonadctl doctor         # environment, permissions, recent log
xmonadctl autostart on   # opt-in LaunchAgent; also off / status
```

The menu bar item offers the same operations, plus two toggles.

"Disable macOS window shortcuts" swallows `Cmd-Tab`, ``Cmd-` ``, the
`Ctrl-arrows` of Mission Control, `Cmd-H`, and `Cmd-M` while tiling is active.
Nothing is written to system preferences, so quitting gives every shortcut
back.

"Log key events to bridge.log" records each modified key press as
`key code=… mask=… bound=… consumed=…`. Turn it on when a binding looks dead:
the mask tells you which modifier actually arrived, where Shift is 1, Control
is 4, Option is 8, and Command is 64.

## Make targets

| Target | Purpose |
|---|---|
| `make bootstrap` | Install the toolchain, build everything, install |
| `make build` | Build the engine and the native app |
| `make engine` / `make native` | Build one side only |
| `make install` | Install the app, engine, and CLI |
| `make reload` | Recompile the config and reload a running app |
| `make run` / `make dry-run` | Launch normally / read-only |
| `make check` | Portable checks, Haskell tests, integration test |
| `make doctor` / `make status` | Diagnostics |
| `make icon` | Regenerate the icons from SVG (needs `rsvg-convert`) |
| `make clean` | Remove `build/` and `dist-newstyle/` |

Every target is a thin wrapper over the matching script in `scripts/`.
`CONFIG=path/to/xmonad.hs` overrides the config for the build and reload
targets.

## Workspaces and recovery

Logical workspaces are not macOS Spaces. Windows hidden by a workspace switch
are minimized through AX, so they land in the Dock with the usual animation.
The `Full` layout minimizes nothing: it stacks every window at the full frame
and raises the focused one.

Windows you minimized yourself are left out of management, and XMonadMac never
restores them on its own.

Before minimizing, it writes an ownership record atomically to
`~/Library/Application Support/XMonadMac/recovery.json`. A normal quit, an
engine failure, an emergency stop, and the response watchdog all restore owned
windows. A `SIGKILL` of the helper or an OS crash cannot restore anything
immediately, so run:

```sh
make recover     # or: xmonadctl recover
make doctor
```

When a window cannot be identified unambiguously, XMonadMac keeps the record
and leaves the window alone. Restore it from the Dock and reconcile the log by
hand. Deleting the record is not a restore. The journal tracks WM-owned
minimization and nothing else, so it is not a snapshot of your original window
geometry.

Switching native Spaces resets the logical epoch and restores owned windows.
Moving windows between Spaces and controlling native full-screen are both out
of scope. Tiling pauses while a native full-screen window is frontmost.

## Working as an upstream fork

This tree does not carry xmonad's full history. To graft it onto the real
upstream history under `macos/`, run:

```sh
./scripts/make-upstream-fork.sh ../xmonad-native-fork
cd ../xmonad-native-fork/macos
make bootstrap
```

That uses base commit `a9a8b5c1b91b63b0836f5810634c9b28ec0af788` and the
branch `macos-native`. It leaves the X11 tree intact, and because this port is
a separate Haskell package, it cannot break the existing build.

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
