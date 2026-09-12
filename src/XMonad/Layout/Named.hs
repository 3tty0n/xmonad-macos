-- Adapted from xmonad-contrib XMonad.Layout.Named (BSD-3-Clause).
-- The upstream module is deprecated; this re-exports renamed [Replace n].
module XMonad.Layout.Named (named, Rename(..)) where
import XMonad.Layout.Renamed

named :: String -> l a -> Renamed l a
named n = renamed [Replace n]
