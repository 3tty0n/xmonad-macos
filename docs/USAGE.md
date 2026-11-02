# Usage

## Config

Search order: explicit path, `$XMONAD_CONFIG`, `~/.xmonad/xmonad.hs`,
`~/.config/xmonad-mac/xmonad.hs`. A `lib/` next to the config is staged with
it. `make build` uses this search order, falling back to `example/xmonad.hs`.
Override with `make build CONFIG=<path>`; tests and packaging use the example.

After editing: `xmonad --recompile`, then `xmonad --restart`. Install a matching
helper with `make build && make install` when native code or the protocol changes.

Mosaic uses a **multiplier**, unlike Tall's additive resize delta:
`mosaic (103/100) [1,1,1]` grows the focused weight by 3% on Expand.
The example's `logHook` sets `SetMosaicResizeFactor (103/100)` and sends
`RepairMosaicWeights`: each workspace's Mosaic shares are equalized once to
repair old saved weights. Completion persists across restart; subsequent
resizing is preserved. Workspace membership, stack order, floats and surrounding
layout settings are unchanged. `M-C-m` explicitly equalizes Mosaic shares again.

## Keys

`M` is Option (`mod1Mask`), `S` is Shift, `C` is Control; `mod4Mask` is Command.
Bindings use physical US keys, not layout-dependent text keysyms.
The table includes example-config additions.

| Key | Action |
|---|---|
| `M-j` / `M-k` / `M-Tab` | Focus next / previous / next |
| `M-m` | Focus master |
| `M-S-j` / `M-S-k` | Swap in the stack |
| `M-←` / `M-→` / `M-↑` / `M-↓` | Focus the window in that direction |
| `M-S-←` / `M-S-→` / `M-S-↑` / `M-S-↓` | Move the window in that direction |
| `M-Return` / `M-S-Return` | Swap with master / launch terminal |
| `M-h` / `M-l` | Shrink / expand master |
| `M-C-m` | Equalize Mosaic shares (other layouts unchanged) |
| `M-,` / `M-.` | More / fewer masters |
| `M-Space` / `M-S-Space` | Next layout / reset |
| `M-1…9`, `M-0` | View that **virtual** workspace |
| `M-S-1…9`, `M-S-0` | Move focused window there |
| `M-w` / `M-e` | Focus screen 0 / 1 |
| `M-r` | Reflect layout (overrides default screen-2 focus) |
| `M-S-w` / `M-S-e` / `M-S-r` | Send to that screen's workspace |
| `M-f` / `M-t` | Float / sink |
| `M-C-Space` | Switch between the tiled and floating layer |
| `M-S-c` | Close (never force-quit) |
| `M-q` / `M-S-q` | Recompile / quit |
| `M-S-p` | Pause and restore hidden windows |
| `M` + left / right drag | Float and move / resize |
| `Ctrl-Opt-Cmd-Esc` | Emergency stop |

Drag sets `W.float`. Across displays, the window joins the workspace visible
there. Override with `mouseBindings` / `additionalMouseBindings`
(`MouseMove`, `MouseResize`, `MouseRaise`). Mask 0 is rejected.

Dialogs (`AXDialog` / `AXFloatingWindow`) float at the app's size. Sheets
and popovers are unmanaged. A window of an accessory (`LSUIElement`) app is
managed while the app owns it: it floats, and a newly shown one is brought
forward because such an app has no Dock icon or ordinary activation path. This
covers Box Drive's integration panel, which is a fixed-size standard window.

Borders: `borderWidth`, `focusedBorderColor`, `normalBorderColor` (0 turns
them off). They are click-through overlays. `focusFollowsMouse` is on by
default. `XMonad.Actions.UpdatePointer`'s `updatePointer` in the `logHook`
moves the pointer to the focused window; the helper skips it when the pointer
is already there or a mod-drag is in progress.

## Displays and focus

One virtual workspace per display. Screen 0 is the macOS primary. A replug
with the same display ID reclaims its workspace. Mission Control Desktops
are still not these workspaces.

## Menu and status

Menu bar: `[2] 1 3 - Tall`. Settings can swallow macOS window shortcuts
while tiling (nothing is written to System Settings), log key events, and
delete old logs. `xmonad status` is JSON for an external bar.

**Restart XMonadMac** (or `xmonad relaunch`) quits the app, restoring its
windows, and starts it again in the same mode.

`bridge.log` is kept as `bridge-<date>-<time>.log` once it passes 5 MB. With
**Delete logs older than 7 days** on, which is the default, kept logs past
that age are removed.

For custom bars, `Hooks.StatusBar` supports `statusBarFile`, `statusBarSpawn`,
`statusBarPipe` and `macMenuBarPP` through `withSB`. Output updates when text
changes. `ppTitle` uses AXTitle; `ppOutput` defaults to stderr because stdout
is reserved for the protocol.

## Paths

| Path | |
|---|---|
| `/Applications` or `~/Applications/XMonadMac.app` | Helper |
| `~/.local/bin/xmonad` | Control command (also `xmonadctl`) |
| `~/Library/Application Support/XMonadMac/` | Engine, `build-kit`, `recovery.json`, `session.json` |
| `~/Library/Logs/XMonadMac/bridge.log` | Log, with kept `bridge-*.log` |

`./scripts/signing-identity.sh` makes the Accessibility grant survive
rebuilds. `xmonad recover` restores WM-hidden windows after a crash.
Ambiguous records are kept, not guessed.

`./scripts/make-upstream-fork.sh` grafts this tree under `macos/` onto
xmonad at `a9a8b5c1`.
