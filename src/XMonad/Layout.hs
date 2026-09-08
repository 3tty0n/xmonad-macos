{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PatternGuards #-}
-- Adapted from xmonad Layout.hs, upstream a9a8b5c1. BSD-3-Clause.
-- Copyright (c) Spencer Janssen 2007; The Xmonad Community.
-- Changes: portable Rectangle; WindowRemoved instead of X DestroyWindowEvent;
-- comments abridged. Tall/Mirror/Choose algorithms retained.
module XMonad.Layout
  ( Full(..), Tall(..), Mirror(..), Resize(..), IncMasterN(..), Choose(..)
  , ThreeCol(..), Circle(CircleRatio,Circle), circleDelta, circleFrac
  , (|||), CLR(..), ChangeLayout(..), JumpToLayout(..), mirrorRect
  , splitVertically, splitHorizontally, splitHorizontallyBy, splitVerticallyBy
  , tile, tile3, split3HorizontallyBy
  ) where
import XMonad.Core
import qualified XMonad.StackSet as W
import Control.Arrow ((***), second)
import Control.Monad
import Data.Maybe (fromMaybe)

data Resize = Shrink | Expand
newtype IncMasterN = IncMasterN Int
instance Message Resize
instance Message IncMasterN
data Full a = Full deriving (Show,Read)
instance LayoutClass Full a where
  -- Every window keeps the whole frame, so entering Full never minimizes the
  -- others into the Dock; the focused window is placed last and raised.
  pureLayout _ r s = [(w,r) | w <- reverse (W.up s) ++ W.down s] ++ [(W.focus s,r)]
data Tall a = Tall
  { tallNMaster :: !Int, tallRatioIncrement :: !Rational, tallRatio :: !Rational }
  deriving (Show,Read)
instance LayoutClass Tall a where
  pureLayout (Tall nmaster _ frac) r s
    | frac == 0 = drop nmaster result
    | frac == 1 = take nmaster result
    | otherwise = result
    where ws = W.integrate s
          result = zip ws (tile frac r nmaster (length ws))
  pureMessage (Tall nmaster delta frac) m =
    msum [resize <$> fromMessage m, inc <$> fromMessage m]
    where resize Shrink = Tall nmaster delta (max 0 $ frac-delta)
          resize Expand = Tall nmaster delta (min 1 $ frac+delta)
          inc (IncMasterN d) = Tall (max 0 $ nmaster+d) delta frac
  description _ = "Tall"
tile :: Rational -> Rectangle -> Int -> Int -> [Rectangle]
tile f r nmaster n = if n <= nmaster || nmaster == 0
  then splitVertically n r
  else splitVertically nmaster r1 ++ splitVertically (n-nmaster) r2
  where (r1,r2) = splitHorizontallyBy f r
splitVertically, splitHorizontally :: Int -> Rectangle -> [Rectangle]
splitVertically n r | n < 2 = [r]
splitVertically n (Rectangle sx sy sw sh) = Rectangle sx sy sw smallh :
  splitVertically (n-1) (Rectangle sx (sy+smallh) sw (sh-smallh))
  where smallh = sh `div` n
splitHorizontally n = map mirrorRect . splitVertically n . mirrorRect
splitHorizontallyBy, splitVerticallyBy :: RealFrac r => r -> Rectangle -> (Rectangle,Rectangle)
splitHorizontallyBy f (Rectangle sx sy sw sh) =
  (Rectangle sx sy leftw sh, Rectangle (sx+leftw) sy (sw-leftw) sh)
  where leftw = floor $ fromIntegral sw * f
splitVerticallyBy f = (mirrorRect *** mirrorRect) . splitHorizontallyBy f . mirrorRect
-- Adapted from xmonad-contrib XMonad.Layout.ThreeColumns (BSD-3-Clause),
-- Copyright (c) Kai Grossjohann and the Xmonad Community. Master column plus
-- two stacks; ThreeColMid puts the master between them. `description` names
-- the two constructors apart, where upstream reports "ThreeCol" for both.
data ThreeCol a = ThreeCol
                    { threeColNMaster :: !Int, threeColDelta :: !Rational
                    , threeColFrac :: !Rational }
                | ThreeColMid
                    { threeColNMaster :: !Int, threeColDelta :: !Rational
                    , threeColFrac :: !Rational }
  deriving (Show,Read)
instance LayoutClass ThreeCol a where
  pureLayout l r s = zip ws (tile3 (middle l) (threeColFrac l) r (threeColNMaster l) (length ws))
    where ws = W.integrate s
          middle ThreeColMid{} = True
          middle ThreeCol{} = False
  pureMessage l m = msum [resize <$> fromMessage m, inc <$> fromMessage m]
    where resize Shrink = l {threeColFrac = max (-0.5) $ threeColFrac l - threeColDelta l}
          resize Expand = l {threeColFrac = min 1 $ threeColFrac l + threeColDelta l}
          inc (IncMasterN d) = l {threeColNMaster = max 0 $ threeColNMaster l + d}
  description ThreeColMid{} = "ThreeColMid"
  description ThreeCol{} = "ThreeCol"
-- A negative fraction is upstream's way of asking for a master narrower than
-- the side columns: it is read as 1+2f of the screen.
tile3 :: Bool -> Rational -> Rectangle -> Int -> Int -> [Rectangle]
tile3 middle f r nmaster n
  | n <= nmaster || nmaster == 0 = splitVertically n r
  | n <= nmaster+1 = splitVertically nmaster s1 ++ splitVertically (n-nmaster) s2
  | otherwise = splitVertically nmaster r1
             ++ splitVertically nmid r2 ++ splitVertically nright r3
  where (r1,r2,r3) = split3HorizontallyBy middle (if f<0 then 1+2*f else f) r
        (s1,s2) = splitHorizontallyBy (if f<0 then 1+f else f) r
        nslave = n-nmaster
        nmid = (nslave+1) `div` 2
        nright = nslave-nmid
split3HorizontallyBy :: RealFrac r => Bool -> r -> Rectangle
                     -> (Rectangle,Rectangle,Rectangle)
split3HorizontallyBy middle f (Rectangle sx sy sw sh)
  | middle = (Rectangle (sx+r3w) sy r1w sh, Rectangle sx sy r3w sh
             ,Rectangle (sx+r3w+r1w) sy r2w sh)
  | otherwise = (Rectangle sx sy r1w sh, Rectangle (sx+r1w) sy r2w sh
                ,Rectangle (sx+r1w+r2w) sy r3w sh)
  where r1w = ceiling $ fromIntegral sw * f
        r2w = ceiling $ fromIntegral (sw-r1w) / (2 :: Double)
        r3w = sw-r1w-r2w
-- Adapted from xmonad-contrib XMonad.Layout.Circle (BSD-3-Clause),
-- Copyright (c) Peter De Wachter and the Xmonad Community. The master window
-- takes a centred area and the rest orbit it, overlapping. The focused window
-- is placed last, which is how this port raises a window.
--
-- Upstream fixes the centre at 1/sqrt 2 of the frame. Here it is a field so
-- Shrink and Expand can resize it; `Circle` is that layout with upstream's
-- proportions, so an existing config keeps working unchanged.
data Circle a = CircleRatio { circleDelta :: !Rational, circleFrac :: !Rational }
  deriving (Show,Read)
pattern Circle :: Circle a
pattern Circle = CircleRatio 0.03 0.707
instance LayoutClass Circle a where
  pureLayout l r s = case splitAt (length $ W.up s) (circleLayout (circleFrac l) r ws) of
    (before,focused:after) -> before ++ after ++ [focused]
    (ps,[]) -> ps
    where ws = W.integrate s
  pureMessage l m = resize <$> fromMessage m
    where resize Shrink = l {circleFrac = max 0.1 $ circleFrac l - circleDelta l}
          resize Expand = l {circleFrac = min 1 $ circleFrac l + circleDelta l}
  description _ = "Circle"
circleLayout :: Rational -> Rectangle -> [a] -> [(a,Rectangle)]
circleLayout _ _ [] = []
circleLayout frac r (w:ws) = (w,centreRect frac r)
  : zip ws (map (satellite r) [0,2*pi/fromIntegral (length ws) ..])
centreRect :: Rational -> Rectangle -> Rectangle
centreRect frac (Rectangle sx sy sw sh) =
  Rectangle (sx+(sw-w) `div` 2) (sy+(sh-h) `div` 2) w h
  where w = max 1 $ round (fromIntegral sw * frac)
        h = max 1 $ round (fromIntegral sh * frac)
satellite :: Rectangle -> Double -> Rectangle
satellite (Rectangle sx sy sw sh) a =
  Rectangle (sx+round (rx+rx*cos a)) (sy+round (ry+ry*sin a)) w h
  where rx = fromIntegral (sw-w)/2 :: Double
        ry = fromIntegral (sh-h)/2 :: Double
        w = sw*10 `div` 25
        h = sh*10 `div` 25
newtype Mirror l a = Mirror (l a) deriving (Show,Read)
instance LayoutClass l a => LayoutClass (Mirror l) a where
  runLayout (W.Workspace i (Mirror l) ms) r =
    (map (second mirrorRect) *** fmap Mirror) <$>
      runLayout (W.Workspace i l ms) (mirrorRect r)
  handleMessage (Mirror l) = fmap (fmap Mirror) . handleMessage l
  description (Mirror l) = "Mirror " ++ description l
mirrorRect :: Rectangle -> Rectangle
mirrorRect (Rectangle x y w h) = Rectangle y x h w

data ChangeLayout = FirstLayout | NextLayout deriving (Eq,Show)
instance Message ChangeLayout
newtype JumpToLayout = JumpToLayout String
instance Message JumpToLayout
(|||) :: l a -> r a -> Choose l r a
(|||) = Choose CL
infixr 5 |||
data Choose l r a = Choose CLR (l a) (r a) deriving (Read,Show)
data CLR = CL | CR deriving (Read,Show,Eq)
data NextNoWrap = NextNoWrap deriving (Eq,Show)
instance Message NextNoWrap
handle :: (LayoutClass l a, Message m) => l a -> m -> X (Maybe (l a))
handle l m = handleMessage l (SomeMessage m)
choose :: (LayoutClass l a, LayoutClass r a)
       => Choose l r a -> CLR -> Maybe (l a) -> Maybe (r a) -> X (Maybe (Choose l r a))
choose (Choose d _ _) d' Nothing Nothing | d == d' = pure Nothing
choose (Choose d l r) d' ml mr = Just <$> liftM2 (Choose d') x y
  where
    l' = fromMaybe l ml
    r' = fromMaybe r mr
    hide z = fromMaybe z <$> handle z Hide
    (x,y) = case (d,d') of
      (CL,CR) -> (hide l',pure r')
      (CR,CL) -> (pure l',hide r')
      _ -> (pure l',pure r')
instance (LayoutClass l a, LayoutClass r a) => LayoutClass (Choose l r) a where
  runLayout (W.Workspace i (Choose CL l r) ms) =
    fmap (second . fmap $ flip (Choose CL) r) . runLayout (W.Workspace i l ms)
  runLayout (W.Workspace i (Choose CR l r) ms) =
    fmap (second . fmap $ Choose CR l) . runLayout (W.Workspace i r ms)
  description (Choose CL l _) = description l
  description (Choose CR _ r) = description r
  handleMessage lr m | Just NextLayout <- fromMessage m = do
    mlr <- handle lr NextNoWrap
    maybe (handle lr FirstLayout) (pure . Just) mlr
  handleMessage c@(Choose d l r) m | Just NextNoWrap <- fromMessage m = case d of
    CL -> do
      ml <- handle l NextNoWrap
      case ml of
        Just _ -> choose c CL ml Nothing
        Nothing -> choose c CR Nothing =<< handle r FirstLayout
    CR -> choose c CR Nothing =<< handle r NextNoWrap
  handleMessage c@(Choose _ l _) m | Just FirstLayout <- fromMessage m =
    flip (choose c CL) Nothing =<< handle l FirstLayout
  handleMessage c@(Choose d l r) m | Just ReleaseResources <- fromMessage m =
    join $ liftM2 (choose c d) (handle l ReleaseResources) (handle r ReleaseResources)
  handleMessage c@(Choose d l r) m | Just e@(WindowRemoved _) <- fromMessage m =
    join $ liftM2 (choose c d) (handle l e) (handle r e)
  handleMessage c@(Choose d l r) m | Just (JumpToLayout desc) <- fromMessage m = do
    ml <- handleMessage l m
    mr <- handleMessage r m
    let d' | desc == description (fromMaybe l ml) = CL
           | desc == description (fromMaybe r mr) = CR
           | otherwise = d
    choose c d' ml mr
  handleMessage c@(Choose d l r) m = do
    ml <- if d == CL then handleMessage l m else pure Nothing
    mr <- if d == CR then handleMessage r m else pure Nothing
    choose c d ml mr
