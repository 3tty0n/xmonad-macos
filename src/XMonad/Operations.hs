module XMonad.Operations where
import XMonad.Core
import qualified XMonad.StackSet as W
import Control.Monad (void)
import Control.Concurrent (forkIO)
import Data.Maybe (fromMaybe)
import System.IO (stderr)
import System.Process

windows :: (WindowSet -> WindowSet) -> X ()
windows f = modify $ \s -> s
  {windowset=f (windowset s), focusRequested=True, focusAgeTicks=0}
withWindowSet :: (WindowSet -> X a) -> X a
withWindowSet f = gets windowset >>= f
withFocused :: (Window -> X ()) -> X ()
withFocused f = gets (W.peek . windowset) >>= flip whenJust f
focus :: Window -> X ()
focus = windows . W.focusWindow
kill :: X ()
kill = withFocused $ \w -> modify $ \s -> s {commands=commands s ++ [Close w]}
refresh :: X ()
refresh = pure ()  -- Each completed action is followed by a layout pass.
spawn :: String -> X ()
spawn cmd = io $ do
  (_,_,_,ph) <- createProcess (shell cmd)
    { std_in=NoStream, std_out=UseHandle stderr, std_err=UseHandle stderr
    , create_group=True, close_fds=True }
  void $ forkIO $ void $ waitForProcess ph
sendMessage :: Message a => a -> X ()
sendMessage msg = do
  ws <- gets windowset
  let currentWS = W.workspace (W.current ws)
  changed <- handleMessage (W.layout currentWS) (SomeMessage msg)
  whenJust changed $ \l -> modify $ \s -> s
    {windowset=W.mapWorkspace (\w -> if W.tag w == W.tag currentWS
                                    then w {W.layout=l} else w) (windowset s)}
broadcastMessage :: Message a => a -> X ()
broadcastMessage msg = do
  ws <- gets windowset
  updated <- mapM (\w -> do
    ml <- handleMessage (W.layout w) (SomeMessage msg)
    pure (W.tag w, fromMaybe (W.layout w) ml)) (W.workspaces ws)
  modify $ \s -> s {windowset=W.mapWorkspace
    (\w -> w {W.layout=fromMaybe (W.layout w) (lookup (W.tag w) updated)}) (windowset s)}
setLayout :: Layout Window -> X ()
setLayout l = do
  t <- gets (W.currentTag . windowset)
  windows $ W.mapWorkspace $ \w -> if W.tag w == t then w {W.layout=l} else w
screenWorkspace :: ScreenId -> X (Maybe WorkspaceId)
screenWorkspace i = gets (W.lookupWorkspace i . windowset)
