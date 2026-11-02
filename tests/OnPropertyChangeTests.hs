-- Tests for XMonad.Hooks.OnPropertyChange: two snapshots, one changed title.
module OnPropertyChangeTests (runOnPropertyChangeTests) where
import XMonad
import qualified XMonad.StackSet as W
import XMonad.MacOS.Engine (initialState, reconcile)
import XMonad.MacOS.Protocol (Snapshot(..))
import XMonad.Hooks.OnPropertyChange
import XMonad.Hooks.DynamicProperty (dynamicTitle)
import Control.Monad (unless)

check :: String -> Bool -> IO ()
check name ok = unless ok $ ioError $ userError $ "FAIL: " ++ name

base :: XConfig Layout
base = def { layoutHook = Layout (layoutHook def), workspaces = ["1","2"] }

displays :: [DisplayInfo]
displays = [DisplayInfo 10 (Rectangle 0 24 1000 800)]

win :: Window -> String -> String -> WindowInfo
win w cls t = WindowInfo w 1 cls ("bundle." ++ cls) t 10
                (Rectangle 0 0 100 100) False False "AXStandardWindow" False

snap :: Int -> [WindowInfo] -> Snapshot
snap g ws = Snapshot g 1 displays ws Nothing Nothing

shiftTitled :: ManageHook
shiftTitled = (title =? "Chat") --> doShift "2"

tagOf :: Window -> XState -> Maybe WorkspaceId
tagOf w = W.findTag w . windowset

run :: XConfig Layout -> [Snapshot] -> IO XState
run c ss = snd <$> runX (XConf c) (initialState c displays) (mapM_ reconcile ss)

runOnPropertyChangeTests :: IO ()
runOnPropertyChangeTests = do
  let c = onTitleChange shiftTitled base
      first = snap 0 [win 1 "Safari" "Home"]
  moved <- run c [first, snap 1 [win 1 "Safari" "Chat"]]
  check "title change runs the hook on the window" (tagOf 1 moved == Just "2")
  still <- run c [first, snap 1 [win 1 "Safari" "Home"]]
  check "an unchanged title does not run the hook" (tagOf 1 still == Just "1")
  fresh <- run c [snap 0 [win 1 "Safari" "Chat"]]
  check "a window's first title is left to manageHook" (tagOf 1 fresh == Just "1")
  legacy <- run (dynamicTitle shiftTitled base)
              [first, snap 1 [win 1 "Safari" "Chat"]]
  check "dynamicTitle matches onTitleChange" (tagOf 1 legacy == Just "2")
  cls <- run (onClassChange (className =? "Mail" --> doShift "2") base)
           [first, snap 1 [win 1 "Mail" "Home"]]
  check "class change runs the hook" (tagOf 1 cls == Just "2")
  titleOnly <- run (onClassChange (doShift "2") base)
                 [first, snap 1 [win 1 "Safari" "Chat"]]
  check "class hook ignores a title change" (tagOf 1 titleOnly == Just "1")
  other <- run (onXPropertyChange "_NET_WM_NAME" shiftTitled base)
             [first, snap 1 [win 1 "Safari" "Chat"]]
  check "_NET_WM_NAME is a title change" (tagOf 1 other == Just "2")
