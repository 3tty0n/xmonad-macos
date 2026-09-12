{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.OneBig (BSD-3-Clause),
-- Copyright (c) Ilya Portnov and the Xmonad Community.
module XMonad.Layout.OneBig (OneBig(..)) where
import XMonad.Core
import XMonad.Layout (Resize(..))
import qualified XMonad.StackSet as W

data OneBig a = OneBig Float Float deriving (Read, Show)

instance LayoutClass OneBig a where
  pureLayout = oneBigLayout
  pureMessage = oneBigMessage
  description _ = "OneBig"

oneBigMessage :: OneBig a -> SomeMessage -> Maybe (OneBig a)
oneBigMessage (OneBig cx cy) m = resize <$> fromMessage m
  where resize Shrink = OneBig (cx-delta) (cy-delta)
        resize Expand = OneBig (cx+delta) (cy+delta)
        delta = 3/100

oneBigLayout :: OneBig a -> Rectangle -> W.Stack a -> [(a, Rectangle)]
oneBigLayout (OneBig cx cy) rect stack =
  let ws = W.integrate stack
      n  = length ws
  in case ws of
    [] -> []
    (master : other) -> (master, masterRect)
                     : divideBottom bottomRect bottomWs
                     ++ divideRight rightRect rightWs
      where
        ht (Rectangle _ _ _ hh) = hh
        wd (Rectangle _ _ ww _) = ww
        h' = round (fromIntegral (ht rect) * cy)
        w = wd rect
        m = calcBottomWs n w h'
        bottomWs = take m other
        rightWs = drop m other
        masterRect = cmaster n m cx cy rect
        bottomRect = cbottom cy rect
        rightRect  = cright cx cy rect

calcBottomWs :: Int -> Dimension -> Dimension -> Int
calcBottomWs n w h' = case n of
  1 -> 0
  2 -> 1
  3 -> 2
  4 -> 2
  _ -> fromIntegral w * (n-1) `div` fromIntegral (h' + fromIntegral w)

cmaster :: Int -> Int -> Float -> Float -> Rectangle -> Rectangle
cmaster n m cx cy (Rectangle x y sw sh) = Rectangle x y ww hh
  where ww = if n > m+1 then round (fromIntegral sw * cx) else sw
        hh = if n > 1 then round (fromIntegral sh * cy) else sh

cbottom :: Float -> Rectangle -> Rectangle
cbottom cy (Rectangle sx sy sw sh) = Rectangle sx y sw h
  where h = round (fromIntegral sh * (1-cy))
        y = round (fromIntegral sh * cy + fromIntegral sy)

cright :: Float -> Float -> Rectangle -> Rectangle
cright cx cy (Rectangle sx sy sw sh) = Rectangle x sy w h
  where w = round (fromIntegral sw * (1-cx))
        x = round (fromIntegral sw * cx + fromIntegral sx)
        h = round (fromIntegral sh * cy)

divideBottom :: Rectangle -> [a] -> [(a, Rectangle)]
divideBottom _ [] = []
divideBottom (Rectangle x y w h) ws = zip ws rects
  where n = length ws
        oneW = w `div` n
        oneRect = Rectangle x y oneW h
        rects = take n $ iterate (shiftR oneW) oneRect

divideRight :: Rectangle -> [a] -> [(a, Rectangle)]
divideRight _ [] = []
divideRight (Rectangle x y w h) ws = zip ws rects
  where n = length ws
        oneH = h `div` n
        oneRect = Rectangle x y w oneH
        rects = take n $ iterate (shiftB oneH) oneRect

shiftR :: Position -> Rectangle -> Rectangle
shiftR s (Rectangle x y w h) = Rectangle (x+s) y w h

shiftB :: Position -> Rectangle -> Rectangle
shiftB s (Rectangle x y w h) = Rectangle x (y+s) w h
