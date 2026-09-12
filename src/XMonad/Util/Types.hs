-- Adapted from xmonad-contrib XMonad.Util.Types (BSD-3-Clause),
-- Copyright (c) Daniel Schoepe and the Xmonad Community.
module XMonad.Util.Types (Direction1D(..), Direction2D(..)) where

data Direction1D = Next | Prev deriving (Eq, Read, Show)

data Direction2D = U | D | R | L deriving (Eq, Read, Show, Ord, Enum, Bounded)
