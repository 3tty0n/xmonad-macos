{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.Minimize (BSD-3-Clause),
-- Copyright (c) 2009 Jan Vornberger and the Xmonad Community. Minimizing is
-- logical: the window leaves the layout and is hidden like any window the
-- layout gives no rectangle; macOS never minimizes it into the Dock.
module XMonad.Layout.Minimize
  ( minimize, MinimizeMsg(..), Minimize, Minimized(..)
  ) where
import XMonad.Core
import XMonad.Layout.LayoutModifier
import XMonad.Operations (sendMessageWithNoRefresh)
import qualified XMonad.Layout.BoringWindows as BW
import qualified XMonad.StackSet as W
import qualified XMonad.Util.ExtensibleState as XS
import Data.List (delete)

-- Most recently minimized first.
newtype Minimized = Minimized { minimizedStack :: [Window] }
  deriving (Eq, Read, Show)

instance ExtensionClass Minimized where
  initialValue = Minimized []

data Minimize a = Minimize deriving (Read, Show)

data MinimizeMsg = MinimizeWin Window
                 | RestoreMinimizedWin Window
                 | RestoreNextMinimizedWin
  deriving (Eq, Read, Show)

instance Message MinimizeMsg

minimize :: LayoutClass l Window
         => l Window -> ModifiedLayout Minimize l Window
minimize = ModifiedLayout Minimize

push :: Window -> Minimized -> Minimized
push w (Minimized ws) = Minimized (w : delete w ws)

instance LayoutModifier Minimize Window where
  modifierDescription _ = "Minimize"
  modifyLayout Minimize ws rect = do
    minimizedWs <- XS.gets minimizedStack
    let stack = W.stack ws >>= W.filter (`notElem` minimizedWs)
    runLayout (ws {W.stack = stack}) rect
  handleMess Minimize m
    | Just (MinimizeWin w) <- fromMessage m =
        Nothing <$ XS.modify (push w)
    | Just (RestoreMinimizedWin w) <- fromMessage m =
        Nothing <$ XS.modify (Minimized . delete w . minimizedStack)
    | Just RestoreNextMinimizedWin <- fromMessage m =
        Nothing <$ XS.modify (Minimized . drop 1 . minimizedStack)
    | Just BW.UpdateBoring <- fromMessage m = do
        minimizedWs <- XS.gets minimizedStack
        ws <- gets (W.workspace . W.current . windowset)
        sendMessageWithNoRefresh (BW.Replace "Minimize" minimizedWs) ws
        pure Nothing
    | otherwise = pure Nothing
