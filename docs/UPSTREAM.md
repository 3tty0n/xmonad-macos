# Upstream

- Base: [xmonad](https://github.com/xmonad/xmonad), commit
  `a9a8b5c1b91b63b0836f5810634c9b28ec0af788` (pinned 2026-09-07).
- `StackSet.hs`, `Layout.hs`, `Core.hs` and ported contrib modules are
  BSD-3-Clause adaptations. Attribution is retained in source headers and
  `LICENSE`. The xmonad-contrib package is not a dependency.
- macOS uses public [AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement),
  [NSScreen.visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe)
  and [CGEvent taps](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)); no XQuartz.
- Icons are original assets in `native/icon.svg` and `native/menubar.svg`.
  `make icon` rebuilds the packaged icons.
