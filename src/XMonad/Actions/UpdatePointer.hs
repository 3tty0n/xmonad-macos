-- Adapted from xmonad-contrib XMonad.Actions.UpdatePointer (BSD-3-Clause),
-- Copyright (c) Robert Marlow and Evgeny Kurnevsky. The pointer follows the
-- window focus changes to.
--
-- Where upstream asks the X server for the focused window's rectangle, this
-- port reads the helper's last observation. The warp itself is the public
-- CGWarpMouseCursorPosition, carried by a MovePointer command; the helper
-- skips it when the pointer is already on the focused window or a mod-drag is
-- in progress, so ordinary plans and the user's own pointer are left alone.
module XMonad.Actions.UpdatePointer (updatePointer) where
import XMonad
import qualified XMonad.StackSet as W
import qualified XMonad.Util.ExtensibleState as XS
import Control.Monad (when)
import qualified Data.Map.Strict as M

-- The window the pointer was last moved to, so a logHook that runs before
-- every plan does not re-issue the move while the focus is unchanged.
newtype PointerTarget = PointerTarget (Maybe Window)

instance ExtensionClass PointerTarget where
  initialValue = PointerTarget Nothing

-- | Put this in the @logHook@ to move the pointer to the current window (or
-- the current screen when nothing is focused). The first pair is a reference
-- point inside the window, (0,0) top-left and (1,1) bottom-right; the second
-- scales a bounding box outwards from it. @(0.5, 0.5) (0, 0)@ is the centre
-- and @(0.5, 0.5) (1, 1)@ the nearest point inside the window.
updatePointer :: (Rational, Rational) -> (Rational, Rational) -> X ()
updatePointer refPos ratio = do
  ws <- gets windowset
  info <- gets windowInfo
  let focused = W.peek ws
  PointerTarget lastW <- XS.get
  when (focused /= lastW) $ do
    XS.put (PointerTarget focused)
    let rect = case focused >>= (`M.lookup` info) of
                 Just wi -> frame wi
                 Nothing -> screenRect . W.screenDetail . W.current $ ws
    modify $ \s -> s
      {commands = commands s ++ [MovePointer (pointerBounds rect refPos ratio) rect]}

-- The box the pointer is clipped into, as upstream: a reference point in the
-- rectangle, then @ratio@ times further out towards its edges.
pointerBounds :: Rectangle -> (Rational, Rational) -> (Rational, Rational) -> Rectangle
pointerBounds (Rectangle rx ry rw rh) (px, py) (qx, qy) =
  Rectangle x1' y1' (max 1 (x2' - x1')) (max 1 (y2' - y1'))
  where
    x0 = lerp px rx (rx + rw)
    y0 = lerp py ry (ry + rh)
    x1 = lerp qx x0 rx
    x2 = lerp qx x0 (rx + rw)
    y1 = lerp qy y0 ry
    y2 = lerp qy y0 (ry + rh)
    x1' = min x1 x2
    x2' = max x1 x2
    y1' = min y1 y2
    y2' = max y1 y2
    lerp r a b = round ((1 - r) * toRational a + r * toRational b)
