# Testing

```sh
make check                  # all automated checks
./scripts/test-portable.sh  # Swift unit tests and static checks
./scripts/test.sh           # Haskell tests and NDJSON integration
make build                  # native SDK and config compilation
make ax-test                # desktop AX fixture checks (needs permission)
```

Tests use `example/xmonad.hs`, staged in `build/config`, not your personal config.

| Suite | Coverage |
|---|---|
| `WireTests.swift` | Protocol, geometry, admission, fingerprints, plan safety, scan backoff, journal format |
| `CoreTests.hs` and companion modules | StackSet, layouts, actions, checkpoints, lifecycle, recompile |
| `integration.py` | Compiled example over NDJSON |
| `static_checks.py` | Source/packaging guards; **not** compilation or desktop testing |

## Native AX fixture

`make ax-test` builds `build/AXFixture.app` and runs the desktop checks against
the running helper. It needs a logged-in desktop, a running/configured
XMonadMac, Accessibility permission for it, and `--allow-desktop` (the Makefile
passes it) because it creates and closes fixture windows. The fixture supports:

- ordinary, duplicate-title, min/max-size and fixed-size windows;
- delayed minimize and explicit unminimize;
- an accessory (`LSUIElement`) mode;
- `hang N` to block its main thread while other apps must keep working.

The driver compares AppKit's actual `topLeftFrame` and `isMiniaturized` state
with the helper's `xmonad dump` snapshot. It covers membership, focus, close,
user-minimize ownership, duplicate titles, native tab groups, delayed minimize,
a hung app not starving a responsive one, and the accessory fixed-size floating
path. It does not replace the manual matrix below for native Spaces, display
hotplug or mixed Retina.

## Recorded results

- Earlier desktop run: macOS 26.6.2, arm64, GHC 9.12.3, cabal 3.18.1.0,
  Swift 6.2. Handshake, tiling, `M-0`, Finder hide/restore, recompile/restart
  and quit were confirmed.
- Latest local checks: `make check` and `make build` passed; 436 Swift checks,
  571 static checks, Haskell tests and NDJSON integration.
- 2026-11-02 desktop run (macOS 26.6.2, arm64, GHC 9.12.3, cabal 3.18.1.0,
  Swift 6.2): `xmonad self-test`, `make ax-test`, `xmonad --recompile`,
  `xmonadctl recompile`, `xmonad autostart on/off/status` and
  `xmonad recover --report` passed. The fixture verified membership, focus,
  close, user-minimize ownership, duplicate titles, delayed minimize, a hung
  app not starving another and the accessory fixed-size floating path. A
  deliberately corrupt `recovery.json` started paused, produced exactly one
  quarantine copy, and `recover --report` returned 2 without adding another.
  The original journal was restored and the helper resumed.
- 2026-11-02 Ghostty tab verification: with four AX windows at one frame
  (native tab group), the helper managed exactly one container. Switching from
  the single-Ghostty workspace to workspace 3 parked it off-screen and switching
  back restored it at its original frame. The extra test tab was closed.
- Recent regressions covered: transient AX eligibility reads, Settings focus
  takeover, popup-role classification and queued-hover invalidation. The log
  showed a known window briefly leaving with `eligible=false` and returning
  with the same handle. Desktop reproduction/verification remains outstanding.

**Not desktop-verified:** hotplug, mixed Retina, native Space transitions,
the 8s wedged-AX-queue exit path, crash injection between journal write and
minimize confirmation, Magnifier, BoringWindows, NamedScratchpad, NoBorders,
Settings/popup focus fixes, transient-read workspace/stack stability,
floating-drag overlay repaint, the real Box Drive panel (the synthetic
accessory fixture is covered), and every native fix below. Automated success
does not establish these.

The accessory path was observed once on the desktop: Box Drive's search panel
entered the snapshot with `accessory=true`, was floated at its own frame (no
constrained-geometry log), and was reported as the focused window. Box closes
that panel on losing focus, so its own lifetime is not a stable target.

Additional regressions:
- Native: fake-clock visibility grace and failed-versus-empty CG queries;
  conservative actionability and owned-window restore; queued-hover
  invalidation; popup/settings focus; floating-drag overlay repaint; the
  constrained-write backoff; and the process-start-time readiness decision.
  A fixed-size standard window of an accessory app is eligible only to float.
  A repeatedly timing-out app enters scan cooldown, keeps its known windows in
  the snapshot but not actionable, and cannot exceed the 30s retry cap.
  Native tab siblings at a container's frame are excluded from same-frame
  ambiguity, so the visible tab group remains manageable.
- Haskell: an accessory-app window is floated and a newly admitted one carries
  a focus action; hovering the already focused window sends no action; Mosaic's
  real Expand/Shrink path, spacing, signed origins, checkpoint/layout reset and
  one-time share repair; bounded retention of a window omitted from a snapshot
  (membership kept, plan-omitted, re-appearance, expiry, no premature removal,
  epoch rebuild).
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
| Box Drive integration panel | Floats with a border; a newly shown one comes to the front and keeps keyboard focus |
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
