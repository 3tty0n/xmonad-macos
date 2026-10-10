module MaximizeMinimizeTests (runMaximizeMinimizeTests) where
import XMonad
import XMonad.Actions.Minimize
import XMonad.Layout.BoringWindows (boringWindows, focusUp)
import XMonad.Layout.Maximize
import XMonad.Layout.Minimize
import XMonad.MacOS.Engine (initialState, makePlan)
import XMonad.MacOS.Protocol (Placement(..), Plan(..))
import XMonad.Operations (sendMessage)
import qualified XMonad.StackSet as W
import Control.Monad (unless)

check :: String -> Bool -> IO ()
check name ok = unless ok $ ioError $ userError $ "FAIL: " ++ name

screen :: Rectangle
screen = Rectangle 0 0 1000 800

stateWith :: Layout Window -> XState
stateWith l = base {windowset = foldr W.insertUp (windowset base) [1,2,3]}
  where
    base = initialState cfg [DisplayInfo 10 screen]
    cfg = def {layoutHook = l, workspaces = ["1"]}

conf :: XConf
conf = XConf (def {layoutHook = Layout (Tall 1 0 0.5 :: Tall Window)})

rects :: X [(Window, Rectangle)]
rects = do
  ws <- gets (W.workspace . W.current . windowset)
  fst <$> runLayout ws screen

runMaximizeMinimizeTests :: IO ()
runMaximizeMinimizeTests = do
  let tallL = Tall 1 (3/100) (1/2) :: Tall Window
      full = Just (Rectangle 25 25 950 750)
  (plain,_) <- runX conf (stateWith (Layout tallL)) rects
  (_,mx) <- runX conf (stateWith (Layout (maximize tallL))) $
    sendMessage (maximizeRestore 2)
  (maxed,_) <- runX conf mx rects
  check "maximize pads the target and lists it last"
    (lookup 2 maxed == full && fst (last maxed) == 2 && length maxed == 3)
  check "maximize leaves the others where they were"
    (filter ((/= 2) . fst) maxed == filter ((/= 2) . fst) plain)
  (_,mx') <- runX conf mx $ sendMessage (maximizeRestore 2)
  (restored,_) <- runX conf mx' rects
  check "maximizeRestore on the target restores" (restored == plain)
  (_,mx2) <- runX conf mx $ sendMessage (maximizeRestore 1)
  (moved,_) <- runX conf mx2 rects
  check "maximizeRestore on another window moves the maximization"
    (lookup 1 moved == full)
  (_,pad) <- runX conf (stateWith (Layout (maximizeWithPadding 0 tallL))) $
    sendMessage (maximizeRestore 3)
  (padded,_) <- runX conf pad rects
  check "maximizeWithPadding 0 fills the screen" (lookup 3 padded == Just screen)

  let st = stateWith (Layout (boringWindows (minimize tallL)))
  (_,mn) <- runX conf st $ minimizeWindow 3
  check "minimizing the focused window moves focus on"
    (W.peek (windowset mn) /= Just 3)
  (plan,_) <- runX conf mn makePlan
  check "a minimized window is hidden by the plan"
    (3 `elem` planHide plan
     && null [() | Placement 3 _ <- planFrames plan])
  (laid,_) <- runX conf mn rects
  check "minimized windows leave the layout"
    (all ((/= 3) . fst) laid && length laid == 2)
  (stk,_) <- runX conf mn $ withMinimized pure
  check "withMinimized lists the minimized window" (stk == [3])
  (_,mn2) <- runX conf mn $ minimizeWindow 1
  (order,_) <- runX conf mn2 $
    (,) <$> withLastMinimized' pure <*> withFirstMinimized' pure
  check "last and first minimized follow minimize order"
    (order == (Just 1, Just 3))
  (_,mn3) <- runX conf mn2 $ withLastMinimized maximizeWindow
  (afterLast,_) <- runX conf mn3 $ withMinimized pure
  check "withLastMinimized restores the most recent" (afterLast == [3])
  (_,mn4) <- runX conf mn2 $ sendMessage RestoreNextMinimizedWin
  (afterNext,_) <- runX conf mn4 $ withMinimized pure
  check "RestoreNextMinimizedWin restores the most recent" (afterNext == [3])
  (_,mn5) <- runX conf mn $ maximizeWindowAndFocus 3
  check "maximizeWindowAndFocus restores and focuses"
    (W.peek (windowset mn5) == Just 3)
  (back,_) <- runX conf mn5 rects
  check "a restored window returns to the layout" (length back == 3)
  (_,walk) <- runX conf mn $ focusUp >> focusUp >> focusUp
  check "BoringWindows skips minimized windows"
    (W.peek (windowset walk) /= Just 3)
