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
| `Layout.ResizableThreeCol` | Both variants; `Shrink` / `Expand` and `MirrorResize` from `ResizableTile` |
| `Layout.Column` / `Spiral` / `Dwindle` / `OneBig` | |
| `Layout.Mosaic` | `mosaic`, `Aspect`, `changeMaster`, `changeFocused`; adds `SetMosaicResizeFactor` and `MosaicWeights` for factor override and explicit/one-time share repair; no `MosaicAlt` |
| `Layout.MultiColumns` / `StackTile` / `Dishes` | |
| `Layout.CenteredIfSingle` / `Roledex` / `ToggleLayouts` | |
| `Layout.IfMax` / `Gaps` / `PerScreen` / `Named` | |
| `Layout.LimitWindows` | No `limitSelect` |
| `Layout.Renamed` / `Reflect` / `PerWorkspace` | |
| `Layout.TwoPane` / `Accordion` / `Spacing` | |
| `Layout.Magnifier` | Magnified window is listed last, not first |
| `Layout.BoringWindows` | |
| `Layout.Maximize` | `maximize`, `maximizeWithPadding`, `maximizeRestore`; maximized window is listed last |
| `Layout.Minimize` / `Actions.Minimize` | Logical minimize in `ExtensibleState` (not the Dock), hidden like any unlaid window; cooperates with `BoringWindows`; not persisted across restart |
| `Layout.BinarySpacePartition` | `emptyBSP` and tree/resize/selection messages; no `SetGeometry` mouse resize or selection highlight |
| `Layout.MultiToggle` / `MultiToggle.Instances` | `REFLECTX` / `REFLECTY` live in `Layout.Reflect` |
| `Layout.NoBorders` | No `OnlyLayoutFloatBelow` / `OtherIndicated`, no deprecated `borderEventHook` |
| `Actions.CycleWS` | `WSType`, `doTo`, `findWorkspace`; no `nextScreen` / `swapNextScreen`; use `PhysicalScreens` or `OnScreen` |
| `Actions.CycleRecentWS` | `recentWS`, `unView`, toggle functions; no held-modifier `cycleRecentWS` / `cycleRecentNonEmptyWS` / `cycleWindowSets` |
| `Actions.DynamicWorkspaces` | Add / append / remove / rename workspaces and the workspace index map. `withWorkspace`, `selectWorkspace`, `renameWorkspace`, `addWorkspacePrompt` and `appendWorkspacePrompt` are not ported (no Prompt package) |
| `Actions.Navigation2D` | Line/center/side strategies, window/screen navigation and swaps, `switchLayer`; observed rectangles, no layout modifier. No unmapped-window rectangles or Prompt integration |
| `Actions.GroupNavigation` | Query-based navigation and `historyHook`; history persists through `ExtensibleState`, without `deepseq` |
| `Actions.UpdatePointer` | `updatePointer refPos ratio` in `logHook`; observed geometry, no warp inside the focused window or during mod-drag. Requires the matching helper |
| `Util.WorkspaceCompare` | Index/tag/physical-position sorts; no `ScreenComparator` or physical-rule variants |
| `Util.Loggers` | Window/display/system loggers and formatting; no `logTitles'`, `TitlesFormat`, `aumixVolume`, `battery`, `loadAvg`. Use `logCmd`; `Align` lives in `Util.Types` |
| `Actions.CycleWindows` | No `cycleRecentWindows` |
| `Actions.WithAll` / `SinkAll` / `RotSlaves` | |
| `Actions.SwapWorkspaces` / `DwmPromote` / `Promote` | |
| `Actions.PhysicalScreens` / `OnScreen` / `FocusNth` | |
| `Actions.CopyWindow` | No `copiesPP` |
| `Actions.FindEmptyWorkspace` / `FloatKeys` | |
| `Actions.SpawnOn` | `spawnOn`, `spawnHere`, `spawnAndDo`, `manageSpawn`, `manageSpawnWithGC`; no Prompt helpers. Matches the window pid against the spawned shell and its descendants (read with `ps`), so apps started through `open` or already running never match; add `manageSpawn` to `manageHook` |
| `Actions.WindowGo` | No `$BROWSER` / `$EDITOR` |
| `Actions.Submap` | No `visualSubmap`; the grab lapses after 5 s |
| `Hooks.ManageHelpers` / `InsertPosition` | No X11 property queries |
| `Hooks.WorkspaceHistory` | History survives a restart |
| `Hooks.StatusBar.PP` | No `ppUrgent`; `ppOutput` defaults to stderr. Supports loggers and re-exports index/tag sorts |
| `Hooks.StatusBar` | `withSB`, `statusBarGeneric`, `statusBarPipe`; adds `statusBarFile`, `statusBarSpawn`, `macMenuBarPP`. No `statusBarProp` / `withEasySB` / `sbCleanupHook` (X11 properties, struts) |
| `Hooks.DynamicLog` | Re-exports `StatusBar.PP` plus `dynamicLog`; no xmobar/dzen launchers |
| `Util.EZConfig` / `Types` / `CustomKeys` | `checkKeymap` logs to stderr, not xmessage |
| `Util.SpawnOnce` | In-process, not persisted |
| `Util.ExtensibleState` | X monad only; `PersistentExtension` rides in the checkpoint |
| `Util.Run` | No dzen / `runInTerm` |
| `Util.NamedScratchpad` | `NSP` is created on demand and shows in the status list; a checkpoint restore drops it |

Not ported: Tabbed, Decoration, Prompt, EWMH, `Layout.WindowNavigation`.

Use `Navigation2D` bindings without importing `WindowNavigation` or adding
`windowNavigation`: this port uses observed window frames. Named scratchpad
exclusives, dynamic scratchpads and `nsHideOnFocusLoss` are unsupported.
Held-modifier cycling is unavailable because modifier releases are not reported.

`NoBorders` / `withBorder` require a matching helper; older helpers ignore
per-window widths and use the configured default.

## Runtime

| API | Status |
|---|---|
| `logHook` | Run before every plan, i.e. after each state change |
| `manageHook` | `composeAll`, `doFloat`, `doShift`, `doIgnore`; dialogs float |
| `className` / `bundleId` / `title` / `subrole` | App name / bundle / `AXTitle` / AX subrole |
| `isDialog` | AX dialog and floating-panel subroles |
| `spawn` / `kill` | Shell command / native Close |
| `keys` / `additionalKeysP` | Sequences (`"M-x a"`) become submaps; unsupported keys and a key that is also a prefix are hard errors |
| `mod1Mask` / `mod4Mask` | Option / Command |
| `mouseBindings` | `move` / `resize` / `raise` |
| Multi-screen | One virtual workspace per display; hotplug by display ID |
| Borders / `focusFollowsMouse` | Overlay; on by default |
| Native tabs, Stage Manager, Spaces | Not implemented |

X11 `Display` / atoms / `withDisplay` are not faked.
