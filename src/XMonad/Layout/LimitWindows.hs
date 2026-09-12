{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.LimitWindows (BSD-3-Clause),
-- Copyright (c) Adam Vogt, Max Rabkin and the Xmonad Community.
-- limitSelect is not ported.
module XMonad.Layout.LimitWindows
  ( limitWindows, limitSlice, increaseLimit, decreaseLimit, setLimit
  , LimitWindows
  ) where
import Control.Monad ((<=<), guard)
import Data.Maybe (fromJust)
import XMonad.Core
import XMonad.Layout.LayoutModifier
import XMonad.Operations (sendMessage)
import qualified XMonad.StackSet as W

increaseLimit, decreaseLimit :: X ()
increaseLimit = sendMessage $ LimitChange succ
decreaseLimit = sendMessage . LimitChange $ max 1 . pred

setLimit :: Int -> X ()
setLimit tgt = sendMessage . LimitChange $ const tgt

limitWindows :: Int -> l a -> ModifiedLayout LimitWindows l a
limitWindows n = ModifiedLayout (LimitWindows FirstN n)

limitSlice :: Int -> l a -> ModifiedLayout LimitWindows l a
limitSlice n = ModifiedLayout (LimitWindows Slice n)

data LimitWindows a = LimitWindows SliceStyle Int deriving (Read, Show)
data SliceStyle = FirstN | Slice deriving (Read, Show)
newtype LimitChange = LimitChange { unLC :: Int -> Int }
instance Message LimitChange

instance LayoutModifier LimitWindows a where
  pureMess (LimitWindows s n) =
    fmap (LimitWindows s) . pos <=< (`applyN` n) . unLC <=< fromMessage
    where pos x = guard (x>=1) >> Just x
          applyN f x = guard (f x /= x) >> Just (f x)
  modifyLayout (LimitWindows style n) ws =
    runLayout ws { W.stack = f n <$> W.stack ws }
    where f = case style of
            FirstN -> firstN
            Slice -> slice

firstN :: Int -> W.Stack a -> W.Stack a
firstN n st = upfocus $ fromJust $ W.differentiate $ take (max 1 n) $ W.integrate st
  where upfocus = foldr (.) id $ replicate (length (W.up st)) W.focusDown'

slice :: Int -> W.Stack t -> W.Stack t
slice n (W.Stack f u d) = W.Stack f (take (nu + unusedD) u) (take (nd + unusedU) d)
  where unusedD = max 0 $ nd - length d
        unusedU = max 0 $ nu - length u
        nd = div (n - 1) 2
        nu = uncurry (+) $ divMod (n - 1) 2
