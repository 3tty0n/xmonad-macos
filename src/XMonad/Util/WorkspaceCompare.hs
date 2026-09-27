-- Adapted from xmonad-contrib XMonad.Util.WorkspaceCompare (BSD-3-Clause),
-- Copyright (c) Spencer Janssen and the Xmonad Community. The configurable
-- ScreenComparator and the physical-rule variants are not ported; the single
-- xinerama rule orders screens by where they sit, since a macOS display id is
-- an arbitrary number rather than a position.
module XMonad.Util.WorkspaceCompare
  ( WorkspaceCompare, WorkspaceSort, filterOutWs, getWsIndex
  , getWsCompare, getWsCompareByTag, getSortByIndex, getSortByTag
  , getSortByXineramaRule, mkWsSort
  ) where
import XMonad.Core
import qualified XMonad.StackSet as W
import Data.List (elemIndex, sortBy, sortOn)

type WorkspaceCompare = WorkspaceId -> WorkspaceId -> Ordering
type WorkspaceSort = [WindowSpace] -> [WindowSpace]

-- Drop the workspaces carrying these tags, for a logHook that should not
-- mention a scratchpad.
filterOutWs :: [WorkspaceId] -> WorkspaceSort
filterOutWs ws = filter (\w -> W.tag w `notElem` ws)

-- Where the tag sits in the config, or Nothing for one the config does not
-- name: the helper's own generated "_screen_N" tags and a scratchpad.
getWsIndex :: X (WorkspaceId -> Maybe Int)
getWsIndex = do
  tags <- asks (workspaces . config)
  pure (`elemIndex` tags)

-- A tag the config does not name comes last, not first.
indexCompare :: Maybe Int -> Maybe Int -> Ordering
indexCompare Nothing Nothing = EQ
indexCompare Nothing (Just _) = GT
indexCompare (Just _) (Nothing) = LT
indexCompare a b = compare a b

getWsCompare :: X WorkspaceCompare
getWsCompare = do
  index <- getWsIndex
  pure $ \a b -> indexCompare (index a) (index b) <> compare a b

getWsCompareByTag :: X WorkspaceCompare
getWsCompareByTag = pure compare

mkWsSort :: X WorkspaceCompare -> X WorkspaceSort
mkWsSort cmpX = do
  cmp <- cmpX
  pure $ sortBy (\a b -> cmp (W.tag a) (W.tag b))

getSortByIndex :: X WorkspaceSort
getSortByIndex = mkWsSort getWsCompare

getSortByTag :: X WorkspaceSort
getSortByTag = mkWsSort getWsCompareByTag

-- Visible workspaces first, in the order their displays sit on the desk, then
-- the rest by tag. This is the ordering a bar should show with more than one
-- display, and the order XMonad.Actions.PhysicalScreens numbers them in.
getSortByXineramaRule :: X WorkspaceSort
getSortByXineramaRule = do
  ws <- gets windowset
  let shown = W.current ws : W.visible ws
      place = [W.tag (W.workspace sc) | sc <- sortOn (corner . W.screenDetail) shown]
      corner (SD r _) = (rect_x r, rect_y r)
      index t = elemIndex t place
  pure $ sortBy (\a b -> indexCompare (index (W.tag a)) (index (W.tag b))
                         <> compare (W.tag a) (W.tag b))
