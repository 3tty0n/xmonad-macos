{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.CenteredIfSingle (BSD-3-Clause),
-- Copyright (c) Leon Kowarschick and the Xmonad Community.
module XMonad.Layout.CenteredIfSingle (centeredIfSingle, CenteredIfSingle) where
import XMonad.Core
import XMonad.Layout.LayoutModifier

data CenteredIfSingle a = CenteredIfSingle !Double !Double deriving (Show, Read)

instance LayoutModifier CenteredIfSingle a where
  pureModifier (CenteredIfSingle ratioX ratioY) r _ [(onlyWindow, _)] =
    ([(onlyWindow, rectangleCenterPiece ratioX ratioY r)], Nothing)
  pureModifier _ _ _ winRects = (winRects, Nothing)

centeredIfSingle :: Double -> Double -> l a -> ModifiedLayout CenteredIfSingle l a
centeredIfSingle ratioX ratioY = ModifiedLayout (CenteredIfSingle ratioX ratioY)

rectangleCenterPiece :: Double -> Double -> Rectangle -> Rectangle
rectangleCenterPiece ratioX ratioY (Rectangle rx ry rw rh) =
  Rectangle startX startY width height
  where
    startX = rx + left
    startY = ry + top
    width  = max 1 $ rw - 2 * left
    height = max 1 $ rh - 2 * top
    left = floor $ fromIntegral rw * (1.0 - ratioX) / 2
    top  = floor $ fromIntegral rh * (1.0 - ratioY) / 2
