{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.Roledex (BSD-3-Clause),
-- Copyright (c) tim.thelion@gmail.com and the Xmonad Community.
module XMonad.Layout.Roledex (Roledex(..)) where
import Data.Ratio
import XMonad.Core
import XMonad.Layout (splitHorizontallyBy, splitVerticallyBy)
import qualified XMonad.StackSet as W

data Roledex a = Roledex deriving (Show, Read)

instance LayoutClass Roledex a where
  doLayout _ = roledexLayout
  description _ = "Roledex"

roledexLayout :: Rectangle -> W.Stack a -> X ([(a, Rectangle)], Maybe (Roledex a))
roledexLayout sc ws = pure ([(W.focus ws, mainPane)] ++ zip ups tops ++ reverse (zip dns bottoms), Nothing)
  where ups = W.up ws
        dns = W.down ws
        c = length ups + length dns
        rect = fst $ splitHorizontallyBy (2%3 :: Rational) $ fst (splitVerticallyBy (2%3 :: Rational) sc)
        gw = div' (w - rw) c
          where Rectangle _ _ w _ = sc
                Rectangle _ _ rw _ = rect
        gh = div' (h - rh) c
          where Rectangle _ _ _ h = sc
                Rectangle _ _ _ rh = rect
        mainPane = mrect (gw * c) (gh * c) rect
        mrect mx my (Rectangle x y w h) = Rectangle (x + mx) (y + my) w h
        tops = map f $ cd c (length dns)
        bottoms = map f [0..length dns]
        f n = mrect (gw * n) (gh * n) rect
        cd n m
          | n > m = (n - 1) : cd (n-1) m
          | otherwise = []

div' :: Integral a => a -> Int -> a
div' _ 0 = 0
div' n o = n `div` fromIntegral o
