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
- Latest local checks: `make check` and `make build` passed; 331 Swift checks,
  491 static checks, Haskell tests and NDJSON integration.
- Recent regressions covered: transient AX eligibility reads, Settings focus
  takeover, popup-role classification and queued-hover invalidation. The log
  showed a known window briefly leaving with `eligible=false` and returning
  with the same handle. Desktop reproduction/verification remains outstanding.

**Not desktop-verified:** hotplug, mixed Retina, native Space transitions,
long AX-queue latency, journal crash recovery, Magnifier, BoringWindows,
NamedScratchpad, NoBorders, Settings/popup focus fixes and transient-read
  workspace/stack stability. Automated success does not establish these.

Additional regressions: fake-clock visibility grace, failed versus empty CG
queries, conservative actionability and owned-window restore; Mosaic's real
Expand/Shrink path, spacing, signed origins and checkpoint/layout reset.
Mosaic factor-override tests verify old checkpoint shares are preserved while
the multiplier changes, subsequent resizing uses it, and invalid overrides
are rejected.
One-time share repair is tested for preserving workspace stack, allowing later
resizes, persisting completion through restart and supporting explicit reset.
Wrapped Mosaic tests also cover a floating window preceding the tiled focus:
resize uses the tiled index and ignores focus on a floating window, including
with REFLECTX enabled.
CG/hidden uncertainty has bounded retention; positive CG/app visibility can
retain policy identity during AX timeouts, without permitting AX mutations.
Sustained snapshot exclusion still loses membership and needs separate work.

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
