{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.ResizableThreeColumns (BSD-3-Clause),
-- Copyright (c) Sam Tay and the Xmonad Community.
module XMonad.Layout.ResizableThreeCol
  (ResizableThreeCol(..), MirrorResize(..)) where
import XMonad.Core
import XMonad.Layout (Resize(..), IncMasterN(..), splitHorizontallyBy)
import XMonad.Layout.ResizableTile (MirrorResize(..))
import qualified XMonad.StackSet as W
import Control.Monad (msum)
import Data.Ratio ((%))

-- Like ThreeCol, but the master column fraction and the per-window heights of
-- the two stacks can be resized. A negative fraction means the stack columns,
-- not the master, name the fraction of the screen they should occupy.
data ResizableThreeCol a = ResizableThreeColMid
  { threeColNMaster :: !Int
  , threeColDelta :: !Rational
  , threeColFrac :: !Rational
  , threeColSlaves :: [Rational]
  }
  | ResizableThreeCol
  { threeColNMaster :: !Int
  , threeColDelta :: !Rational
  , threeColFrac :: !Rational
  , threeColSlaves :: [Rational]
  } deriving (Show,Read)

instance LayoutClass ResizableThreeCol a where
  pureLayout l r s = zip ws (tile3 (middle l) (threeColFrac l)
                              (threeColSlaves l ++ repeat 1) r
                              (threeColNMaster l) (length ws))
    where ws = W.integrate s
          middle ResizableThreeColMid{} = True
          middle ResizableThreeCol{} = False
  pureMessage l m = msum [resize <$> fromMessage m, inc <$> fromMessage m]
    where
      resize Shrink = l {threeColFrac = max (-0.5) $ threeColFrac l - threeColDelta l}
      resize Expand = l {threeColFrac = min 1 $ threeColFrac l + threeColDelta l}
      inc (IncMasterN d) = l {threeColNMaster = max 0 $ threeColNMaster l + d}
  -- A mirror resize needs to know which window is focused, so it cannot be a
  -- pure message like Shrink and Expand.
  handleMessage l m
    | Just e <- fromMessage m = do
        stack <- gets (W.stack . W.workspace . W.current . windowset)
        pure (mirrorResize l e <$> stack)
    | otherwise = pure (pureMessage l m)
  -- Upstream reports "ResizableThreeCol" for both variants; naming them apart
  -- matches this port's ThreeCol so Choose can tell them apart.
  description ResizableThreeColMid{} = "ResizableThreeColMid"
  description ResizableThreeCol{} = "ResizableThreeCol"

mirrorResize :: ResizableThreeCol a -> MirrorResize -> W.Stack w -> ResizableThreeCol a
mirrorResize l e stack = l {threeColSlaves = take total modified}
  where
    nmaster = threeColNMaster l
    delta = case e of MirrorShrink -> threeColDelta l
                      MirrorExpand -> negate (threeColDelta l)
    up = length (W.up stack)
    down = length (W.down stack)
    total = up + down + 1
    -- Focused window's position in the flattened weight list, adjusted so the
    -- two stack columns keep a shared height where upstream does.
    pos = if up == nmaster - 1
             || up == total - 1
             || up `elem` [down, down + 1]
            then up - 1
            else up
    modified = modifymfrac (threeColSlaves l ++ repeat 1) delta pos
    modifymfrac [] _ _ = []
    modifymfrac (f:fx) d n
      | n == 0 = f+d : fx
      | otherwise = f : modifymfrac fx d (n-1)

-- Master column plus the two stacks. With enough windows each stack gets its
-- own column; weights accumulate in flattened window order.
tile3 :: Bool -> Rational -> [Rational] -> Rectangle -> Int -> Int -> [Rectangle]
tile3 middle f mf r nmaster n
  | n <= nmaster || nmaster == 0 = splitVertically mf n r
  | n <= nmaster+1 = splitVertically mf nmaster s1
                  ++ splitVertically (drop nmaster mf) (n-nmaster) s2
  | otherwise = splitVertically mf nmaster r1
             ++ splitVertically (drop nmaster mf) nstack1 r2
             ++ splitVertically (drop (nmaster+nstack1) mf) nstack2 r3
  where
    (r1,r2,r3) = split3HorizontallyBy middle (if f<0 then 1+2*f else f) r
    (s1,s2) = splitHorizontallyBy (if f<0 then 1+f else f) r
    nstack = n - nmaster
    nstack1 = ceiling (nstack % 2) :: Int
    nstack2 = nstack - nstack1

-- Weighted vertical split: each window takes its share of the average height of
-- those still to place, so one window can be made taller without a full reflow.
splitVertically :: RealFrac r => [r] -> Int -> Rectangle -> [Rectangle]
splitVertically [] _ r = [r]
splitVertically _ n r | n < 2 = [r]
splitVertically (f:fx) n (Rectangle sx sy sw sh) =
  let smallh = min sh (floor $ fromIntegral (sh `div` n) * f)
  in Rectangle sx sy sw smallh :
       splitVertically fx (n-1) (Rectangle sx (sy+smallh) sw (sh-smallh))

split3HorizontallyBy :: Bool -> Rational -> Rectangle -> (Rectangle,Rectangle,Rectangle)
split3HorizontallyBy middle f (Rectangle sx sy sw sh)
  | middle = ( Rectangle (sx+r3w) sy r1w sh
             , Rectangle (sx+r3w+r1w) sy r2w sh
             , Rectangle sx sy r3w sh )
  | otherwise = ( Rectangle sx sy r1w sh
                , Rectangle (sx+r1w) sy r2w sh
                , Rectangle (sx+r1w+r2w) sy r3w sh )
  where r1w = ceiling $ fromIntegral sw * f
        r2w = ceiling $ (sw-r1w) % 2
        r3w = sw-r1w-r2w
