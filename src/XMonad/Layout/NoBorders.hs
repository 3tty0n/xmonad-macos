{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PatternGuards #-}
-- Adapted from xmonad-contrib XMonad.Layout.NoBorders (BSD-3-Clause),
-- Copyright (c) 2007 David Roundy and the Xmonad Community. A window cannot be
-- given a border from here: the border is an overlay the helper draws, so the
-- width decided for a window travels with the next plan. The X11 rectangle
-- helpers are reimplemented over signed points, and the deprecated
-- borderEventHook is not provided.
module XMonad.Layout.NoBorders
  ( noBorders, smartBorders, withBorder, lessBorders
  , SetsAmbiguous(..), Ambiguity(..), With(..)
  , WithBorder, ConfigurableBorder, SmartBorder
  , BorderMessage(..), hasBorder
  ) where
import XMonad.Core
import XMonad.Layout.LayoutModifier
import XMonad.ManageHook (idHook)
import XMonad.Operations
  (broadcastMessage, scaleRationalRect, setWindowBorderWidth)
import qualified XMonad.StackSet as W
import qualified Data.Map.Strict as M
import Data.List (intersect, union, (\\))

data WithBorder a = WithBorder Int [a] deriving (Read, Show)

-- How two ambiguity rules are combined.
data With = Union | Difference | Intersection deriving (Read, Show)

-- Which windows a layout calls ambiguous, from least to most ambiguous.
data Ambiguity = Combine With Ambiguity Ambiguity
               | OnlyLayoutFloat
               | OnlyScreenFloat
               | Never
               | EmptyScreen
               | OnlyFloat
               | Screen
  deriving (Read, Show)

class SetsAmbiguous p where
  hiddens :: p -> WindowSet -> Rectangle -> Maybe (W.Stack Window)
          -> [(Window, Rectangle)] -> [Window]

data ConfigurableBorder p w = ConfigurableBorder
  { _generateHidden :: p
  , alwaysHidden :: [w]
  , neverHidden :: [w]
  , currentHidden :: [w]
  } deriving (Read, Show)

type SmartBorder = ConfigurableBorder Ambiguity

data BorderMessage = HasBorder Bool Window | ResetBorder Window
  deriving (Read, Show)

instance Message BorderMessage

instance SetsAmbiguous Ambiguity where
  hiddens amb wset lr mst wrs
    | Combine Union a b <- amb = on union next a b
    | Combine Difference a b <- amb = on (\\) next a b
    | Combine Intersection a b <- amb = on intersect next a b
    | otherwise = tiled ms ++ floats
    where
      next p = hiddens p wset lr mst wrs
      on f g a b = f (g a) (g b)
      -- The tiled windows this layout is actually showing, in layout order.
      ms = filter (`elem` W.integrate' mst) (map fst wrs)
      integrate scr = W.integrate' (W.stack (W.workspace scr))
      -- Screens this layout covers. Never keeps empty ones: an empty screen
      -- says nothing about how ambiguous the layout is.
      screens = filter relevant (W.screens wset)
      relevant scr = not (isEmpty (screenRect (W.screenDetail scr)))
                     && (isNever || not (null (integrate scr)))
      isNever = case amb of
        Never -> True
        _ -> False
      thisScreen = [ scr | scr <- screens
                    , screenRect (W.screenDetail scr) `supersetOf` lr ]
      floats = [ w1 | scr <- thisScreen
               , let sr = screenRect (W.screenDetail scr)
                     fs = [ (w, scaleRationalRect sr wr)
                          | w <- reverse (integrate scr)
                          , Just wr <- [M.lookup w (W.floating wset)] ]
               , (w1, wr1) <- fs
               , ambiguous sr wr1 ]
      -- A float is only removed when it covers what it floats over.
      ambiguous sr wr1
        | OnlyLayoutFloat <- amb = lr == wr1
        | OnlyFloat <- amb = True
        | otherwise = wr1 `supersetOf` sr
      -- A lone tiled window has no neighbour to share a border with.
      tiled [w]
        | Screen <- amb = [w]
        | OnlyScreenFloat <- amb = []
        | OnlyLayoutFloat <- amb = []
        | OnlyFloat <- amb = []
        | otherwise = if singleton screens then [w] else []
      tiled _ = []

instance LayoutModifier WithBorder Window where
  unhook (WithBorder _ s) = setBorders s =<< configuredWidth
  redoLayout (WithBorder n s) _ _ wrs = do
    width <- configuredWidth
    setBorders (s \\ ws) width
    setBorders ws n
    pure (wrs, Just (WithBorder n ws))
    where ws = map fst wrs

instance (Read p, Show p, SetsAmbiguous p) =>
         LayoutModifier (ConfigurableBorder p) Window where
  unhook cb = setBorders (currentHidden cb) =<< configuredWidth
  redoLayout cb@(ConfigurableBorder gh ah nh ch) lr mst wrs = do
    wset <- gets windowset
    let ch' = (ah `union` hiddens gh wset lr mst wrs) \\ nh
    width <- configuredWidth
    setBorders (ch \\ ch') width
    setBorders ch' 0
    pure (wrs, Just cb {currentHidden = ch'})
  pureMess cb m
    | Just (HasBorder b w) <- fromMessage m = remember cb b w
    | Just (ResetBorder w) <- fromMessage m = forget cb w
    | Just (WindowRemoved w) <- fromMessage m = forget cb w
    | otherwise = Nothing

-- A border the user asked for, or asked to drop, is remembered unless the
-- window is already listed on either side. Never matters more than always,
-- which is why the never list is subtracted when the hidden set is built.
remember :: Eq w => ConfigurableBorder p w -> Bool -> w
         -> Maybe (ConfigurableBorder p w)
remember cb True w
  | w `elem` neverHidden cb || w `elem` alwaysHidden cb = Nothing
  | otherwise = Just cb {neverHidden = w : neverHidden cb}
remember cb False w
  | w `elem` alwaysHidden cb || w `elem` neverHidden cb = Nothing
  | otherwise = Just cb {alwaysHidden = w : alwaysHidden cb}

forget :: Eq w => ConfigurableBorder p w -> w -> Maybe (ConfigurableBorder p w)
forget cb w
  | w `elem` alwaysHidden cb || w `elem` neverHidden cb =
      Just cb {alwaysHidden = filter (/= w) (alwaysHidden cb)
              ,neverHidden = filter (/= w) (neverHidden cb)}
  | otherwise = Nothing

configuredWidth :: X Int
configuredWidth = asks (borderWidth . config)

-- Every border in the port is drawn by the helper, so a width reaches it as an
-- instruction in the next plan rather than as an X11 call.
setBorders :: [Window] -> Int -> X ()
setBorders ws width = mapM_ (`setWindowBorderWidth` width) ws

isEmpty :: Rectangle -> Bool
isEmpty (Rectangle _ _ w h) = w <= 0 || h <= 0

-- Does the first rectangle contain the second?
supersetOf :: Rectangle -> Rectangle -> Bool
supersetOf (Rectangle x1 y1 w1 h1) (Rectangle x2 y2 w2 h2) =
  x1 <= x2 && y1 <= y2 && x1+w1 >= x2+w2 && y1+h1 >= y2+h2

singleton :: [a] -> Bool
singleton = null . drop 1

noBorders :: LayoutClass l Window
          => l Window -> ModifiedLayout WithBorder l Window
noBorders = withBorder 0

withBorder :: LayoutClass l Window => Int
           -> l Window -> ModifiedLayout WithBorder l Window
withBorder b = ModifiedLayout (WithBorder b [])

smartBorders :: LayoutClass l Window
             => l Window -> ModifiedLayout SmartBorder l Window
smartBorders = lessBorders Never

lessBorders :: (SetsAmbiguous p, Read p, Show p, LayoutClass l Window)
            => p -> l Window -> ModifiedLayout (ConfigurableBorder p) l Window
lessBorders amb = ModifiedLayout (ConfigurableBorder amb [] [] [])

-- Keep or drop one window's border, wherever it is shown.
hasBorder :: Bool -> ManageHook
hasBorder b = do
  w <- ask
  liftX $ broadcastMessage (HasBorder b w)
  idHook
