{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.Grid (BSD-3-Clause),
-- Copyright (c) Lukas Mai and the Xmonad Community.
module XMonad.Layout.Grid (Grid(..)) where
import XMonad.Core
import XMonad.Layout (splitVertically, splitHorizontally)
import qualified XMonad.StackSet as W

data Grid a = Grid | GridRatio !Double deriving (Show,Read)
instance LayoutClass Grid a where
  pureLayout Grid r s = pureLayout (GridRatio (16/9)) r s
  pureLayout (GridRatio ratio) r s = zip ws (arrange ratio r (length ws))
    where ws = W.integrate s
  description _ = "Grid"

-- Columns are chosen to keep cells near the requested aspect ratio, then the
-- windows are spread over them as evenly as possible.
arrange :: Double -> Rectangle -> Int -> [Rectangle]
arrange _ _ n | n < 1 = []
arrange ratio r@(Rectangle _ _ rw rh) n = concat
  [splitVertically k c | (k,c) <- zip counts (splitHorizontally ncolumns r)]
  where
    ncolumns = max 1 $ min n $ round $ sqrt $
      fromIntegral n * fromIntegral rw / (ratio * fromIntegral rh)
    (q,e) = n `divMod` ncolumns
    counts = replicate e (q+1) ++ replicate (ncolumns-e) q
