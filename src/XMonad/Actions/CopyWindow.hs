-- Adapted from xmonad-contrib XMonad.Actions.CopyWindow (BSD-3-Clause),
-- Copyright (c) David Roundy, Ivan Veselov, Lanny Ripple and the Xmonad Community.
-- copiesPP is not ported (no StatusBar).
module XMonad.Actions.CopyWindow
  ( copy, copyToAll, copyWindow, runOrCopy
  , killAllOtherCopies, kill1, taggedWindows, copiesOfOn, wsContainingCopies
  ) where
import Control.Monad (filterM)
import XMonad.Core
import XMonad.ManageHook
import XMonad.Operations (kill, spawn, windows, withWindowSet)
import qualified XMonad.StackSet as W

copy :: (Eq s, Eq i, Eq a) => i -> W.StackSet i l a s sd -> W.StackSet i l a s sd
copy n s | Just w <- W.peek s = copyWindow w n s
         | otherwise = s

copyToAll :: (Eq s, Eq i, Eq a) => W.StackSet i l a s sd -> W.StackSet i l a s sd
copyToAll s = foldr (copy . W.tag) s (W.workspaces s)

copyWindow :: (Eq a, Eq i, Eq s) => a -> i -> W.StackSet i l a s sd -> W.StackSet i l a s sd
copyWindow w n = copy'
  where copy' s
          | n `W.tagMember` s = W.view (W.currentTag s) $ insertUp' w $ W.view n s
          | otherwise = s
        insertUp' a = W.modify (Just $ W.Stack a [] [])
          (\(W.Stack t l r) -> if a `elem` t:l++r
             then Just $ W.Stack t l r
             else Just $ W.Stack a l (t:r))

runOrCopy :: String -> Query Bool -> X ()
runOrCopy cmd qry = ifWindow qry copyWin (spawn cmd)
  where copyWin = ask >>= \w -> doF (\ws -> copyWindow w (W.currentTag ws) ws)
        ifWindow q mh el = withWindowSet $ \wins -> do
          matches <- filterM (runQuery q) (W.allWindows wins)
          case matches of
            [] -> el
            (w:_) -> windows . appEndo =<< runQuery mh w

kill1 :: X ()
kill1 = do
  ss <- gets windowset
  whenJust (W.peek ss) $ \w ->
    if W.member w (delete'' w ss) then windows (delete'' w) else kill
  where delete'' w = W.modify Nothing (W.filter (/= w))

killAllOtherCopies :: X ()
killAllOtherCopies = do
  ss <- gets windowset
  whenJust (W.peek ss) $ \w -> windows $ W.view (W.currentTag ss) . delFromAllButCurrent w
  where
    delFromAllButCurrent w ss = foldr (delWinFromWorkspace w . W.tag) ss
      (W.hidden ss ++ map W.workspace (W.visible ss))
    delWinFromWorkspace w tag = viewing tag $ W.modify Nothing (W.filter (/= w))
    viewing wis f ss = W.view (W.currentTag ss) $ f $ W.view wis ss

wsContainingCopies :: X [WorkspaceId]
wsContainingCopies = do
  ws <- gets windowset
  pure $ copiesOfOn (W.peek ws) (taggedWindows $ W.hidden ws)

taggedWindows :: [W.Workspace i l a] -> [(i, [a])]
taggedWindows = map $ \w -> (W.tag w, W.integrate' (W.stack w))

copiesOfOn :: Eq a => Maybe a -> [(i, [a])] -> [i]
copiesOfOn foc tw = maybe [] hasCopyOf foc
  where hasCopyOf f = map fst $ filter ((f `elem`) . snd) tw
