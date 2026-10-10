{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.MouseResizableTile (BSD-3-Clause),
-- Copyright (c) Jan Vornberger and the Xmonad Community. Tiling geometry and
-- keyboard messages only: there are no X11 dragger windows on macOS, so
-- `draggerType` sets the gap between windows but nothing can be dragged.
module XMonad.Layout.MouseResizableTile
  ( mouseResizableTile, mouseResizableTileMirrored
  , MouseResizableTile(..), MRTMessage(..), DraggerType(..)
  ) where
import XMonad.Core
import XMonad.Layout (Resize(..), IncMasterN(..), mirrorRect)
import qualified XMonad.StackSet as W
import Control.Monad (msum)

data DraggerType
  = FixedDragger { gapWidth :: Dimension, draggerWidth :: Dimension }
  | BordersDragger
  deriving (Show,Read,Eq)

data MRTMessage
  = SetMasterFraction Rational
  | SetLeftSlaveFraction Int Rational
  | SetRightSlaveFraction Int Rational
  | ShrinkSlave
  | ExpandSlave
  deriving (Show,Read,Eq)
instance Message MRTMessage

-- Slave fractions are the share of the space still remaining in the column
-- that each window takes; missing entries split the remainder evenly.
data MouseResizableTile a = MRT
  { nmaster :: Int
  , masterFrac :: Rational
  , slaveFrac :: Rational
  , fracIncrement :: Rational
  , leftFracs :: [Rational]
  , rightFracs :: [Rational]
  , draggers :: [Window]
  , focusPos :: Int
  , numWindows :: Int
  , isMirrored :: Bool
  , draggerType :: DraggerType
  } deriving (Show,Read)

mouseResizableTile :: MouseResizableTile a
mouseResizableTile = MRT
  { nmaster = 1, masterFrac = 1/2, slaveFrac = 1/2, fracIncrement = 3/100
  , leftFracs = [], rightFracs = [], draggers = [], focusPos = 0
  , numWindows = 0, isMirrored = False, draggerType = FixedDragger 6 6 }

mouseResizableTileMirrored :: MouseResizableTile a
mouseResizableTileMirrored = mouseResizableTile {isMirrored = True}

instance LayoutClass MouseResizableTile Window where
  doLayout st sr (W.Stack w l r) = pure (zip wins rects, Just st')
    where
      wins = reverse l ++ w : r
      num = length wins
      pos = length l
      st' = (if num /= numWindows st then st {leftFracs=[], rightFracs=[]} else st)
              {focusPos = pos, numWindows = num}
      area = if isMirrored st then mirrorRect sr else sr
      tiled = tileColumns st' area num
      rects = if isMirrored st then map mirrorRect tiled else tiled
  emptyLayout _ _ = pure ([], Nothing)
  handleMessage st m = pure $ msum
    [ resize <$> fromMessage m, inc <$> fromMessage m, mrt <$> fromMessage m ]
    where
      d = fracIncrement st
      resize Shrink = st {masterFrac = clampFrac (masterFrac st - d)}
      resize Expand = st {masterFrac = clampFrac (masterFrac st + d)}
      inc (IncMasterN n) = st {nmaster = max 0 (nmaster st + n)}
      mrt (SetMasterFraction f) = st {masterFrac = clampFrac f}
      mrt (SetLeftSlaveFraction i f) = setFrac True i f
      mrt (SetRightSlaveFraction i f) = setFrac False i f
      mrt ShrinkSlave = slave (negate d)
      mrt ExpandSlave = slave d
      (nm, nr) = columnSizes st
      setFrac isLeft i f
        | i < 0 || i >= k - 1 = st
        | isLeft = st {leftFracs = update i f (leftFracs st) k}
        | otherwise = st {rightFracs = update i f (rightFracs st) k}
        where k = if isLeft then nm else nr
      slave dx
        | focusPos st < nm = st {leftFracs = adjust dx (focusPos st) nm (leftFracs st)}
        | otherwise = st {rightFracs = adjust dx (focusPos st - nm) nr (rightFracs st)}
  description st = if isMirrored st then "MouseResizableTileMirrored"
                   else "MouseResizableTile"

clampFrac :: Rational -> Rational
clampFrac = max (1/20) . min (19/20)

-- Number of windows in the master and in the slave column.
columnSizes :: MouseResizableTile a -> (Int, Int)
columnSizes st
  | n <= nmaster st = (n, 0)
  | otherwise = (nmaster st, n - nmaster st)
  where n = numWindows st

fullFracs :: [Rational] -> Int -> [Rational]
fullFracs fs k = take (k-1) (fs ++ [1 / fromIntegral (k-i) | i <- [0..]])

update :: Int -> Rational -> [Rational] -> Int -> [Rational]
update i f fs k = [if j == i then clampFrac f else x | (j,x) <- zip [0..] (fullFracs fs k)]

-- The last window of a column has no fraction of its own, so resizing it
-- moves the boundary above it in the opposite direction.
adjust :: Rational -> Int -> Int -> [Rational] -> [Rational]
adjust dx p k fs
  | k < 2 = fs
  | p < k - 1 = update p (full !! p + dx) fs k
  | otherwise = update (p-1) (full !! (p-1) - dx) fs k
  where full = fullFracs fs k

gapOf :: DraggerType -> Position
gapOf (FixedDragger g _) = fromIntegral g
gapOf BordersDragger = 0

tileColumns :: MouseResizableTile a -> Rectangle -> Int -> [Rectangle]
tileColumns st sr@(Rectangle sx sy sw sh) num
  | num <= 0 = []
  | num <= nm' = column (leftFracs st) sr num
  | nm' == 0 = column (rightFracs st) sr num
  | otherwise = column (leftFracs st) master nm'
             ++ column (rightFracs st) slaves (num-nm')
  where
    nm' = nmaster st
    gap = gapOf (draggerType st)
    split = sx + floor (fromIntegral sw * masterFrac st)
    lw = max 1 (split - sx - gap `div` 2)
    rx = sx + lw + gap
    master = Rectangle sx sy (fromIntegral lw) sh
    slaves = Rectangle rx sy (fromIntegral (max 1 (sx + fromIntegral sw - rx))) sh
    column fs (Rectangle x y w h) k = go y (fullFracs fs k) k
      where
        avail = fromIntegral h - (k-1) * fromIntegral gap :: Int
        end = y + fromIntegral h
        go cy _ 1 = [Rectangle x cy w (fromIntegral (max 1 (end - cy)))]
        go cy (f:rest) j = Rectangle x cy w (fromIntegral hh)
                         : go (cy + hh + gap) rest (j-1 :: Int)
          where used = cy - y - (k-j) * gap
                hh = max 1 (floor (f * fromIntegral (avail - used)))
        go cy [] j = go cy [1 / fromIntegral j] j
