# NDJSON protocol v1

The helper talks to its own child process over stdin and stdout: one JSON
object per line, UTF-8, newline-terminated. Engine diagnostics go to stderr;
printing to stdout is forbidden.

Haskell rejects input lines over 1 MiB, and the native reader rejects an
unparsed buffer over 2 MiB. The Haskell limit is applied after reading the
line, so it is a sanity bound rather than a strict bounded-memory parser — the
peer is the helper's own child.

## Handshake

The engine emits `configure` first:

```json
{"type":"configure","protocol":1,"keys":[{"mask":8,"sym":106}],"mouseMask":8,"mouse":[{"mask":8,"button":1,"action":"move"},{"mask":8,"button":3,"action":"resize"}],"borderWidth":1,"borderColor":"#ff0000","normalBorderColor":"#dddddd","focusFollowsMouse":true}
```

`mask` is the OR of Shift=1, Control=4, Option=8, Command=64. `sym` is a
restricted set of X keysym numbers that the helper maps to physical key
positions. `mouse` lists modifier+button gestures: `move`, `resize`, or
`raise`. `mouseMask` is still sent as `modMask` for older helpers. A binding
with mask 0 is rejected. `borderWidth`, `borderColor` and `normalBorderColor`
describe the overlays traced around focused and other visible windows; a width
of 0 turns them off. `focusFollowsMouse` decides whether the helper reports
the window under the pointer at all.

## Helper → engine

`{"type":"pointerFocus","wid":N}` says the pointer moved onto a window, and is
sent only while `focusFollowsMouse` is on, or when a `raise` mouse binding
fires. Policy decides what to do with it.

`{"type":"ack","action":7,"focused":1,"expired":false}` acknowledges a plan's
focus request. `expired` is true when `focusForMs` elapsed without the
requested window taking AX focus; a dropped plan never consumes the id.

Snapshot of the observed world:

```json
{"type":"snapshot","generation":3,"epoch":1,"screens":[{"display":10,"usable":{"x":0,"y":24,"width":1600,"height":1000}}],"windows":[{"wid":1,"pid":123,"app":"Terminal","bundle":"com.apple.Terminal","titleText":"shell","onDisplay":10,"frame":{"x":0,"y":24,"width":800,"height":1000},"minimized":false,"ownedHidden":false,"subrole":"AXStandardWindow"}],"focused":1,"restore":null}
```

- `wid` — the helper's per-session identifier.
- `screens` — usable logical-point rectangles.
- `focused` — `null` means no managed window is confirmed to hold focus.
- `ownedHidden` — true for windows the WM hid, by parking them off-screen or,
  where an app clamps that or (Finder) ignores the park, by minimizing them;
  they stay listed so their logical workspace is not lost.
- `subrole` — the AX subrole. Dialogs and floating panels are floated on
  manage; a missing field is treated as `AXStandardWindow`.

Key press, and the start of a mod+mouse drag:

```json
{"type":"key","mask":8,"sym":106}
{"type":"mouseFloat","wid":1}
```

For a drag, the helper identifies the target AX window by public hit-test and
asks Haskell to float it. The drag geometry is then applied on the AX queue,
and the next snapshot synchronizes the relative float rectangle.

## Engine → helper

A placement plan:

```json
{"type":"plan","generation":3,"epoch":1,"frames":[{"wid":1,"frame":{"x":4,"y":28,"width":1592,"height":992}}],"hide":[],"focus":1,"action":7,"focusForMs":400,"workspace":"1","layout":"Tall","screen":10,"checkpoint":{}}
```

- `frames` — windows to show and place, in stacking order, focused last.
- `hide` — managed windows to hide for this layout or workspace, by parking
  them past the edge of the displays, or by minimizing Finder. A window may
  never appear in both lists.
- `workspaces` — one entry per workspace in config order, with `tag`,
  `windows`, `current` and `visible`, for the menu bar and external bars.
- `focus` — set only for explicit user-driven focus intent.
- `action` — monotonic id for that intent. The helper acknowledges with
  `{"type":"ack","action":N,"focused":1}` (or `"expired":true` if the
  `focusForMs` deadline passed without observing the requested window). A
  dropped plan does not consume the id; the next matching plan resends it.
  AX still naming the window that had focus when the action started is not a
  takeover. A later ack with a different `focused` window is the user taking
  over, and the engine stops requesting the old one. An expired ack does not
  move policy focus back to a stale observation.
- `screen` — the display the current screen sits on. The helper moves the
  pointer there when it is on another display, so a screen change is visible
  even when the workspace there holds no window.
- Windows ignored by `manageHook` appear in neither list.

`generation` is the observation generation; `epoch` is the policy generation,
bumped by native Space switches. A plan is applied only when both match, and
the native store re-checks after queueing so a plan that went stale in the
queue is dropped.

`checkpoint` is produced by Haskell and stored by the helper as opaque JSON,
then handed back in the `restore` field of the first snapshot after an engine
reload. Across a helper restart the helper rewrites window ids by matching
public fingerprints (bundle + AXIdentifier, or title and frame) and sets
`savedEpoch` to the new session. It holds `savedVersion`, `savedEpoch`, each
workspace's layout `show` representation, window order, focus, display
affinity (including currently disconnected displays), and float rectangles.
If a layout type change makes it unreadable, the new config's layout is used.

## Control messages

```json
{"type":"ping"}
{"type":"pong"}
{"type":"command","name":"close","wid":1}
{"type":"command","name":"reload"}
{"type":"command","name":"recompile"}
{"type":"command","name":"pause"}
{"type":"command","name":"quit"}
{"type":"exit"}
```

`ping` and `exit` go helper → engine; `pong` and `command` go engine → helper.

- `recompile` — the helper runs the installed engine with `--recompile`
  against the build kit and swaps the engine only after validation succeeds.
- `reload` — restart the already-compiled engine, no build.
- `close` — press the Close button of a known handle; unknown handles are
  ignored.

No received JSON string is ever executed as a shell command. That is only what
your config's `spawn` does.
