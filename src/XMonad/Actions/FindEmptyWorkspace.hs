-- Adapted from xmonad-contrib XMonad.Actions.FindEmptyWorkspace (BSD-3-Clause),
-- Copyright (c) Miikka Koskinen and the Xmonad Community.
module XMonad.Actions.FindEmptyWorkspace
  ( viewEmptyWorkspace, tagToEmptyWorkspace, sendToEmptyWorkspace
  ) where
import Data.List (find)
import Data.Maybe (isNothing)
import XMonad.Core
import XMonad.Operations (windows)
import qualified XMonad.StackSet as W

findEmptyWorkspace :: W.StackSet i l a s sd -> Maybe (W.Workspace i l a)
findEmptyWorkspace = find (isNothing . W.stack) . allWorkspaces
  where allWorkspaces ss = W.workspace (W.current ss)
                         : map W.workspace (W.visible ss) ++ W.hidden ss

withEmptyWorkspace :: (WorkspaceId -> X ()) -> X ()
withEmptyWorkspace f = do
  ws <- gets windowset
  whenJust (findEmptyWorkspace ws) (f . W.tag)

viewEmptyWorkspace :: X ()
viewEmptyWorkspace = withEmptyWorkspace (windows . W.view)

tagToEmptyWorkspace :: X ()
tagToEmptyWorkspace = withEmptyWorkspace $ \w -> windows $ W.view w . W.shift w

sendToEmptyWorkspace :: X ()
sendToEmptyWorkspace = withEmptyWorkspace $ \w -> windows $ W.shift w
