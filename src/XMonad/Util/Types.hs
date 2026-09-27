-- Adapted from xmonad-contrib XMonad.Util.Types (BSD-3-Clause),
-- Copyright (c) Daniel Schoepe and the Xmonad Community. Align is a plain
-- enumeration, so it lives here rather than in the X11-only XMonad.Util.Font
-- that upstream keeps it beside.
module XMonad.Util.Types (Direction1D(..), Direction2D(..), Align(..)) where

data Direction1D = Next | Prev deriving (Eq, Read, Show)

data Direction2D = U | D | R | L deriving (Eq, Read, Show, Ord, Enum, Bounded)

data Align = AlignLeft | AlignCenter | AlignRight deriving (Eq, Read, Show)
