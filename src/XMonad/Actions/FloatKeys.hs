-- Adapted from xmonad-contrib XMonad.Actions.FloatKeys (BSD-3-Clause),
-- Copyright (c) Karsten Schoelzel and the Xmonad Community. Moves and
-- resizes using the last snapshot frame rather than X11 attributes.
module XMonad.Actions.FloatKeys
  ( keysMoveWindow, keysMoveWindowTo, keysResizeWindow, keysAbsResizeWindow
  , directionMoveWindow, directionResizeWindow
  , Direction2D(..), P, G, ChangeDim
  ) where
import qualified Data.Map.Strict as M
import XMonad.Core
import XMonad.Operations (floatWithRect, isClient)
import XMonad.Util.Types

type G = (Rational, Rational)
type P = (Position, Position)
type ChangeDim = (Int, Int)

directionMoveWindow :: Int -> Direction2D -> Window -> X ()
directionMoveWindow delta dir win = case dir of
  U -> keysMoveWindow (0, -delta) win
  D -> keysMoveWindow (0, delta)  win
  R -> keysMoveWindow (delta, 0)  win
  L -> keysMoveWindow (-delta, 0) win

directionResizeWindow :: Int -> Direction2D -> Window -> X ()
directionResizeWindow delta dir win = case dir of
  U -> keysResizeWindow (0, -delta) (0, 0) win
  D -> keysResizeWindow (0, delta)  (0, 0) win
  R -> keysResizeWindow (delta, 0)  (0, 0) win
  L -> keysResizeWindow (-delta, 0) (0, 0) win

withFrame :: Window -> (Rectangle -> X ()) -> X ()
withFrame w f = whenX (isClient w) $ do
  info <- gets windowInfo
  whenJust (frame <$> M.lookup w info) f

keysMoveWindow :: ChangeDim -> Window -> X ()
keysMoveWindow (dx,dy) w = withFrame w $ \(Rectangle x y ww hh) ->
  floatWithRect w (Rectangle (x+dx) (y+dy) ww hh)

keysMoveWindowTo :: P -> G -> Window -> X ()
keysMoveWindowTo (x,y) (gx, gy) w = withFrame w $ \(Rectangle _ _ ww hh) ->
  floatWithRect w (Rectangle (x - round (gx * fromIntegral ww))
                             (y - round (gy * fromIntegral hh)) ww hh)

keysResizeWindow :: ChangeDim -> G -> Window -> X ()
keysResizeWindow (dx,dy) (gx, gy) w = withFrame w $ \(Rectangle x y ww hh) ->
  let nw = max 1 (ww + dx)
      nh = max 1 (hh + dy)
      nx = round $ fromIntegral x + gx * fromIntegral ww - gx * fromIntegral nw
      ny = round $ fromIntegral y + gy * fromIntegral hh - gy * fromIntegral nh
  in floatWithRect w (Rectangle nx ny nw nh)

keysAbsResizeWindow :: ChangeDim -> P -> Window -> X ()
keysAbsResizeWindow (dx,dy) (ax, ay) w = withFrame w $ \(Rectangle x y ww hh) ->
  let nw = max 1 (ww + dx)
      nh = max 1 (hh + dy)
      nx = round (fromIntegral (ax * ww + nw * (x - ax)) / fromIntegral ww)
      ny = round (fromIntegral (ay * hh + nh * (y - ay)) / fromIntegral hh)
  in floatWithRect w (Rectangle nx ny nw nh)
