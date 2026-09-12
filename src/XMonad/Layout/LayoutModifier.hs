{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.LayoutModifier (BSD-3-Clause),
-- Copyright (c) David Roundy and the Xmonad Community.
module XMonad.Layout.LayoutModifier (LayoutModifier(..), ModifiedLayout(..)) where
import XMonad.Core
import qualified XMonad.StackSet as W
import Control.Monad (mplus)
import Data.Maybe (fromMaybe)

class (Show (m a), Read (m a)) => LayoutModifier m a where
  modifyLayout :: LayoutClass l a =>
                  m a -> W.Workspace WorkspaceId (l a) a -> Rectangle
               -> X ([(a, Rectangle)], Maybe (l a))
  modifyLayout _ = runLayout
  modifyLayoutWithUpdate :: LayoutClass l a =>
                            m a -> W.Workspace WorkspaceId (l a) a -> Rectangle
                         -> X (([(a, Rectangle)], Maybe (l a)), Maybe (m a))
  modifyLayoutWithUpdate m w r = (\x -> (x, Nothing)) <$> modifyLayout m w r
  handleMess :: m a -> SomeMessage -> X (Maybe (m a))
  handleMess m mess
    | Just Hide <- fromMessage mess = unhook m >> pure Nothing
    | Just ReleaseResources <- fromMessage mess = unhook m >> pure Nothing
    | otherwise = pure (pureMess m mess)
  handleMessOrMaybeModifyIt :: m a -> SomeMessage -> X (Maybe (Either (m a) SomeMessage))
  handleMessOrMaybeModifyIt m mess = fmap Left <$> handleMess m mess
  pureMess :: m a -> SomeMessage -> Maybe (m a)
  pureMess _ _ = Nothing
  redoLayout :: m a -> Rectangle -> Maybe (W.Stack a) -> [(a, Rectangle)]
             -> X ([(a, Rectangle)], Maybe (m a))
  redoLayout m r ms wrs = hook m >> pure (pureModifier m r ms wrs)
  pureModifier :: m a -> Rectangle -> Maybe (W.Stack a) -> [(a, Rectangle)]
               -> ([(a, Rectangle)], Maybe (m a))
  pureModifier _ _ _ wrs = (wrs, Nothing)
  hook :: m a -> X ()
  hook _ = pure ()
  unhook :: m a -> X ()
  unhook _ = pure ()
  modifierDescription :: m a -> String
  modifierDescription _ = ""
  modifyDescription :: LayoutClass l a => m a -> l a -> String
  modifyDescription m l = case modifierDescription m of
    "" -> description l
    d -> d ++ " " ++ description l

instance (LayoutModifier m a, LayoutClass l a, Typeable m) =>
         LayoutClass (ModifiedLayout m l) a where
  runLayout (W.Workspace i (ModifiedLayout m l) ms) r = do
    ((ws, ml'), mm') <- modifyLayoutWithUpdate m (W.Workspace i l ms) r
    (ws', mm'') <- redoLayout (fromMaybe m mm') r ms ws
    let ml'' = case mm'' `mplus` mm' of
          Just m' -> Just $ ModifiedLayout m' $ fromMaybe l ml'
          Nothing -> ModifiedLayout m <$> ml'
    pure (ws', ml'')
  handleMessage (ModifiedLayout m l) mess = do
    mm' <- handleMessOrMaybeModifyIt m mess
    ml' <- case mm' of
      Just (Right mess') -> handleMessage l mess'
      _ -> handleMessage l mess
    pure $ case mm' of
      Just (Left m') -> Just $ ModifiedLayout m' $ fromMaybe l ml'
      _ -> ModifiedLayout m <$> ml'
  description (ModifiedLayout m l) = modifyDescription m l

data ModifiedLayout m l a = ModifiedLayout (m a) (l a) deriving (Read, Show)
