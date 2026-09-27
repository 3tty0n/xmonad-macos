-- Adapted from xmonad-contrib XMonad.Actions.CycleRecentWS (BSD-3-Clause),
-- Copyright (c) Michal Janeczek and the Xmonad Community.
-- The held-modifier cyclers (cycleWindowSets and the cycleRecentWS /
-- cycleRecentNonEmptyWS wrappers) are not ported: they run a blocking
-- keyboard grab that only concludes when the invoking modifier is released,
-- and the macOS helper reports pressed keys, not modifier releases. A config
-- that used them should bind toggleRecentWS instead. recentWS, unView and
-- toggleWindowSets are the portable policy underneath those actions; unView is
-- exported here so it can be tested directly.
module XMonad.Actions.CycleRecentWS
  ( recentWS, unView
  , toggleRecentWS, toggleRecentNonEmptyWS, toggleWindowSets
  ) where
import XMonad.Core
import XMonad.Operations (windows)
import qualified XMonad.StackSet as W
import Data.Function (on)

-- | Switch to the most recent workspace. The stack of most recently used
-- workspaces is updated, so repeated use toggles between a pair of workspaces.
toggleRecentWS :: X ()
toggleRecentWS = toggleWindowSets $ recentWS (const True)

-- | Like 'toggleRecentWS', but restricted to non-empty workspaces.
toggleRecentNonEmptyWS :: X ()
toggleRecentNonEmptyWS = toggleWindowSets $ recentWS (not . null . W.stack)

-- | Given a predicate @p@ and the current 'WindowSet' @w@, create a
-- list of workspaces to choose from. They are ordered by recency and
-- have to satisfy @p@.
recentWS :: (WindowSpace -> Bool) -- ^ A workspace predicate.
         -> WindowSet             -- ^ The current WindowSet
         -> [WorkspaceId]
recentWS p w = map W.tag
             $ filter p
             $ map W.workspace (W.visible w)
               ++ W.hidden w
               ++ [W.workspace (W.current w)]

-- | Given an old and a new 'WindowSet', which is __exactly__ one
-- 'view' away from the old one, restore the workspace order of the
-- former inside of the latter. This respects any new state that the
-- new 'WindowSet' may have accumulated.
unView :: (Eq i, Eq s)
       => W.StackSet i l a s sd -> W.StackSet i l a s sd -> W.StackSet i l a s sd
unView w0 w1 = fixOrderH . fixOrderV . view' (W.currentTag w0) $ w1
 where
  view' = if W.screen (W.current w0) == W.screen (W.current w1)
            then W.greedyView else W.view
  fixOrderV w | v : vs <- W.visible w =
                  w { W.visible = insertAt (pfxV (W.visible w0) vs) v vs }
              | otherwise = w
  fixOrderH w | h : hs <- W.hidden w =
                  w { W.hidden = insertAt (pfxH (W.hidden w0) hs) h hs }
              | otherwise = w
  pfxV = commonPrefix `on` fmap (W.tag . W.workspace)
  pfxH = commonPrefix `on` fmap W.tag

  insertAt n x xs = let (l, r) = splitAt n xs in l ++ [x] ++ r

  commonPrefix a b = length $ takeWhile id $ zipWith (==) a b

-- | Given some function that generates a list of workspaces from a
-- given 'WindowSet', switch to the first generated workspace.
toggleWindowSets :: (WindowSet -> [WorkspaceId]) -> X ()
toggleWindowSets genOptions = do
  options <- gets $ genOptions . windowset
  case options of
    []  -> pure ()
    o:_ -> windows (W.view o)
