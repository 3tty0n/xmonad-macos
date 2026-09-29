# Changelog

Written when a version tag is cut; between tags, see the git log.

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
