-- Adapted from xmonad-contrib XMonad.Actions.WindowGo (public domain).
-- Browser/editor helpers that read $BROWSER/$EDITOR via Prompt.Shell are not
-- ported.
module XMonad.Actions.WindowGo
  ( raise, raiseNext, runOrRaise, runOrRaiseNext
  , raiseMaybe, raiseNextMaybe, raiseNextMaybeCustomFocus
  , runOrRaiseAndDo, runOrRaiseMaster, raiseAndDo, raiseMaster
  , ifWindows, ifWindow, raiseHook
  ) where
import Control.Monad (filterM)
import Data.List (nub, sortBy)
import XMonad.Core
import XMonad.ManageHook
import XMonad.Operations (spawn, windows, withWindowSet)
import qualified XMonad.StackSet as W

workspacesSorted :: Ord i => W.StackSet i l a s sd -> [W.Workspace i l a]
workspacesSorted s = sortBy (\u t -> W.tag u `compare` W.tag t) $ W.workspaces s

allWindowsSorted :: (Ord i, Eq a) => W.StackSet i l a s sd -> [a]
allWindowsSorted = nub . concatMap (W.integrate' . W.stack) . workspacesSorted

ifWindows :: Query Bool -> ([Window] -> X ()) -> X () -> X ()
ifWindows qry f el = withWindowSet $ \wins -> do
  matches <- filterM (runQuery qry) $ allWindowsSorted wins
  case matches of
    [] -> el
    ws -> f ws

ifWindow :: Query Bool -> ManageHook -> X () -> X ()
ifWindow qry mh = ifWindows qry $ \ws ->
  case ws of
    (w:_) -> windows . appEndo =<< runQuery mh w
    [] -> pure ()

raiseHook :: ManageHook
raiseHook = ask >>= doF . W.focusWindow

raiseMaybe :: X () -> Query Bool -> X ()
raiseMaybe f qry = ifWindow qry raiseHook f

raise :: Query Bool -> X ()
raise = raiseMaybe (pure ())

runOrRaise :: String -> Query Bool -> X ()
runOrRaise cmd = raiseMaybe (spawn cmd)

raiseNextMaybeCustomFocus :: (Window -> WindowSet -> WindowSet) -> X () -> Query Bool -> X ()
raiseNextMaybeCustomFocus focusFn f qry = flip (ifWindows qry) f $ \ws -> do
  foc <- withWindowSet (pure . W.peek)
  case foc of
    Just w | w `elem` ws ->
      let rest = drop 1 $ dropWhile (/= w) (cycle ws)
      in case rest of
           (y:_) -> windows $ focusFn y
           [] -> windows $ focusFn w
    _ -> case ws of
           (w:_) -> windows $ focusFn w
           [] -> pure ()

raiseNextMaybe :: X () -> Query Bool -> X ()
raiseNextMaybe = raiseNextMaybeCustomFocus W.focusWindow

raiseNext :: Query Bool -> X ()
raiseNext = raiseNextMaybe (pure ())

runOrRaiseNext :: String -> Query Bool -> X ()
runOrRaiseNext cmd = raiseNextMaybe (spawn cmd)

raiseAndDo :: X () -> Query Bool -> (Window -> X ()) -> X ()
raiseAndDo f qry after = ifWindow qry (afterRaise `mappend` raiseHook) f
  where afterRaise = ask >>= (>> idHook) . liftX . after

runOrRaiseAndDo :: String -> Query Bool -> (Window -> X ()) -> X ()
runOrRaiseAndDo cmd = raiseAndDo (spawn cmd)

raiseMaster :: X () -> Query Bool -> X ()
raiseMaster raisef thatUserQuery = raiseAndDo raisef thatUserQuery (\_ -> windows W.swapMaster)

runOrRaiseMaster :: String -> Query Bool -> X ()
runOrRaiseMaster run query = runOrRaiseAndDo run query (\_ -> windows W.swapMaster)
