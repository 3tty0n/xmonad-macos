-- The parts of a config that only make sense on macOS: matching by bundle
-- identifier, and asking the helper to do something to itself.
module XMonad.MacOS (bundleId, toggleFloat, reload, recompile, quit, pause) where
import XMonad.Core
import XMonad.ManageHook (resource, doFloat)
import XMonad.Operations (withFocused, windows)
import qualified XMonad.StackSet as W
import qualified Data.Map.Strict as M

-- The stable identifier for an application, unlike its localized name.
bundleId :: Query String
bundleId = resource

-- Float a tiled window where it currently sits, or tile a floating one.
toggleFloat :: X ()
toggleFloat = withFocused $ \w -> do
  floating <- gets (M.member w . W.floating . windowset)
  if floating then windows (W.sink w) else do
    Endo f <- runQuery doFloat w
    windows f

-- Requests for the helper, carried out after the current plan is applied.
reload, recompile, quit, pause :: X ()
reload = request Reload
recompile = request Recompile
quit = request Quit
pause = request TogglePause

request :: NativeCommand -> X ()
request cmd = modify $ \s -> s {commands = commands s ++ [cmd]}
