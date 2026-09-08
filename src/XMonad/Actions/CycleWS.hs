-- Adapted from xmonad-contrib XMonad.Actions.CycleWS (BSD-3-Clause),
-- Copyright (c) Joachim Fasting, Brent Yorgey and the Xmonad Community.
-- The predicate-and-type machinery of the upstream module is not ported; these
-- are the workspace-order actions people bind keys to.
module XMonad.Actions.CycleWS
  ( nextWS, prevWS, shiftToNext, shiftToPrev, toggleWS, moveTo, shiftTo
  , Direction1D(..)
  ) where
import XMonad.Core
import XMonad.Operations (windows)
import qualified XMonad.StackSet as W
import Data.List (elemIndex)
import Data.Maybe (fromMaybe)

data Direction1D = Next | Prev deriving (Eq, Show, Read)

-- Workspace order is the order in the config, wrapping at both ends.
neighbour :: Direction1D -> X WorkspaceId
neighbour d = do
  tags <- asks (workspaces . config)
  current <- gets (W.currentTag . windowset)
  let i = fromMaybe 0 (elemIndex current tags)
      n = length tags
      j = case d of Next -> (i+1) `mod` max 1 n
                    Prev -> (i-1) `mod` max 1 n
  pure $ if null tags then current else tags !! j

moveTo, shiftTo :: Direction1D -> X ()
moveTo d = neighbour d >>= windows . W.view
shiftTo d = neighbour d >>= windows . W.shift

nextWS, prevWS, shiftToNext, shiftToPrev :: X ()
nextWS = moveTo Next
prevWS = moveTo Prev
shiftToNext = shiftTo Next
shiftToPrev = shiftTo Prev

-- The most recently left workspace is the head of the hidden list.
toggleWS :: X ()
toggleWS = do
  hidden <- gets (W.hidden . windowset)
  case hidden of
    w:_ -> windows (W.view (W.tag w))
    [] -> pure ()
