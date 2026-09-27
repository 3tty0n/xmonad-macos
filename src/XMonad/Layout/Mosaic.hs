{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PatternGuards #-}
-- Adapted from xmonad-contrib XMonad.Layout.Mosaic (BSD-3-Clause),
-- Copyright (c) 2009 Adam Vogt, 2007 James Webb and the Xmonad Community.
-- Changes: LayoutClass only (no X11); the geometry lives in a pure
-- `pureLayout` so it can be tested without running X, while `doLayout` keeps
-- upstream's aspect-index bookkeeping. `MosaicAlt`/`MosaicMsg` are not part of
-- this module: MosaicAlt is a separate upstream layout
-- (XMonad.Layout.MosaicAlt), and MosaicMsg is not exported by upstream.
module XMonad.Layout.Mosaic
  ( Aspect(..), mosaic, changeMaster, changeFocused, Mosaic(..)
  ) where
import XMonad.Core
import XMonad.Layout (Resize(..), splitHorizontallyBy, splitVerticallyBy)
import XMonad.Operations (sendMessage, withWindowSet)
import qualified XMonad.StackSet as W
import Control.Arrow (first, second)
import Control.Monad (mplus)
import Data.Function (on)
import Data.List (sortBy)

-- | The message that chooses an aspect ratio or changes the relative sizes.
data Aspect
  = Taller
  | Wider
  | Reset
  | SlopeMod ([Rational] -> [Rational])

instance Message Aspect

-- | @mosaic delta sizes@ gives each window a share of the frame set by the
-- relative magnitudes in @sizes@ (the sign is ignored). The first entry is the
-- master window; the list is extended with @++ repeat 1@. The first parameter
-- is the factor used for 'Expand' and 'Shrink' on the focused window.
mosaic :: Rational -> [Rational] -> Mosaic a
mosaic = Mosaic Nothing

-- | True to override the aspect, current index, maximum index.
data Mosaic a = Mosaic (Maybe (Bool, Rational, Int)) Rational [Rational]
  deriving (Read, Show)

instance LayoutClass Mosaic a where
  description _ = "Mosaic"

  -- The selected arrangement, drawn without touching the aspect state.
  pureLayout (Mosaic mstate _ ss) r st =
    zip ws (variants !! aspectIndex mstate nls)
    where
      ws = W.integrate st
      ssExt = zipWith const (ss ++ repeat 1) ws
      variants = splits r ssExt
      nls = length variants

  pureMessage (Mosaic Nothing _ _) _ = Nothing
  pureMessage (Mosaic (Just (_, ix, mix)) delta ss) ms = fromMessage ms >>= ixMod
    where
      ixMod Taller | round ix >= mix = Nothing
                   | otherwise = Just $ Mosaic (Just (False, succ ix, mix)) delta ss
      ixMod Wider  | round ix <= (0 :: Integer) = Nothing
                   | otherwise = Just $ Mosaic (Just (False, pred ix, mix)) delta ss
      ixMod Reset                = Just $ Mosaic Nothing delta ss
      ixMod (SlopeMod f)         = Just $ Mosaic (Just (False, ix, mix)) delta (f ss)

  handleMessage l@(Mosaic _ delta _) ms
    | Just Expand <- fromMessage ms = changeFocused (*delta) >> pure Nothing
    | Just Shrink <- fromMessage ms = changeFocused (/delta) >> pure Nothing
    | otherwise = pure (pureMessage l ms)

  -- Upstream's mutable aspect index lives in the layout value, so `doLayout`
  -- advances it while `pureLayout` reproduces the same geometry immutably.
  doLayout (Mosaic mstate delta ss) r st =
    pure (zip ws (variants !! aspectIndex mstate nls), Just (Mosaic state' delta ss'))
    where
      ws = W.integrate st
      ssExt = zipWith const (ss ++ repeat 1) ws
      variants = splits r ssExt
      nls = length variants
      state' = fmap (\x@(ov, _, _) -> (ov, nextIx x nls, pred nls)) mstate
                 `mplus` Just (True, fromIntegral nls / 2, pred nls)
      ss' = maybe ss (either (const ss) (const ssExt)) (zipRemain ss ssExt)

-- The index of the arrangement the aspect state selects; the middle one when
-- there is no override.
aspectIndex :: Maybe (Bool, Rational, Int) -> Int -> Int
aspectIndex Nothing nls = nls `div` 2
aspectIndex (Just s) nls = round (nextIx s nls)

nextIx :: (Bool, Rational, Int) -> Int -> Rational
nextIx (ov, ix, mix) nls
  | mix <= 0 || ov = fromIntegral $ nls `div` 2
  | otherwise = max 0 $ (* fromIntegral (pred nls)) $ min 1 $ ix / fromIntegral mix

zipRemain :: [a] -> [b] -> Maybe (Either [a] [b])
zipRemain (_:xs) (_:ys) = zipRemain xs ys
zipRemain [] [] = Nothing
zipRemain [] y = Just (Right y)
zipRemain x [] = Just (Left x)

-- | Apply a function to the master window's relative size.
changeMaster :: (Rational -> Rational) -> X ()
changeMaster = sendMessage . SlopeMod . onHead

-- | Apply a function to the ratio that represents the focused window.
changeFocused :: (Rational -> Rational) -> X ()
changeFocused f = withWindowSet $ sendMessage . SlopeMod
                    . maybe id (mulIx . length . W.up)
                    . W.stack . W.workspace . W.current
  where mulIx i = uncurry (++) . second (onHead f) . splitAt i

onHead :: (a -> a) -> [a] -> [a]
onHead f = uncurry (++) . first (fmap f) . splitAt 1

splits :: Rectangle -> [Rational] -> [[Rectangle]]
splits rect = map (reverse . map snd . sortBy (compare `on` fst))
                . splitsL rect . makeTree snd . zip [1..]
                . normalize . reverse . map abs

splitsL :: Rectangle -> Tree (Int, Rational) -> [[(Int, Rectangle)]]
splitsL _rect Empty = []
splitsL rect (Leaf (x, _)) = [[(x, rect)]]
splitsL rect (Branch l r) = do
  let mkSplit f = f ((sumSnd l /) $ sumSnd l + sumSnd r) rect
      sumSnd = sum . fmap snd
  (rl, rr) <- map mkSplit [splitVerticallyBy, splitHorizontallyBy]
  splitsL rl l `interleave` splitsL rr r

-- like zipWith (++), but when one list is shorter, its elements are duplicated
-- so that they match
interleave :: [[a]] -> [[a]] -> [[a]]
interleave xs ys | lx > ly = zc xs (extend lx ys)
                 | otherwise = zc (extend ly xs) ys
  where lx = length xs
        ly = length ys
        zc = zipWith (++)

        extend :: Int -> [a] -> [a]
        extend n pat = do
          (p, e) <- zip pat $ replicate m True ++ repeat False
          [p | e] ++ replicate d p
          where (d, m) = n `divMod` length pat

normalize :: Fractional a => [a] -> [a]
normalize x = let s = sum x in map (/s) x

data Tree a = Branch (Tree a) (Tree a) | Leaf a | Empty
  deriving (Functor, Show, Foldable)

instance Semigroup (Tree a) where
  Empty <> x = x
  x <> Empty = x
  x <> y = Branch x y

instance Monoid (Tree a) where
  mempty = Empty

makeTree :: (Num a1, Ord a1) => (a -> a1) -> [a] -> Tree a
makeTree _ [] = Empty
makeTree _ [x] = Leaf x
makeTree f xs = Branch (makeTree f a) (makeTree f b)
  where ((a, b), _) = foldr go (([], []), (0, 0)) xs
        go n ((ls, rs), (l, r))
          | l > r = ((ls, n:rs), (l, f n + r))
          | otherwise = ((n:ls, rs), (f n + l, r))
