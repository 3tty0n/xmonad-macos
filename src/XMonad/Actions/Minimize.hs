-- Adapted from xmonad-contrib XMonad.Actions.Minimize (BSD-3-Clause),
-- Copyright (c) 2009 Jan Vornberger and the Xmonad Community.
module XMonad.Actions.Minimize
  ( minimizeWindow, maximizeWindow, maximizeWindowAndFocus
  , withLastMinimized, withLastMinimized'
  , withFirstMinimized, withFirstMinimized'
  , withMinimized
  ) where
import XMonad.Core
import XMonad.Layout.Minimize
import XMonad.Operations (sendMessage, windows, withWindowSet)
import qualified XMonad.Layout.BoringWindows as BW
import qualified XMonad.StackSet as W
import qualified XMonad.Util.ExtensibleState as XS
import Data.List (intersect)
import Data.Maybe (listToMaybe)

-- Minimize a window and move focus to the next one that is not boring.
minimizeWindow :: Window -> X ()
minimizeWindow w = do
  sendMessage BW.UpdateBoring
  sendMessage (MinimizeWin w)
  BW.focusDown

maximizeWindow :: Window -> X ()
maximizeWindow = sendMessage . RestoreMinimizedWin

maximizeWindowAndFocus :: Window -> X ()
maximizeWindowAndFocus w = maximizeWindow w >> windows (W.focusWindow w)

-- The windows minimized on the current workspace, most recent first.
withMinimized :: ([Window] -> X a) -> X a
withMinimized action = do
  minimized <- XS.gets minimizedStack
  onWorkspace <- withWindowSet (pure . W.index)
  action (minimized `intersect` onWorkspace)

withLastMinimized :: (Window -> X ()) -> X ()
withLastMinimized = withLastMinimized' . maybe (pure ())

withLastMinimized' :: (Maybe Window -> X a) -> X a
withLastMinimized' f = withMinimized (f . listToMaybe)

withFirstMinimized :: (Window -> X ()) -> X ()
withFirstMinimized = withFirstMinimized' . maybe (pure ())

withFirstMinimized' :: (Maybe Window -> X a) -> X a
withFirstMinimized' f = withMinimized (f . listToMaybe . reverse)
