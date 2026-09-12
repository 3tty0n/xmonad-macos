{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.Spiral (BSD-3-Clause),
-- Copyright (c) Joe Thornber and the Xmonad Community.
module XMonad.Layout.Spiral
  ( spiral, spiralWithDir, Rotation(..), Direction(..), SpiralWithDir
  ) where
import Data.Ratio
import XMonad.Core
import XMonad.Layout (Resize(..))
import qualified XMonad.StackSet as W

fibs :: [Integer]
fibs = 1 : 1 : zipWith (+) fibs (drop 1 fibs)

mkRatios :: [Integer] -> [Rational]
mkRatios (x1:x2:xs) = (x1 % x2) : mkRatios (x2:xs)
mkRatios _ = []

data Rotation = CW | CCW deriving (Read, Show)
data Direction = East | South | West | North deriving (Eq, Enum, Read, Show)

blend :: Rational -> [Rational] -> [Rational]
blend scale ratios = zipWith (+) ratios scaleFactors
  where
    len = length ratios
    step = (scale - 1) / fromIntegral (max 1 len)
    scaleFactors = map (* step) . reverse . take len $ [0..]

spiral :: Rational -> SpiralWithDir a
spiral = spiralWithDir East CW

spiralWithDir :: Direction -> Rotation -> Rational -> SpiralWithDir a
spiralWithDir = SpiralWithDir

data SpiralWithDir a = SpiralWithDir Direction Rotation Rational
                     deriving (Read, Show)

instance LayoutClass SpiralWithDir a where
  pureLayout (SpiralWithDir dir rot scale) sc stack = zip ws rects
    where ws = W.integrate stack
          ratios = blend scale . reverse . take (max 0 (length ws - 1)) . mkRatios $ drop 1 fibs
          rects = divideRects (zip ratios dirs) sc
          dirs = dropWhile (/= dir) $ case rot of
            CW  -> cycle [East .. North]
            CCW -> cycle [North, West, South, East]
  handleMessage (SpiralWithDir dir rot scale) = pure . fmap resize . fromMessage
    where resize Expand = spiralWithDir dir rot $ (21 % 20) * scale
          resize Shrink = spiralWithDir dir rot $ (20 % 21) * scale
  description _ = "Spiral"

divideRects :: [(Rational, Direction)] -> Rectangle -> [Rectangle]
divideRects [] r = [r]
divideRects ((r,d):xs) rect = case divideRect r d rect of
  (r1, r2) -> r1 : divideRects xs r2

data Rect = Rect Integer Integer Integer Integer

fromRect :: Rect -> Rectangle
fromRect (Rect x y w h) = Rectangle (fromIntegral x) (fromIntegral y) (fromIntegral w) (fromIntegral h)

toRect :: Rectangle -> Rect
toRect (Rectangle x y w h) = Rect (fromIntegral x) (fromIntegral y) (fromIntegral w) (fromIntegral h)

divideRect :: Rational -> Direction -> Rectangle -> (Rectangle, Rectangle)
divideRect r d rect = let (r1, r2) = divideRect' r d (toRect rect) in (fromRect r1, fromRect r2)

divideRect' :: Rational -> Direction -> Rect -> (Rect, Rect)
divideRect' ratio dir (Rect x y w h) = case dir of
  East -> let (w1, w2) = chop ratio w in (Rect x y w1 h, Rect (x + w1) y w2 h)
  South -> let (h1, h2) = chop ratio h in (Rect x y w h1, Rect x (y + h1) w h2)
  West -> let (w1, w2) = chop (1 - ratio) w in (Rect (x + w1) y w2 h, Rect x y w1 h)
  North -> let (h1, h2) = chop (1 - ratio) h in (Rect x (y + h1) w h2, Rect x y w h1)

chop :: Rational -> Integer -> (Integer, Integer)
chop rat n = let f = (n * numerator rat) `div` denominator rat in (f, n - f)
