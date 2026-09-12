{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.ToggleLayouts (BSD-3-Clause),
-- Copyright (c) David Roundy and the Xmonad Community.
module XMonad.Layout.ToggleLayouts (toggleLayouts, ToggleLayout(..), ToggleLayouts) where
import XMonad.Core
import qualified XMonad.StackSet as W
import Data.Maybe (fromMaybe)

data ToggleLayouts lt lf a = ToggleLayouts Bool (lt a) (lf a) deriving (Read, Show)
data ToggleLayout = ToggleLayout | Toggle String deriving (Read, Show)
instance Message ToggleLayout

toggleLayouts :: (LayoutClass lt a, LayoutClass lf a) => lt a -> lf a -> ToggleLayouts lt lf a
toggleLayouts = ToggleLayouts False

instance (LayoutClass lt a, LayoutClass lf a) => LayoutClass (ToggleLayouts lt lf) a where
  runLayout (W.Workspace i (ToggleLayouts True lt lf) ms) r = do
    (ws, mlt') <- runLayout (W.Workspace i lt ms) r
    pure (ws, fmap (\lt' -> ToggleLayouts True lt' lf) mlt')
  runLayout (W.Workspace i (ToggleLayouts False lt lf) ms) r = do
    (ws, mlf') <- runLayout (W.Workspace i lf ms) r
    pure (ws, fmap (ToggleLayouts False lt) mlf')
  description (ToggleLayouts True lt _) = description lt
  description (ToggleLayouts False _ lf) = description lf
  handleMessage (ToggleLayouts bool lt lf) m
    | Just ReleaseResources <- fromMessage m = do
        mlf' <- handleMessage lf m
        mlt' <- handleMessage lt m
        pure $ case (mlt', mlf') of
          (Nothing, Nothing) -> Nothing
          (Just lt', Nothing) -> Just $ ToggleLayouts bool lt' lf
          (Nothing, Just lf') -> Just $ ToggleLayouts bool lt lf'
          (Just lt', Just lf') -> Just $ ToggleLayouts bool lt' lf'
  handleMessage (ToggleLayouts True lt lf) m
    | Just ToggleLayout <- fromMessage m = do
        mlt' <- handleMessage lt (SomeMessage Hide)
        pure $ Just $ ToggleLayouts False (fromMaybe lt mlt') lf
    | Just (Toggle d) <- fromMessage m, d == description lt || d == description lf = do
        mlt' <- handleMessage lt (SomeMessage Hide)
        pure $ Just $ ToggleLayouts False (fromMaybe lt mlt') lf
    | otherwise = fmap (\lt' -> ToggleLayouts True lt' lf) <$> handleMessage lt m
  handleMessage (ToggleLayouts False lt lf) m
    | Just ToggleLayout <- fromMessage m = do
        mlf' <- handleMessage lf (SomeMessage Hide)
        pure $ Just $ ToggleLayouts True lt (fromMaybe lf mlf')
    | Just (Toggle d) <- fromMessage m, d == description lt || d == description lf = do
        mlf' <- handleMessage lf (SomeMessage Hide)
        pure $ Just $ ToggleLayouts True lt (fromMaybe lf mlf')
    | otherwise = fmap (ToggleLayouts False lt) <$> handleMessage lf m
