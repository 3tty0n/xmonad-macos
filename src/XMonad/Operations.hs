-- Actions a config calls: everything here changes policy state, and the
-- helper is told about it by the plan that follows.
module XMonad.Operations
  ( windows, modifyWindowSet, withWindowSet, withFocused, withUnfocused
  , focus, kill, killWindow, refresh, spawn
  , float, floatLocation, floatWithRect, isClient
  , sendMessage, sendMessageWithNoRefresh, broadcastMessage, setLayout
  , screenWorkspace, containedIn, pointWithin, scaleRationalRect
  ) where
import XMonad.Core
import qualified XMonad.StackSet as W
import Control.Monad (void)
import Control.Concurrent (forkIO)
import Data.List (find)
import Data.Maybe (fromMaybe)
import qualified Data.Map.Strict as M
import System.IO (stderr)
import System.Process

-- Any deliberate change to the window set is also a focus request: the user
-- asked for it, so the helper may raise and activate the result.
windows :: (WindowSet -> WindowSet) -> X ()
windows f = modify $ \s ->
  let ws'=f (windowset s)
      n=nextActionId s+1
  in s {windowset=ws', nextActionId=n, pendingFocus=(,) n <$> W.peek ws'}

-- Change the window set without treating it as a user focus request.
modifyWindowSet :: (WindowSet -> WindowSet) -> X ()
modifyWindowSet f = modify $ \s -> s {windowset=f (windowset s)}

withWindowSet :: (WindowSet -> X a) -> X a
withWindowSet f = gets windowset >>= f

withFocused :: (Window -> X ()) -> X ()
withFocused f = gets (W.peek . windowset) >>= flip whenJust f

withUnfocused :: (Window -> X ()) -> X ()
withUnfocused f = withWindowSet $ \ws ->
  mapM_ f [w | w <- W.index ws, Just w /= W.peek ws]

focus :: Window -> X ()
focus = windows . W.focusWindow

isClient :: Window -> X Bool
isClient w = gets (W.member w . windowset)

-- Closing is a request to the helper, which presses the window's own close
-- button. Nothing here can force-quit an application.
kill :: X ()
kill = withFocused killWindow

killWindow :: Window -> X ()
killWindow w = modify $ \s -> s {commands=commands s ++ [Close w]}

-- Float the focused window at its observed frame, relative to its screen.
float :: X ()
float = withFocused $ \w -> windows . W.float w =<< floatLocation w

floatLocation :: Window -> X W.RationalRect
floatLocation w = do
  s <- get
  pure $ fromMaybe centred $ do
    wi <- M.lookup w (windowInfo s)
    sc <- find ((==onDisplay wi) . displayID . W.screenDetail)
            (W.screens $ windowset s)
    rectOnScreen (screenRect (W.screenDetail sc)) (frame wi)
  where centred = W.RationalRect (1/5) (1/5) (3/5) (3/5)

-- Float @w@ at an absolute logical-point rectangle on the screen it occupies.
floatWithRect :: Window -> Rectangle -> X ()
floatWithRect w r = do
  s <- get
  let rr = fromMaybe centred $ do
        wi <- M.lookup w (windowInfo s)
        sc <- find ((==onDisplay wi) . displayID . W.screenDetail)
                (W.screens $ windowset s)
        rectOnScreen (screenRect (W.screenDetail sc)) r
      centred = W.RationalRect (1/5) (1/5) (3/5) (3/5)
  windows (W.float w rr)

rectOnScreen :: Rectangle -> Rectangle -> Maybe W.RationalRect
rectOnScreen (Rectangle sx sy sw sh) (Rectangle x y ww hh)
  | sw <= 0 || sh <= 0 = Nothing
  | otherwise = Just $ W.RationalRect
      (toRational (x-sx) / toRational sw) (toRational (y-sy) / toRational sh)
      (toRational ww / toRational sw) (toRational hh / toRational sh)

containedIn :: Rectangle -> Rectangle -> Bool
containedIn (Rectangle x y w h) (Rectangle x' y' w' h') =
  x >= x' && y >= y' && x+w <= x'+w' && y+h <= y'+h'

pointWithin :: Position -> Position -> Rectangle -> Bool
pointWithin x y (Rectangle rx ry rw rh) =
  x >= rx && x < rx+rw && y >= ry && y < ry+rh

scaleRationalRect :: Rectangle -> W.RationalRect -> Rectangle
scaleRationalRect (Rectangle sx sy sw sh) (W.RationalRect x y w h) =
  Rectangle (sx + floor (fromIntegral sw * x))
            (sy + floor (fromIntegral sh * y))
            (max 1 $ floor (fromIntegral sw * w))
            (max 1 $ floor (fromIntegral sh * h))

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

sendMessageWithNoRefresh :: Message a => a -> WindowSpace -> X ()
sendMessageWithNoRefresh msg w = do
  changed <- handleMessage (W.layout w) (SomeMessage msg)
  whenJust changed $ setLayoutOf (W.tag w)

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
