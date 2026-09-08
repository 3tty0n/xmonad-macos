# XMonadMac

xmonad's policy core, ported to macOS. Your `xmonad.hs` is compiled as real
Haskell and drives a signed Swift helper.

> [!IMPORTANT]
> It is a subset, not a drop-in replacement. See [Compatibility](docs/COMPATIBILITY.md)
> for the exact limitations.

## Install

```sh
git clone <this-repo> xmonad-macos
cd xmonad-macos
make bootstrap
```

Then,

- System Settings -> Privacy & Security -> Accessibility
- Add `~/Applications/XMonadMac.app`
- Restart it

## Prerequisite

- macOS 13+
- Xcode Command Line Tools
- Homebrew

## Run

```sh
make dry-run     # read-only: logs what it would do, touches nothing
make run
```

> [!CAUTION]
> Stage manager compatibility is unsupported

## Configure

Put your config in `~/.config/xmonad-mac/xmonad.hs` (or `~/.xmonad/`):

```haskell
import XMonad
import XMonad.Util.EZConfig
import XMonad.MacOS

main :: IO ()
main = xmonad $ def
  { terminal = "open -a Terminal"
  , modMask = mod1Mask                       -- Option
  , workspaces = map show [1..9] ++ ["0"]
  , layoutHook = Tall 1 (3/100) (1/2) ||| Full
  , manageHook = composeAll
      [ bundleId =? "com.apple.systempreferences" --> doFloat ]
  }
  `additionalKeysP` [ ("M-f", toggleFloat) ]
```

Apply it:

```sh
xmonad --recompile     # compile; the running engine keeps going
xmonad --restart       # run the new one
```

A compile failure never replaces the running engine.

Match windows with `bundleId` (stable), `className` (localized app name), or
`title`.

> [!NOTE]
> More layouts, hooks and ported contrib modules: [Compatibility](docs/COMPATIBILITY.md).
> Other config locations: [Usage](docs/USAGE.md).

## Keys

`M` is Option, `S` is Shift.

| Key | Action |
|---|---|
| `M-j` / `M-k` | Focus next / previous |
| `M-S-j` / `M-S-k` | Move window down / up the stack |
| `M-Return` | Make the focused window master |
| `M-S-Return` | Launch the terminal |
| `M-h` / `M-l` | Shrink / expand the master area |
| `M-Space` | Next layout |
| `M-1…0` | Go to that workspace |
| `M-S-1…0` | Send the window to that workspace |
| `M-f` / `M-t` | Float / unfloat |
| `M` + drag | Move (left button) or resize (right button) |
| `M-S-c` | Close the window |
| `M-q` / `M-S-q` | Recompile / quit |
| `Ctrl-Opt-Cmd-Esc` | Emergency stop, restores every hidden window |

> [!TIP]
> Full list, including per-screen keys: [Usage](docs/USAGE.md).

## Workspaces

Workspaces are XMonadMac's own:  **not** macOS Desktops, which cannot be used
for this because macOS forbids moving another app's window between them.

Windows on other workspaces are placed off-screen. An app that refuses to be
placed is minimized instead. Either way they return to where they were.

> [!TIP]
> Type `xmonad recover`. It puts every hidden window back.

## Commands

`make` builds, `xmonad` drives a running instance.

| | |
|---|---|
| `make bootstrap` | Toolchain, build, install |
| `make build` / `make install` | Build / install |
| `make run` / `make dry-run` | Launch / launch read-only |
| `make check` | Run the tests |
| `xmonad --recompile` / `--restart` | Compile the config / run it |
| `xmonad status` / `log` / `doctor` | What it is doing, and why not |
| `xmonad pause` / `resume` / `recover` | Suspend / resume / unhide windows |
| `xmonad autostart on` | Start at login |

The menu bar shows the workspace row and layout, xmobar style: `[2] 1 3 -
Tall`, and `xmonad status` publishes the same as JSON for sketchybar or
Übersicht. Menu toggles and installed paths: [Usage](docs/USAGE.md).

## Keeping the Accessibility grant

Rebuilding changes the app's identity, so macOS asks you to grant
Accessibility again. Run this once to stop that:

```sh
./scripts/signing-identity.sh
```

It creates a local signing certificate, once, with a password prompt.

## Documentation

- [Usage](docs/USAGE.md): every key, menu, path and recovery step.
- [Design](docs/DESIGN.md): how it works and why.
- [Compatibility](docs/COMPATIBILITY.md): what of xmonad's API works.
- [Protocol](docs/PROTOCOL.md): the contract between the two halves.
- [Testing](docs/TESTING.md): automated checks and the manual matrix.
- [Upstream](docs/UPSTREAM.md): attribution and primary sources.

## License

BSD-3-Clause, preserving xmonad's original copyright. See [LICENSE](LICENSE).
