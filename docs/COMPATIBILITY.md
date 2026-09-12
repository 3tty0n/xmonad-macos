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
| `idHook` / `(<+>)` / `doFloat` / `killWindow` / `float` | Portable equivalents of the upstream operations |
| `Shrink` / `Expand` / `IncMasterN` / `NextLayout` / `JumpToLayout` | Handled as layout messages |
| Custom pure layouts | Supported at source level, using portable types only |
| Custom stateful layouts | Limited to what the `X` monad exposes; no X11 calls |
| `Rectangle` | Signed `Int` logical points, not the X11 `CShort`/`CUShort` ABI |
| `Window` | A per-session `Word64` handle, not an XID or `CGWindowID` |

## Ported xmonad-contrib modules

The xmonad-contrib package cannot be a dependency: it is written against the
X11 runtime this port replaces. Individual modules whose logic is pure
`StackSet` or geometry are ported under their own module paths, so a config
importing them compiles unchanged.

| Module | Ported |
|---|---|
| `XMonad.Layout.LayoutModifier` | `LayoutModifier`, `ModifiedLayout` |
| `XMonad.Layout.LayoutCombinators` | `(\|\|\|)`, `JumpToLayout`; not Combo/DragPane |
| `XMonad.Layout.ThreeColumns` | `ThreeCol`, `ThreeColMid` |
| `XMonad.Layout.Circle` | `Circle`, plus Shrink/Expand resizing |
| `XMonad.Layout.Grid` | `Grid`, `GridRatio` |
| `XMonad.Layout.Simplest` | `Simplest` |
| `XMonad.Layout.SimplestFloat` | Snapshot frames instead of X11 attributes |
| `XMonad.Layout.ResizableTile` | `ResizableTall`, `MirrorShrink`, `MirrorExpand` |
| `XMonad.Layout.Column` | `Column` |
| `XMonad.Layout.Spiral` | `spiral`, `spiralWithDir` |
| `XMonad.Layout.Dwindle` | `Dwindle`, `Spiral`, `Squeeze` |
| `XMonad.Layout.OneBig` | `OneBig` |
| `XMonad.Layout.MultiColumns` | `multiCol` |
| `XMonad.Layout.StackTile` | `StackTile` |
| `XMonad.Layout.Dishes` | `Dishes` |
| `XMonad.Layout.CenteredIfSingle` | `centeredIfSingle` |
| `XMonad.Layout.Roledex` | `Roledex` |
| `XMonad.Layout.ToggleLayouts` | `toggleLayouts`, `ToggleLayout` |
| `XMonad.Layout.IfMax` | `ifMax` |
| `XMonad.Layout.LimitWindows` | `limitWindows`, `limitSlice`; not `limitSelect` |
| `XMonad.Layout.Gaps` | `gaps`, `GapMessage` |
| `XMonad.Layout.PerScreen` | `ifWider` |
| `XMonad.Layout.Named` | `named` (re-export of `renamed [Replace n]`) |
| `XMonad.Actions.CycleWS` | `nextWS`, `prevWS`, `shiftToNext`, `shiftToPrev`, `toggleWS`, `moveTo`, `shiftTo`; not the predicate/`WSType` API |
| `XMonad.Actions.CycleWindows` | rotations; not `cycleRecentWindows` |
| `XMonad.Actions.WithAll` / `SinkAll` | `withAll`, `killAll`, `sinkAll` |
| `XMonad.Layout.Renamed` | `renamed`, `Replace`/`Prepend`/`Append`/`CutLeft`/`CutRight` |
| `XMonad.Layout.Reflect` | `reflectHoriz`, `reflectVert` |
| `XMonad.Layout.PerWorkspace` | `onWorkspace`, `onWorkspaces` |
| `XMonad.Layout.TwoPane` | `TwoPane` |
| `XMonad.Layout.Accordion` | `Accordion` |
| `XMonad.Actions.RotSlaves` | `rotSlavesUp/Down`, `rotAllUp/Down`, the pure `rotSlaves'`/`rotAll'` |
| `XMonad.Actions.SwapWorkspaces` | `swapWithCurrent`, `swapWith`, `swapWorkspaces` |
| `XMonad.Actions.DwmPromote` / `Promote` | `dwmpromote`, `promote` |
| `XMonad.Actions.PhysicalScreens` | `PhysicalScreen`, `getScreen`, `viewScreen`, `sendToScreen` |
| `XMonad.Actions.CopyWindow` | `copy`, `kill1`; not `copiesPP` |
| `XMonad.Actions.FocusNth` | `focusNth`, `swapNth` |
| `XMonad.Actions.OnScreen` | `viewOnScreen` and friends |
| `XMonad.Actions.FindEmptyWorkspace` | `viewEmptyWorkspace`, `tagToEmptyWorkspace` |
| `XMonad.Actions.WindowGo` | `runOrRaise`, `raise`; not `$BROWSER`/`$EDITOR` |
| `XMonad.Actions.FloatKeys` | pixel move/resize via snapshot frames, not X11 |
| `XMonad.Hooks.ManageHelpers` | `composeOne`, `-?>`, `doRectFloat`, `doCenterFloat`, `doFullFloat`, `doSink`, `isDialog`; not the X11 property queries |
| `XMonad.Hooks.InsertPosition` | `insertPosition` |
| `XMonad.Util.EZConfig` | `additionalKeysP`, `removeKeysP`, key parser |
| `XMonad.Util.Types` | `Direction1D`, `Direction2D` |
| `XMonad.Util.SpawnOnce` | `spawnOnce` (in-process; not a persisted extension) |
| `XMonad.Util.CustomKeys` | `customKeys` |
| `XMonad.Util.Run` | `safeSpawn`, `safeSpawnProg`; not dzen/`runInTerm` |
| `XMonad.Layout.Spacing` | `spacing` |

