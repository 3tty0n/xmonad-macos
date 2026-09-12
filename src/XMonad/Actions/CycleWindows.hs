-- Adapted from xmonad-contrib XMonad.Actions.CycleWindows (BSD-3-Clause),
-- Copyright (c) Wirt Wolff and the Xmonad Community.
-- cycleRecentWindows needs a key-repeat grab and is not ported.
module XMonad.Actions.CycleWindows
  ( rotOpposite, rotOpposite'
  , rotFocused', rotFocusedUp, rotFocusedDown, shiftToFocus'
  , rotUnfocused', rotUnfocusedUp, rotUnfocusedDown
  , rotUp, rotDown
  ) where
import XMonad.Actions.RotSlaves (rotSlaves')
import XMonad.Core
import XMonad.Operations (windows)
import qualified XMonad.StackSet as W

shiftToFocus' :: Eq a => a -> W.Stack a -> W.Stack a
shiftToFocus' w s@(W.Stack _ ls _) = W.Stack w (reverse revls') rs'
  where (revls', rs') = splitAt (length ls) . filter (/= w) $ W.integrate s

rotOpposite :: X ()
rotOpposite = windows $ W.modify' rotOpposite'

rotOpposite' :: W.Stack a -> W.Stack a
rotOpposite' (W.Stack t l r) = case reverse (take part rrvl ++ t : drop part rrvl) of
  xs -> let (l', rest) = splitAt (length l) xs
        in case reverse rest of
             t':r' -> W.Stack t' l' r'
             [] -> W.Stack t l r
  where rrvl = r ++ reverse l
        part = (length rrvl + 1) `div` 2

rotFocusedUp, rotFocusedDown :: X ()
rotFocusedUp = windows . W.modify' $ rotFocused' rotUp
rotFocusedDown = windows . W.modify' $ rotFocused' rotDown

rotFocused' :: ([a] -> [a]) -> W.Stack a -> W.Stack a
rotFocused' _ s@(W.Stack _ [] []) = s
rotFocused' f (W.Stack t [] (r:rs)) = case f (t:rs) of
  t':rs' -> W.Stack t' [] (r:rs')
  [] -> W.Stack t [] (r:rs)
rotFocused' f s = rotSlaves' f s

rotUnfocusedUp, rotUnfocusedDown :: X ()
rotUnfocusedUp = windows . W.modify' $ rotUnfocused' rotUp
rotUnfocusedDown = windows . W.modify' $ rotUnfocused' rotDown

rotUnfocused' :: ([a] -> [a]) -> W.Stack a -> W.Stack a
rotUnfocused' _ s@(W.Stack _ [] []) = s
rotUnfocused' f s@(W.Stack _ [] _) = rotSlaves' f s
rotUnfocused' f (W.Stack t ls@(l:ll) rs) = W.Stack t (reverse revls') rs'
  where master:revls = reverse (l:ll)
        (revls',rs') = splitAt (length ls) (f $ master:revls ++ rs)

rotUp, rotDown :: [a] -> [a]
rotUp [] = []
rotUp (x:xs) = xs ++ [x]
rotDown [] = []
rotDown xs = last xs : init xs
