{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.Maximize (BSD-3-Clause),
-- Copyright (c) 2007 James Webb and the Xmonad Community. The maximized
-- window is listed last, which is the top of the stack here.
module XMonad.Layout.Maximize
  ( maximize, maximizeWithPadding, maximizeRestore
  , Maximize, MaximizeRestore
  ) where
import XMonad.Core
import XMonad.Layout.LayoutModifier
import Data.List (partition)

data Maximize a = Maximize Dimension (Maybe Window) deriving (Read, Show)

newtype MaximizeRestore = MaximizeRestore Window deriving (Eq, Read, Show)

instance Message MaximizeRestore

-- Pad the maximized window by 25 points on every side.
maximize :: LayoutClass l Window
         => l Window -> ModifiedLayout Maximize l Window
maximize = maximizeWithPadding 25

maximizeWithPadding :: LayoutClass l Window => Dimension -> l Window
                    -> ModifiedLayout Maximize l Window
maximizeWithPadding padding = ModifiedLayout (Maximize padding Nothing)

-- Maximizes the window, or restores it if it is already maximized.
maximizeRestore :: Window -> MaximizeRestore
maximizeRestore = MaximizeRestore

instance LayoutModifier Maximize Window where
  modifierDescription _ = "Maximize"
  pureModifier (Maximize padding (Just target)) (Rectangle x y w h) _ wrs
    | target `elem` map fst wrs = (rest ++ [(target, full)], Nothing)
    where
      rest = snd (partition ((== target) . fst) wrs)
      full = Rectangle (x + padding) (y + padding)
                       (max 1 (w - 2 * padding)) (max 1 (h - 2 * padding))
  pureModifier _ _ _ wrs = (wrs, Nothing)
  pureMess (Maximize padding current) m = case fromMessage m of
    Just (MaximizeRestore w)
      | current == Just w -> Just (Maximize padding Nothing)
      | otherwise -> Just (Maximize padding (Just w))
    Nothing -> Nothing