Anything drawing with X11 (`Tabbed`, `Decoration`, `Prompt`, `NoBorders`) or
reaching for `Display`, atoms, EWMH or `ExtensibleState` is out of reach
without a runtime that does not exist here.

Workspaces are XMonadMac's own, unrelated to macOS Desktops: a hidden window is
parked off-screen. `Full` stacks every window at the full frame and raises the
focused one, so switching to it hides nothing at all.

## Hooks and matching

| API | Status |
|---|---|
| `idHook` / `(<+>)` | Identity and compose, as upstream |
| `manageHook` | `composeAll`, comparisons, `doFloat`, `doShift`, `doIgnore`; dialogs float by default |
| `className` | The app's macOS display name, not `WM_CLASS` |
| `resource` / `appName` / `bundleId` | Bundle identifier, not an X11 resource name |
| `title` | The `AXTitle` string |
| `subrole` | The AX subrole string (`AXStandardWindow`, `AXDialog`, …) |
| `isDialog` | AX dialog and floating-panel subroles, not `_NET_WM_WINDOW_TYPE` |
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
| Built-in mouse drag | Default `mouseBindings`: `modMask` + left to move, right to resize; feeds `W.float` |
| Configurable `mouseBindings` | Implemented: `move`, `resize`, `raise`; compose with `additionalMouseBindings` |
| Keyboard-layout character resolution, chords | Not implemented; bindings are physical key positions |

## Windows and displays

| Feature | Status |
|---|---|
| Workspaces across displays | Uses `W.view` / `greedyView` with stable display IDs |
| State across a config reload | Workspace, layout, and float state survive inside one helper |
| State across a helper restart | Restored by matching public fingerprints (bundle + `AXIdentifier`, or unique title and frame); ambiguous windows are left unmatched |
| Native tabs, tab grouping, Stage Manager, moving windows between Spaces | Not implemented |
| Dialogs and floating panels | Floated at their observed size when AX position is settable; sheets and popovers are not managed |
| `borderWidth`, `focusedBorderColor` | A click-through overlay at the public overlay window level, raised on every scan; another app's window cannot be given a real border |
| `normalBorderColor` | Unfocused managed windows get the same overlay in this colour, clipped so it does not cover the focused window |
| `focusFollowsMouse` | Implemented; on by default, as upstream |

## Displays

| API | Status |
|---|---|
| Multiple screens | Supported: one workspace per display, per-display layout |
| `screenWorkspace`, `M-w`/`M-e`/`M-r` | Work as upstream |
| Hotplug | Workspaces survive unplug and return on replug by display ID, including a remembered assignment while the display is gone |
| Xinerama-specific config | Not applicable; screens come from `NSScreen` |

## Not supported, deliberately

| Feature | Why |
|---|---|
| X11 `Display` / `Atom` / root window / `Event` / `withDisplay` | No fake handles are offered |
| EWMH, docks, xmobar, X11 property hooks | No macOS equivalent contract is defined yet |
| Adding `xmonad-contrib` as a dependency | It targets a different package; modules must be ported one at a time |

Unsupported APIs fail to compile rather than existing as silent no-ops. An
`ewmh` that accepted its argument and did nothing would read as support.

## Porting an existing config

Copy it to a new file and remove X11-specific imports and fields first.
Modifiers that read X11 properties cannot be ported until their native
equivalent is defined.
