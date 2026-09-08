{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.PerWorkspace (BSD-3-Clause),
-- Copyright (c) Brent Yorgey and the Xmonad Community.
module XMonad.Layout.PerWorkspace (PerWorkspace, onWorkspace, onWorkspaces) where
import XMonad.Core
import qualified XMonad.StackSet as W

-- The first layout on the listed workspaces, the second everywhere else.
data PerWorkspace l1 l2 a = PerWorkspace [WorkspaceId] (l1 a) (l2 a)
  deriving (Show,Read)

onWorkspace :: WorkspaceId -> l1 a -> l2 a -> PerWorkspace l1 l2 a
onWorkspace t = PerWorkspace [t]

onWorkspaces :: [WorkspaceId] -> l1 a -> l2 a -> PerWorkspace l1 l2 a
onWorkspaces = PerWorkspace

instance (LayoutClass l1 a, LayoutClass l2 a)
    => LayoutClass (PerWorkspace l1 l2) a where
  runLayout (W.Workspace t p@(PerWorkspace ts l1 l2) s) r
    | t `elem` ts = do
        (rects,changed) <- runLayout (W.Workspace t l1 s) r
        pure (rects, (\l -> PerWorkspace ts l l2) <$> changed)
    | otherwise = do
        (rects,changed) <- runLayout (W.Workspace t l2 s) r
        pure (rects, PerWorkspace ts l1 <$> changed)
    where _ = p
  -- A message goes to both, so the layout that is not showing keeps up.
  handleMessage (PerWorkspace ts l1 l2) m = do
    m1 <- handleMessage l1 m
    m2 <- handleMessage l2 m
    pure $ case (m1,m2) of
      (Nothing,Nothing) -> Nothing
      _ -> Just (PerWorkspace ts (maybe l1 id m1) (maybe l2 id m2))
  description (PerWorkspace _ _ l2) = description l2
