{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.Dishes (BSD-3-Clause),
-- Copyright (c) Jeremy Apthorp and the Xmonad Community.
module XMonad.Layout.Dishes (Dishes(..)) where
import XMonad.Core
import XMonad.Layout (IncMasterN(..), splitHorizontally, splitVertically, splitVerticallyBy)
import qualified XMonad.StackSet as W

data Dishes a = Dishes Int Rational deriving (Show, Read)

instance LayoutClass Dishes a where
  pureLayout (Dishes nmaster h) r s = zip (W.integrate s) (dishes h r nmaster (length (W.integrate s)))
  pureMessage (Dishes nmaster h) m = incmastern <$> fromMessage m
    where incmastern (IncMasterN d) = Dishes (max 0 (nmaster+d)) h
  description _ = "Dishes"

dishes :: Rational -> Rectangle -> Int -> Int -> [Rectangle]
dishes h s nmaster n
  | n <= nmaster = splitHorizontally n s
  | otherwise = splitHorizontally nmaster m ++ splitVertically (n - nmaster) rest
  where (m,rest) = splitVerticallyBy (1 - fromIntegral (n - nmaster) * h) s
