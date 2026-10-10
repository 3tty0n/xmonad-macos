{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
-- Adapted from xmonad-contrib XMonad.Layout.TwoPanePersistent (BSD-3-Clause),
-- Copyright (c) Behrouz Abbasi and the Xmonad Community.
module XMonad.Layout.TwoPanePersistent (TwoPanePersistent(..)) where
import XMonad.Core
import XMonad.Layout (Resize(..), splitHorizontallyBy)
import qualified XMonad.StackSet as W

-- Like TwoPane, but the right pane keeps showing the last slave when the
-- master is focused, instead of the window after the master.
data TwoPanePersistent a = TwoPanePersistent
  { slaveWindow :: Maybe a
  , dFrac :: Rational
  , mFrac :: Rational
  } deriving (Show,Read)

instance LayoutClass TwoPanePersistent Window where
  doLayout (TwoPanePersistent slave delta frac) r s =
    pure (panes, Just (TwoPanePersistent slave' delta frac))
    where
      (left,right) = splitHorizontallyBy frac r
      focus = W.focus s
      (panes,slave') = case reverse (W.up s) of
        (master:_) -> ([(master,left),(focus,right)], Just focus)
        [] -> case slave of
          Just w | w `elem` W.down s -> ([(focus,left),(w,right)], slave)
          _ -> case W.down s of
            (next:_) -> ([(focus,left),(next,right)], Just next)
            [] -> ([(focus,r)], Nothing)
  pureMessage (TwoPanePersistent slave delta frac) m = resize <$> fromMessage m
    where resize Shrink = TwoPanePersistent slave delta (max 0 $ frac-delta)
          resize Expand = TwoPanePersistent slave delta (min 1 $ frac+delta)
  description _ = "TwoPanePersistent"
