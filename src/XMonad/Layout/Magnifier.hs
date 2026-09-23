{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.Magnifier (BSD-3-Clause),
-- Copyright (c) 2007 Andrea Rossato and the Xmonad Community. Two changes:
-- the magnified window is placed last, which is the top of the stack here,
-- and rectangles are signed logical points rather than Position/Dimension.
module XMonad.Layout.Magnifier
  ( Magnifier, MagnifyMsg(..), MagnifyThis(..)
  , magnify, magnifyxy
  , magnifier, magnifierOff, magnifiercz, magnifierczOff
  , magnifierxy, magnifierxyOff, maxMagnifierOff, maximizeVertical
  , magnifier', magnifiercz', magnifierczOff'
  , magnifierxy', magnifierxyOff'
  ) where
import XMonad.Core
import XMonad.Layout (IncMasterN(..))
import XMonad.Layout.LayoutModifier
import XMonad.Operations (withWindowSet)
import qualified XMonad.StackSet as W
import Numeric.Natural (Natural)

data Toggle = On | Off deriving (Read, Show)

-- Which windows may be magnified, and the least number of windows on screen
-- for magnifying to happen at all.
data MagnifyThis = AllWins !Natural | NoMaster !Natural deriving (Read, Show)

data Magnifier a = Mag
  { masterWins :: !Natural
  , zoomFactor :: !(Double, Double)
  , toggle :: !Toggle
  , magWhen :: !MagnifyThis
  } deriving (Read, Show)

data MagnifyMsg = MagnifyMore | MagnifyLess | ToggleOn | ToggleOff | Toggle
  deriving (Read, Show)

instance Message MagnifyMsg

instance LayoutModifier Magnifier Window where
  redoLayout _ _ Nothing wrs = pure (wrs, Nothing)
  redoLayout (Mag n z t scope) r (Just s) wrs = case (t, scope) of
    (On, AllWins k)
      | fromIntegral k <= length (W.integrate s) -> magnifyFocused z r wrs
    (On, NoMaster k)
      | fromIntegral k <= length (W.integrate s)
      , not (null (drop (fromIntegral n - 1) (W.up s))) -> magnifyFocused z r wrs
    _ -> pure (wrs, Nothing)
  handleMess (Mag n z On scope) mess
    | Just MagnifyMore <- fromMessage mess = pure $ Just $ Mag n (addto z 0.1) On scope
    | Just MagnifyLess <- fromMessage mess =
        pure $ Just $ Mag n (addto z (-0.1)) On scope
    | Just ToggleOff <- fromMessage mess = pure $ Just $ Mag n z Off scope
    | Just Toggle <- fromMessage mess = pure $ Just $ Mag n z Off scope
    | Just (IncMasterN d) <- fromMessage mess =
        pure $ Just $ Mag (max 0 (n + fromIntegral d)) z On scope
    | otherwise = pure Nothing
  handleMess (Mag n z Off scope) mess
    | Just ToggleOn <- fromMessage mess = pure $ Just $ Mag n z On scope
    | Just Toggle <- fromMessage mess = pure $ Just $ Mag n z On scope
    | Just (IncMasterN d) <- fromMessage mess =
        pure $ Just $ Mag (max 0 (n + fromIntegral d)) z Off scope
    | otherwise = pure Nothing
  modifierDescription (Mag _ _ On (AllWins _)) = "Magnifier"
  modifierDescription (Mag _ _ On (NoMaster _)) = "Magnifier NoMaster"
  modifierDescription _ = "Magnifier (off)"

addto :: (Double, Double) -> Double -> (Double, Double)
addto (x, y) i = (x + i, y + i)

-- Scale the focused window about its centre, clip it to the layout rectangle,
-- and put it last so the neighbours it covers stay underneath.
magnifyFocused :: (Double, Double) -> Rectangle -> [(Window, Rectangle)]
               -> X ([(Window, Rectangle)], Maybe (Magnifier Window))
magnifyFocused z r wrs = do
  focused <- withWindowSet (pure . W.peek)
  pure (foldr (step focused z r) [] wrs, Nothing)

step :: Maybe Window -> (Double, Double) -> Rectangle -> (Window, Rectangle)
     -> [(Window, Rectangle)] -> [(Window, Rectangle)]
step focused z r (w, wr) acc
  | Just w == focused = acc ++ [(w, fit r (scaleRect z wr))]
  | otherwise = (w, wr) : acc

scaleRect :: (Double, Double) -> Rectangle -> Rectangle
scaleRect (zx, zy) (Rectangle x y w h) =
  Rectangle (x - dw `div` 2) (y - dh `div` 2) w' h'
  where
    w' = round (fromIntegral w * zx)
    h' = round (fromIntegral h * zy)
    dw = w' - w
    dh = h' - h

-- Cap the size at the layout rectangle and pull it back inside.
fit :: Rectangle -> Rectangle -> Rectangle
fit (Rectangle sx sy sw sh) (Rectangle x y w h) = Rectangle x' y' w' h'
  where
    w' = min sw w
    h' = min sh h
    x' = max sx (x - max 0 (x + w - sx - sw))
    y' = max sy (y - max 0 (y + h - sy - sh))

magnifyxy :: Rational -> Rational -> MagnifyThis -> Bool
          -> l Window -> ModifiedLayout Magnifier l Window
magnifyxy cx cy mt start = ModifiedLayout $
  Mag 1 (fromRational cx, fromRational cy) (if start then On else Off) mt

magnify :: Rational -> MagnifyThis -> Bool
        -> l Window -> ModifiedLayout Magnifier l Window
magnify cz = magnifyxy cz cz

magnifier :: l Window -> ModifiedLayout Magnifier l Window
magnifier = magnifiercz 1.5

magnifiercz :: Rational -> l Window -> ModifiedLayout Magnifier l Window
magnifiercz cz = magnify cz (AllWins 1) True

magnifierOff :: l Window -> ModifiedLayout Magnifier l Window
magnifierOff = magnifierczOff 1.5

magnifierczOff :: Rational -> l Window -> ModifiedLayout Magnifier l Window
magnifierczOff cz = magnify cz (AllWins 1) False

maxMagnifierOff :: l Window -> ModifiedLayout Magnifier l Window
maxMagnifierOff = magnifierczOff 1000

magnifierxy :: Rational -> Rational -> l Window
            -> ModifiedLayout Magnifier l Window
magnifierxy cx cy = magnifyxy cx cy (AllWins 1) True

magnifierxyOff :: Rational -> Rational -> l Window
               -> ModifiedLayout Magnifier l Window
magnifierxyOff cx cy = magnifyxy cx cy (AllWins 1) False

magnifier' :: l Window -> ModifiedLayout Magnifier l Window
magnifier' = magnifiercz' 1.5

magnifiercz' :: Rational -> l Window -> ModifiedLayout Magnifier l Window
magnifiercz' cz = magnify cz (NoMaster 1) True

magnifierczOff' :: Rational -> l Window -> ModifiedLayout Magnifier l Window
magnifierczOff' cz = magnify cz (NoMaster 1) False

magnifierxy' :: Rational -> Rational -> l Window
             -> ModifiedLayout Magnifier l Window
magnifierxy' cx cy = magnifyxy cx cy (NoMaster 1) True

magnifierxyOff' :: Rational -> Rational -> l Window
                -> ModifiedLayout Magnifier l Window
magnifierxyOff' cx cy = magnifyxy cx cy (NoMaster 1) False

maximizeVertical :: l Window -> ModifiedLayout Magnifier l Window
maximizeVertical = ModifiedLayout $ Mag 1 (1, 1000) Off (AllWins 1)
