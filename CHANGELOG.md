# Changelog

Written when a version tag is cut; between tags, see the git log.

## 1.2.0 - 2026-10-10

- Popups stop stealing focus back: right-click menus and Chrome extension
  popups stay open, a newly focused Settings-style float is not hidden behind
  older windows, and hover targeting no longer clicks through a menu to its
  owner.
- A window the helper briefly fails to observe keeps its workspace, stack
  position and floating state instead of being re-adopted onto one workspace.
  The same holds across a display wake, and a window from an app whose process
  start time cannot be read is tiled normally.
- Mod-dragging a floating window repaints its focus overlay as it moves, and a
  size an app clamps is retried with a per-window backoff instead of every two
  seconds.
- Mosaic: resizing uses the tiled window's index when floats are present; the
  shipped multiplier is `103/100`; old saved multipliers and distorted shares
  are repaired once per workspace without resetting the arrangement; `M-C-m`
  equalizes Mosaic shares explicitly.
- `Actions.GroupNavigation`, `Actions.CycleRecentWS`, `Actions.DynamicWorkspaces`
  and `Actions.UpdatePointer`, the `BinarySpacePartition`, `Mosaic` and
  `ResizableThreeCol` layouts, and `Util.Loggers` / `Util.WorkspaceCompare`
  are ported, with `docs/COMPATIBILITY.md` listing what is absent.

## 1.1.0 - 2026-09-29

- Ported more xmonad-contrib modules: the `BinarySpacePartition`, `Mosaic` and
  `ResizableThreeCol` layouts, and the `Navigation2D`, `UpdatePointer`,
  `GroupNavigation`, `CycleRecentWS`, `DynamicWorkspaces`, `Loggers`,
  `WorkspaceCompare` actions and helpers, with the `WSType` predicates in
  `CycleWS` (see `docs/COMPATIBILITY.md` for what is not ported).
- `make build` compiles `~/.xmonad/xmonad.hs` when one exists; the shipped
  config lives in `example/xmonad.hs`.
- Focus follows the mouse, and the pointer follows the focused window.
- Fixed moving a window to another workspace dragging the map there with it.
- Fixed a display wake piling every window onto one workspace.

## 1.0.0

This is the first release of xmonad-macos.
