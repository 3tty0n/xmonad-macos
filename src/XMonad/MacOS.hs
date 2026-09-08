module XMonad.MacOS (bundleId, toggleFloat, reload, recompile, quit, pause) where
import XMonad.Core
import XMonad.ManageHook (resource,doFloat)
import XMonad.Operations (withFocused,windows)
import qualified XMonad.StackSet as W
import qualified Data.Map.Strict as M
bundleId :: Query String
bundleId=resource
toggleFloat :: X ()
toggleFloat=withFocused $ \w -> do
  floated <- gets (M.member w . W.floating . windowset)
  if floated then windows (W.sink w) else do
    Endo f <- runQuery doFloat w
    windows f
reload, recompile, quit, pause :: X ()
reload=modify $ \s -> s {commands=commands s ++ [Reload]}
recompile=modify $ \s -> s {commands=commands s ++ [Recompile]}
quit=modify $ \s -> s {commands=commands s ++ [Quit]}
pause=modify $ \s -> s {commands=commands s ++ [TogglePause]}
