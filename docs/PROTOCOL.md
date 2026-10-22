# NDJSON protocol v1

One UTF-8 JSON object per line on stdin/stdout. Diagnostics go to stderr.
Haskell rejects lines over 1 MiB.

## Handshake

Engine first:

```json
{"type":"configure","protocol":1,"keys":[{"mask":8,"sym":106}],"mouseMask":8,"mouse":[{"mask":8,"button":1,"action":"move"},{"mask":8,"button":3,"action":"resize"}],"borderWidth":1,"borderColor":"#ff0000","normalBorderColor":"#dddddd","focusFollowsMouse":true}
```

`mask`: Shift=1, Control=4, Option=8, Command=64. `sym` is a keysym mapped
to a physical key. Mask 0 is rejected. `borderWidth` 0 turns overlays off.

## Helper → engine

`pointerFocus` — pointer entered a window (`focusFollowsMouse` or
`MouseRaise`). `ack` — a plan's focus request observed, taken over, or
expired. Snapshot:

```json
{"type":"snapshot","generation":3,"epoch":1,"screens":[{"display":10,"usable":{"x":0,"y":24,"width":1600,"height":1000}}],"windows":[{"wid":1,"pid":123,"app":"Terminal","bundle":"com.apple.Terminal","titleText":"shell","onDisplay":10,"frame":{"x":0,"y":24,"width":800,"height":1000},"minimized":false,"ownedHidden":false,"subrole":"AXStandardWindow"}],"focused":1,"restore":null}
```

`ownedHidden` is true for windows this WM parked or minimized, so their
**virtual** workspace is kept. Missing `subrole` is `AXStandardWindow`.

```json
{"type":"key","mask":8,"sym":106}
{"type":"key","mask":0,"sym":97,"grabbed":true}
{"type":"mouseFloat","wid":1}
```

`grabbed` answers a `grab`; any key is allowed (`sym=0` if unknown).
An ordinary key event clears any pending grab.

## Engine → helper

```json
{"type":"plan","generation":3,"epoch":1,"frames":[{"wid":1,"frame":{"x":4,"y":28,"width":1592,"height":992}}],"hide":[],"focus":1,"action":7,"focusForMs":400,"workspace":"1","layout":"Tall","screen":10,"checkpoint":{},"borders":[{"wid":1,"width":0}]}
```

`frames` / `hide` are disjoint. `focus` + `action` only for explicit
intent. `epoch` bumps on a native Space switch; both `generation` and
`epoch` must match or the plan is dropped.

`borders` overrides widths for this plan only; 0 disables a border, omitted
windows use the handshake default. Entries for unplaced windows are ignored,
not rejected. Older helpers ignore this field.

`floating`, when present, lists the placed windows that are floating, bottom
to top. After focusing a tiled window the helper re-raises the floats of the
same app, in that order. Older helpers ignore it; older engines omit it and
nothing is raised.

`status`, when present, is menu bar text a logHook rendered
(`macMenuBarPP`); without it the helper builds its own workspace row.

`checkpoint` is stored by the helper and returned in `restore`.
`savedExtensions` contains persistent (type, `show`) pairs; absent means no
extensible state. Helper restarts remap handles using public fingerprints.

## Control

`ping`/`exit` helper→engine; `pong`/`command`/`movePointer` engine→helper.
Commands: `close`, `reload`, `recompile`, `pause`, `quit`, `grab`. JSON is
never executed as a shell command.

`movePointer` carries `bounds` (clip box) and `focus` (window rectangle).
The helper uses `CGWarpMouseCursorPosition` only outside `focus` and without
an active mod-drag. Older helpers reject this message; install the matching app.

`grab` captures one stroke for a submap. Nested submaps reissue it. It expires
after 5 s, on pause or on `configure`; emergency stop is never captured.
Escape or an unbound stroke cancels in the engine; there is no `ungrab`.
