-- Adapted from xmonad-contrib XMonad.Actions.Promote (BSD-3-Clause),
-- Copyright (c) Miikka Koskinen and the Xmonad Community.
module XMonad.Actions.Promote (promote) where
import XMonad.Core
import XMonad.Operations (windows)
import qualified XMonad.StackSet as W

promote :: X ()
promote = windows $ W.modify' $ \c -> case c of
  W.Stack _ [] []     -> c
  W.Stack t [] (x:rs) -> W.Stack x [] (t:rs)
  W.Stack t ls rs     -> W.Stack t [] (reverse ls ++ rs)
