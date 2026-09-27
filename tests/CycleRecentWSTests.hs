-- Tests for XMonad.Actions.CycleRecentWS: the recency order, the portable
-- toggle actions, and unView's order restoration. The held-modifier cyclers
-- are not ported, so this exercises the policy they were built on.
module CycleRecentWSTests (runCycleRecentWSTests) where
import XMonad
import XMonad.Actions.CycleRecentWS
import XMonad.Hooks.WorkspaceHistory (workspaceHistory, workspaceHistoryHook)
import XMonad.MacOS.Engine (initialState)
import qualified XMonad.StackSet as W
import Control.Monad (unless)

check :: String -> Bool -> IO ()
check name ok = unless ok $ ioError $ userError ("FAIL: " ++ name)

cfg :: XConfig Layout
cfg = def { layoutHook = Layout (layoutHook def), workspaces = ["1","2","3"] }

conf :: XConf
conf = XConf cfg

display1 :: DisplayInfo
display1 = DisplayInfo 10 (Rectangle 0 24 1000 800)

-- Workspace tags in stack order: the current screen's workspace first, then
-- the hidden ones. This is what unView is supposed to restore.
tagsOf :: WindowSet -> [WorkspaceId]
tagsOf = map W.tag . W.workspaces

-- Visit 1, 2, 3, recording each as workspace history. The final state shows
-- "3", with "2" then "1" behind it in most-recently-used order.
recencyRun :: XState -> IO (XState, [WorkspaceId])
recencyRun start = do
  (seen, st) <- runX conf start $ do
    workspaceHistoryHook
    windows (W.view "2") >> workspaceHistoryHook
    windows (W.view "3") >> workspaceHistoryHook
    workspaceHistory
  pure (st, seen)

runCycleRecentWSTests :: IO ()
runCycleRecentWSTests = do
  let start = initialState cfg [display1]
  (st, recency) <- recencyRun start
  check "workspace history is most recent first" (recency == ["3","2","1"])
  check "recentWS lists most recent first, with the current workspace last"
    (recentWS (const True) (windowset st) == ["2","1","3"])
  -- Windows only on the hidden "2" and the current "3"; "1" stays empty.
  (_, busy) <- runX conf st $ do
    windows (W.insertUp (1::Window))
    windows (W.view "2")
    windows (W.insertUp (2::Window))
    windows (W.view "3")
  check "a non-empty predicate drops empty workspaces"
    (recentWS (not . null . W.stack) (windowset busy) == ["2","3"])
  -- Toggling follows the recency list, and the stack update keeps it to a pair.
  (_, to1) <- runX conf st toggleRecentWS
  check "toggleRecentWS views the most recent other workspace"
    (W.currentTag (windowset to1) == "2")
  (_, to2) <- runX conf to1 toggleRecentWS
  check "toggleRecentWS returns to the previous workspace"
    (W.currentTag (windowset to2) == "3")
  (_, to3) <- runX conf to2 toggleRecentWS
  check "repeated toggling stops on the same pair"
    (W.currentTag (windowset to3) == "2")
  (_, ne) <- runX conf busy toggleRecentNonEmptyWS
  check "toggleRecentNonEmptyWS skips an empty workspace"
    (W.currentTag (windowset ne) == "2")
  let w0 = windowset st
      restoredV = unView w0 (W.view "2" w0)
      restoredG = unView w0 (W.greedyView "2" w0)
      sameOrder r = tagsOf r == tagsOf w0 && W.currentTag r == W.currentTag w0
  check "unView restores the workspace order after view and greedyView"
    (sameOrder restoredV && sameOrder restoredG)
