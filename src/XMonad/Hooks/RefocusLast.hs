{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Hooks.RefocusLast (BSD-3-Clause),
-- Copyright (c) 2018 Tim Schwartz and the Xmonad Community.
-- Closing is observed from the helper's snapshots, so the layout hook checks
-- each workspace on every layout pass: when the window recorded as focused is
-- gone, the previously focused one is focused instead of the stack neighbour.
-- Recents hold window ids, so they are not kept across a restart.
module XMonad.Hooks.RefocusLast
  ( refocusLastLogHook, refocusLastLayoutHook, refocusLastWhen, isFloat
  , toggleFocus, swapWithLast
  , RecentWins(..), RecentsMap(..), RefocusLastLayoutHook
  ) where
import qualified Data.Map.Strict as M
import XMonad.Core
import XMonad.Layout.LayoutModifier
import XMonad.Operations (modifyWindowSet, windows)
import qualified XMonad.StackSet as W
import qualified XMonad.Util.ExtensibleState as XS

-- The focused window of a workspace and the one focused before it.
data RecentWins = Empty | Single !Window | Double !Window !Window
  deriving (Eq, Read, Show)

newtype RecentsMap = RecentsMap (M.Map WorkspaceId RecentWins)

instance ExtensionClass RecentsMap where
  initialValue = RecentsMap M.empty

-- Record the focus of every visible workspace; add it to the logHook.
refocusLastLogHook :: X ()
refocusLastLogHook = refocusLastWhen (pure True)

-- Like 'refocusLastLogHook', but a focused window the predicate rejects
-- forgets the history, so closing it refocuses the stack neighbour.
refocusLastWhen :: X Bool -> X ()
refocusLastWhen p = do
  ws <- gets windowset
  mapM_ (record ws) (W.current ws : W.visible ws)
  where
    record ws sc = case W.stack (W.workspace sc) of
      Nothing -> setRecents tag Empty
      Just st -> do
        let w = W.focus st
        ok <- if tag == W.currentTag ws then p else pure True
        old <- recentsOf tag
        setRecents tag (if ok then push w old else Single w)
      where tag = W.tag (W.workspace sc)

push :: Window -> RecentWins -> RecentWins
push w r = case r of
  Empty -> Single w
  Single a | a == w -> r
           | otherwise -> Double w a
  Double a b | a == w -> r
             | b == w -> Double w a
             | otherwise -> Double w a

recentsOf :: WorkspaceId -> X RecentWins
recentsOf t = XS.gets $ \(RecentsMap m) -> M.findWithDefault Empty t m

setRecents :: WorkspaceId -> RecentWins -> X ()
setRecents t r = XS.modify $ \(RecentsMap m) ->
  RecentsMap (if r == Empty then M.delete t m else M.insert t r m)

-- Whether the focused window of the current workspace is floating.
isFloat :: X Bool
isFloat = gets $ \s -> case W.peek (windowset s) of
  Just w -> M.member w (W.floating (windowset s))
  Nothing -> False

data RefocusLastLayoutHook a = RefocusLastLayoutHook
  deriving (Read, Show)

refocusLastLayoutHook :: l a -> ModifiedLayout RefocusLastLayoutHook l a
refocusLastLayoutHook = ModifiedLayout RefocusLastLayoutHook

instance LayoutModifier RefocusLastLayoutHook Window where
  modifyLayout _ w r = refocus w >>= \w' -> runLayout w' r

-- Refocus the previous window when the recorded focused one has gone, and
-- hand the inner layout the corrected stack.
refocus :: W.Workspace WorkspaceId (l Window) Window
        -> X (W.Workspace WorkspaceId (l Window) Window)
refocus w = do
  let tag = W.tag w
  recents <- recentsOf tag
  ws <- gets windowset
  let full = maybe [] W.integrate (stackOf tag ws)
      focused = W.focus <$> stackOf tag ws
  case recents of
    Double cur prev
      | cur `notElem` full, Just f <- focused, f /= prev, prev `elem` full -> do
          setRecents tag (Single prev)
          modifyWindowSet $ W.mapWorkspace $ \wk ->
            if W.tag wk == tag then wk {W.stack = W.stack wk >>= toWindow prev}
            else wk
          requestFocus tag ws prev
          pure w {W.stack = W.stack w >>= toWindow prev}
    _ -> pure w
  where
    stackOf t ws = W.stack =<< lookupWs t ws
    lookupWs t ws = case filter ((== t) . W.tag) (W.workspaces ws) of
      x:_ -> Just x
      [] -> Nothing

requestFocus :: WorkspaceId -> WindowSet -> Window -> X ()
requestFocus t ws prev
  | t == W.currentTag ws = modify $ \s ->
      let n = nextActionId s + 1
      in s {nextActionId = n, pendingFocus = Just (n, prev)}
  | otherwise = pure ()

-- Focus a window within a stack, if it is in it.
toWindow :: Window -> W.Stack Window -> Maybe (W.Stack Window)
toWindow x st
  | x `elem` W.integrate st = Just (until ((== x) . W.focus) W.focusDown' st)
  | otherwise = Just st

-- Focus the window that was focused before this one, on this workspace.
toggleFocus :: X ()
toggleFocus = do
  tag <- gets (W.currentTag . windowset)
  r <- recentsOf tag
  case r of
    Double _ prev -> windows (W.focusWindow prev)
    _ -> pure ()

-- Swap the focused window with the previously focused one in the stack;
-- the focus stays on the window that was focused.
swapWithLast :: X ()
swapWithLast = do
  tag <- gets (W.currentTag . windowset)
  r <- recentsOf tag
  case r of
    Double cur prev -> windows $ W.modify' $ \st ->
      let ws = W.integrate st
          swap x | x == cur = prev
                 | x == prev = cur
                 | otherwise = x
          (up, rest) = break (== cur) (map swap ws)
      in if prev `elem` ws
           then case rest of
             x:down -> W.Stack x (reverse up) down
             [] -> st
           else st
    _ -> pure ()
