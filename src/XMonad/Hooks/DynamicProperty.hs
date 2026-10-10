-- Adapted from xmonad-contrib XMonad.Hooks.DynamicProperty (BSD-3-Clause),
-- Copyright (c) Brandon S Allbery KF8NH and the Xmonad Community. Upstream
-- takes an X11 Event; here the hook is installed on the config instead.
module XMonad.Hooks.DynamicProperty
  ( dynamicPropertyChange, dynamicTitle
  ) where
import XMonad.Core
import XMonad.Hooks.OnPropertyChange

dynamicPropertyChange :: String -> ManageHook -> XConfig l -> XConfig l
dynamicPropertyChange = onXPropertyChange

dynamicTitle :: ManageHook -> XConfig l -> XConfig l
dynamicTitle = onTitleChange
