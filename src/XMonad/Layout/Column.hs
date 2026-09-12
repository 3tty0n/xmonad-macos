{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.Column (BSD-3-Clause),
-- Copyright (c) Ilya Portnov and the Xmonad Community.
module XMonad.Layout.Column (Column(..)) where
import XMonad.Core
import XMonad.Layout (Resize(..))
import qualified XMonad.StackSet as W

newtype Column a = Column Float deriving (Read, Show)

instance LayoutClass Column a where
  pureLayout = columnLayout
  pureMessage = columnMessage
  description _ = "Column"

columnMessage :: Column a -> SomeMessage -> Maybe (Column a)
columnMessage (Column q) m = resize <$> fromMessage m
  where resize Shrink = Column (q-0.1)
        resize Expand = Column (q+0.1)

columnLayout :: Column a -> Rectangle -> W.Stack a -> [(a, Rectangle)]
columnLayout (Column q) rect stack = zip ws rects
  where ws = W.integrate stack
        n = length ws
        heights = map (xn n rect q) [1..n]
        ys = [fromIntegral $ sum $ take k heights | k <- [0..n-1]]
        rects = zipWith (curry (mkRect rect)) heights ys

mkRect :: Rectangle -> (Dimension, Position) -> Rectangle
mkRect (Rectangle xs ys ws _) (h,y) = Rectangle xs (ys+y) ws h

xn :: Int -> Rectangle -> Float -> Int -> Dimension
xn n (Rectangle _ _ _ h) q k
  | q == 1 = h `div` fromIntegral n
  | otherwise = round (fromIntegral h * q^(n-k) * (1-q) / (1-q^n))
