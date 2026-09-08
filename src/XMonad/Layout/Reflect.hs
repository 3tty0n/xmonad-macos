{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.Reflect (BSD-3-Clause),
-- Copyright (c) Brent Yorgey and the Xmonad Community.
module XMonad.Layout.Reflect (Reflect, reflectHoriz, reflectVert) where
import XMonad.Core
import qualified XMonad.StackSet as W

data Axis = Horiz | Vert deriving (Show,Read,Eq)

data Reflect l a = Reflect Axis (l a) deriving (Show,Read)

-- Flip the layout left to right, or top to bottom, within its own frame.
reflectHoriz, reflectVert :: l a -> Reflect l a
reflectHoriz = Reflect Horiz
reflectVert = Reflect Vert

instance LayoutClass l a => LayoutClass (Reflect l) a where
  runLayout (W.Workspace t (Reflect axis l) s) r = do
    (rects,changed) <- runLayout (W.Workspace t l s) r
    pure ([(w,reflect axis r rect) | (w,rect) <- rects], Reflect axis <$> changed)
  handleMessage (Reflect axis l) m = fmap (Reflect axis) <$> handleMessage l m
  description (Reflect axis l) = show axis ++ " " ++ description l

reflect :: Axis -> Rectangle -> Rectangle -> Rectangle
reflect Horiz (Rectangle sx _ sw _) (Rectangle x y w h) =
  Rectangle (2*sx+fromIntegral sw-x-fromIntegral w) y w h
reflect Vert (Rectangle _ sy _ sh) (Rectangle x y w h) =
  Rectangle x (2*sy+fromIntegral sh-y-fromIntegral h) w h
