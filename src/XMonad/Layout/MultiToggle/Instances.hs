{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.MultiToggle.Instances
-- (BSD-3-Clause), Copyright (c) Lukas Mai and the Xmonad Community.
module XMonad.Layout.MultiToggle.Instances (StdTransformers(..)) where
import XMonad.Core
import XMonad.Layout
import XMonad.Layout.LayoutModifier
import XMonad.Layout.MultiToggle
import XMonad.Layout.NoBorders

data StdTransformers = FULL | NBFULL | MIRROR | NOBORDERS | SMARTBORDERS
  deriving (Read, Show, Eq)

instance Transformer StdTransformers Window where
  transform FULL x k = k Full (const x)
  transform NBFULL x k = k (noBorders Full) (const x)
  transform MIRROR x k = k (Mirror x) (\(Mirror x') -> x')
  transform NOBORDERS x k = k (noBorders x) (\(ModifiedLayout _ x') -> x')
  transform SMARTBORDERS x k = k (smartBorders x) (\(ModifiedLayout _ x') -> x')
