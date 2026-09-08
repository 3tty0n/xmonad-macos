# Testing

## Automated checks

```sh
make check          # everything below
./scripts/test-portable.sh  # Swift unit tests, static checks, ops smoke test
./scripts/test.sh           # Haskell core tests + compiled-engine integration
```

| Suite | What it covers |
|---|---|
| `tests/WireTests.swift` | 156 checks: signed coordinate conversion, displays above/left/below the primary, no double Retina scaling, display selection, JSON fields, key mapping, plan validation |
| `tests/static_checks.py` | 121 source and packaging checks |
| `tests/ops_smoke.sh` | The installed recompile is atomic; a simulated build failure preserves the previous engine byte-for-byte |
| `tests/CoreTests.hs` | StackSet focus/swap/shift/uniqueness, `Tall` geometry and area, `Full` stacking, `Choose` cycling, user vs. WM minimization, ignore, multiple displays, hotplug, checkpoints, key parsing, JSON |
| `tests/integration.py` | Runs the shipped config as a real engine and drives focus, mouse-float, layout, shift, view, checkpoint, and ping over NDJSON |

`scripts/test.sh` stages the shipped config into `build/config`; it never tests or
modifies your personal config.

## Verified on macOS

Last recorded run: macOS 26.5.2, arm64, GHC 9.12.3, cabal-install 3.18.1.0,
Apple Swift 6.2.

- `make check` passes end to end.
- The native app builds, signs, verifies, and launches.
- The engine handshake, tiling, layout switching, and workspace switching
  (including `M-0`) were confirmed against the running app by injecting key
  events and reading `status.json`.
- Config recompile and reload through `xmonad --recompile` / `--restart`.

## Not yet verified

The manual matrix below, in particular: display hotplug, mixed Retina scaling,
native Space transitions, app-specific AX behavior and timeouts, crash
recovery from the journal, and long-session AX queue latency. Until those
pass, treat this as a working prototype rather than a finished daily driver.

## Manual acceptance matrix

Preconditions: the shipped config, one native Space per display, Stage Manager
off, yabai/skhd stopped, and no unsaved work in the windows you test with.

| Test | Steps | Expected |
|---|---|---|
| AX permission | Launch before and after granting | Stops explicitly when not granted; works after a restart |
| Read-only | `make dry-run` with three normal windows | Plans in the log; nothing moved, minimized, or intercepted |
| AX self-test | Focus a normal window, `xmonad self-test` | Standard window, settable attributes, same-frame write/read-back, CGWindow correlation all pass |
| First tile | Open three windows, launch normally | All tiled inside the usable area; constraints logged |
| Focus | Repeat `M-j` / `M-k`, then click another app | Keys move focus; passive observation never steals it |
| Native tabs | Switch tabs in Terminal or Ghostty | Still one AX window; tabs are not mistaken for windows |
| Swap / layout | `M-S-j`, `M-h`, `M-Space` | Order, ratio, and Tall/Mirror/Full all apply |
| Full layout | `M-Space` until Full | Focused window covers the screen; **nothing is minimized to the Dock** |
| Mouse move | `M` + left drag | The window floats and does not snap back mid-drag |
| Mouse resize | `M` + right drag | Resizes down to the 80x60 floor and keeps its geometry after release |
| Cross-display drag | Drag a floating window to another display | Joins the workspace visible there; the next plan does not pull it back |
| Owned hidden | `M-2` then `M-1` | Only WM-minimized windows are restored |
| User minimized | `Cmd-M` yourself, then switch workspaces | Your minimized window is never restored automatically |
| Hidden app | `Cmd-H`, then unhide | The hidden app is not forced; it returns to management on reappearance |
| Async race | Switch workspaces rapidly; move focus in Full | No bounce back to the old workspace, no stranded minimization |
| Recompile | Change the ratio, then `M-q` | The engine swaps only after a successful build; the helper is untouched |
| Reload | `xmonad reload` | Restarts the compiled engine and keeps the checkpoint |
| Compile failure | Introduce a syntax error, then `M-q` | The running engine keeps going; the failure appears in status and log |
| Autostart | `xmonad autostart on`, log out and in | The bundle starts once; `off` stops it |
| Helper crash | Kill the helper, then `xmonad recover` | Uniquely identifiable windows are restored; ambiguous ones keep their record |
| Engine crash | Kill only the engine | The helper pauses and restores owned minimizations |
| Engine hang | `SIGSTOP` the engine | The watchdog pauses and restores; kill the stopped process afterwards |
| Emergency | `Ctrl-Opt-Cmd-Esc` | Pause and restore without going through Haskell |
| Key-up | Hold `M-j`, release the modifier first | No unmatched key-up leaks to other apps |
| Displays | Screens left/above/below, hotplug, mixed Retina | Negative coordinates preserved; window set and workspace identity intact |
| Native Space | Switch Spaces in macOS | Stale-epoch plans are discarded and state rebuilt |
| Full-screen | Green-button an app | Tiling pauses while it is frontmost |
| Quit | Quit while windows are hidden | WM-owned minimizations restored; yours left alone |

Record OS build, CPU architecture, Swift and GHC versions, app names and
versions, and the display arrangement with your results.

## Debugging

```sh
xmonad log        # follow the bridge log
xmonad doctor     # environment, permissions, signature, recent log
xmonad dump       # write a diagnostic snapshot
```

Enable **Log key events to bridge.log** from the menu when a binding looks
dead. Each modified key press is logged as
`key code=… mask=… bound=… consumed=… tiling=…`, which distinguishes "the tap
never saw it" from "a different modifier arrived" from "no binding matched".

Snapshots and logs contain window titles. Redact them before sharing.
