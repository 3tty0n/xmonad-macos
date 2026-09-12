-- Actions a config calls: everything here changes policy state, and the
-- helper is told about it by the plan that follows.
module XMonad.Operations
  ( windows, withWindowSet, withFocused, focus, kill, refresh, spawn
  , sendMessage, broadcastMessage, setLayout, screenWorkspace
  ) where
import XMonad.Core
import qualified XMonad.StackSet as W
import Control.Monad (void)
import Control.Concurrent (forkIO)
import Data.Maybe (fromMaybe)
import System.IO (stderr)
import System.Process

-- Any deliberate change to the window set is also a focus request: the user
-- asked for it, so the helper may raise and activate the result.
windows :: (WindowSet -> WindowSet) -> X ()
windows f = modify $ \s ->
  let ws'=f (windowset s)
      n=nextActionId s+1
  in s {windowset=ws', nextActionId=n, pendingFocus=(,) n <$> W.peek ws'}

withWindowSet :: (WindowSet -> X a) -> X a
withWindowSet f = gets windowset >>= f

withFocused :: (Window -> X ()) -> X ()
withFocused f = gets (W.peek . windowset) >>= flip whenJust f

focus :: Window -> X ()
focus = windows . W.focusWindow

-- Closing is a request to the helper, which presses the window's own close
-- button. Nothing here can force-quit an application.
kill :: X ()
kill = withFocused $ \w -> modify $ \s -> s {commands=commands s ++ [Close w]}

-- Every completed action is followed by a layout pass, so an explicit refresh
-- has nothing left to do.
refresh :: X ()
refresh = pure ()

-- Detached, in its own process group, with output folded into the log.
spawn :: String -> X ()
spawn cmd = io $ do
  (_,_,_,handle) <- createProcess (shell cmd)
    { std_in=NoStream, std_out=UseHandle stderr, std_err=UseHandle stderr
    , create_group=True, close_fds=True }
  void $ forkIO $ void $ waitForProcess handle

-- To the layout of the visible workspace only.
sendMessage :: Message a => a -> X ()
sendMessage msg = do
  current <- gets (W.workspace . W.current . windowset)
  changed <- handleMessage (W.layout current) (SomeMessage msg)
  whenJust changed $ \l -> setLayoutOf (W.tag current) l

-- To every workspace, for messages about the world rather than the user, such
-- as a window that closed.
broadcastMessage :: Message a => a -> X ()
broadcastMessage msg = do
  workspaces' <- gets (W.workspaces . windowset)
  updated <- mapM (\w -> do
    changed <- handleMessage (W.layout w) (SomeMessage msg)
    pure (W.tag w,fromMaybe (W.layout w) changed)) workspaces'
  modify $ \s -> s {windowset = W.mapWorkspace
    (\w -> w {W.layout=fromMaybe (W.layout w) (lookup (W.tag w) updated)})
    (windowset s)}

setLayout :: Layout Window -> X ()
setLayout l = do
  t <- gets (W.currentTag . windowset)
  windows $ W.mapWorkspace $ \w -> if W.tag w == t then w {W.layout=l} else w

setLayoutOf :: WorkspaceId -> Layout Window -> X ()
setLayoutOf t l = modify $ \s -> s {windowset = W.mapWorkspace
  (\w -> if W.tag w == t then w {W.layout=l} else w) (windowset s)}

screenWorkspace :: ScreenId -> X (Maybe WorkspaceId)
screenWorkspace i = gets (W.lookupWorkspace i . windowset)
