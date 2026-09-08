-- Adapted from xmonad-contrib XMonad.Actions.WithAll (BSD-3-Clause),
-- Copyright (c) Robert Marlow and the Xmonad Community.
module XMonad.Actions.WithAll (withAll, withAll', killAll, sinkAll) where
import XMonad.Core
import XMonad.Operations (windows)
import qualified XMonad.StackSet as W
import Control.Monad (forM_)

-- Every window on the current workspace, floating ones included.
withAll' :: (Window -> WindowSet -> WindowSet) -> X ()
withAll' f = windows $ \ws ->
  foldr f ws (W.integrate' . W.stack . W.workspace . W.current $ ws)

withAll :: (Window -> X ()) -> X ()
withAll f = do
  ws <- gets (W.integrate' . W.stack . W.workspace . W.current . windowset)
  forM_ ws f

killAll :: X ()
killAll = do
  ws <- gets (W.integrate' . W.stack . W.workspace . W.current . windowset)
  modify $ \s -> s {commands = commands s ++ map Close ws}

sinkAll :: X ()
sinkAll = withAll' W.sink
