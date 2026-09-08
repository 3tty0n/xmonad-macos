-- Adapted from xmonad-contrib XMonad.Actions.SwapWorkspaces (BSD-3-Clause),
-- Copyright (c) Devin Mullins and the Xmonad Community.
module XMonad.Actions.SwapWorkspaces (swapWith, swapWithCurrent, swapWorkspaces) where
import XMonad.Core
import qualified XMonad.StackSet as W

-- Exchange the contents of two workspaces, leaving the tags where they are on
-- screen, so a workspace can be pulled to the display you are looking at.
swapWorkspaces :: Eq i => i -> i -> W.StackSet i l a s sd -> W.StackSet i l a s sd
swapWorkspaces t1 t2 = W.mapWorkspace swap
  where swap w | W.tag w == t1 = w {W.tag=t2}
               | W.tag w == t2 = w {W.tag=t1}
               | otherwise = w

swapWithCurrent :: Eq i => i -> W.StackSet i l a s sd -> W.StackSet i l a s sd
swapWithCurrent t s = swapWorkspaces t (W.currentTag s) s

swapWith :: Eq i => i -> i -> W.StackSet i l a s sd -> W.StackSet i l a s sd
swapWith = swapWorkspaces
