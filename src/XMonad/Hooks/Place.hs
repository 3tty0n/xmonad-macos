-- Adapted from xmonad-contrib XMonad.Hooks.Place (BSD-3-Clause),
-- Copyright (c) Florian Frunz and the Xmonad Community. Window sizes and
-- neighbours come from the last snapshot instead of X11 attributes. The
-- helper does not report the pointer to the engine, so 'underMouse' treats
-- the centre of the window's screen as the pointer position. 'smart' picks
-- the candidate position with the least overlap; ties go to the corner named
-- by its argument, which may differ from upstream's choice among equals.
module XMonad.Hooks.Place
  ( Placement, smart, simpleSmart, fixed, underMouse, inBounds, withGaps
  , placeFocused, placeHook, purePlaceWindow
  ) where
import Data.List (minimumBy)
import Data.Maybe (fromMaybe, mapMaybe)
import Data.Ord (comparing)
import qualified Data.Map.Strict as M
import XMonad.Core
import XMonad.Operations (scaleRationalRect, windows)
import qualified XMonad.StackSet as W

data Placement
  = Fixed (Rational, Rational)
  | UnderMouse (Rational, Rational)
  | Smart (Rational, Rational)
  | Bounds (Dimension, Dimension, Dimension, Dimension) Placement
  deriving (Show, Eq)

-- | Place at a point of the screen: (0,0) top-left, (1,1) bottom-right.
fixed :: (Rational, Rational) -> Placement
fixed = Fixed

-- | Put the point of the window given by the pair under the pointer.
underMouse :: (Rational, Rational) -> Placement
underMouse = UnderMouse

-- | Least overlap with other windows, preferring the given corner.
smart :: (Rational, Rational) -> Placement
smart = Smart

simpleSmart :: Placement
simpleSmart = inBounds (smart (0, 0))

-- | Keep the placed window inside the screen.
inBounds :: Placement -> Placement
inBounds = withGaps (0, 0, 0, 0)

-- | Keep it inside the screen minus gaps (top, right, bottom, left).
withGaps :: (Dimension, Dimension, Dimension, Dimension) -> Placement -> Placement
withGaps = Bounds

-- | Screen, other windows, pointer and the window itself, to the new frame.
purePlaceWindow :: Placement -> Rectangle -> [Rectangle] -> (Position, Position)
                -> Rectangle -> Rectangle
purePlaceWindow (Bounds (t, r, b, l) p) (Rectangle sx sy sw sh) ws pnt win =
  Rectangle (clamp (sx + l) (sx + sw - r - w) x) (clamp (sy + t) (sy + sh - b - h) y) w h
  where
    inner = Rectangle (sx + l) (sy + t) (sw - l - r) (sh - t - b)
    Rectangle x y w h = purePlaceWindow p inner ws pnt win
    clamp lo hi = max lo . min hi
purePlaceWindow (Fixed (rx, ry)) (Rectangle sx sy sw sh) _ _ (Rectangle _ _ w h) =
  Rectangle (sx + truncate (rx * toRational (sw - w)))
            (sy + truncate (ry * toRational (sh - h))) w h
purePlaceWindow (UnderMouse (rx, ry)) _ _ (px, py) (Rectangle _ _ w h) =
  Rectangle (px - truncate (rx * toRational w)) (py - truncate (ry * toRational h)) w h
purePlaceWindow (Smart pref) s ws _ (Rectangle _ _ w h) = placeSmart pref s ws w h

placeSmart :: (Rational, Rational) -> Rectangle -> [Rectangle] -> Dimension
           -> Dimension -> Rectangle
placeSmart (rx, ry) (Rectangle sx sy sw sh) ws w h =
  let (x, y) = minimumBy (comparing score) [(cx, cy) | cy <- ys, cx <- xs]
  in Rectangle x y w h
  where
    fitX = max sx . min (sx + sw - w)
    fitY = max sy . min (sy + sh - h)
    xs = dedup $ map fitX $ sx : sx + sw - w
           : concat [[ox + ow, ox - w] | Rectangle ox _ ow _ <- ws]
    ys = dedup $ map fitY $ sy : sy + sh - h
           : concat [[oy + oh, oy - h] | Rectangle _ oy _ oh <- ws]
    wantX = toRational sx + rx * toRational (sw - w)
    wantY = toRational sy + ry * toRational (sh - h)
    score (cx, cy) =
      ( sum [overlap (Rectangle cx cy w h) o | o <- ws]
      , abs (toRational cy - wantY), abs (toRational cx - wantX), cy, cx )
    dedup = M.keys . M.fromList . map (\v -> (v, ()))

overlap :: Rectangle -> Rectangle -> Integer
overlap (Rectangle ax ay aw ah) (Rectangle bx by bw bh) =
  span' ax aw bx bw * span' ay ah by bh
  where span' p pl q ql =
          toInteger (max 0 (min (p + pl) (q + ql) - max p q))

-- | Re-place the focused window if it floats.
placeFocused :: Placement -> X ()
placeFocused p = do
  ws <- gets windowset
  info <- gets windowInfo
  whenJust (W.peek ws) $ \w -> windows (placeIn p info w)

-- | Place a floating window when it is managed. Put it before 'doFloat' in a
-- '<+>' chain so the float is applied first; tiled windows are untouched.
placeHook :: Placement -> ManageHook
placeHook p = do
  w <- ask
  info <- liftX (gets windowInfo)
  pure (Endo (placeIn p info w))

placeIn :: Placement -> M.Map Window WindowInfo -> Window -> WindowSet -> WindowSet
placeIn p info w ws = fromMaybe ws $ do
  rr <- M.lookup w (W.floating ws)
  let tag = W.findTag w ws
      sc = case [s | s <- W.screens ws, Just (W.tag (W.workspace s)) == tag] of
             (s : _) -> s
             [] -> W.current ws
      area = screenRect (W.screenDetail sc)
      size = case M.lookup w info of
        Just wi -> frame wi
        Nothing -> scaleRationalRect area rr
      here = [x | Just t <- [tag], space <- W.workspaces ws, W.tag space == t
                , x <- W.integrate' (W.stack space)]
      others = mapMaybe neighbour (filter (/= w) here)
      Rectangle ax ay aw ah = area
      pointer = (ax + aw `div` 2, ay + ah `div` 2)
      Rectangle nx ny nw nh = purePlaceWindow p area others pointer size
      toRR = W.RationalRect (toRational (nx - ax) / toRational aw)
                            (toRational (ny - ay) / toRational ah)
                            (toRational nw / toRational aw)
                            (toRational nh / toRational ah)
  if aw <= 0 || ah <= 0 then Nothing else Just (W.float w toRR ws)
  where
    neighbour o = do
      wi <- M.lookup o info
      if minimized wi || ownedHidden wi then Nothing else Just (frame wi)
