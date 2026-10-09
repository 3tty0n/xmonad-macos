# Testing

```sh
make check
./scripts/test-portable.sh   # Swift unit tests + static checks
./scripts/test.sh            # Haskell core + engine integration
```

| Suite | Covers |
|---|---|
| `tests/WireTests.swift` | Coordinates, protocol, Emacs admission, plan safety, fingerprints |
| `tests/static_checks.py` | Packaging and contract greps |
| `tests/CoreTests.hs` | StackSet, layouts, lifecycle, checkpoints, atomic recompile |
| `tests/integration.py` | Shipped config over NDJSON |

`test.sh` uses `build/config`, never your personal `xmonad.hs`.

## Last recorded run

macOS 26.6.2, arm64, GHC 9.12.3, cabal-install 3.18.1.0, Apple Swift 6.2.
`make check` passed; handshake, tiling, `M-0`, Finder hide/restore,
`xmonad --recompile` / `--restart`, and quit were confirmed on the machine.

Not yet verified: hotplug, mixed Retina, native Space transitions, long
AX-queue latency, crash recovery from the journal.

Magnifier, BoringWindows, NamedScratchpad and NoBorders are covered by
`CoreTests` (and the Swift side by `WireTests.swift`) only. No desktop run has
observed a magnified frame, a skipped window, a scratchpad parked on `NSP`, or
a border the layout dropped.

## Manual matrix

Settings-focus regression: a newly observed, natively focused Settings window
matched by `doFloat` cancels an older pending focus request. CoreTests covers
that takeover and verifies stale focus observations still retain the request.
Queued hover results are discarded if observed focus changed during the
hit-test. Desktop verification of opening Settings remains outstanding.

Popup-focus regression: `make check` and `make build` passed locally after
switching hover targeting to AX hit-testing and treating a focused menu or
unmanaged popup as takeover of an outstanding focus request. Portable tests
cover transient-role classification only. Still needs desktop verification:
right-click menus and Chrome extension popups stay open while the pointer
moves inside them; normal hover focus resumes after closing them.

Shipped config, one native Space per display, Stage Manager off, no unsaved
work.

| Test | Expected |
|---|---|
| AX permission | Stops until granted |
| `make dry-run` | Plans logged; nothing moved |
| `xmonad self-test` | Focused standard window, settable geometry, CG correlation |
| Three windows | Tiled in the usable area |
| `M-j` / `M-k` | Focus moves; observation does not steal it |
| Native tabs | One AX window |
| `M-Space` to Full | Focused window fills the screen; nothing minimized |
| `M` + drag | Floats; no snap-back |
| Save panel | Floated, not tiled |
| `M-2` then `M-1` | Only WM-hidden windows return |
| Finder `M-2` / `M-1` | Minimizes, then tiles again |
| Your `Cmd-M` | Never auto-restored |
| Bad `M-q` | Old engine keeps running |
| Kill helper | `xmonad recover` restores owned hides |
| Native Space switch | Stale-epoch plans dropped |
| Green-button full-screen | Tiling pauses |

`xmonad log` / `doctor` / `dump` for debugging. Redact titles before sharing.
