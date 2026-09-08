# Upstream and attribution

## Base

Repository: [`xmonad/xmonad`](https://github.com/xmonad/xmonad)
Pinned commit: `a9a8b5c1b91b63b0836f5810634c9b28ec0af788`

That was `HEAD` when this port was started on 2026-09-07, with a commit
timestamp of 2026-06-28. It is a fixed reference point, not a claim about any
later upstream `HEAD`.

## Derived sources

Parts of `StackSet.hs`, `Layout.hs`, and `Core.hs` are derivatives of the
BSD-3-Clause sources below. Comments were abridged and the runtime was ported,
so these are adaptations rather than byte-for-byte vendored copies. `LICENSE`
keeps the original copyright and terms.

- [`src/XMonad/StackSet.hs`](https://github.com/xmonad/xmonad/blob/a9a8b5c1b91b63b0836f5810634c9b28ec0af788/src/XMonad/StackSet.hs)
- [`src/XMonad/Layout.hs`](https://github.com/xmonad/xmonad/blob/a9a8b5c1b91b63b0836f5810634c9b28ec0af788/src/XMonad/Layout.hs)
- [`src/XMonad/Core.hs`](https://github.com/xmonad/xmonad/blob/a9a8b5c1b91b63b0836f5810634c9b28ec0af788/src/XMonad/Core.hs)
- [`LICENSE`](https://github.com/xmonad/xmonad/blob/a9a8b5c1b91b63b0836f5810634c9b28ec0af788/LICENSE)

## Derived from xmonad-contrib

`ThreeCol`, `ThreeColMid` and `Circle` in `src/XMonad/Layout.hs` are adapted
from [`xmonad/xmonad-contrib`](https://github.com/xmonad/xmonad-contrib), also
BSD-3-Clause: `XMonad.Layout.ThreeColumns` and `XMonad.Layout.Circle`. They
live in this port's `XMonad.Layout` rather than under a contrib module path,
because contrib itself is not supported.

## Platform references

Why XQuartz is not the answer:

- [XQuartz](https://www.xquartz.org/) — the X.Org X Window System on macOS
- [quartz-wm](https://github.com/XQuartz/quartz-wm/blob/master/man/quartz-wm.man) — its X11 window manager

The APIs this port is built on:

- [AXUIElement](https://developer.apple.com/documentation/applicationservices/axuielement)
- [AXUIElementSetAttributeValue](https://developer.apple.com/documentation/applicationservices/1460434-axuielementsetattributevalue)
- [AXObserverCreate](https://developer.apple.com/documentation/applicationservices/1460133-axobservercreate)
- [AXUIElementSetMessagingTimeout](https://developer.apple.com/documentation/applicationservices/1459345-axuielementsetmessagingtimeout)
- [NSScreen.visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe)
- [CGEvent.tapCreate](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:))

Toolchain:

- [Homebrew GHC](https://formulae.brew.sh/formula/ghc)
- [Homebrew cabal-install](https://formulae.brew.sh/formula/cabal-install)

These document the APIs and the upstream design. They are not evidence that
this port behaves correctly on macOS — see [TESTING.md](TESTING.md) for that.

## Icon

The app and menu bar icons are derived from the xmonad logo by Hans Heintze,
licensed [CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/).
Source SVGs live in `native/icon.svg` and `native/menubar.svg`.
