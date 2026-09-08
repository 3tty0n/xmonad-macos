{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.Renamed (BSD-3-Clause),
-- Copyright (c) Adam Vogt and the Xmonad Community. A standalone wrapper
-- rather than a LayoutModifier, which this port does not have.
module XMonad.Layout.Renamed (Rename(..), Renamed, renamed) where
import XMonad.Core
import qualified XMonad.StackSet as W

data Rename = Replace String | Prepend String | Append String
            | CutLeft Int | CutRight Int
  deriving (Show,Read)

data Renamed l a = Renamed [Rename] (l a) deriving (Show,Read)

renamed :: [Rename] -> l a -> Renamed l a
renamed = Renamed

instance LayoutClass l a => LayoutClass (Renamed l) a where
  runLayout (W.Workspace t (Renamed rs l) s) r = do
    (rects,changed) <- runLayout (W.Workspace t l s) r
    pure (rects, Renamed rs <$> changed)
  handleMessage (Renamed rs l) m = fmap (Renamed rs) <$> handleMessage l m
  description (Renamed rs l) = foldl apply (description l) rs
    where
      apply name r = case r of
        Replace new -> new
        Prepend p -> p ++ name
        Append a -> name ++ a
        CutLeft n -> drop n name
        CutRight n -> take (max 0 (length name-n)) name
