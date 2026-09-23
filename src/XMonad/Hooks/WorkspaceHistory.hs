-- Adapted from xmonad-contrib XMonad.Hooks.WorkspaceHistory (BSD-3-Clause),
-- Copyright (c) 2013 Dmitri Iouchtchenko and the Xmonad Community.
module XMonad.Hooks.WorkspaceHistory
  ( workspaceHistoryHook, workspaceHistoryHookExclude
  , workspaceHistory, workspaceHistoryByScreen, workspaceHistoryWithScreen
  , workspaceHistoryTransaction, workspaceHistoryModify
  ) where
import Data.List (delete, find, sort)
import Data.Containers.ListUtils (nubOrd)
import XMonad.Core
import qualified XMonad.StackSet as W
import qualified XMonad.Util.ExtensibleState as XS

newtype WorkspaceHistory = WorkspaceHistory
  { history :: [(ScreenId, WorkspaceId)] } deriving (Read, Show)

instance ExtensionClass WorkspaceHistory where
  initialValue = WorkspaceHistory []
  extensionType = PersistentExtension

-- Record the workspace on each screen; add it to the logHook.
workspaceHistoryHook :: X ()
workspaceHistoryHook = workspaceHistoryHookExclude []

workspaceHistoryHookExclude :: [WorkspaceId] -> X ()
workspaceHistoryHookExclude ws = do
  s <- gets windowset
  XS.modify $ \h -> WorkspaceHistory $
    filter ((`notElem` ws) . snd) $ history (updateLastActiveOnEachScreen s h)

-- Most recent first, without duplicates.
workspaceHistory :: X [WorkspaceId]
workspaceHistory = XS.gets $ nubOrd . map snd . history

workspaceHistoryByScreen :: X [(ScreenId, [WorkspaceId])]
workspaceHistoryByScreen = XS.gets $ \(WorkspaceHistory h) ->
  [(sc,[t | (s,t) <- h, s == sc]) | sc <- sort (nubOrd (map fst h))]

workspaceHistoryWithScreen :: X [(ScreenId, WorkspaceId)]
workspaceHistoryWithScreen = XS.gets history

-- Run an action, recording only where it ends up, not the steps between.
workspaceHistoryTransaction :: X () -> X ()
workspaceHistoryTransaction action = do
  start <- XS.gets history
  action
  s <- gets windowset
  XS.put $ updateLastActiveOnEachScreen s (WorkspaceHistory start)

workspaceHistoryModify :: ([(ScreenId, WorkspaceId)] -> [(ScreenId, WorkspaceId)]) -> X ()
workspaceHistoryModify f = XS.modify $ WorkspaceHistory . f . history

updateLastActiveOnEachScreen :: WindowSet -> WorkspaceHistory -> WorkspaceHistory
updateLastActiveOnEachScreen ws wh = WorkspaceHistory $
  entry cur (foldl lastForScreen (history wh) (W.visible ws ++ [cur]))
  where
    cur = W.current ws
    entry sc h = let e = (W.screen sc, W.tag (W.workspace sc)) in e : delete e h
    lastForScreen h sc
      | find ((== W.screen sc) . fst) h == Just (W.screen sc, W.tag (W.workspace sc)) = h
      | otherwise = entry sc h
