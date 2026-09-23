{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE UndecidableInstances #-}
-- Adapted from xmonad-contrib XMonad.Layout.MultiToggle (BSD-3-Clause),
-- Copyright (c) Lukas Mai and the Xmonad Community.
module XMonad.Layout.MultiToggle
  ( Transformer(..), Toggle(..), (??), EOT(..), single, mkToggle, mkToggle1
  , HList, HCons, MultiToggle
  ) where
import XMonad.Core
import qualified XMonad.StackSet as W
import Data.Maybe (fromMaybe)
import Data.Typeable (cast)

-- A transformer wraps a layout and knows how to take its wrapper off again.
class (Eq t, Typeable t) => Transformer t a | t -> a where
  transform :: LayoutClass l a => t -> l a
            -> (forall l'. LayoutClass l' a => l' a -> (l' a -> l a) -> b) -> b

data EL l a = forall l'. LayoutClass l' a => EL (l' a) (l' a -> l a)

unEL :: LayoutClass l a => EL l a -> (forall l'. LayoutClass l' a => l' a -> b) -> b
unEL (EL x _) k = k x

deEL :: LayoutClass l a => EL l a -> l a
deEL (EL x det) = det x

transform' :: (Transformer t a, LayoutClass l a) => t -> EL l a -> EL l a
transform' t (EL l det) = transform t l (\l' det' -> EL l' (det . det'))

-- Toggle the transformer on, or off when it is the one already on.
data Toggle a = forall t. Transformer t a => Toggle t
instance Typeable a => Message (Toggle a)

data MultiToggleS ts l a = MultiToggleS (l a) (Maybe Int) ts deriving (Read, Show)

data MultiToggle ts l a = MultiToggle
  { currLayout :: EL l a, currIndex :: Maybe Int, transformers :: ts }

expand :: (LayoutClass l a, HList ts a) => MultiToggleS ts l a -> MultiToggle ts l a
expand (MultiToggleS b i ts) =
  resolve ts (fromMaybe (-1) i) id
    (\x mt -> mt { currLayout = transform' x (currLayout mt) })
    (MultiToggle (EL b id) i ts)

collapse :: LayoutClass l a => MultiToggle ts l a -> MultiToggleS ts l a
collapse mt = MultiToggleS (deEL (currLayout mt)) (currIndex mt) (transformers mt)

instance (LayoutClass l a, Read (l a), HList ts a, Read ts) => Read (MultiToggle ts l a) where
  readsPrec p s = [(expand x, r) | (x, r) <- readsPrec p s]

instance (Show ts, Show (l a), LayoutClass l a) => Show (MultiToggle ts l a) where
  showsPrec p = showsPrec p . collapse

mkToggle :: LayoutClass l a => ts -> l a -> MultiToggle ts l a
mkToggle ts l = MultiToggle (EL l id) Nothing ts

mkToggle1 :: LayoutClass l a => t -> l a -> MultiToggle (HCons t EOT) l a
mkToggle1 t = mkToggle (single t)

data EOT = EOT deriving (Read, Show)
data HCons a b = HCons a b deriving (Read, Show)

infixr 0 ??
(??) :: a -> b -> HCons a b
(??) = HCons

single :: a -> HCons a EOT
single = (?? EOT)

class HList c a where
  find :: Transformer t a => c -> t -> Maybe Int
  resolve :: c -> Int -> b -> (forall t. Transformer t a => t -> b) -> b

instance HList EOT w where
  find EOT _ = Nothing
  resolve EOT _ d _ = d

instance (Transformer a w, HList b w) => HList (HCons a b) w where
  find (HCons x xs) t
    | Just x == cast t = Just 0
    | otherwise = succ <$> find xs t
  resolve (HCons x xs) n d k = case compare n 0 of
    LT -> d
    EQ -> k x
    GT -> resolve xs (pred n) d k

instance (Typeable a, Show ts, Typeable ts, HList ts a, LayoutClass l a)
    => LayoutClass (MultiToggle ts l) a where
  description mt = unEL (currLayout mt) description
  runLayout (W.Workspace i mt s) r = case currLayout mt of
    EL l det -> fmap (fmap (\x -> mt { currLayout = EL x det }))
                  <$> runLayout (W.Workspace i l s) r
  handleMessage mt m
    | Just (Toggle t) <- fromMessage m, i@(Just _) <- find (transformers mt) t =
        case currLayout mt of
          EL l det -> do
            l' <- fromMaybe l <$> handleMessage l (SomeMessage ReleaseResources)
            let cur = i == currIndex mt
            pure $ Just mt
              { currLayout = (if cur then id else transform' t) (EL (det l') id)
              , currIndex = if cur then Nothing else i }
    | otherwise = case currLayout mt of
        EL l det -> fmap (\x -> mt { currLayout = EL x det }) <$> handleMessage l m
