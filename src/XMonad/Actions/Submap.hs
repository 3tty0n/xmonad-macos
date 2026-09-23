-- Adapted from xmonad-contrib XMonad.Actions.Submap (BSD-3-Clause),
-- Copyright (c) Jason Creighton and the Xmonad Community.
-- There is no blocking X11 keyboard grab: the submap is armed here and the
-- helper grabs the next stroke for it. visualSubmap is not ported.
module XMonad.Actions.Submap
  (submap, submapDefault, submapDefaultWithKey) where
import XMonad.Core
import qualified Data.Map.Strict as M

-- An unbound stroke, Escape included, does nothing and ends the submap.
submap :: M.Map (KeyMask,KeySym) (X ()) -> X ()
submap = submapDefault (pure ())

submapDefault :: X () -> M.Map (KeyMask,KeySym) (X ()) -> X ()
submapDefault = submapDefaultWithKey . const

submapDefaultWithKey :: ((KeyMask,KeySym) -> X ()) -> M.Map (KeyMask,KeySym) (X ()) -> X ()
submapDefaultWithKey def keys = modify $ \s -> s
  { keyGrab = Just (\k -> M.findWithDefault (def k) k keys)
  , commands = commands s ++ [GrabKeyboard | null (keyGrab s)] }
