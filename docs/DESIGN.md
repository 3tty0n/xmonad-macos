# Design

## Why not XQuartz

XQuartz is the X.Org X Window System running on macOS. Managing its X11
clients with stock xmonad is a different problem from managing Safari, Finder,
and Terminal windows: native windows never become X11 children of a window
manager, no matter what is running.

A proxy design — one X11 stand-in per native window, translating X11 geometry
into AX calls — is possible, but it has to keep focus, destruction,
coordinates, visibility, and window attributes synchronized between the real
window and its stand-in, and it still cannot honor the semantics of contrib
APIs that assume a real X11 object. Porting the pure state and layout
interfaces keeps the boundary far clearer.

## Responsibilities

```text
xmonad.hs + user lib/*.hs
             │ GHC / Cabal
             ▼
      xmonad-engine process
      ├─ XMonad.StackSet        upstream zipper
      ├─ LayoutClass            runLayout / handleMessage
      ├─ Tall / Mirror / Full   original layout algorithms
      ├─ X / ManageHook / keys  macOS runtime
      └─ reconcile / plan / session checkpoint
             ⇅ NDJSON over stdin/stdout
      XMonadMac.app (the signed, privileged native helper)
      ├─ main runloop           AppKit, menu, supervision
      ├─ event tap threads      detect keys and mouse only; never call AX
      ├─ serial AX queue        enumerate, mutate, restore, observe
      └─ pipe reader/writer     isolates the UI from a stalled engine
             ⇅ public AX / AppKit / CoreGraphics
      native application windows
```

Haskell owns policy; Swift owns mechanism. No layout logic lives on the Swift
side, and window-management state is not duplicated in both languages. The
Swift registry holds AX objects, transient handles, ownership records, and
observations — nothing else.

The two halves are separate processes rather than one GHC-FFI binary so that
the AppKit main thread, code signature, and TCC grant stay stable while your
Haskell config is recompiled. The signed `.app` runs the engine from
Application Support as a child, so a config change never re-signs the app.
Rebuilding the helper changes its code directory hash, which invalidates an
ad-hoc signature's TCC grant. `scripts/signing-identity.sh` creates a
persistent local certificate once; TCC then keys the grant on the certificate
and the rebuilt helper keeps it. Trusting the certificate needs a password
prompt, so the build never does it implicitly — it probes with `--if-ready`
and falls back to ad-hoc with a hint.

## What was ported

`StackSet.hs` is a shortened, adapted derivative of the upstream zipper.
`Layout.hs` keeps `Tall`, `Mirror`, and `Choose`, replacing the X11
`Rectangle` and `DestroyWindowEvent` with a portable rectangle and
`WindowRemoved`. `Core.hs` keeps the `LayoutClass` and `Message` contracts but
not the X11 `Display`, root window, atoms, or event loop.

So this is neither stock xmonad with an XQuartz config, nor a shim that fills
the X11 API with fabricated values. It is a narrow portability fork with a new
runtime underneath. BSD attribution is preserved in every derived source and
in `LICENSE`.

## Window identity

A `Window` is a monotonically increasing `Word64` handle, valid only while the
helper runs. It is deliberately not a `CGWindowID` or an XID. `AXUIElement`
values are re-identified with `CFEqual` inside a per-PID registry, and the
app's launch date is tracked so PID reuse cannot alias two processes.

Using public APIs only, this implementation does not claim to correlate an AX
window with its `CGWindow` perfectly. It matches PID and frame against the
currently visible CG windows, and conservatively excludes candidates whenever
same-PID, same-frame matches outnumber the visible windows. It never reads CG
window names or screen images, so Screen Recording permission is not needed.
If the OS or an app withholds the metadata, a window can still be missed.

Only `AXStandardWindow` windows whose position, size, and minimized state are
settable are managed. Dialogs, sheets, popovers, native full-screen windows,
user-minimized windows, and hidden apps are left alone. The admission rule is
deliberately narrow.

## State transitions and focus

Each reconciliation removes windows that vanished from the snapshot, inserts
new ones into the workspace of the display they appeared on, and applies
`manageHook` once per window. Windows the WM minimized stay in the snapshot:
treating them as destroyed would drop their logical workspace every time,
which is why user-minimized and owned-hidden are distinguished.

Observing focus in a snapshot never triggers a native activate or raise. Focus
intent is included in a plan only when a key binding asked for it. Because
minimization is asynchronous and stale plans are dropped, that intent is
carried until it is observed or four reconciliation ticks pass. Ticks are not
wall-clock seconds under load; explicit action sequences with monotonic
deadlines are the intended replacement.

A manual move of a floating window updates its relative rectangle only when
the observed frame actually changed. The built-in mod+left / mod+right drag
captures pointer events in the tap but performs hit-testing and the move or
resize on the serial AX queue. Drag start sends `mouseFloat` so that policy
sets `W.float` and focus intent; the drag target is excluded from plan moves
and hides until release, which prevents snap-back races. A floating window
dragged across displays is shifted to the logical workspace visible on the
destination display, and its `RationalRect` is recomputed there.

