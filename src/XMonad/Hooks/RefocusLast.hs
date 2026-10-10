{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Hooks.RefocusLast (BSD-3-Clause),
-- Copyright (c) 2018 L. S. Leary and the Xmonad Community.
-- There is no X11 event stream, so refocusLastWhen is a logHook rather than an
-- event hook. A closed window is already gone from the window set by then, so
-- the predicate is evaluated on each workspace's focused window on every pass
-- and the last verdict is used when that window disappears. It records the
-- recents itself: use it instead of refocusLastLogHook, not together with
-- refocusLastLayoutHook, which would record the new focus first.
module XMonad.Hooks.RefocusLast
  ( refocusLastLogHook, refocusLastLayoutHook, refocusLastWhen
  , refocusingIsActive, isFloat
  , toggleRefocusing, toggleFocus, swapWithLast, refocusWhen, shiftRLWhen
  , updateRecentsOn
  , RecentWins(..), RecentsMap(..), RefocusLastLayoutHook(..)
  , RefocusLastToggle(..)
  , withRecentsIn
  ) where
import Control.Monad (forM_, when)
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import XMonad.Core
import XMonad.Layout.LayoutModifier
import XMonad.Operations (windows, withWindowSet)
import qualified XMonad.StackSet as W
import qualified XMonad.Util.ExtensibleState as XS

data RecentWins = Recent { previous :: !Window, current :: !Window }
  deriving (Show, Read, Eq)

newtype RecentsMap = RecentsMap (M.Map WorkspaceId RecentWins)
  deriving (Show, Read, Eq)

instance ExtensionClass RecentsMap where
  initialValue = RecentsMap M.empty
  extensionType = PersistentExtension

data RefocusLastLayoutHook a = RefocusLastLayoutHook
  deriving (Show, Read)

instance LayoutModifier RefocusLastLayoutHook a where
  modifyLayout _ w@(W.Workspace tg _ _) r = updateRecentsOn tg >> runLayout w r

newtype RefocusLastToggle = RefocusLastToggle { refocusing :: Bool }
  deriving (Show, Read, Eq)

instance ExtensionClass RefocusLastToggle where
  initialValue = RefocusLastToggle { refocusing = True }
  extensionType = PersistentExtension

-- The predicate's last verdict on each workspace's focused window.
newtype Verdicts = Verdicts (M.Map WorkspaceId Bool)

instance ExtensionClass Verdicts where
  initialValue = Verdicts M.empty

refocusLastLogHook :: X ()
refocusLastLogHook = withWindowSet (updateRecentsOn . W.currentTag)

refocusLastLayoutHook :: l a -> ModifiedLayout RefocusLastLayoutHook l a
refocusLastLayoutHook = ModifiedLayout RefocusLastLayoutHook

-- Add to the logHook. When the recorded focused window of a visible workspace
-- has been closed and the predicate held for it, focus the previous one.
refocusLastWhen :: Query Bool -> X ()
refocusLastWhen p = do
  ws <- gets windowset
  let visibleTags = map (W.tag . W.workspace) (W.current ws : W.visible ws)
  Verdicts verdicts <- XS.get
  forM_ visibleTags $ \tag ->
    withRecentsIn tag () $ \lw cw ->
      when (W.findTag cw ws == Nothing && M.findWithDefault False tag verdicts) $
        focusPrevious tag lw
  ws' <- gets windowset
  new <- mapM (\tag -> do
                 b <- maybe (pure False) (runQuery p) (W.peek (W.view tag ws'))
                 pure (tag, b)) visibleTags
  XS.put (Verdicts (M.fromList new))
  mapM_ updateRecentsOn visibleTags

focusPrevious :: WorkspaceId -> Window -> X ()
focusPrevious tag lw = do
  ws <- gets windowset
  let ws' = tryFocusIn tag [lw] ws
  when (W.peek ws' /= W.peek ws) $ modify $ \s ->
    let n = nextActionId s + 1
    in s { windowset = ws'
         , nextActionId = if tag == W.currentTag ws then n else nextActionId s
         , pendingFocus = if tag == W.currentTag ws
                            then (,) n <$> W.peek ws' else pendingFocus s }

refocusingIsActive :: Query Bool
refocusingIsActive = liftX (XS.gets refocusing)

isFloat :: Query Bool
isFloat = ask >>= \w -> liftX (gets (M.member w . W.floating . windowset))

toggleRefocusing :: X ()
toggleRefocusing = XS.modify (RefocusLastToggle . not . refocusing)

toggleFocus :: X ()
toggleFocus = withRecents $ \lw cw ->
  when (cw /= lw) . windows $ tryFocus [lw]

swapWithLast :: X ()
swapWithLast = withRecents $ \lw cw ->
  when (cw /= lw) . windows . W.modify' $ \st ->
    let swap w | w == lw = cw
               | w == cw = lw
               | otherwise = w
    in W.Stack (swap (W.focus st)) (map swap (W.up st)) (map swap (W.down st))

refocusWhen :: Query Bool -> WorkspaceId -> X (WindowSet -> WindowSet)
refocusWhen p tag = withRecentsIn tag id $ \lw cw -> do
  b <- runQuery p cw
  pure (if b then tryFocusIn tag [cw, lw] else id)

shiftRLWhen :: Query Bool -> WorkspaceId -> X (WindowSet -> WindowSet)
shiftRLWhen p to = withWindowSet $ \ws -> do
  refocus <- refocusWhen p (W.currentTag ws)
  let shift = maybe id (W.shiftWin to) (W.peek ws)
  pure (refocus . shift)

updateRecentsOn :: WorkspaceId -> X ()
updateRecentsOn tag = withWindowSet $ \ws ->
  whenJust (W.peek $ W.view tag ws) $ \fw -> do
    RecentsMap m <- XS.get
    let insertRecent l c = XS.put . RecentsMap $ M.insert tag (Recent l c) m
    case M.lookup tag m of
      Just (Recent _ cw) -> when (cw /= fw) (insertRecent cw fw)
      Nothing -> insertRecent fw fw

tryFocus :: [Window] -> WindowSet -> WindowSet
tryFocus wins = W.modify' $ \s ->
  fromMaybe s (firstJust [focusIn w s | w <- wins])

tryFocusIn :: WorkspaceId -> [Window] -> WindowSet -> WindowSet
tryFocusIn tag wins ws =
  W.view (W.currentTag ws) . tryFocus wins . W.view tag $ ws

focusIn :: Window -> W.Stack Window -> Maybe (W.Stack Window)
focusIn w s
  | w `elem` W.integrate s = Just (until ((== w) . W.focus) W.focusDown' s)
  | otherwise = Nothing

firstJust :: [Maybe a] -> Maybe a
firstJust xs = case [x | Just x <- xs] of
  x:_ -> Just x
  [] -> Nothing

withRecentsIn :: WorkspaceId -> a -> (Window -> Window -> X a) -> X a
withRecentsIn tag dflt f = do
  RecentsMap m <- XS.get
  maybe (pure dflt) (\(Recent lw cw) -> f lw cw) (M.lookup tag m)

withRecents :: (Window -> Window -> X ()) -> X ()
withRecents f = withWindowSet $ \ws -> withRecentsIn (W.currentTag ws) () f
