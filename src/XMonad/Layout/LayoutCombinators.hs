-- Adapted from xmonad-contrib XMonad.Layout.LayoutCombinators (BSD-3-Clause),
-- Copyright (c) David Roundy and the Xmonad Community.
-- Combo/DragPane combinators are not ported; this module re-exports the
-- Choose combinator and JumpToLayout, which is what most configs import it for.
module XMonad.Layout.LayoutCombinators
  ( (|||)
  , JumpToLayout(..)
  , NewSelect
  ) where
import XMonad.Layout (Choose, JumpToLayout(..), (|||))

type NewSelect = Choose
{-# DEPRECATED NewSelect "Use Choose instead." #-}
