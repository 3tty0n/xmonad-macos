-- Adapted from xmonad-contrib XMonad.Hooks.DynamicLog (BSD-3-Clause), which
-- is now a compatibility shim over Hooks.StatusBar and Hooks.StatusBar.PP.
-- xmobar/dzen launchers need X11 properties or dzen, so they are not ported.
module XMonad.Hooks.DynamicLog
  ( module XMonad.Hooks.StatusBar.PP, dynamicLog
  ) where
import XMonad.Core
import XMonad.Hooks.StatusBar.PP

dynamicLog :: X ()
dynamicLog = dynamicLogWithPP def
