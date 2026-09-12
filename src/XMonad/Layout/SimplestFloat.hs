{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.SimplestFloat (BSD-3-Clause),
-- Copyright (c) Jussi Mäki and the Xmonad Community. Window size is taken
-- from the last snapshot rather than X11 attributes.
module XMonad.Layout.SimplestFloat (simplestFloat, SimplestFloat) where
import Data.Maybe (fromMaybe)
import qualified Data.Map.Strict as M
import XMonad.Core
import qualified XMonad.StackSet as W

simplestFloat :: SimplestFloat a
simplestFloat = SF

data SimplestFloat a = SF deriving (Show, Read)

instance LayoutClass SimplestFloat Window where
  doLayout SF sc (W.Stack w l r) = do
    info <- gets windowInfo
    pure (map (size sc info) (w : reverse l ++ r), Nothing)
  description _ = "SimplestFloat"

size :: Rectangle -> M.Map Window WindowInfo -> Window -> (Window, Rectangle)
size sc info w = (w, fromMaybe sc (frame <$> M.lookup w info))
