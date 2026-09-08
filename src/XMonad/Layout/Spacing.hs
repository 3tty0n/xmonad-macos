{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Small native-safe module; not the complete xmonad-contrib Spacing API.
module XMonad.Layout.Spacing (Spacing, spacing, spacingRawSimple, inset) where
import XMonad.Core
import qualified XMonad.StackSet as W

data Spacing l a = Spacing Int (l a) deriving (Show,Read)
spacing :: Int -> l a -> Spacing l a
spacing n = Spacing (max 0 n)
spacingRawSimple :: Int -> l a -> Spacing l a
spacingRawSimple = spacing
instance LayoutClass l a => LayoutClass (Spacing l) a where
  runLayout (W.Workspace t (Spacing n l) s) r = do
    (rs,ml) <- runLayout (W.Workspace t l s) r
    pure ([(w,inset n rect) | (w,rect) <- rs], Spacing n <$> ml)
  handleMessage (Spacing n l) m = fmap (Spacing n) <$> handleMessage l m
  description (Spacing _ l) = description l
inset :: Int -> Rectangle -> Rectangle
inset n (Rectangle x y w h) = Rectangle (x+dx) (y+dy) (max 1 $ w-2*dx) (max 1 $ h-2*dy)
  where dx = max 0 $ min n ((w-1) `div` 2)
        dy = max 0 $ min n ((h-1) `div` 2)
