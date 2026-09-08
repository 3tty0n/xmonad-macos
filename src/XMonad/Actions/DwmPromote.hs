-- Adapted from xmonad-contrib XMonad.Actions.DwmPromote (BSD-3-Clause),
-- Copyright (c) Miikka Koskinen and the Xmonad Community.
module XMonad.Actions.DwmPromote (dwmpromote) where
import XMonad.Core
import XMonad.Operations (windows)
import qualified XMonad.StackSet as W

-- Move the focused window to master, or, if it is already master, swap it
-- with the window below.
dwmpromote :: X ()
dwmpromote = windows $ W.modify' $ \c -> case c of
  W.Stack _ [] [] -> c
  W.Stack t [] (x:rs) -> W.Stack t [x] rs
  W.Stack t ls rs -> case reverse ls of
    (x:xs) -> W.Stack t [] (xs ++ x:rs)
    [] -> c
