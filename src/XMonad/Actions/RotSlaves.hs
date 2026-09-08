-- Adapted from xmonad-contrib XMonad.Actions.RotSlaves (BSD-3-Clause),
-- Copyright (c) Hans Philipp Annen, Mischa Dieterle and the Xmonad Community.
module XMonad.Actions.RotSlaves
  (rotSlaves', rotSlavesUp, rotSlavesDown, rotAll', rotAllUp, rotAllDown) where
import XMonad.Core
import XMonad.Operations (windows)
import qualified XMonad.StackSet as W

rotSlavesUp, rotSlavesDown, rotAllUp, rotAllDown :: X ()
rotSlavesUp = windows $ W.modify' (rotSlaves' rotUp)
rotSlavesDown = windows $ W.modify' (rotSlaves' rotDown)
rotAllUp = windows $ W.modify' (rotAll' rotUp)
rotAllDown = windows $ W.modify' (rotAll' rotDown)

-- Rotate everything except the master window.
rotSlaves' :: ([a] -> [a]) -> W.Stack a -> W.Stack a
rotSlaves' _ s@(W.Stack _ [] []) = s
rotSlaves' f (W.Stack t [] rs) = W.Stack t [] (f rs)
rotSlaves' f s@(W.Stack _ ls _) = W.Stack t' (reverse revls') rs'
  where (master:rest) = W.integrate s
        (revls',t':rs') = splitAt (length ls) (master : f rest)
        ls = W.up s

-- Rotate the whole stack, master included.
rotAll' :: ([a] -> [a]) -> W.Stack a -> W.Stack a
rotAll' f s = W.Stack focus' (reverse revls) rs
  where (revls,focus':rs) = splitAt (length $ W.up s) (f (W.integrate s))

rotUp, rotDown :: [a] -> [a]
rotUp [] = []
rotUp (x:xs) = xs ++ [x]
rotDown [] = []
rotDown xs = last xs : init xs
