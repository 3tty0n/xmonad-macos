{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.Dwindle (BSD-3-Clause),
-- Copyright (c) Norbert Zeh and the Xmonad Community.
module XMonad.Layout.Dwindle (Dwindle(..), Direction2D(..), Chirality(..)) where
import Data.List (unfoldr)
import XMonad.Core
import XMonad.Layout (Resize(..))
import qualified XMonad.StackSet as W
import XMonad.Util.Types (Direction2D(..))

data Dwindle a = Dwindle !Direction2D !Chirality !Rational !Rational
               | Spiral  !Direction2D !Chirality !Rational !Rational
               | Squeeze !Direction2D !Rational !Rational
               deriving (Read, Show)

data Chirality = CW | CCW deriving (Read, Show)

instance LayoutClass Dwindle a where
  pureLayout (Dwindle dir rot ratio _) = dwindle alternate dir rot ratio
  pureLayout (Spiral  dir rot ratio _) = dwindle rotate    dir rot ratio
  pureLayout (Squeeze dir     ratio _) = squeeze           dir     ratio
  pureMessage (Dwindle dir rot ratio delta) =
    fmap (\ratio' -> Dwindle dir rot ratio' delta) . changeRatio ratio delta
  pureMessage (Spiral dir rot ratio delta) =
    fmap (\ratio' -> Spiral dir rot ratio' delta) . changeRatio ratio delta
  pureMessage (Squeeze dir ratio delta) =
    fmap (\ratio' -> Squeeze dir ratio' delta) . changeRatio ratio delta
  description Dwindle{} = "Dwindle"
  description Spiral{} = "Spiral"
  description Squeeze{} = "Squeeze"

changeRatio :: Rational -> Rational -> SomeMessage -> Maybe Rational
changeRatio ratio delta = fmap f . fromMessage
  where f Expand = ratio * delta
        f Shrink = ratio / delta

dwindle :: AxesGenerator -> Direction2D -> Chirality -> Rational -> Rectangle -> W.Stack a
        -> [(a, Rectangle)]
dwindle trans dir rot ratio rect st = unfoldr genRects (W.integrate st, rect, dirAxes dir, rot)
  where genRects ([],   _, _, _ ) = Nothing
        genRects ([w],  r, a, rt) = Just ((w, r),  ([], r,   a,  rt))
        genRects (w:ws, r, a, rt) = Just ((w, r'), (ws, r'', a', rt'))
          where (r', r'') = splitRect r ratio a
                (a', rt') = trans a rt

squeeze :: Direction2D -> Rational -> Rectangle -> W.Stack a -> [(a, Rectangle)]
squeeze dir ratio rect st = zip wins rects
  where wins    = W.integrate st
        nwins   = length wins
        sizes   = take nwins $ unfoldr (\r -> Just (r * ratio, r * ratio)) 1
        totals' = 0 : zipWith (+) sizes totals'
        totals  = drop 1 totals'
        splits  = zip (drop 1 sizes) totals
        ratios  = reverse $ map (uncurry (/)) splits
        rects   = genRects rect ratios
        genRects r []     = [r]
        genRects r (x:xs) = r' : genRects r'' xs
          where (r', r'') = splitRect r x (dirAxes dir)

splitRect :: Rectangle -> Rational -> Axes -> (Rectangle, Rectangle)
splitRect (Rectangle x y w h) ratio (ax, ay) =
  (Rectangle x' y' w' h', Rectangle x'' y'' w'' h'')
  where portion = ratio / (ratio + 1)
        w1  = round (fromIntegral w * portion)
        w2  = w - w1
        h1  = round (fromIntegral h * portion)
        h2  = h - h1
        x'  = x + negate ax * (1 - ax) * w2 `div` 2
        y'  = y + negate ay * (1 - ay) * h2 `div` 2
        w'  = w1 + (1 - abs ax) * w2
        h'  = h1 + (1 - abs ay) * h2
        x'' = x + ax * (1 + ax) * w1 `div` 2
        y'' = y + ay * (1 + ay) * h1 `div` 2
        w'' = w2 + (1 - abs ax) * w1
        h'' = h2 + (1 - abs ay) * h1

type Axes = (Int, Int)
type AxesGenerator = Axes -> Chirality -> (Axes, Chirality)

dirAxes :: Direction2D -> Axes
dirAxes L = (-1,  0)
dirAxes R = ( 1,  0)
dirAxes U = ( 0, -1)
dirAxes D = ( 0,  1)

alternate :: AxesGenerator
alternate = chDir alt

rotate :: AxesGenerator
rotate = chDir id

chDir :: (Chirality -> Chirality) -> AxesGenerator
chDir f (x, y) r = (a' r, r')
  where a' CW  = (-y,  x)
        a' CCW = ( y, -x)
        r' = f r

alt :: Chirality -> Chirality
alt CW  = CCW
alt CCW = CW
