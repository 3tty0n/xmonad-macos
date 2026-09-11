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
app's process instance is tracked so PID reuse cannot alias two processes.
That instance is `NSRunningApplication.launchDate` where macOS reports one.
It reports none for the session's own launchd children - Finder is the one
that matters - so the BSD process start time from `sysctl(KERN_PROC_PID)` is
the fallback. Without an instance a hide cannot be journaled and is refused,
which is why Finder was never hidden at all.

The element is not the identity, though: waking a display makes macOS destroy
every window's element and issue a fresh one. A record whose element has gone
is kept for three scans, and a new element from the same application is
adopted into it when it matches uniquely - by `AXIdentifier`, or by title plus
either the old frame or our own ownership of the window. Two candidates for
one element is never guessed at; those windows are re-admitted as new.

Using public APIs only, this implementation does not claim to correlate an AX
window with its `CGWindow` perfectly. It matches PID and frame against the
currently visible CG windows on application layers (normal, floating, modal
panel, utility), and conservatively excludes candidates whenever same-PID,
same-frame matches outnumber the visible windows. It never reads CG
window names or screen images, so Screen Recording permission is not needed.
If the OS or an app withholds the metadata, a window can still be missed.
Google Chrome withholds that on-screen list entirely; those windows are
admitted from AX, which already omits Chrome's windows on inactive Spaces.
Chromium also leaves the system-wide focused-application lookup empty: focus
falls back to `NSWorkspace.frontmostApplication` and that app's
`AXFocusedWindow`. Geometry writes temporarily clear `AXEnhancedUserInterface`
so a frame lands instead of animating away.

Only `AXStandardWindow` windows whose position, size, and minimized state are
settable are tiled. Dialogs and floating panels (`AXDialog`, `AXSystemDialog`,
`AXFloatingWindow`, `AXSystemFloatingWindow`) are admitted when position is
settable, reported with their AX subrole, and floated by policy so they keep
the size the application chose. Sheets, popovers, native full-screen windows,
user-minimized windows, and hidden apps are left alone. The admission rule is
deliberately still narrow: a sheet is tied to its parent.

## State transitions and focus

Each reconciliation removes windows that vanished from the snapshot, inserts
new ones into the workspace of the display they appeared on, floats dialogs
and floating panels at their observed size, and applies `manageHook` once
per window. `doIgnore` still removes a dialog; `doSink` can put one in the
tiling. Because a window that disappears loses its
workspace, the helper never reports one gone on a single observation: an
application missing from `NSWorkspace.runningApplications` has to be missing
twice and be confirmed dead with `kill(pid,0)`, and a scan with no
applications at all is discarded. Coming back from display sleep, macOS
briefly reports both. Windows the WM minimized stay in the snapshot:
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

Hiding a window means parking it past the bottom-right corner of the display
arrangement, keeping its size. There is no X11 unmap to use, and `AXMinimized`
- the obvious substitute - involves the Dock, an animation whose intermediate
states AX reports inconsistently, and apps that refuse or delay it. Parking is
a plain position write on the same path as tiling.

`NSWindow.constrainFrameRect` keeps roughly 40 points of a window on screen:
parking an 880-point window past a 3360-point display's right edge lands it at
3320, not 3424. In the corner both limits apply at once and about 40x32 points
remain, which the admission rule treats as hidden. An app that clamps harder
would leave a visible strip over the workspace, so `hide` re-reads the frame
and minimizes that window instead. Finder ignores a position-only park (the
set succeeds, the frame does not change) and clamps a size-position-size park
into a large visible corner panel, so it is minimized and never parked. For
other apps, a later scan compares the journaled original against the on-screen
CGWindow list and minimizes if it is still there. The window server still
lists the pre-park frame for a moment, so that check is not done in the same
call as the park. Observed focus is followed only onto a workspace that is on
a screen, so a window that has not yet left the display cannot reverse a
view. The token is kept if minimize is refused, so the engine does not adopt
the window as new. The `Full` layout hides nothing at all.

Native Spaces would be the natural home for workspaces, and are not usable.
`SLSMoveWindowsToManagedSpace` silently ignores a window owned by another
process, so a workspace switch could change Desktop while the window stayed
behind; this was measured, not assumed. Doing it properly requires injecting
into `Dock.app` with SIP disabled, which is outside this project's
public-API premise, and `tests/static_checks.py` fails the build if a `CGS`,
`SLS` or `_AXUIElementGetWindow` symbol appears in the sources.

A native Space switch bumps the epoch so older plans are discarded, restores
hidden windows to their recorded frames, and rebuilds Haskell state. Logical
workspaces that span native Spaces are not guaranteed. Tiling pauses while a
native full-screen window is frontmost.

## Validation and recovery

Every plan must match the current generation and epoch. Plans are rejected for
duplicate IDs, IDs outside the current snapshot, a window that is both shown
and hidden, focus on a hidden window, or an invalid rectangle. Stale plans are
never applied; when one is dropped under load, the next reconciliation
recomputes placement from the still-authoritative policy state.

Before hiding a window, an ownership record with its current frame is written
atomically to a private file. If that write fails, the window is not hidden.
Restore only touches windows with an ownership token, and the token is kept
until a scan sees the window back on a display. A short settling interval covers minimize/restore transitions
that arrive out of order.

While the owning process lives, restoration works through the AX object.
After a helper restart it requires PID + process instance + bundle + `AXIdentifier`,
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

The `xmonad` command is the compiled config itself, as upstream's is: control
arguments are handled before any engine starts, so `xmonad status` works
without a running helper and `xmonad --recompile` works from the binary it is
about to replace.

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
