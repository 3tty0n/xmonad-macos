-- Adapted from xmonad-contrib XMonad.Actions.OnScreen (BSD-3-Clause),
-- Copyright (c) Nils Schweinsberg and the Xmonad Community.
module XMonad.Actions.OnScreen
  ( onScreen, onScreen', Focus(..)
  , viewOnScreen, greedyViewOnScreen, onlyOnScreen
  , toggleOnScreen, toggleGreedyOnScreen
  ) where
import Control.Monad (guard)
import Data.Maybe (fromMaybe)
import XMonad.Core
import XMonad.Operations (windows)
import qualified XMonad.StackSet as W

data Focus
  = FocusNew
  | FocusCurrent
  | FocusTag WorkspaceId
  | FocusTagVisible WorkspaceId

onScreen :: (WindowSet -> WindowSet) -> Focus -> ScreenId -> WindowSet -> WindowSet
onScreen f foc sc st = fromMaybe st $ do
  ws <- W.lookupWorkspace sc st
  let fStack = f $ W.view ws st
  Just $ setFocus foc st fStack

setFocus :: Focus -> WindowSet -> WindowSet -> WindowSet
setFocus FocusNew _ new = new
setFocus FocusCurrent old new =
  case W.lookupWorkspace (W.screen $ W.current old) new of
    Nothing -> new
    Just i -> W.view i new
setFocus (FocusTag i) _ new = W.view i new
setFocus (FocusTagVisible i) old new
  | i `elem` map (W.tag . W.workspace) (W.visible old) = setFocus (FocusTag i) old new
  | otherwise = setFocus FocusCurrent old new

onScreen' :: X () -> Focus -> ScreenId -> X ()
onScreen' x foc sc = do
  st <- gets windowset
  case W.lookupWorkspace sc st of
    Nothing -> pure ()
    Just ws -> do
      windows $ W.view ws
      x
      windows $ setFocus foc st

viewOnScreen :: ScreenId -> WorkspaceId -> WindowSet -> WindowSet
viewOnScreen sid i = onScreen (W.view i) (FocusTag i) sid

greedyViewOnScreen :: ScreenId -> WorkspaceId -> WindowSet -> WindowSet
greedyViewOnScreen sid i = onScreen (W.greedyView i) (FocusTagVisible i) sid

onlyOnScreen :: ScreenId -> WorkspaceId -> WindowSet -> WindowSet
onlyOnScreen sid i = onScreen (W.view i) FocusCurrent sid

toggleOnScreen :: ScreenId -> WorkspaceId -> WindowSet -> WindowSet
toggleOnScreen sid i = onScreen (toggleOrView' W.view i) FocusCurrent sid

toggleGreedyOnScreen :: ScreenId -> WorkspaceId -> WindowSet -> WindowSet
toggleGreedyOnScreen sid i = onScreen (toggleOrView' W.greedyView i) FocusCurrent sid

toggleOrView' :: (WorkspaceId -> WindowSet -> WindowSet) -> WorkspaceId -> WindowSet -> WindowSet
toggleOrView' f i st = fromMaybe (f i st) $ do
  guard $ i == W.tag (W.workspace (W.current st))
  case W.hidden st of
    [] -> Nothing
    (h:_) -> Just $ f (W.tag h) st
