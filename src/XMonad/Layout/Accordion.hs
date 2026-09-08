{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.Accordion (BSD-3-Clause),
-- Copyright (c) glasser@mit.edu and the Xmonad Community.
module XMonad.Layout.Accordion (Accordion(..)) where
import XMonad.Core
import qualified XMonad.StackSet as W

-- The focused window keeps most of the frame; the others become title-bar
-- sized strips above and below it, in stack order.
data Accordion a = Accordion deriving (Show,Read)

instance LayoutClass Accordion a where
  pureLayout Accordion r@(Rectangle sx sy sw sh) s
    | null above && null below = [(W.focus s,r)]
    | otherwise = zip above aboveStrips
               ++ [(W.focus s,Rectangle sx (sy+top) sw focusHeight)]
               ++ zip below belowStrips
    where
      above = reverse (W.up s)
      below = W.down s
      others = length above + length below
      lane = max 1 (min 60 (sh `div` max 1 (2*(others+1))))
      top = lane * length above
      focusHeight = max 1 (sh - lane*others)
      aboveStrips = [Rectangle sx (sy+lane*n) sw lane | n <- [0..length above-1]]
      belowStrips = [Rectangle sx (sy+top+focusHeight+lane*n) sw lane
                    | n <- [0..length below-1]]
  description _ = "Accordion"
