{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PatternGuards #-}
-- Adapted from xmonad Layout.hs, upstream a9a8b5c1. BSD-3-Clause.
-- Copyright (c) Spencer Janssen 2007; The Xmonad Community.
-- Changes: portable Rectangle; WindowRemoved instead of X DestroyWindowEvent;
-- comments abridged. Tall/Mirror/Choose algorithms retained.
module XMonad.Layout
  ( Full(..), Tall(..), Mirror(..), Resize(..), IncMasterN(..), Choose(..)
  , (|||), CLR(..), ChangeLayout(..), JumpToLayout(..), mirrorRect
  , splitVertically, splitHorizontally, splitHorizontallyBy, splitVerticallyBy, tile
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
