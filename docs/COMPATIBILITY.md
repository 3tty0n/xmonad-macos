# Compatibility

Unsupported APIs fail to compile; they are not silent no-ops.

Workspaces are **virtual xmonad tags**, not macOS Spaces.

## Core

| API | Status |
|---|---|
| `import XMonad`, `xmonad $ def { ... }` | Fields listed here |
| `XMonad.StackSet` | `view` / `greedyView` / `focus` / `swap` / `shift` / `float` / `sink` |
| `LayoutClass` | `runLayout`, `handleMessage`, `description`, … |
| `Tall` / `Mirror` / `Full` / `Choose` / `(\|\|\|)` | Portable |
| `doFloat` / `killWindow` / `float` | Portable |
| `Shrink` / `Expand` / `IncMasterN` / `NextLayout` / `JumpToLayout` | Layout messages |
| Custom pure layouts | Portable types only |
| `Rectangle` / `Window` | Signed logical points / per-session `Word64` |

## Contrib (ported modules, not the package)

xmonad-contrib cannot be a dependency. These modules are reimplemented under
the same names.

| Module | Notes |
|---|---|
| `Layout.LayoutModifier` / `LayoutCombinators` | No Combo/DragPane |
| `Layout.ThreeColumns` / `Circle` / `Grid` / `Simplest` | |
| `Layout.SimplestFloat` / `ResizableTile` | Snapshot frames, not X11 |
| `Layout.Column` / `Spiral` / `Dwindle` / `OneBig` | |
| `Layout.MultiColumns` / `StackTile` / `Dishes` | |
| `Layout.CenteredIfSingle` / `Roledex` / `ToggleLayouts` | |
| `Layout.IfMax` / `Gaps` / `PerScreen` / `Named` | |
| `Layout.LimitWindows` | No `limitSelect` |
| `Layout.Renamed` / `Reflect` / `PerWorkspace` | |
| `Layout.TwoPane` / `Accordion` / `Spacing` | |
| `Layout.Magnifier` | Magnified window is listed last, not first |
| `Layout.BoringWindows` | |
| `Layout.MultiToggle` / `MultiToggle.Instances` | `REFLECTX` / `REFLECTY` live in `Layout.Reflect` |
| `Layout.NoBorders` | No `OnlyLayoutFloatBelow` / `OtherIndicated`, no deprecated `borderEventHook` |
| `Actions.CycleWS` | No predicate / `WSType` API |
| `Actions.CycleWindows` | No `cycleRecentWindows` |
| `Actions.WithAll` / `SinkAll` / `RotSlaves` | |
| `Actions.SwapWorkspaces` / `DwmPromote` / `Promote` | |
| `Actions.PhysicalScreens` / `OnScreen` / `FocusNth` | |
| `Actions.CopyWindow` | No `copiesPP` |
| `Actions.FindEmptyWorkspace` / `FloatKeys` | |
| `Actions.WindowGo` | No `$BROWSER` / `$EDITOR` |
| `Hooks.ManageHelpers` / `InsertPosition` | No X11 property queries |
| `Hooks.WorkspaceHistory` | History survives a restart |
| `Hooks.StatusBar.PP` | No `ppUrgent` (no urgency hints); default `ppOutput` is stderr, since stdout is the protocol |
| `Hooks.StatusBar` | `withSB`, `statusBarGeneric`, `statusBarPipe`; adds `statusBarFile`, `statusBarSpawn`, `macMenuBarPP`. No `statusBarProp` / `withEasySB` / `sbCleanupHook` (X11 properties, struts) |
| `Hooks.DynamicLog` | Re-exports `StatusBar.PP` plus `dynamicLog`; no xmobar/dzen launchers |
| `Util.EZConfig` / `Types` / `CustomKeys` | |
| `Util.SpawnOnce` | In-process, not persisted |
| `Util.ExtensibleState` | X monad only; `PersistentExtension` rides in the checkpoint |
| `Util.Run` | No dzen / `runInTerm` |
| `Util.NamedScratchpad` | `NSP` is created on demand and shows in the status list; a checkpoint restore drops it |

Not ported: Tabbed, Decoration, Prompt, EWMH.
Named scratchpad exclusives, dynamic scratchpads and `nsHideOnFocusLoss` are
not provided. `cycleRecentWindows` needs a grab that holds until the modifier
is released, which the helper does not report.

A layout's border widths reach the helper in the plan, so `NoBorders` and
`withBorder` need a helper built alongside the engine. An older installed app
ignores the field and draws the width from the config for every window.

## Runtime

| API | Status |
|---|---|
| `logHook` | Run before every plan, i.e. after each state change |
| `manageHook` | `composeAll`, `doFloat`, `doShift`, `doIgnore`; dialogs float |
| `className` / `bundleId` / `title` / `subrole` | App name / bundle / `AXTitle` / AX subrole |
| `isDialog` | AX dialog and floating-panel subroles |
| `spawn` / `kill` | Shell command / native Close |
| `keys` / `additionalKeysP` | Single stroke; unsupported keys are a hard error |
| `mod1Mask` / `mod4Mask` | Option / Command |
| `mouseBindings` | `move` / `resize` / `raise` |
| Multi-screen | One virtual workspace per display; hotplug by display ID |
| Borders / `focusFollowsMouse` | Overlay; on by default |
| Native tabs, Stage Manager, Spaces | Not implemented |

X11 `Display` / atoms / `withDisplay` are not faked.
