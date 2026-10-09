# Design

```text
xmonad.hs → Haskell engine ⇄ NDJSON ⇄ signed Swift helper → macOS windows
```

- **Haskell:** `StackSet`, layouts, messages, hooks and configuration.
- **Swift:** public AX, AppKit and event taps. AX mutations run on a serial
  queue, never on the event-tap thread.
- No XQuartz, X11 proxy, private CGS/SLS APIs or Dock injection.

## Windows and workspaces

`Window` is a per-session handle, not an XID or CGWindowID. Window identity
uses AX elements and public fingerprints; process identity includes launch time.
Admission uses AX roles/capabilities and conservative public PID/frame matching.
Chrome's missing CG metadata and Emacs's AX roles have explicit handling.

Workspaces are **xmonad tags, not macOS Spaces**. Hidden windows are parked
off-screen; apps that refuse parking (Finder) are minimized. `Full` hides
nothing. Dialogs float; sheets, popovers, hidden apps and user-minimized windows
are left alone. Native full-screen suspends tiling.

Epoch rebuilds carry workspace stacks, layouts, current workspace and floats
for surviving windows. Failed AX eligibility reads retain the last known state.

## Safety and recovery

- Plans require matching generation and epoch.
- Explicit focus requests have action IDs and deadlines. User takeover cancels
  retries; ordinary scans do not activate apps.
- Hides are journaled **before** mutation. Recovery restores only WM-owned
  hides, not user-minimized windows; it is not a full geometry rollback.
- `session.json` restores workspace/float state after helper restart using
  public fingerprints. Ambiguous matches remain unresolved.
- Emergency stop and recovery do not depend on the Haskell engine.

## Recompile

The engine lives outside the signed app. `xmonad --recompile` builds against
the installed `build-kit` and replaces the engine only after validation.
A failed compile leaves the old engine running. `xmonad autostart on` registers
the signed app with launchd.
