-- Adapted from xmonad-contrib XMonad.Hooks.ManageHelpers (BSD-3-Clause),
-- Copyright (c) Ivan Tarasov and the Xmonad Community. The X11 property
-- queries (isDialog, isFullscreen, transience) have no macOS counterpart and
-- are not ported; only standard windows are managed in the first place.
module XMonad.Hooks.ManageHelpers
  ( MaybeManageHook, composeOne, (-?>)
  , doRectFloat, doCenterFloat, doFullFloat, doSink
  ) where
import XMonad.Core
import XMonad.ManageHook (doF)
import qualified XMonad.StackSet as W

type MaybeManageHook = Query (Maybe (Endo WindowSet))

-- The first matching rule wins, unlike composeAll, which applies them all.
composeOne :: [MaybeManageHook] -> ManageHook
composeOne [] = mempty
composeOne (r:rs) = do
  matched <- r
  case matched of
    Just hook -> pure hook
    Nothing -> composeOne rs

(-?>) :: Query Bool -> ManageHook -> MaybeManageHook
cond -?> action = do
  matched <- cond
  if matched then Just <$> action else pure Nothing
infixr 0 -?>

-- Float the window at a rectangle relative to its screen.
doRectFloat :: W.RationalRect -> ManageHook
doRectFloat r = ask >>= \w -> doF (W.float w r)

-- Float it centred, at half the screen in each direction.
doCenterFloat :: ManageHook
doCenterFloat = doRectFloat (W.RationalRect (1/4) (1/4) (1/2) (1/2))

doFullFloat :: ManageHook
doFullFloat = doRectFloat (W.RationalRect 0 0 1 1)

doSink :: ManageHook
doSink = ask >>= doF . W.sink
