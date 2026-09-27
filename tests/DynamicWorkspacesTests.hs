{-# LANGUAGE FlexibleContexts #-}
module DynamicWorkspacesTests (runDynamicWorkspacesTests) where
import XMonad
import XMonad.Actions.DynamicWorkspaces
import XMonad.MacOS.Engine (initialState)
import qualified XMonad.StackSet as W
import Control.Monad (unless)

check :: String -> Bool -> IO ()
check name ok = unless ok $ ioError $ userError $ "FAIL: " ++ name

-- A small config so "4" and other tags are genuinely new.
cfg :: XConfig Layout
cfg = def { workspaces = ["1", "2", "3"], layoutHook = Layout (layoutHook def) }

displays :: [DisplayInfo]
displays = [ DisplayInfo 10 (Rectangle 0 24 1000 800)
           , DisplayInfo 20 (Rectangle (-1000) 24 1000 800) ]

conf :: XConf
conf = XConf cfg

base :: XState
base = initialState cfg displays

-- The current workspace "1" already has one window on it.
withWindow :: XState
withWindow = base { windowset = W.insertUp 1 (windowset base) }

runDynamicWorkspacesTests :: IO ()
runDynamicWorkspacesTests = do
  (_, added) <- runX conf base (addWorkspace "4")
  check "addWorkspace adds an unseen tag and switches to it"
    (W.tagMember "4" (windowset added) && W.currentTag (windowset added) == "4")

  (_, twice) <- runX conf base (addWorkspace "4" >> addWorkspace "4")
  check "adding an existing workspace is a no-op"
    (length (filter ((== "4") . W.tag) (W.workspaces (windowset twice))) == 1)

  (_, appended) <- runX conf base (appendWorkspace "z")
  check "appendWorkspace adds the tag and views it"
    (W.tagMember "z" (windowset appended) && W.currentTag (windowset appended) == "z")

  (_, removed) <- runX conf withWindow removeWorkspace
  check "removeWorkspace merges its windows into another workspace"
    (W.findTag 1 (windowset removed) == Just "3"
     && not (W.tagMember "1" (windowset removed)))

  (_, kept) <- runX conf withWindow removeEmptyWorkspace
  check "removeEmptyWorkspace keeps a non-empty workspace"
    (W.tagMember "1" (windowset kept) && W.findTag 1 (windowset kept) == Just "1")

  (_, renamed) <- runX conf withWindow (renameWorkspaceByName "renamed")
  check "renameWorkspaceByName renames without losing windows"
    (W.currentTag (windowset renamed) == "renamed"
     && W.findTag 1 (windowset renamed) == Just "renamed"
     && not (W.tagMember "1" (windowset renamed)))

  (_, nth) <- runX conf base (windows (W.view "2") >> withNthWorkspace W.greedyView 0)
  check "withNthWorkspace greedyView 0 views the first sorted workspace"
    (W.currentTag (windowset nth) == "1")

  (_, indexed) <- runX conf base
    (setWorkspaceIndex 5 >> windows (W.view "2") >> withWorkspaceIndex W.greedyView 5)
  check "setWorkspaceIndex / withWorkspaceIndex round-trips"
    (W.currentTag (windowset indexed) == "1")
