{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.MouseResizableTile (BSD-3-Clause),
-- Copyright (c) Jan Vornberger 2009 and the Xmonad Community. Tiling geometry
-- and keyboard messages only: there are no X11 dragger windows on macOS, so
-- `draggerType` still sets the gap between windows but nothing can be
-- dragged, and `BordersDragger` assumes a zero border width.
module XMonad.Layout.MouseResizableTile
  ( mouseResizableTile
  , mouseResizableTileMirrored
  , MRTMessage(ShrinkSlave, ExpandSlave, SetMasterFraction
              , SetLeftSlaveFraction, SetRightSlaveFraction)
  , nmaster, masterFrac, slaveFrac, fracIncrement, isMirrored, draggerType
  , DraggerType(..)
  , MouseResizableTile
  ) where
import XMonad.Core
import XMonad.Layout (Resize(..), IncMasterN(..), mirrorRect)
import qualified XMonad.StackSet as W

data MRTMessage
  = SetMasterFraction Rational
  | SetLeftSlaveFraction Int Rational
  | SetRightSlaveFraction Int Rational
  | ShrinkSlave
  | ExpandSlave
instance Message MRTMessage

data DraggerType
  = FixedDragger { gapWidth :: Dimension, draggerWidth :: Dimension }
  | BordersDragger
  deriving (Show,Read)

-- (offset of the next window, gap width), as in upstream's DraggerGeometry.
type DraggerGeometry = (Position, Dimension)

data MouseResizableTile a = MRT
  { nmaster :: Int
  , masterFrac :: Rational
  , slaveFrac :: Rational
  , fracIncrement :: Rational
  , leftFracs :: [Rational]
  , rightFracs :: [Rational]
  , draggerType :: DraggerType
  , focusPos :: Int
  , numWindows :: Int
  , isMirrored :: Bool
  } deriving (Show,Read)

mouseResizableTile :: MouseResizableTile a
mouseResizableTile = MRT 1 0.5 0.5 0.03 [] [] (FixedDragger 6 6) 0 0 False

mouseResizableTileMirrored :: MouseResizableTile a
mouseResizableTileMirrored = mouseResizableTile {isMirrored = True}

instance LayoutClass MouseResizableTile Window where
  doLayout st sr (W.Stack w l r) =
    pure (zip wins rects', Just st {focusPos = length l, numWindows = length wins})
    where
      drg = draggerGeometry (draggerType st)
      wins = reverse l ++ w : r
      num = length wins
      sr' = mirrorAdjust sr (mirrorRect sr)
      rects = tile (nmaster st) (masterFrac st)
                   (leftFracs st ++ repeat (slaveFrac st))
                   (rightFracs st ++ repeat (slaveFrac st)) sr' num drg
      rects' = map (mirrorAdjust id mirrorRect . sanitizeRectangle sr') rects
      mirrorAdjust a b = if isMirrored st then b else a

  handleMessage st m = pure (pick (fromMessage m) (fromMessage m) (fromMessage m))
    where
      d = fracIncrement st
      pick (Just (IncMasterN n)) _ _ = Just st {nmaster = max 0 (nmaster st + n)}
      pick _ (Just Shrink) _ = Just st {masterFrac = max 0 (masterFrac st - d)}
      pick _ (Just Expand) _ = Just st {masterFrac = min 1 (masterFrac st + d)}
      pick _ _ (Just msg) = Just (mrt msg)
      pick _ _ Nothing = Nothing
      mrt ShrinkSlave = modifySlave st (negate d)
      mrt ExpandSlave = modifySlave st d
      mrt (SetMasterFraction f) = st {masterFrac = clamp f}
      mrt (SetLeftSlaveFraction p f) =
        st {leftFracs = replaceAtPos (slaveFrac st) (leftFracs st) p (clamp f)}
      mrt (SetRightSlaveFraction p f) =
        st {rightFracs = replaceAtPos (slaveFrac st) (rightFracs st) p (clamp f)}

  description st = (if isMirrored st then ("Mirror " ++) else id) "MouseResizableTile"

clamp :: Rational -> Rational
clamp = max 0 . min 1

draggerGeometry :: DraggerType -> DraggerGeometry
draggerGeometry (FixedDragger g _) = (fromIntegral (g `div` 2), g)
draggerGeometry BordersDragger = (0, 0)

modifySlave :: MouseResizableTile a -> Rational -> MouseResizableTile a
modifySlave st delta
  | pos < nm = if left > 0
      then let p = min (left-1) pos
           in st {leftFracs = bump (leftFracs st) p}
      else st
  | right > 0 = let p = min (right-1) (pos-nm)
                in st {rightFracs = bump (rightFracs st) p}
  | otherwise = st
  where
    pos = focusPos st
    nm = nmaster st
    left = nm - 1
    right = numWindows st - nm - 1
    sl = slaveFrac st
    bump fs p = replaceAtPos sl fs p (clamp ((fs ++ repeat sl) !! p + delta))

replaceAtPos :: Rational -> [Rational] -> Int -> Rational -> [Rational]
replaceAtPos _ [] 0 x' = [x']
replaceAtPos d [] pos x' = d : replaceAtPos d [] (pos-1) x'
replaceAtPos _ (_:xs) 0 x' = x' : xs
replaceAtPos d (x:xs) pos x' = x : replaceAtPos d xs (pos-1) x'

sanitizeRectangle :: Rectangle -> Rectangle -> Rectangle
sanitizeRectangle (Rectangle sx sy swh sht) (Rectangle x y wh ht) =
  Rectangle (within 0 (sx + fromIntegral swh) x) (within 0 (sy + fromIntegral sht) y)
            (within 1 swh wh) (within 1 sht ht)

within :: Ord a => a -> a -> a -> a
within low high a = max low $ min high a

tile :: Int -> Rational -> [Rational] -> [Rational] -> Rectangle -> Int
     -> DraggerGeometry -> [Rectangle]
tile nm mf lf rf sr num drg
  | num <= nm = splitVertically (take (num-1) lf) sr drg
  | nm == 0 = splitVertically (take (num-1) rf) sr drg
  | otherwise = leftRects ++ rightRects
  where
    (sr1,sr2) = splitHorizontallyBy mf sr drg
    leftRects = splitVertically (take (nm-1) lf) sr1 drg
    rightRects = splitVertically (take (num-nm-1) rf) sr2 drg

splitVertically :: [Rational] -> Rectangle -> DraggerGeometry -> [Rectangle]
splitVertically [] r _ = [r]
splitVertically (f:fx) (Rectangle sx sy sw sh) drg@(drOff,drSz) =
  Rectangle sx sy sw (smallh - drSz `div` 2)
    : splitVertically fx
        (Rectangle sx (sy + fromIntegral smallh + drOff) sw
                   (sh - smallh - drSz `div` 2)) drg
  where smallh = floor (fromIntegral sh * f)

splitHorizontallyBy :: Rational -> Rectangle -> DraggerGeometry
                    -> (Rectangle, Rectangle)
splitHorizontallyBy f (Rectangle sx sy sw sh) (drOff,drSz) =
  (Rectangle sx sy (leftw - drSz `div` 2) sh,
   Rectangle (sx + fromIntegral leftw + drOff) sy
             (sw - leftw - drSz `div` 2) sh)
  where leftw = floor (fromIntegral sw * f)
