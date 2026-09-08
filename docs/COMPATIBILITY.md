# Compatibility

"Implemented" means the source implements it. Where a row needs a caveat, the
caveat is the point of the row.

## Core API

| API | Status |
|---|---|
| `import XMonad`, `xmonad $ def { ... }` | Works for the fields listed below |
| `XMonad.StackSet` | Upstream `view` / `greedyView` / `focus` / `swap` / `shift` / `float` / `sink` |
| `LayoutClass` | `runLayout`, `doLayout`, `pureLayout`, `emptyLayout`, `handleMessage`, `pureMessage`, `description` |
| `Tall` / `Mirror` / `Full` / `Choose` / `(\|\|\|)` | Upstream algorithms, made portable |
| `ThreeCol` / `ThreeColMid` / `Circle` | Ported from xmonad-contrib. `XMonad` re-exports them, and `XMonad.Layout.ThreeColumns` / `XMonad.Layout.Circle` exist so contrib configs compile unchanged |
| `Shrink` / `Expand` / `IncMasterN` / `NextLayout` / `JumpToLayout` | Handled as layout messages |
| Custom pure layouts | Supported at source level, using portable types only |
| Custom stateful layouts | Limited to what the `X` monad exposes; no X11 calls |
| `Rectangle` | Signed `Int` logical points, not the X11 `CShort`/`CUShort` ABI |
| `Window` | A per-session `Word64` handle, not an XID or `CGWindowID` |

Workspaces are XMonadMac's own, unrelated to macOS Desktops: a hidden window is
parked off-screen. `Full` stacks every window at the full frame and raises the
focused one, so switching to it hides nothing at all.

## Hooks and matching

| API | Status |
|---|---|
| `manageHook` | `composeAll`, comparisons, `doFloat`, `doShift`, `doIgnore` |
| `className` | The app's macOS display name, not `WM_CLASS` |
| `resource` / `appName` / `bundleId` | Bundle identifier, not an X11 resource name |
| `title` | The `AXTitle` string |
| `startupHook` / `logHook` | Whatever the `X` monad offers; must not write to stdout |
| `spawn` | Runs your shell command; logs to stderr and reaps children asynchronously |
| `kill` | Presses the native Close button; never `kill(2)` |
| `spacing` | A plain inset, not the full contrib `Spacing` API |

## Input

| API | Status |
|---|---|
| `keys` / `additionalKeys(P)` / `removeKeys(P)` | Single stroke only; unsupported keys are a hard error |
| `mod1Mask` / `mod4Mask` | Option / Command; Control and Shift also work |
| Other X modifier masks | The constants exist, but key validation rejects them |
| Built-in mouse drag | `modMask` + left to move, right to resize; feeds `W.float` |
| Configurable `mouseBindings` | Not implemented — the two built-in gestures are fixed |
| Keyboard-layout character resolution, chords | Not implemented; bindings are physical key positions |

## Windows and displays

| Feature | Status |
|---|---|
| Workspaces across displays | Uses `W.view` / `greedyView` with stable display IDs |
| State across a config reload | Workspace, layout, and float state survive inside one helper |
| State across a helper restart | Not implemented; only the ownership journal persists |
| Native tabs, tab grouping, Stage Manager, moving windows between Spaces | Not implemented |
| `borderWidth`, `borderColor`, `focusFollowsMouse` | Not implemented; the fields do not exist |

## Not supported, deliberately

| Feature | Why |
|---|---|
| X11 `Display` / `Atom` / root window / `Event` / `withDisplay` | No fake handles are offered |
| EWMH, docks, xmobar, X11 property hooks | No macOS equivalent contract is defined yet |
| Adding `xmonad-contrib` as a dependency | It targets a different package; modules must be ported one at a time |

Unsupported APIs fail to compile rather than existing as silent no-ops. An
`ewmh` that accepted its argument and did nothing would read as support.

## Porting an existing config

Copy it to a new file and remove X11-specific imports and fields first. Future
contrib support starts with pure layouts such as `ThreeCol` and `Grid`, each
with geometry, message, and serialization tests. Modifiers that read X11
properties cannot be ported until their native equivalent is defined.
