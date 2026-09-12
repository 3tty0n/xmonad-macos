{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.StackTile (BSD-3-Clause),
-- Copyright (c) Rickard Gustafsson and the Xmonad Community.
module XMonad.Layout.StackTile (StackTile(..)) where
import XMonad.Core
import XMonad.Layout (Resize(..), IncMasterN(..), splitHorizontally, splitVertically, splitVerticallyBy)
import qualified XMonad.StackSet as W
import Control.Monad (msum)

data StackTile a = StackTile !Int !Rational !Rational deriving (Show, Read)

instance LayoutClass StackTile a where
  pureLayout (StackTile nmaster _ frac) r s = zip ws rs
    where ws = W.integrate s
          rs = tile frac r nmaster (length ws)
  pureMessage (StackTile nmaster delta frac) m =
    msum [resize <$> fromMessage m, incmastern <$> fromMessage m]
    where resize Shrink = StackTile nmaster delta (max 0 $ frac-delta)
          resize Expand = StackTile nmaster delta (min 1 $ frac+delta)
          incmastern (IncMasterN d) = StackTile (max 0 (nmaster+d)) delta frac
  description _ = "StackTile"

tile :: Rational -> Rectangle -> Int -> Int -> [Rectangle]
tile f r nmaster n
  | n <= nmaster || nmaster == 0 = splitHorizontally n r
  | otherwise = splitHorizontally nmaster r1 ++ splitVertically (n-nmaster) r2
  where (r1,r2) = splitVerticallyBy f r
