-- Adapted from xmonad-contrib XMonad.Actions.CycleWS (BSD-3-Clause),
-- Copyright (c) Joachim Fasting, Brent Yorgey and the Xmonad Community.
-- Screen cycling (nextScreen, swapNextScreen, shiftScreenBy) is not ported:
-- XMonad.Actions.PhysicalScreens and XMonad.Actions.OnScreen name a display
-- directly, which is what a macOS desk wants.
module XMonad.Actions.CycleWS
  ( Direction1D(..), WSType(..)
  , emptyWS, hiddenWS, anyWS, wsTagGroup, ignoringWSs
  , nextWS, prevWS, shiftToNext, shiftToPrev
  , moveTo, shiftTo, doTo, findWorkspace
  , toggleWS, toggleWS', toggleOrView, toggleOrDoSkip, skipTags
  ) where
import XMonad.Core
import XMonad.Operations (windows)
import XMonad.Util.Types (Direction1D(..))
import XMonad.Util.WorkspaceCompare (WorkspaceSort, getSortByIndex)
import XMonad.Hooks.WorkspaceHistory (workspaceHistory)
import qualified XMonad.StackSet as W
import Data.List (find, findIndex)
import Data.Maybe (isJust, isNothing)

-- Which workspaces a cycle may land on. The deprecated upstream spellings
-- (EmptyWS, AnyWS, ...) are kept so an existing config still builds; the
-- lowercase names below are the ones to write.
data WSType
  = EmptyWS | NonEmptyWS | HiddenWS | HiddenNonEmptyWS | HiddenEmptyWS
  | AnyWS | WSTagGroup Char
  -- An arbitrary predicate, so a config can cycle on anything it can observe.
  | WSIs (X (WindowSpace -> Bool))
  | WSType :&: WSType | WSType :|: WSType | Not WSType

wsTypeToPred :: WSType -> X (WindowSpace -> Bool)
wsTypeToPred EmptyWS = pure (isNothing . W.stack)
wsTypeToPred NonEmptyWS = pure (isJust . W.stack)
wsTypeToPred HiddenWS = do
  hidden <- gets (map W.tag . W.hidden . windowset)
  pure (\w -> W.tag w `elem` hidden)
wsTypeToPred HiddenNonEmptyWS = both NonEmptyWS HiddenWS
wsTypeToPred HiddenEmptyWS = both EmptyWS HiddenWS
wsTypeToPred AnyWS = pure (const True)
-- The group is everything up to the first separator, so tags like "web-1"
-- and "web-2" cycle among themselves.
wsTypeToPred (WSTagGroup sep) = do
  here <- groupName . W.tag . W.workspace . W.current <$> gets windowset
  pure ((here ==) . groupName . W.tag)
  where groupName = takeWhile (/= sep)
wsTypeToPred (WSIs p) = p
wsTypeToPred (p :&: q) = both p q
wsTypeToPred (p :|: q) = eitherOf p q
wsTypeToPred (Not p) = combine not p

both :: WSType -> WSType -> X (WindowSpace -> Bool)
both p q = combine2 (&&) p q

eitherOf :: WSType -> WSType -> X (WindowSpace -> Bool)
eitherOf p q = combine2 (||) p q

