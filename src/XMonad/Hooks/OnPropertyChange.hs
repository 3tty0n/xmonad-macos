-- Adapted from xmonad-contrib XMonad.Hooks.OnPropertyChange (BSD-3-Clause),
-- Copyright (c) Ilya Portnov and the Xmonad Community. There are no X property
-- events: the engine compares each snapshot's title and application with the
-- previous one, so a change is noticed one snapshot late. Only the properties
-- named below are known.
module XMonad.Hooks.OnPropertyChange
  ( onXPropertyChange, onTitleChange, onClassChange
  ) where
import XMonad.Core
import XMonad.Operations (modifyWindowSet)
import Control.Monad (when)

onXPropertyChange :: String -> ManageHook -> XConfig l -> XConfig l
onXPropertyChange prop hook c = c { windowChangeHook = \w old new -> do
  windowChangeHook c w old new
  when (changes prop old new) $ do
    Endo f <- runQuery hook w
    modifyWindowSet f }

onTitleChange, onClassChange :: ManageHook -> XConfig l -> XConfig l
onTitleChange = onXPropertyChange "WM_NAME"
onClassChange = onXPropertyChange "WM_CLASS"

changes :: String -> WindowInfo -> WindowInfo -> Bool
changes prop old new
  | prop `elem` ["WM_NAME", "_NET_WM_NAME"] = titleText old /= titleText new
  | prop == "WM_CLASS" = app old /= app new || bundle old /= bundle new
  | otherwise = False
