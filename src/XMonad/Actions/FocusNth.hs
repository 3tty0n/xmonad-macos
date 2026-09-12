-- Adapted from xmonad-contrib XMonad.Actions.FocusNth (BSD-3-Clause),
-- Copyright (c) Karsten Schoelzel and the Xmonad Community.
module XMonad.Actions.FocusNth (focusNth, focusNth', swapNth, swapNth') where
import XMonad.Core
import XMonad.Operations (windows)
import qualified XMonad.StackSet as W

focusNth :: Int -> X ()
focusNth = windows . W.modify' . focusNth'

focusNth' :: Int -> W.Stack a -> W.Stack a
focusNth' n s
  | n >= 0, (ls, t:rs) <- splitAt n (W.integrate s) = W.Stack t (reverse ls) rs
  | otherwise = s

swapNth :: Int -> X ()
swapNth = windows . W.modify' . swapNth'

swapNth' :: Int -> W.Stack a -> W.Stack a
swapNth' n s@(W.Stack c l r)
  | n < 0 || n > length l + length r || n == length l = s
  | n < length l =
      let (nl, rest) = splitAt (length l - n - 1) l
      in case rest of
           nc:nr -> W.Stack nc (nl ++ c : nr) r
           [] -> s
  | otherwise =
      let (nl, rest) = splitAt (n - length l - 1) r
      in case rest of
           nc:nr -> W.Stack nc l (nl ++ c : nr)
           [] -> s
