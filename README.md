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

By default the app is ad-hoc signed, and every rebuild changes its identity,
so you would have to add it again. To avoid that, once:

```sh
./scripts/signing-identity.sh   # asks for your login password
```

That creates `XMonadMac Local Signing` in your login keychain and trusts it
for code signing. The grant then follows the certificate rather than the
build, and later rebuilds keep Accessibility working. `CODESIGN_IDENTITY=...`
signs with your own identity instead.

Changing the signing identity does invalidate the grant, and macOS ignores a
re-add while the stale entry is present. `make install` detects this, clears
the entry with `tccutil reset Accessibility org.xmonad.XMonadMac`, and asks
you to add the app once more.

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
Finder, holding no unsaved work. The tested setup is a single display with
Stage Manager off.

`--dry-run` skips `startupHook` and changes nothing natively, but your config
is an ordinary Haskell program. Any IO you wrote in `manageHook` or `logHook`
still runs, so treat it as your own code rather than a sandbox.

## Workspaces are not macOS Desktops

Workspaces are XMonadMac's own. A window on another workspace is parked past
the right edge of your displays, so switching is instant and nothing goes to
the Dock. AppKit keeps about 40 points of a window on screen no matter where
you put it, so a window whose app enforces that is minimized instead; both
kinds come back to the same frame.

macOS Desktops are not involved, and cannot be: the window server refuses to
let an ordinary process move another app's window to another Desktop, which is
why yabai needs System Integrity Protection disabled for that one feature.

So keep macOS on a single Desktop. `Control-1`/`Control-2`, a swipe, or
Mission Control switches the *native* Desktop, which resets XMonadMac's
workspace assignments and brings hidden windows back.

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
        ||| ThreeCol 1 (3/100) (1/2)     -- or ThreeColMid, master centred
        ||| Circle                        -- centred master, the rest around it
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
xmonad --restart        # run the compiled config, starting the app if needed
xmonad recompile        # both, in one step
```

A compile failure never replaces the running engine.

## Default keys

`M` is **Option** (`mod1Mask`). Use `mod4Mask` for Command, or
`controlMask .|. mod4Mask` for both. `S` is Shift.

| Key | Action |
|---|---|
| `M-j` / `M-k` | Focus next / previous |
| `M-S-j` / `M-S-k` | Swap position in the stack |
| `M-Return` / `M-S-Return` | Make the focused window master / launch terminal |
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

`make install` creates `~/.local/bin/xmonad` (and `xmonadctl`, the same
script). It
also copies a self-contained build kit to
`~/Library/Application Support/XMonadMac/build-kit`, so recompiling your
config keeps working after you move or delete the checkout.

```sh
xmonad --recompile       # compile xmonad.hs into a new engine
xmonad --restart         # run the compiled config
xmonad status            # bridge status as JSON
xmonad pause             # and resume
xmonad config            # open xmonad.hs
xmonad log               # follow the log
xmonad self-test         # AX read/write/read-back on the focused window
xmonad doctor            # environment, permissions, Spaces, recent log
xmonad autostart on      # opt-in LaunchAgent; also off / status
```

The menu bar item shows the workspace row and the current layout, in the style
of xmobar: `[2] 1 3 · Tall`. The current workspace is in brackets, a workspace
visible on another screen is in parentheses, and a workspace with no windows is
left out. Its menu keeps Pause, Recompile and Open to hand, with the rest under
Settings (the macOS-shortcut and key-logging toggles) and Diagnostics (reload,
log, snapshot, AX self-test).

For a real status bar — sketchybar, Übersicht, a shell loop — the same data is
in `xmonad status` under `workspaces`, one entry per workspace with `tag`,
`windows`, `current` and `visible`:

```sh
xmonad status | jq -r '[.workspaces[] | select(.windows > 0 or .current)
  | if .current then "[\(.tag)]" else .tag end] | join(" ")'
```

Settings → "Disable macOS window shortcuts" swallows `Cmd-Tab`, ``Cmd-` ``, the
`Ctrl-arrows` of Mission Control, `Cmd-H`, and `Cmd-M` while tiling is active.
Nothing is written to system preferences, so quitting gives every shortcut
back.

Settings → "Log key events" records each modified key press as
`key code=… mask=… bound=… consumed=…`. Turn it on when a binding looks dead:
the mask tells you which modifier actually arrived, where Shift is 1, Control
is 4, Option is 8, and Command is 64.

## Make targets

| Target | Purpose |
|---|---|
| `make bootstrap` | Install the toolchain, build everything, install |
| `make build` | Build the engine and the native app |
| `make install` | Install the app, engine, and the `xmonad` command |
| `make run` / `make dry-run` | Launch normally / read-only |
| `make check` | Portable checks, Haskell tests, integration test |
| `make icon` | Regenerate the icons from SVG (needs `rsvg-convert`) |
| `make clean` | Remove `build/` and `dist-newstyle/` |

Everything that acts on a running XMonadMac is a `xmonad` command, not a make
target: `--recompile`, `--restart`, `status`, `doctor`, `log`, `recover`,
`pause`, `quit`, `autostart`.

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
xmonad recover
xmonad doctor
```

When a window cannot be identified unambiguously, XMonadMac keeps the record
and leaves the window alone. Restore it from the Dock and reconcile the log by
hand. Deleting the record is not a restore. The journal tracks WM-owned
minimization and nothing else, so it is not a snapshot of your original window
geometry.

In the minimize-based fallback, switching native Spaces resets the epoch and
restores owned windows. With workspaces mapped onto Desktops, nothing is
minimized, so there is nothing to recover.
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
