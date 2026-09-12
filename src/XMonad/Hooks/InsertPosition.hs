-- Adapted from xmonad-contrib XMonad.Hooks.InsertPosition (BSD-3-Clause),
-- Copyright (c) Adam Vogt and the Xmonad Community.
module XMonad.Hooks.InsertPosition
  ( setupInsertPosition, insertPosition, Focus(..), Position(..)
  ) where
import Data.List (find)
import XMonad.Core hiding (Position)
import qualified XMonad.StackSet as W

data Position = Master | End | Above | Below
data Focus = Newer | Older

setupInsertPosition :: Position -> Focus -> XConfig a -> XConfig a
setupInsertPosition pos foc cfg =
  cfg { manageHook = insertPosition pos foc <> manageHook cfg }

insertPosition :: Position -> Focus -> ManageHook
insertPosition pos foc = Endo . g <$> ask
  where
    g w = viewingWs w (updateFocus w . ins w . W.delete' w)
    ins w = (\f ws -> maybe id W.focusWindow (W.peek ws) $ f ws) $
      case pos of
        Master -> W.insertUp w . W.focusMaster
        End    -> insertDown w . W.modify' focusLast'
        Above  -> W.insertUp w
        Below  -> insertDown w
    updateFocus = case foc of
      Older -> const id
      Newer -> W.focusWindow

viewingWs :: (Eq a, Eq s, Eq i) => a -> (W.StackSet i l a s sd -> W.StackSet i l a s sd)
          -> W.StackSet i l a s sd -> W.StackSet i l a s sd
viewingWs w f ss =
  let i = W.tag (W.workspace (W.current ss))
  in maybe ss (W.view i . f . (`W.view` ss) . W.tag)
       (find (elem w . W.integrate' . W.stack) (W.workspaces ss))

insertDown :: Eq a => a -> W.StackSet i l a s sd -> W.StackSet i l a s sd
insertDown w = W.swapDown . W.insertUp w

focusLast' :: W.Stack a -> W.Stack a
focusLast' st = case reverse (W.integrate st) of
  [] -> st
  (l:ws) -> W.Stack l ws []
