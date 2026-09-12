{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.Gaps (BSD-3-Clause),
-- Copyright (c) Brent Yorgey and the Xmonad Community.
module XMonad.Layout.Gaps
  ( Direction2D(..), Gaps, GapSpec, gaps, gaps', GapMessage(..)
  , weakModifyGaps, modifyGap, setGaps, setGap
  ) where
import Data.List (delete)
import XMonad.Core
import XMonad.Layout.LayoutModifier
import XMonad.Util.Types (Direction2D(..))

type GapSpec = [(Direction2D, Int)]

data Gaps a = Gaps GapSpec [Direction2D] deriving (Show, Read)

data GapMessage
  = ToggleGaps
  | ToggleGap !Direction2D
  | IncGap !Int !Direction2D
  | DecGap !Int !Direction2D
  | ModifyGaps (GapSpec -> GapSpec)

instance Message GapMessage

instance LayoutModifier Gaps a where
  modifyLayout g w r = runLayout w (applyGaps g r)
  pureMess (Gaps conf cur) m
    | Just ToggleGaps <- fromMessage m = Just $ Gaps conf (toggleGaps conf cur)
    | Just (ToggleGap d) <- fromMessage m = Just $ Gaps conf (toggleGap conf cur d)
    | Just (IncGap i d) <- fromMessage m = Just $ Gaps (limit . continuation (+i) d $ conf) cur
    | Just (DecGap i d) <- fromMessage m = Just $ Gaps (limit . continuation (+(-i)) d $ conf) cur
    | Just (ModifyGaps f) <- fromMessage m = Just $ Gaps (limit . f $ conf) cur
    | otherwise = Nothing

weakModifyGaps :: (Direction2D -> Int -> Int) -> GapMessage
weakModifyGaps = ModifyGaps . weakToStrong

modifyGap :: (Int -> Int) -> Direction2D -> GapMessage
modifyGap f d = ModifyGaps $ continuation f d

setGaps :: GapSpec -> GapMessage
setGaps = ModifyGaps . const

setGap :: Int -> Direction2D -> GapMessage
setGap = modifyGap . const

limit :: GapSpec -> GapSpec
limit = weakToStrong $ \_ -> max 0

weakToStrong :: (Direction2D -> Int -> Int) -> GapSpec -> GapSpec
weakToStrong f gs = zip (map fst gs) (map (uncurry f) gs)

continuation :: (Int -> Int) -> Direction2D -> GapSpec -> GapSpec
continuation f d1 = weakToStrong h
  where h d2 | d2 == d1 = f
             | otherwise = id

applyGaps :: Gaps a -> Rectangle -> Rectangle
applyGaps gs r = foldr applyGap r (activeGaps gs)
  where
    applyGap (U,z) (Rectangle x y w h) = Rectangle x (y + z) w (max 1 $ h - z)
    applyGap (D,z) (Rectangle x y w h) = Rectangle x y w (max 1 $ h - z)
    applyGap (L,z) (Rectangle x y w h) = Rectangle (x + z) y (max 1 $ w - z) h
    applyGap (R,z) (Rectangle x y w h) = Rectangle x y (max 1 $ w - z) h

activeGaps :: Gaps a -> GapSpec
activeGaps (Gaps conf cur) = filter ((`elem` cur) . fst) conf

toggleGaps :: GapSpec -> [Direction2D] -> [Direction2D]
toggleGaps conf [] = map fst conf
toggleGaps _    _  = []

toggleGap :: GapSpec -> [Direction2D] -> Direction2D -> [Direction2D]
toggleGap conf cur d
  | d `elem` cur = delete d cur
  | d `elem` map fst conf = d:cur
  | otherwise = cur

gaps :: GapSpec -> l a -> ModifiedLayout Gaps l a
gaps g = ModifiedLayout (Gaps g (map fst g))

gaps' :: [((Direction2D, Int), Bool)] -> l a -> ModifiedLayout Gaps l a
gaps' g = ModifiedLayout (Gaps (map fst g) [d | ((d,_),v) <- g, v])
