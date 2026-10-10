-- Tests for XMonad.Hooks.RefocusLast: closing the focused window returns
-- focus to the previously focused one, a predicate can opt windows out, and
-- the manual toggle and swap actions follow the same record.
module RefocusLastTests (runRefocusLastTests) where
import XMonad
import XMonad.Hooks.RefocusLast
import XMonad.MacOS.Protocol (Plan(..))
import XMonad.MacOS.Engine (initialState, makePlan)
import XMonad.Operations (windows)
import qualified XMonad.StackSet as W
import Control.Monad (unless, void)

check :: String -> Bool -> IO ()
check name ok = unless ok $ ioError $ userError ("FAIL: " ++ name)

cfgWith :: X () -> XConfig Layout
cfgWith hook = def
  { layoutHook = Layout (layoutHook def)
  , workspaces = ["1","2"], logHook = hook }

display1 :: DisplayInfo
display1 = DisplayInfo 10 (Rectangle 0 24 1000 800)

-- Windows 1, 2, 3 on workspace "1"; 3 is focused.
startWith :: XConfig Layout -> XState
startWith c = let s = initialState c [display1]
  in s { windowset = foldl (flip W.insertUp) (windowset s) [1,2,3::Window] }

focusOf :: XState -> Maybe Window
focusOf = W.peek . windowset

closing :: Window -> XState -> XState
closing w s = s { windowset = W.delete w (windowset s) }

-- Visit 1, then 3 again: the stack is 3 2 1, focus 3, previous 1.
visited :: XConf -> XState -> IO XState
visited conf s = snd <$> runX conf s
  (pass >> windows (W.focusWindow 1) >> pass >> windows (W.focusWindow 3) >> pass)
  where pass = void makePlan

runRefocusLastTests :: IO ()
runRefocusLastTests = do
  let c = cfgWith (refocusLastWhen (pure True))
      conf = XConf c
  s1 <- visited conf (startWith c)
  check "focus follows the requests" (focusOf s1 == Just 3)
  check "plain deletion would not pick the previous window"
    (focusOf (closing 3 s1) /= Just 1)
  (plan, s2) <- runX conf (closing 3 s1) makePlan
  check "closing the focused window refocuses the previous one"
    (focusOf s2 == Just 1)
  check "the helper is asked to focus it" (planFocus plan == Just 1)
  (_, s3) <- runX conf (closing 2 s1) makePlan
  check "closing an unfocused window keeps focus" (focusOf s3 == Just 3)

  let c2 = cfgWith (refocusLastWhen (pure False))
      conf2 = XConf c2
  t1 <- visited conf2 (startWith c2)
  (_, t2) <- runX conf2 (closing 3 t1) makePlan
  check "a rejected window leaves the stack neighbour focused"
    (focusOf t2 == focusOf (closing 3 t1))

  let cf = cfgWith (refocusLastWhen isFloat)
  f1 <- visited (XConf cf) (startWith cf)
  let floated = f1 { windowset = W.float 3 (W.RationalRect 0 0 1 1) (windowset f1) }
  (_, f2) <- runX (XConf cf) floated (windows (W.focusWindow 3) >> makePlan >> pure ())
  (_, f3) <- runX (XConf cf) f2 (windows (W.delete 3) >> makePlan >> pure ())
  check "a closed float refocuses the previous window" (focusOf f3 == Just 1)
  (_, f4) <- runX (XConf cf) f1 (windows (W.delete 3) >> makePlan >> pure ())
  check "a closed tiled window is not refocused under isFloat"
    (focusOf f4 /= Just 1)
  (isf, _) <- runX conf s1 (runQuery isFloat 3)
  check "isFloat is false for a tiled window" (not isf)
  (isf2, _) <- runX conf s1
    (windows (W.float 3 (W.RationalRect 0 0 1 1)) >> runQuery isFloat 3)
  check "isFloat is true for a floating window" isf2
  (act, _) <- runX conf s1 (runQuery refocusingIsActive 3)
  (off, _) <- runX conf s1 (toggleRefocusing >> runQuery refocusingIsActive 3)
  check "toggleRefocusing flips refocusingIsActive" (act && not off)

  (_, shifted) <- runX conf s1 $
    shiftRLWhen (pure True) "2" >>= windows
  check "shiftRLWhen moves the window and refocuses the previous one"
    (focusOf shifted == Just 1 && W.findTag 3 (windowset shifted) == Just "2")
  (_, shifted') <- runX conf s1 $
    shiftRLWhen (pure False) "2" >>= windows
  check "shiftRLWhen with a false predicate shifts like W.shift"
    (focusOf shifted' == Just 2)

  let lc = def { layoutHook = Layout (refocusLastLayoutHook (layoutHook def))
               , workspaces = ["1","2"] }
  l1 <- visited (XConf lc) (startWith lc)
  (_, l2) <- runX (XConf lc) l1 toggleFocus
  check "the layout hook records recents for toggleFocus" (focusOf l2 == Just 1)

  (_, g1) <- runX conf s1 toggleFocus
  check "toggleFocus focuses the previous window" (focusOf g1 == Just 1)
  (_, w1) <- runX conf s1 swapWithLast
  check "swapWithLast exchanges the windows under the focus position"
    (focusOf w1 == Just 1
     && W.index (windowset w1) == swapped (W.index (windowset s1)))
  where swapped = map (\x -> case x of 1 -> 3; 3 -> 1; y -> y)
