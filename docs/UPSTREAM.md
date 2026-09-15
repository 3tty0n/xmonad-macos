# Upstream

Base: [`xmonad/xmonad`](https://github.com/xmonad/xmonad) at
`a9a8b5c1b91b63b0836f5810634c9b28ec0af788` (pinned 2026-09-07).

`StackSet.hs`, `Layout.hs`, and `Core.hs` are BSD-3-Clause adaptations of
those files. `LICENSE` keeps the original copyright.
`ThreeCol` / `Circle` are adapted from xmonad-contrib; the contrib
**package** is not a dependency.

Public APIs only: [AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement),
[NSScreen.visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe),
[CGEvent tap](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:)).
Not XQuartz.

Icons: original XM² in `native/icon.svg` / `native/menubar.svg`; `make icon`
rebuilds `AppIcon.icns` and `MenuBarIcon.pdf`.
