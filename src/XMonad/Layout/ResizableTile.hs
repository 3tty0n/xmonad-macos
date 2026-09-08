{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.ResizableTile (BSD-3-Clause),
-- Copyright (c) Lukas Mai and the Xmonad Community.
module XMonad.Layout.ResizableTile (ResizableTall(..), MirrorResize(..)) where
import XMonad.Core
import XMonad.Layout (Resize(..), IncMasterN(..), splitHorizontallyBy, mirrorRect)
import qualified XMonad.StackSet as W
import Control.Monad (msum)

data MirrorResize = MirrorShrink | MirrorExpand deriving (Show,Read)
instance Message MirrorResize

-- `slaves` holds a height multiplier per window, master column first, so a
-- single window can be made taller without disturbing the others.
data ResizableTall a = ResizableTall
  { resizableNMaster :: !Int, resizableDelta :: !Rational
  , resizableFrac :: !Rational, resizableSlaves :: [Rational]
  } deriving (Show,Read)

instance LayoutClass ResizableTall a where
  pureLayout (ResizableTall nmaster _ frac mfrac) r s = zip ws rs
    where ws = W.integrate s
          rs = tileWeighted frac mfrac r nmaster (length ws)
  pureMessage l@(ResizableTall nmaster delta frac _) m = msum
    [resize <$> fromMessage m, inc <$> fromMessage m]
    where
      resize Shrink = l {resizableFrac = max 0 $ frac-delta}
      resize Expand = l {resizableFrac = min 1 $ frac+delta}
      inc (IncMasterN d) = l {resizableNMaster = max 0 $ nmaster+d}
  -- A mirror resize needs to know which window is focused, so it cannot be a
  -- pure message like Shrink and Expand.
  handleMessage l m
    | Just e <- fromMessage m = do
        stack <- gets (W.stack . W.workspace . W.current . windowset)
        pure (mirrorResize l e <$> stack)
    | otherwise = pure (pureMessage l m)
  description _ = "ResizableTall"

mirrorResize :: ResizableTall a -> MirrorResize -> W.Stack w -> ResizableTall a
mirrorResize l e stack = l {resizableSlaves = take total (weigh mfrac position)}
  where
    mfrac = resizableSlaves l ++ repeat 1
    above = length (W.up stack)
    total = above + length (W.down stack) + 1
    position = if above == length (resizableSlaves l) then above-1 else above
    step = case e of MirrorShrink -> resizableDelta l
                     MirrorExpand -> negate (resizableDelta l)
    weigh (f:fs) 0 = max (1/100) (f+step) : fs
    weigh (f:fs) k = f : weigh fs (k-1)
    weigh [] _ = []

-- Master column, then the stack split by the per-window weights.
tileWeighted :: Rational -> [Rational] -> Rectangle -> Int -> Int -> [Rectangle]
tileWeighted frac mfrac r nmaster n
  | n <= nmaster || nmaster == 0 = splitWeighted (weights n) r
  | otherwise = splitWeighted (weights nmaster) r1
             ++ splitWeighted (drop nmaster (weights n)) r2
  where (r1,r2) = splitHorizontallyBy frac r
        weights k = take k (mfrac ++ repeat 1)

splitWeighted :: [Rational] -> Rectangle -> [Rectangle]
splitWeighted ws r@(Rectangle sx sy sw sh)
  | null ws = []
  | total <= 0 = [r]
  | otherwise = go sy ws
  where
    total = sum ws
    go _ [] = []
    go y [_] = [Rectangle sx y sw (sh-(y-sy))]
    go y (w:rest) = Rectangle sx y sw h : go (y+h) rest
      where h = floor (toRational sh * w / total)
