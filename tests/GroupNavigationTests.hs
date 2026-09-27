-- Tests for XMonad.Actions.GroupNavigation. Self-contained: it defines its
-- own check and runs against the same XConf/XState harness CoreTests uses.
module GroupNavigationTests (runGroupNavigationTests) where
import XMonad
import qualified XMonad.StackSet as W
import XMonad.MacOS.Engine (initialState)
import XMonad.Actions.GroupNavigation
import qualified Data.Map.Strict as M
import Control.Monad (unless)
import Data.List (sort)

check :: String -> Bool -> IO ()
check name ok = unless ok $ ioError $ userError $ "FAIL: " ++ name

cfg :: XConfig Layout
cfg = def { layoutHook = Layout (layoutHook def), workspaces = ["1","2","3"] }

displays :: [DisplayInfo]
displays = [DisplayInfo 10 (Rectangle 0 24 1000 800)]

initial :: XState
initial = initialState cfg displays

conf :: XConf
conf = XConf cfg

win :: Window -> String -> WindowInfo
win w cls = WindowInfo w 123 cls "com.apple." (show w) 10
              (Rectangle 0 0 100 100) False False "AXStandardWindow"

-- Windows 1, 2 and 3 on workspace "1", focused on 1.
threeState :: XState
threeState = initial
  { windowset = W.focusWindow 1 (foldl (flip W.insertUp) (windowset initial) [1,2,3])
  , windowInfo = M.fromList [(w, win w "Terminal") | w <- [1,2,3]] }

-- The same windows, with 3 moved to the hidden workspace "2" and 1 focused.
splitState :: XState
splitState = threeState
  { windowset = W.focusWindow 1
      (W.shiftWin "2" 3 (windowset threeState))
  , windowInfo = M.fromList [(w, win w "Terminal") | w <- [1,2,3]] }

-- Two window classes: 1 and 2 are "Terminal", 3 is "Safari".
classState :: XState
classState = threeState
  { windowInfo = M.fromList [ (1, win 1 "Terminal")
                            , (2, win 2 "Terminal")
                            , (3, win 3 "Safari") ] }

peekId :: XState -> Maybe Window
peekId = W.peek . windowset

peekX :: X (Maybe Window)
peekX = gets peekId

runGroupNavigationTests :: IO ()
runGroupNavigationTests = do
  -- History: after a sequence of focus changes, nextMatch History walks back
  -- to the most recently focused window.
  (_, back) <- runX conf threeState $ do
    windows (W.focusWindow 1); historyHook
    windows (W.focusWindow 2); historyHook
    nextMatch History (return True)
  check "nextMatch History returns to the previously focused window"
    (peekId back == Just 1)

  -- A window that has been closed is dropped from the history, so the walk
  -- lands on the next live window rather than the deleted one.
  (_, dropped) <- runX conf threeState $ do
    windows (W.focusWindow 1); historyHook
    windows (W.focusWindow 2); historyHook
    windows (W.focusWindow 3); historyHook
    windows (W.focusWindow 1); historyHook
    windows (W.delete 1); historyHook
    nextMatch History (return True)
  check "window history drops a closed window" (peekId dropped == Just 3)

  -- Forward cycles through every window exactly once and wraps back around.
  (visits, _) <- runX conf threeState $ do
    a <- nextMatch Forward (return True) >> peekX
    b <- nextMatch Forward (return True) >> peekX
    c <- nextMatch Forward (return True) >> peekX
    return [a,b,c]
  check "nextMatch Forward visits every window exactly once"
    (sort visits == [Just 1, Just 2, Just 3])
  check "nextMatch Forward wraps back to where it started"
    (last visits == Just 1)
  (_, noMatch) <- runX conf threeState (nextMatch Forward (return False))
  check "nextMatch Forward does nothing when nothing matches"
    (peekId noMatch == Just 1)

  -- nextMatchOrDo runs the alternate action when the query matches nothing.
  (_, orDo) <- runX conf threeState
    (nextMatchOrDo Forward (return False) (windows (W.view "2")))
  check "nextMatchOrDo runs the alternate action when nothing matches"
    (W.currentTag (windowset orDo) == "2")

  -- nextMatchWithThis only cycles through windows whose query value equals
  -- the current window's, skipping the different class.
  (classes, _) <- runX conf classState $ do
    a <- nextMatchWithThis Forward className >> peekX
    b <- nextMatchWithThis Forward className >> peekX
    return [a,b]
  check "nextMatchWithThis skips a window with a different query value"
    (classes == [Just 2, Just 1])

  -- isOnAnyVisibleWS: unfocused windows on a shown workspace match; the
  -- focused window and windows on hidden workspaces do not.
  (visibleFocused, _) <- runX conf splitState (runQuery isOnAnyVisibleWS 1)
  (visibleUnfocused, _) <- runX conf splitState (runQuery isOnAnyVisibleWS 2)
  (hidden, _) <- runX conf splitState (runQuery isOnAnyVisibleWS 3)
  check "isOnAnyVisibleWS rejects the focused window" (not visibleFocused)
  check "isOnAnyVisibleWS accepts an unfocused window on a shown workspace"
    visibleUnfocused
  check "isOnAnyVisibleWS rejects a window on a hidden workspace" (not hidden)