## Coordinates and displays

Geometry uses global, top-left logical points, as AX and Quartz do.
Conversion from AppKit's bottom-left origin uses the primary display's
`frame.maxY` as `H`: `y = H - frame.maxY`. Negative coordinates from displays
above or to the left are preserved, and Retina scale is never applied twice.

Placement uses `NSScreen.visibleFrame`, avoiding the Dock and menu bar. It
does not attempt to model every notch or app-specific constraint. A display
that returns with the same display ID reclaims its workspaces; a disconnected
display's workspaces become hidden rather than losing their windows.
Remembering display affinity permanently across reconnects is not implemented.

## Workspaces

With one display and the Space bridge available, workspace *N* **is** Desktop
*N*: the *N*-th user Space in Mission Control order. Switching workspaces
switches the Space (`SLSManagedDisplaySetCurrentSpace`) and sending a window
moves it (`SLSMoveWindowsToManagedSpace`, addressing the window by the
`CGWindowID` behind its AX element). Nothing is minimized, and a Space the
user switches to by any other means — `Control-N`, a swipe, Mission Control —
is reported in the next snapshot and simply becomes the current workspace.

These are not public API, so they are resolved with `dlsym` at startup and the
whole path is skipped if any symbol is missing. A second display also falls
back, because Spaces are per display and one workspace list cannot yet address
several Space lists. More workspaces than Desktops logs a warning; the extra
workspaces have nowhere to go.

## Logical workspaces (fallback)

Hiding a window means `AXMinimized = true`. Unlike an X11 unmap, that involves
the Dock, an animation, and apps that may refuse or clamp. It is the initial
implementation chosen to build workspaces on public API alone, not a full
substitute for Spaces. The `Full` layout avoids it entirely by stacking every
window at the same frame and raising the focused one.

A native Space switch bumps the epoch so older plans are discarded, restores
hidden windows to their recorded frames, and rebuilds Haskell state. Logical workspaces that
span native Spaces are not guaranteed at this stage. Tiling pauses while a
native full-screen window is frontmost.

## Validation and recovery

Every plan must match the current generation and epoch. Plans are rejected for
duplicate IDs, IDs outside the current snapshot, a window that is both shown
and hidden, focus on a hidden window, or an invalid rectangle. Stale plans are
never applied; when one is dropped under load, the next reconciliation
recomputes placement from the still-authoritative policy state.

Before minimizing, an ownership record is written atomically to a private
file. If that write fails, the window is not minimized. Restore only touches
windows with an ownership token, and the token is kept until AX confirms the
window is back. A short settling interval covers minimize/restore transitions
that arrive out of order.

While the owning process lives, restoration works through the AX object.
After a helper restart it requires PID + launch date + bundle + `AXIdentifier`,
or, absent an identifier, a unique title-and-frame match. If nothing matches
uniquely, the record is kept rather than risking the wrong window. This is not
full crash recovery, and it never rolls back original geometry.

Keyboard and pointer callbacks never call AX, and the emergency stop does not
route through the Haskell process. Neither helps if the helper's own main loop
fails or the tap is forbidden — the CLI recovery path and manual Dock restore
exist for that. The engine's 8-second response watchdog covers a stalled
child, but it does not measure total AX queue latency; that remains open work.

## Operations and privileges

There is no listener and no network command channel. NDJSON travels over a
pipe to the helper's own child. Arbitrary IO in your config runs with your
privileges, so the config is not a sandbox. stdout carries protocol only;
diagnostics go to stderr, including the stdout of anything `spawn` starts.

Logs, snapshots, and recovery records can contain window titles. Directories
are `0700`, the recovery record is `0600`, and the process umask is `077`.
Review them before attaching anything to a public issue.

## Config recompilation

Installation copies the portable Haskell sources and Cabal metadata to
`build-kit` under Application Support. Recompiling `xmonad.hs` happens in a
separate process from the running engine; the new engine must pass
`--check-config`, and the helper must validate its key bindings, before an
atomic rename swaps it in. A syntax error, a type error, or an unsupported key
therefore leaves the running engine untouched.

`M-q`, the menu's Recompile, and `xmonad --recompile` all take this path.
`Reload compiled xmonad.hs` and `xmonad --restart` skip the build and restart
the existing engine. Reinstalling the app refreshes the build kit and never
overwrites your config.

Login startup is separate from installation: a LaunchAgent is created only
when you run `xmonadctl autostart on`, and it launches the app bundle through
LaunchServices so that no unsigned helper receives Accessibility rights.

## AX self-test

`xmonadctl self-test` inspects the focused standard AX window: role and
subrole, whether position, size, and minimized are settable, whether the frame
reads back, whether writing the *same* frame round-trips, and whether the
public `CGWindowListCopyWindowInfo` entry correlates by PID and rectangle. It
never moves or minimizes the window. It is an aid to real-machine acceptance,
not a replacement for the multi-window, ownership, and Spaces-race tests in
[TESTING.md](TESTING.md).
