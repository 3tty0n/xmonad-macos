# Design

Haskell owns policy (`StackSet`, `LayoutClass`, `xmonad.hs`). The signed
Swift app owns AX, AppKit, and the event tap. They talk NDJSON over a pipe.
There is no XQuartz, no X11 proxy, and no private CGS/SLS API.

```text
xmonad.hs  →  xmonad-engine (GHC)  ⇄ NDJSON  ⇄  XMonadMac.app  →  native windows
```

The helper stays signed while you recompile the engine. Layout does not live
in Swift.

## Windows

A `Window` is a per-session `Word64`, not an XID or `CGWindowID`. AX elements
are re-identified with `CFEqual`; process identity uses
`NSRunningApplication.launchDate` or the BSD start time.

Tiled: `AXStandardWindow` (and Emacs frames listed in `AXWindows` as
`AXTextField`) with settable position and size. Dialogs and floating panels
are floated. Sheets, popovers, native full-screen, user-minimized windows,
and hidden apps are left alone.

On-screen matching is PID + frame against public CG layers. Chrome withholds
that list, so those windows are admitted from AX. emacs-mac chrome can shift
AX vs CG by a titlebar; matching allows that slop.

## Virtual workspaces

Workspaces are xmonad tags, **not** macOS Spaces. Native Spaces cannot host
them: `SLSMoveWindowsToManagedSpace` ignores another process's window, and
this port does not inject into Dock.app.

Hiding a window parks it off-screen. Apps that clamp (Finder) are minimized
instead. `Full` hides nothing. A native Space switch bumps `epoch` and rebuilds
window membership; each workspace keeps the layout the user chose. Tiling
pauses while a native full-screen window is frontmost.

## Plans, focus, recovery

Plans must match `generation` and `epoch`. Focus is requested only from a
key binding, with an action id and a short deadline; the helper will not
steal a window the user already raised.

Hides are journaled before mutation. Restore only touches WM-owned windows.
After a helper restart, workspace and float state come from `session.json`
fingerprints; ambiguous matches are left unmatched.

AX never runs on the event-tap thread. Emergency stop and `xmonad recover`
do not go through Haskell.

## Recompile

`xmonad --recompile` (and M-q) builds against Application Support
`build-kit` and swaps the engine only after validation. A failed compile
leaves the running engine in place. `xmonad autostart on` is a LaunchAgent
for the signed `.app`.