combine :: (Bool -> Bool) -> WSType -> X (WindowSpace -> Bool)
combine f p = do
  p' <- wsTypeToPred p
  pure (f . p')

combine2 :: (Bool -> Bool -> Bool) -> WSType -> WSType -> X (WindowSpace -> Bool)
combine2 f p q = do
  p' <- wsTypeToPred p
  q' <- wsTypeToPred q
  pure (\w -> f (p' w) (q' w))

emptyWS, hiddenWS, anyWS :: WSType
emptyWS = WSIs (wsTypeToPred EmptyWS)
hiddenWS = WSIs (wsTypeToPred HiddenWS)
anyWS = WSIs (wsTypeToPred AnyWS)

wsTagGroup :: Char -> WSType
wsTagGroup = WSIs . wsTypeToPred . WSTagGroup

-- Everything except these tags, so a scratchpad workspace can be stepped over.
ignoringWSs :: [WorkspaceId] -> WSType
ignoringWSs tags = WSIs . pure $ \w -> W.tag w `notElem` tags

-- The tag n places from here in the given direction, wrapping, among the
-- workspaces that satisfy the predicate and sort by the given order.
findWorkspace :: X WorkspaceSort -> Direction1D -> WSType -> Int -> X WorkspaceId
findWorkspace srt dir t n = findWorkspaceGen srt (wsTypeToPred t) (step dir n)
  where step Next d = d
        step Prev d = -d

findWorkspaceGen :: X WorkspaceSort -> X (WindowSpace -> Bool) -> Int -> X WorkspaceId
findWorkspaceGen _ _ 0 = gets (W.currentTag . windowset)
findWorkspaceGen sortX predX d = do
  matches <- predX
  order <- sortX
  ws <- gets windowset
  let here = W.workspace (W.current ws)
      -- Pivot at the current workspace so "next" means next from here, and a
      -- workspace the config does not name sorts where the order puts it.
      (before,after) = span ((/= W.tag here) . W.tag) (order (W.workspaces ws))
      candidates = filter matches (after ++ before)
      at = findIndex ((== W.tag here) . W.tag) candidates
      offset = if d > 0 then d - 1 else d
      next = case (candidates, at) of
        ([], _) -> here
        (_, Nothing) -> candidates !! (offset `mod` length candidates)
        (_, Just i) -> candidates !! ((i + d) `mod` length candidates)
  pure (W.tag next)

-- Move to the next workspace that satisfies the predicate, in config order.
moveTo :: Direction1D -> WSType -> X ()
moveTo dir t = doTo dir t getSortByIndex (windows . W.greedyView)

-- Send the focused window there instead.
shiftTo :: Direction1D -> WSType -> X ()
shiftTo dir t = doTo dir t getSortByIndex (windows . W.shift)

doTo :: Direction1D -> WSType -> X WorkspaceSort -> (WorkspaceId -> X ()) -> X ()
doTo dir t srt act = findWorkspace srt dir t 1 >>= act

nextWS, prevWS, shiftToNext, shiftToPrev :: X ()
nextWS = switchWorkspace 1
prevWS = switchWorkspace (-1)
shiftToNext = shiftBy 1
shiftToPrev = shiftBy (-1)

switchWorkspace :: Int -> X ()
switchWorkspace d = wsBy d >>= windows . W.greedyView

shiftBy :: Int -> X ()
shiftBy d = wsBy d >>= windows . W.shift

wsBy :: Int -> X WorkspaceId
wsBy = findWorkspace getSortByIndex Next anyWS

-- Back to the workspace shown before this one, skipping any listed tag.
toggleWS :: X ()
toggleWS = toggleWS' []

toggleWS' :: [WorkspaceId] -> X ()
toggleWS' skips = lastViewedHiddenExcept skips >>= flip whenJust (windows . W.view)

-- The workspace's own key, or the previously shown one when it is already up.
toggleOrView :: WorkspaceId -> X ()
toggleOrView = toggleOrDoSkip [] W.greedyView

-- The general form: run any "view a workspace" action, or toggle away when the
-- workspace asked for is the one already showing.
toggleOrDoSkip :: [WorkspaceId] -> (WorkspaceId -> WindowSet -> WindowSet) -> WorkspaceId -> X ()
toggleOrDoSkip skips f toWS = do
  here <- gets (W.currentTag . windowset)
  if toWS == here
    then lastViewedHiddenExcept skips >>= flip whenJust (windows . f)
    else windows (f toWS)

skipTags :: Eq i => [W.Workspace i l a] -> [i] -> [W.Workspace i l a]
skipTags wss tags = filter ((`notElem` tags) . W.tag) wss

-- The most recently shown hidden workspace that is not skipped. The history is
-- only populated while XMonad.Hooks.WorkspaceHistory is in the logHook, so fall
-- back to the head of the hidden list, which is the workspace just left.
lastViewedHiddenExcept :: [WorkspaceId] -> X (Maybe WorkspaceId)
lastViewedHiddenExcept skips = do
  ws <- gets windowset
  recent <- workspaceHistory
  let hidden = map W.tag (skipTags (W.hidden ws) skips)
  pure (choose hidden (find (`elem` hidden) recent))
  where choose [] _ = Nothing
        choose (h:_) Nothing = Just h
        choose _ seen = seen
