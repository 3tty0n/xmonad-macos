{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.MultiColumns (BSD-3-Clause),
-- Copyright (c) Anders Engstrom and the Xmonad Community.
module XMonad.Layout.MultiColumns (multiCol, MultiCol) where
import XMonad.Core
import XMonad.Layout (Resize(..), IncMasterN(..), splitVertically)
import qualified XMonad.StackSet as W
import Data.Maybe (listToMaybe)
import Control.Monad (msum)

multiCol :: [Int] -> Int -> Rational -> Rational -> MultiCol a
multiCol n defn ds s = MultiCol (map (max 0) n) (max 0 defn) ds s 0

data MultiCol a = MultiCol
  { multiColNWin :: ![Int]
  , multiColDefWin :: !Int
  , multiColDeltaSize :: !Rational
  , multiColSize :: !Rational
  , multiColActive :: !Int
  } deriving (Show, Read, Eq)

instance LayoutClass MultiCol a where
  doLayout l r s = pure (combine s rlist, resl)
    where rlist = doL (multiColNWin l') (multiColSize l') r wlen
          wlen = length $ W.integrate s
          nw = multiColNWin l ++ repeat (multiColDefWin l)
          l' = l { multiColNWin = take (max (length $ multiColNWin l) $ getCol (wlen-1) nw + 1) nw
                 , multiColActive = getCol (length $ W.up s) nw }
          resl = if l'==l then Nothing else Just l'
          combine (W.Stack foc left right) rs = zip (foc : reverse left ++ right) $ raiseFocused (length left) rs
  handleMessage l m = pure $ msum [resize <$> fromMessage m, incmastern <$> fromMessage m]
    where resize Shrink = l { multiColSize = max (-0.5) $ s-ds }
          resize Expand = l { multiColSize = min 1 $ s+ds }
          incmastern (IncMasterN x) = l { multiColNWin = take a n ++ [newval] ++ drop 1 rest }
            where newval = max 0 $ maybe 0 (x +) (listToMaybe rest)
                  rest = drop a n
          n = multiColNWin l
          ds = multiColDeltaSize l
          s = multiColSize l
          a = multiColActive l
  description _ = "MultiCol"

raiseFocused :: Int -> [a] -> [a]
raiseFocused n xs = actual ++ before ++ after
  where (before,rest) = splitAt n xs
        (actual,after) = splitAt 1 rest

getCol :: Int -> [Int] -> Int
getCol w (k:ns)
  | k < 1 || w < k = 0
  | otherwise = 1 + getCol (w-k) ns
getCol _ _ = 0

doL :: [Int] -> Rational -> Rectangle -> Int -> [Rectangle]
doL nwin s r n = rlist
  where ncol = getCol (n-1) nwin + 1
        size = floor $ abs s * fromIntegral (rect_width r)
        c = take (ncol-1) nwin
        col = c ++ [n-sum c]
        width
          | s>0 = if ncol==1
                  then [rect_width r]
                  else size : replicate (ncol-1) ((rect_width r - size) `div` (ncol-1))
          | fromIntegral ncol * abs s >= 1 = replicate ncol $ rect_width r `div` ncol
          | otherwise = (rect_width r - (ncol-1)*size) : replicate (ncol-1) size
        xpos = accumEx (rect_x r) width
        accumEx a (x:xs) = a : accumEx (a+x) xs
        accumEx _ _ = []
        cr = zipWith (\x w -> r { rect_x=x, rect_width=w }) xpos width
        rlist = concat $ zipWith splitVertically col cr
