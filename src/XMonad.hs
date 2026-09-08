module XMonad
  ( module XMonad.Core, module XMonad.Layout, module XMonad.Operations
  , module XMonad.ManageHook, def, defaultConfig, xmonad, (.|.) ) where
import XMonad.Core
import XMonad.Layout
import XMonad.Operations
import XMonad.ManageHook
import XMonad.Config
import XMonad.MacOS.Engine (xmonad)
import Data.Bits ((.|.))
