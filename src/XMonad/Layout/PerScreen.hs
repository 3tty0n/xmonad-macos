{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.PerScreen (BSD-3-Clause),
-- Copyright (c) Edward Z. Yang and the Xmonad Community.
module XMonad.Layout.PerScreen (PerScreen, ifWider) where
import XMonad.Core
import qualified XMonad.StackSet as W
import Data.Maybe (fromMaybe)

ifWider :: (LayoutClass l1 a, LayoutClass l2 a)
        => Dimension -> l1 a -> l2 a -> PerScreen l1 l2 a
ifWider w = PerScreen w False

data PerScreen l1 l2 a = PerScreen Dimension Bool (l1 a) (l2 a) deriving (Read, Show)

mkNewPerScreenT :: PerScreen l1 l2 a -> Maybe (l1 a) -> PerScreen l1 l2 a
mkNewPerScreenT (PerScreen w _ lt lf) mlt' =
  PerScreen w True (fromMaybe lt mlt') lf

mkNewPerScreenF :: PerScreen l1 l2 a -> Maybe (l2 a) -> PerScreen l1 l2 a
mkNewPerScreenF (PerScreen w _ lt lf) mlf' =
  PerScreen w False lt (fromMaybe lf mlf')

instance (LayoutClass l1 a, LayoutClass l2 a) => LayoutClass (PerScreen l1 l2) a where
  runLayout (W.Workspace i p@(PerScreen w _ lt lf) ms) r
    | rect_width r > w = do
        (wrs, mlt') <- runLayout (W.Workspace i lt ms) r
        pure (wrs, Just $ mkNewPerScreenT p mlt')
    | otherwise = do
        (wrs, mlf') <- runLayout (W.Workspace i lf ms) r
        pure (wrs, Just $ mkNewPerScreenF p mlf')
  handleMessage (PerScreen w bool lt lf) m
    | bool = fmap (\nt -> PerScreen w bool nt lf) <$> handleMessage lt m
    | otherwise = fmap (PerScreen w bool lt) <$> handleMessage lf m
  description (PerScreen _ True l1 _) = description l1
  description (PerScreen _ _ _ l2) = description l2
