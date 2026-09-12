{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.IfMax (BSD-3-Clause),
-- Copyright (c) Ilya Portnov and the Xmonad Community.
module XMonad.Layout.IfMax (IfMax(..), ifMax) where
import Control.Arrow ((&&&))
import Data.List ((\\))
import Data.Maybe (fromMaybe, isNothing)
import qualified Data.Map.Strict as M
import XMonad.Core
import XMonad.Operations (withWindowSet)
import qualified XMonad.StackSet as W

data IfMax l1 l2 w = IfMax Int (l1 w) (l2 w) deriving (Read, Show)

instance (LayoutClass l1 Window, LayoutClass l2 Window) => LayoutClass (IfMax l1 l2) Window where
  runLayout (W.Workspace wname (IfMax n l1 l2) s) rect = withWindowSet $ \ws ->
    arrange (W.integrate' s) (M.keys . W.floating $ ws)
    where
      arrange wins fw
        | length (wins \\ fw) <= n = do
            (wrs, ml1') <- runLayout (W.Workspace wname l1 s) rect
            let l1' = fromMaybe l1 ml1'
            l2' <- fromMaybe l2 <$> handleMessage l2 (SomeMessage Hide)
            pure (wrs, Just $ IfMax n l1' l2')
        | otherwise = do
            (wrs, ml2') <- runLayout (W.Workspace wname l2 s) rect
            l1' <- fromMaybe l1 <$> handleMessage l1 (SomeMessage Hide)
            let l2' = fromMaybe l2 ml2'
            pure (wrs, Just $ IfMax n l1' l2')
  handleMessage (IfMax n l1 l2) m | Just ReleaseResources <- fromMessage m = do
    l1' <- handleMessage l1 (SomeMessage ReleaseResources)
    l2' <- handleMessage l2 (SomeMessage ReleaseResources)
    if isNothing l1' && isNothing l2'
      then pure Nothing
      else pure $ Just $ IfMax n (fromMaybe l1 l1') (fromMaybe l2 l2')
  handleMessage (IfMax n l1 l2) m = do
    (allWindows, floatingWindows) <- gets
      ((W.integrate' . W.stack . W.workspace . W.current &&& M.keys . W.floating) . windowset)
    if length (allWindows \\ floatingWindows) <= n
      then fmap (flip (IfMax n) l2) <$> handleMessage l1 m
      else fmap (IfMax n l1) <$> handleMessage l2 m
  description (IfMax n l1 l2) =
    "If number of windows is <= " ++ show n ++ ", then " ++ description l1 ++ ", else " ++ description l2

ifMax :: (LayoutClass l1 w, LayoutClass l2 w) => Int -> l1 w -> l2 w -> IfMax l1 l2 w
ifMax = IfMax
