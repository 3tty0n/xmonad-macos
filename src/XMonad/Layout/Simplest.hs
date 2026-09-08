{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.Simplest (BSD-3-Clause),
-- Copyright (c) David Roundy and the Xmonad Community.
module XMonad.Layout.Simplest (Simplest(..)) where
import XMonad.Core
import qualified XMonad.StackSet as W

data Simplest a = Simplest deriving (Show,Read)
instance LayoutClass Simplest a where
  pureLayout Simplest r s = [(w,r) | w <- W.integrate s]
  description _ = "Simplest"
