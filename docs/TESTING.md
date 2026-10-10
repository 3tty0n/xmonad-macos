# Testing

```sh
make check                  # all automated checks
./scripts/test-portable.sh  # Swift unit tests and static checks
./scripts/test.sh           # Haskell tests and NDJSON integration
make build                  # native SDK and config compilation
```

Tests use `example/xmonad.hs`, staged in `build/config`, not your personal config.

| Suite | Coverage |
|---|---|
| `WireTests.swift` | Protocol, geometry, admission, fingerprints, plan safety |
| `CoreTests.hs` and companion modules | StackSet, layouts, actions, checkpoints, lifecycle, recompile |
| `integration.py` | Compiled example over NDJSON |
| `static_checks.py` | Source/packaging guards; **not** compilation or desktop testing |

## Recorded results

- Earlier desktop run: macOS 26.6.2, arm64, GHC 9.12.3, cabal 3.18.1.0,
  Swift 6.2. Handshake, tiling, `M-0`, Finder hide/restore, recompile/restart
  and quit were confirmed.
- Latest local checks: `make check` and `make build` passed; 371 Swift checks,
  492 static checks, Haskell tests and NDJSON integration.
- Recent regressions covered: transient AX eligibility reads, Settings focus
  takeover, popup-role classification and queued-hover invalidation. The log
  showed a known window briefly leaving with `eligible=false` and returning
  with the same handle. Desktop reproduction/verification remains outstanding.

**Not desktop-verified:** hotplug, mixed Retina, native Space transitions,
long AX-queue latency, journal crash recovery, Magnifier, BoringWindows,
NamedScratchpad, NoBorders, Settings/popup focus fixes, transient-read
workspace/stack stability, floating-drag overlay repaint, and every native fix
below. Automated success does not establish these.

Additional regressions:
- Native: fake-clock visibility grace and failed-versus-empty CG queries;
  conservative actionability and owned-window restore; queued-hover
  invalidation; popup/settings focus; floating-drag overlay repaint; the
  constrained-write backoff; and the process-start-time readiness decision.
- Haskell: Mosaic's real Expand/Shrink path, spacing, signed origins,
  checkpoint/layout reset and one-time share repair; bounded retention of a
  window omitted from a snapshot (membership kept, plan-omitted, re-appearance,
  expiry, no premature removal, epoch rebuild).
- The bridge log showed a known window briefly leaving with `eligible=false`
  and returning with the same handle; a drag moved a floating frame without
  repainting its overlay. Desktop reproduction remains outstanding.

**Remaining limit:** a prolonged omission beyond the generation grace still
drops membership; extending retention further needs a persistence contract.

## Desktop checklist

Use saved, sacrificial windows, the example config, one native Space per
display and Stage Manager off. TCC permission requires interactive consent.

| Test | Expected |
|---|---|
| AX permission / dry-run | Waits for permission; dry-run moves nothing |
| `xmonad self-test` | Focused standard window, settable geometry, CG correlation |
| Three windows / native tabs | Tiles in usable area; tabs appear as one AX window |
| `M-j` / `M-k` | Focus moves without being stolen back |
| `M-Space` to Full | All windows remain unminimized; focused window fills screen |
| `M` + left/right drag | Floats and moves/resizes without snap-back |
| Save panel / Settings | Floats; newly focused Settings stays in front |
| Right-click / Chrome extension popup | Stays open; hover resumes after dismissal |
| `M-2` then `M-1` | Only WM-hidden windows return; Finder minimizes/restores |
| User `Cmd-M` | Never auto-restored |
| Bad `M-q` | Old engine keeps running |
| Kill helper / `xmonad recover` | Restores WM-owned hides |
| Space switch / display wake | Rejects stale plans; preserves surviving workspace state |
| Native full-screen | Suspends tiling |
| Temporary AX timeout | Does not re-adopt known windows or change their stack/workspace |

Debug with `xmonad log`, `doctor` and `dump`. Logs/dumps are private and may
contain titles; redact them before sharing.
