# Usage

## Config

Search order: explicit path, `$XMONAD_CONFIG`, `~/.xmonad/xmonad.hs`,
`~/.config/xmonad-mac/xmonad.hs`. A `lib/` next to the config is staged with
it.

`M` is Option (`mod1Mask`); `mod4Mask` is Command. Bindings are physical US
keys. AZERTY/QWERTZ and chords are not implemented.

| Key | Action |
|---|---|
| `M-j` / `M-k` / `M-Tab` | Focus next / previous / next |
| `M-m` | Focus master |
| `M-S-j` / `M-S-k` | Swap in the stack |
| `M-Return` / `M-S-Return` | Swap with master / launch terminal |
| `M-h` / `M-l` | Shrink / expand master |
| `M-,` / `M-.` | More / fewer masters |
| `M-Space` / `M-S-Space` | Next layout / reset |
| `M-1…9`, `M-0` | View that **virtual** workspace |
| `M-S-1…9`, `M-S-0` | Move focused window there |
| `M-w` / `M-e` / `M-r` | Focus screen 0 / 1 / 2 |
| `M-S-w` / `M-S-e` / `M-S-r` | Send to that screen's workspace |
| `M-f` / `M-t` | Float / sink |
| `M-S-c` | Close (never force-quit) |
| `M-q` / `M-S-q` | Recompile / quit |
| `M-S-p` | Pause and restore hidden windows |
| `M` + left / right drag | Float and move / resize |
| `Ctrl-Opt-Cmd-Esc` | Emergency stop |

Drag sets `W.float`. Across displays, the window joins the workspace visible
there. Override with `mouseBindings` / `additionalMouseBindings`
(`MouseMove`, `MouseResize`, `MouseRaise`). Mask 0 is rejected.

Dialogs (`AXDialog` / `AXFloatingWindow`) float at the app's size. Sheets
and popovers are unmanaged.

Borders: `borderWidth`, `focusedBorderColor`, `normalBorderColor` (0 turns
them off). They are click-through overlays. `focusFollowsMouse` is on by
default.

## Displays

One virtual workspace per display. Screen 0 is the macOS primary. A replug
with the same display ID reclaims its workspace. Mission Control Desktops
are still not these workspaces.

## Menu and status

Menu bar: `[2] 1 3 - Tall`. Settings can swallow macOS window shortcuts
while tiling (nothing is written to System Settings) and log key events.
`xmonad status` is JSON for an external bar.

## Paths

| Path | |
|---|---|
| `~/Applications/XMonadMac.app` | Helper |
| `~/.local/bin/xmonad` | Control command (also `xmonadctl`) |
| `~/Library/Application Support/XMonadMac/` | Engine, `build-kit`, `recovery.json`, `session.json` |
| `~/Library/Logs/XMonadMac/bridge.log` | Log |

`./scripts/signing-identity.sh` makes the Accessibility grant survive
rebuilds. `xmonad recover` restores WM-hidden windows after a crash.
Ambiguous records are kept, not guessed.

`./scripts/make-upstream-fork.sh` grafts this tree under `macos/` onto
xmonad at `a9a8b5c1`.
