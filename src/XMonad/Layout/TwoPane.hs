{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.TwoPane (BSD-3-Clause),
-- Copyright (c) Spencer Janssen and the Xmonad Community.
module XMonad.Layout.TwoPane (TwoPane(..)) where
import XMonad.Core
import XMonad.Layout (Resize(..), splitHorizontallyBy)
import qualified XMonad.StackSet as W

-- Master on the left, and one other window on the right: whichever is
-- focused, or the one after the master. The rest are hidden.
data TwoPane a = TwoPane !Rational !Rational deriving (Show,Read)

instance LayoutClass TwoPane a where
  pureLayout (TwoPane _ frac) r s = case reverse (W.up s) of
    (master:_) -> [(master,left),(W.focus s,right)]
    [] -> case W.down s of
      (next:_) -> [(W.focus s,left),(next,right)]
      [] -> [(W.focus s,r)]
    where (left,right) = splitHorizontallyBy frac r
  pureMessage (TwoPane delta frac) m = resize <$> fromMessage m
    where resize Shrink = TwoPane delta (max 0 $ frac-delta)
          resize Expand = TwoPane delta (min 1 $ frac+delta)
  description _ = "TwoPane"
