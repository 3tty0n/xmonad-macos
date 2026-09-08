{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
module XMonad.MacOS.Engine
  ( xmonad, initialState, reconcile, floatObservedWindow, makePlan, rescreen
  , checkpoint, restoreCheckpoint ) where
import XMonad.Core
import XMonad.MacOS.Protocol
import XMonad.MacOS.CLI (handleCommand)
import XMonad.Operations (broadcastMessage)
import qualified XMonad.StackSet as W
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.Aeson
import Data.List (find, nub, foldl', (\\))
import Data.Maybe (fromMaybe, mapMaybe)
import Control.Applicative ((<|>))
import Control.Monad (forM_, when, unless)
import System.IO
import System.Environment (getArgs)
import GHC.Generics (Generic)

initialState :: XConfig Layout -> [DisplayInfo] -> XState
initialState c ds = XState
  { windowset=W.new (layoutHook c) tags [SD (usable d) (display d) | d <- ds']
  , windowInfo=M.empty, ignoredWindows=S.empty, generation=(-1), epoch=(-1)
  , focusRequested=False, focusAgeTicks=0, commands=[] }
  where
    ds' = if null ds then [DisplayInfo 0 (Rectangle 0 0 1 1)] else ds
    configured = nub (filter (not . null) $ workspaces c)
    candidates = configured ++ ["_screen_" ++ show n | n <- [(1::Int)..]
                                , ("_screen_" ++ show n) `notElem` configured]
    tags = take (max (length configured) (length ds')) candidates

-- Stable physical display identity; preserve existing workspace assignments.
-- A new display cannot steal a workspace from one retained later in the list.
rescreen :: [DisplayInfo] -> WindowSet -> WindowSet
rescreen [] ws = ws
rescreen ds ws = ws { W.current=cur, W.visible=filter ((/=W.screen cur) . W.screen) scrs
                   , W.hidden=filter ((`notElem` selectedTags) . W.tag) allWS }
  where
    original = W.workspaces ws
    template = W.layout (W.workspace $ W.current ws)
    allWS = original ++ take (max 0 $ length ds-length original)
      [W.Workspace t template Nothing | n <- [(1::Int)..]
       , let t="_screen_" ++ show n, not (W.tagMember t ws)]
    retained = [(display d, W.workspace old) | d <- ds
      , Just old <- [find ((==display d) . displayID . W.screenDetail) (W.screens ws)]]
    retainedTags = map (W.tag . snd) retained
    pool = filter ((`notElem` retainedTags) . W.tag) allWS
    assignments = fst $ foldl' assign ([],pool) ds
    assign (acc,p) d = case lookup (display d) retained of
      Just w -> (acc ++ [(d,w)],p)
      Nothing -> case p of
        w:rest -> (acc ++ [(d,w)],rest)
        [] -> error "rescreen: impossible empty workspace pool"
    scrs = [W.Screen w n (SD (usable d) (display d)) | (n,(d,w)) <- zip [0..] assignments]
    wanted = displayID (W.screenDetail $ W.current ws)
    cur = fromMaybe (head scrs) $ find ((==wanted) . displayID . W.screenDetail) scrs
    selectedTags = map (W.tag . W.workspace) scrs

rationalRect :: Rectangle -> Rectangle -> W.RationalRect
rationalRect (Rectangle sx sy sw sh) (Rectangle x y w h) = W.RationalRect
  (toRational (x-sx) / toRational (max 1 sw))
  (toRational (y-sy) / toRational (max 1 sh))
  (toRational w / toRational (max 1 sw)) (toRational h / toRational (max 1 sh))

-- Fold one observation of the world into policy state. Each step is a
-- separate function below, in the order they must run: adopt the snapshot,
-- restore a checkpoint, follow the user's own moves, admit new windows,
-- follow focus, and tell layouts about windows that went away.
reconcile :: Snapshot -> X ()
reconcile snap = do
  c <- asks config
  previous <- get
  let restarted = snapEpoch snap /= epoch previous
      observed = observedWindows snap
  adoptSnapshot snap c previous observed
  when (generation previous < 0) $ restoreSaved snap c observed
  unless restarted $ followFloatDrags previous observed
  admitNewWindows c observed
  followObservedFocus snap observed
  unless restarted $ announceRemovals previous (M.keysSet observed)

-- Windows worth managing: everything the helper reported, minus the ones the
-- user minimized. A window we hid stays, or its workspace would be forgotten.
observedWindows :: Snapshot -> M.Map Window WindowInfo
observedWindows snap = M.fromList
  [(wid wi,wi) | wi <- snapWindows snap, not (minimized wi) || ownedHidden wi]

-- Replace the state with one that matches the snapshot: a different native
-- Space epoch starts over, displays are re-assigned, and windows that are
-- gone are dropped.
adoptSnapshot :: Snapshot -> XConfig Layout -> XState
              -> M.Map Window WindowInfo -> X ()
adoptSnapshot snap c previous observed = put base
  { windowset = surviving
  , windowInfo = observed
  , ignoredWindows = S.intersection live (ignoredWindows base)
  , generation = snapGeneration snap
  , epoch = snapEpoch snap
  -- A focus request survives a few ticks so a dropped plan does not lose it,
  -- but never forever: an app that refuses focus must not lock policy.
  , focusRequested = focusRequested base && focusAgeTicks base < 4
  , focusAgeTicks = if focusRequested base then focusAgeTicks base+1 else 0
  , commands = []
  }
  where
    base | snapEpoch snap /= epoch previous = initialState c (snapDisplays snap)
         | otherwise = previous
    live = M.keysSet observed
    rescreened = rescreen (snapDisplays snap) (windowset base)
    surviving = foldr W.delete rescreened
      [w | w <- W.allWindows rescreened, S.notMember w live]

-- A checkpoint from the previous engine, replayed once at startup.
restoreSaved :: Snapshot -> XConfig Layout -> M.Map Window WindowInfo -> X ()
restoreSaved snap c observed = whenJust (snapRestore snap) $ \saved -> do
  s <- get
  case restoreCheckpoint c (snapEpoch snap) (snapDisplays snap) observed saved of
    Left problem -> trace $ "Checkpoint ignored: " ++ problem
    Right restored -> put s {windowset=restored}

-- A floating window the user dragged keeps its new geometry, and joins the
-- workspace of the display it landed on. Only an actually changed frame
-- counts, so a queued, unchanged snapshot cannot undo our own W.float.
followFloatDrags :: XState -> M.Map Window WindowInfo -> X ()
followFloatDrags previous observed = forM_ (M.elems observed) $ \wi -> do
  s <- get
  let w = wid wi
      wasFloating = M.member w (W.floating $ windowset s)
      onScreen = not (ownedHidden wi) && not (minimized wi)
      frameChanged = maybe False ((/=frame wi) . frame)
        (M.lookup w (windowInfo previous))
  when (wasFloating && onScreen && frameChanged) $
    whenJust (screenFor wi (windowset s)) $ \sc -> modify $ \st ->
      let moved = W.shiftWin (W.tag $ W.workspace sc) w (windowset st)
          spot = rationalRect (screenRect $ W.screenDetail sc) (frame wi)
      in st {windowset=W.float w spot moved}

-- A window we have not seen before joins the workspace of its display, and
-- manageHook decides where it really belongs. A hook that removes it means
-- "ignore this window", which we remember so it is not adopted again.
admitNewWindows :: XConfig Layout -> M.Map Window WindowInfo -> X ()
admitNewWindows c observed = forM_ (M.elems observed) $ \wi -> do
  s <- get
  let w = wid wi
  unless (W.member w (windowset s) || S.member w (ignoredWindows s)) $ do
    let ws = windowset s
        here = W.currentTag ws
        target = maybe here (W.tag . W.workspace) (screenFor wi ws)
    put s {windowset=W.view here . W.insertUp w . W.view target $ ws}
    Endo hook <- runQuery (manageHook c) w
    modify $ \st ->
      let managed = hook (windowset st)
      in st { windowset = managed
            , ignoredWindows = if W.member w managed then ignoredWindows st
                               else S.insert w (ignoredWindows st) }

-- Follow the focus the helper observed, unless a request of our own is still
-- outstanding. A window being hidden must not drag us back to its workspace.
followObservedFocus :: Snapshot -> M.Map Window WindowInfo -> X ()
followObservedFocus snap observed = whenJust (snapFocused snap) $ \w -> do
  s <- get
  let known = W.member w (windowset s)
      visible = maybe False (\wi -> not (minimized wi) && not (ownedHidden wi))
        (M.lookup w observed)
      ours = not (focusRequested s) || W.peek (windowset s) == Just w
  when (known && visible && ours) $ put s
    {windowset=W.focusWindow w (windowset s),focusRequested=False,focusAgeTicks=0}

-- Layouts that track windows need to hear about the ones that closed.
announceRemovals :: XState -> S.Set Window -> X ()
announceRemovals previous live = forM_ gone (broadcastMessage . WindowRemoved)
  where gone = [w | w <- W.allWindows (windowset previous), S.notMember w live]

screenFor :: WindowInfo -> WindowSet -> Maybe WindowScreen
screenFor wi ws =
  find ((==onDisplay wi) . displayID . W.screenDetail) (W.screens ws)

fromRationalRect :: Rectangle -> W.RationalRect -> Rectangle
fromRationalRect (Rectangle x y w h) (W.RationalRect rx ry rw rh) = Rectangle
  (x+round (rx*toRational w)) (y+round (ry*toRational h))
  (max 1 $ round (rw*toRational w)) (max 1 $ round (rh*toRational h))

floatObservedWindow :: Window -> X ()
floatObservedWindow w = do
  s <- get
  case M.lookup w (windowInfo s) of
    Nothing -> pure ()
    Just wi | W.member w (windowset s) ->
      whenJust (find ((==onDisplay wi) . displayID . W.screenDetail)
                (W.screens $ windowset s)) $ \sc ->
        put s {windowset=W.focusWindow w $ W.float w
                  (rationalRect (screenRect $ W.screenDetail sc) (frame wi)) (windowset s)
              ,focusRequested=True,focusAgeTicks=0}
    _ -> pure ()

-- Turn the current policy state into instructions for the helper: where the
-- visible windows go, what to hide, what to focus, and what a status bar
-- should show.
makePlan :: X Plan
makePlan = do
  screens <- gets (W.screens . windowset)
  placements <- concat <$> mapM placeScreen screens
  c <- asks config
  catchX (logHook c) (pure ())
  s <- get
  let ws = windowset s
      shown = [w | Placement w _ <- placements]
  pure Plan
    { planGeneration = generation s
    , planEpoch = epoch s
    , planFrames = placements
    , planHide = W.allWindows ws \\ shown
    , planFocus = requestedFocus s shown
    , planWorkspace = W.currentTag ws
    , planLayout = description . W.layout . W.workspace $ W.current ws
    , planCheckpoint = checkpoint s
    , planWorkspaces = workspaceSummary c ws
    }

-- Run one screen's layout, keep any layout state it returns, and add the
-- floating windows, whose geometry is relative to that screen.
placeScreen :: WindowScreen -> X [Placement]
placeScreen sc = do
  floats <- gets (W.floating . windowset)
  let ws = W.workspace sc
      area = screenRect (W.screenDetail sc)
      tiled = ws {W.stack = W.stack ws >>= W.filter (`M.notMember` floats)}
  (tiledRects,newLayout) <- runLayout tiled area
  whenJust newLayout $ \l -> modify $ \s -> s {windowset = W.mapWorkspace
    (\cw -> if W.tag cw == W.tag ws then cw {W.layout=l} else cw) (windowset s)}
  let floatRects = [(w,fromRationalRect area rr)
                   | w <- W.integrate' (W.stack ws), Just rr <- [M.lookup w floats]]
  pure [Placement w rect | (w,rect) <- tiledRects ++ floatRects]

-- Focus is only ever requested for a window a key binding asked for, and only
-- while that window is actually being shown.
requestedFocus :: XState -> [Window] -> Maybe Window
requestedFocus s shown = case (focusRequested s,W.peek (windowset s)) of
  (True,Just w) | w `elem` shown -> Just w
  _ -> Nothing

-- One entry per workspace for the status bar, in config order, with any
-- generated tags after them.
workspaceSummary :: XConfig Layout -> WindowSet -> [WorkspaceInfo]
workspaceSummary c ws =
  [ WorkspaceInfo (W.tag w) (length $ W.integrate' $ W.stack w)
      (W.tag w == W.currentTag ws) (W.tag w `elem` onScreens)
  | w <- configured ++ generated ]
  where
    onScreens = map (W.tag . W.workspace) (W.screens ws)
    configured = [w | t <- workspaces c
                 , Just w <- [find ((==t) . W.tag) (W.workspaces ws)]]
    generated = [w | w <- W.workspaces ws, W.tag w `notElem` workspaces c]

-- A bridge-session checkpoint. AX handles are never persisted across a new
-- native process. read-layout failures fall back to the new config's layout.
data SavedWorkspace = SavedWorkspace
  { savedTag :: String, savedLayout :: String, savedWindows :: [Window]
  , savedFocus :: Maybe Window } deriving (Generic,Show)
instance ToJSON SavedWorkspace
instance FromJSON SavedWorkspace
data SavedFloat = SavedFloat Window Double Double Double Double deriving (Generic,Show)
instance ToJSON SavedFloat
instance FromJSON SavedFloat
data Saved = Saved
  { savedVersion :: Int, savedEpoch :: Int, savedCurrent :: String
  , savedWorkspaces :: [SavedWorkspace], savedDisplays :: [(Int,String)]
  , savedFloats :: [SavedFloat] } deriving (Generic,Show)
instance ToJSON Saved
instance FromJSON Saved
checkpoint :: XState -> Value
checkpoint s = toJSON $ Saved 1 (epoch s) (W.currentTag ws)
  [SavedWorkspace (W.tag w) (show $ W.layout w) (W.integrate' $ W.stack w)
                  (W.focus <$> W.stack w) | w <- W.workspaces ws]
  [(displayID $ W.screenDetail sc,W.tag $ W.workspace sc) | sc <- W.screens ws]
  [SavedFloat w (fromRational x) (fromRational y) (fromRational rw) (fromRational rh)
    | (w,W.RationalRect x y rw rh) <- M.toList (W.floating ws)]
  where ws=windowset s
-- Rebuild policy state from a checkpoint. Rejected outright if it describes a
-- different protocol version or a different native Space epoch; otherwise
-- every window in it must still exist, and each may appear on one workspace.
restoreCheckpoint :: XConfig Layout -> Int -> [DisplayInfo]
                  -> M.Map Window WindowInfo -> Value -> Either String WindowSet
restoreCheckpoint c ep ds live value = case fromJSON value of
  Error e -> Left e
  Success saved
    | savedVersion saved /= 1 -> Left "unsupported version"
    | savedEpoch saved /= ep -> Left "different native Space epoch"
    | otherwise -> Right (rebuild c ds live saved)

rebuild :: XConfig Layout -> [DisplayInfo] -> M.Map Window WindowInfo
        -> Saved -> WindowSet
rebuild c ds live saved = W.view (savedCurrent saved) placed {W.floating=floats}
  where
    base = windowset (initialState c ds)
    tags = map W.tag (W.workspaces base)
    workspaces' = restoreWorkspaces c live saved tags
    placed = assignScreens base ds saved tags workspaces'
    floats = restoreFloats saved placed

-- One workspace per known tag, holding the windows the checkpoint listed that
-- are still alive. A window claimed by two workspaces stays on the first.
restoreWorkspaces :: XConfig Layout -> M.Map Window WindowInfo -> Saved
                  -> [WorkspaceId] -> [WindowSpace]
restoreWorkspaces c live saved tags = snd (foldl' step (S.empty,[]) tags)
  where
    step (claimed,acc) t = case find ((==t) . savedTag) (savedWorkspaces saved) of
      Nothing -> (claimed,acc ++ [W.Workspace t (layoutHook c) Nothing])
      Just sw -> (S.union claimed (S.fromList ids)
                 ,acc ++ [W.Workspace t (savedLayoutOr c sw) (stackOf sw ids)])
        where ids = nub [w | w <- savedWindows sw
                       , M.member w live, S.notMember w claimed]
    stackOf sw ids = case savedFocus sw of
      Just f | (before,_:after) <- break (==f) ids -> Just (W.Stack f (reverse before) after)
      _ -> W.differentiate ids

-- A layout that no longer parses falls back to the config's layout.
savedLayoutOr :: XConfig Layout -> SavedWorkspace -> Layout Window
savedLayoutOr c sw = case readsLayout (layoutHook c) (savedLayout sw) of
  [(l,"")] -> l
  _ -> layoutHook c

-- Give each display the workspace it had, provided that display is still
-- attached and no other display has already taken that workspace.
assignScreens :: WindowSet -> [DisplayInfo] -> Saved -> [WorkspaceId]
              -> [WindowSpace] -> WindowSet
assignScreens base ds saved tags workspaces' = case screens of
  [] -> base
  sc:rest -> base {W.current=sc,W.visible=rest,W.hidden=offScreen}
  where
    requested = [(d,t) | (d,t) <- savedDisplays saved, t `elem` tags]
    attached = S.fromList (map display ds)
    spokenFor = [t | (d,t) <- requested, S.member d attached]
    unclaimed = filter ((`notElem` spokenFor) . W.tag) workspaces'
    (_,screens) = foldl' alloc (unclaimed,[]) (zip [0..] ds)
    alloc (pool,acc) (n,d) = (filter ((/=W.tag chosen) . W.tag) pool
                             ,acc ++ [W.Screen chosen n (SD (usable d) (display d))])
      where
        taken = map (W.tag . W.workspace) acc
        preferred = lookup (display d) requested >>= \t ->
          find (\w -> W.tag w == t && t `notElem` taken) workspaces'
        chosen = fromMaybe (error "checkpoint display allocation")
          (preferred <|> find ((`notElem` taken) . W.tag) (pool ++ workspaces'))
    onScreen = map (W.tag . W.workspace) screens
    offScreen = filter ((`notElem` onScreen) . W.tag) workspaces'

-- Float rectangles are relative, so only finite, positive ones are usable.
restoreFloats :: Saved -> WindowSet -> M.Map Window W.RationalRect
restoreFloats saved ws = M.fromList
  [ (w,W.RationalRect (toRational x) (toRational y) (toRational rw) (toRational rh))
  | SavedFloat w x y rw rh <- savedFloats saved, W.member w ws
  , all (\a -> not (isNaN a || isInfinite a)) [x,y,rw,rh], rw > 0, rh > 0 ]

emit :: ToJSON a => a -> IO ()
emit a = BL.hPutStrLn stdout (encode a) >> hFlush stdout

-- The engine's entry point, called from the user's xmonad.hs. It announces
-- its key bindings, then answers every event with a plan until stdin closes.
xmonad :: (LayoutClass l Window, Read (l Window)) => XConfig l -> IO ()
xmonad user = do
  mapM_ (`hSetBuffering` LineBuffering) [stdin,stdout,stderr]
  hSetEncoding stderr utf8
  -- A control command never starts an engine, and must work even when the
  -- config it was compiled from is one this build would reject.
  args <- getArgs
  handleCommand args
  let c = user {layoutHook = Layout (layoutHook user)}
      conf = XConf c
      keymap = keys c c
  either (ioError . userError) pure (checkWorkspaces c)
  emit (handshake c keymap)
  unless ("--check-config" `elem` args) $ do
    (_,initial) <- runX conf (initialState c [])
      (unless ("--no-startup" `elem` args) $ catchX (startupHook c) (pure ()))
    loop conf keymap initial

-- Workspace tags name things the user types and the helper displays, so they
-- have to exist and be distinguishable.
checkWorkspaces :: XConfig Layout -> Either String ()
checkWorkspaces c
  | null tags = Left "workspaces must not be empty"
  | any null tags = Left "workspace names must not be empty"
  | length (nub tags) /= length tags = Left "workspace names must be distinct"
  | otherwise = Right ()
  where tags = workspaces c

handshake :: XConfig Layout -> M.Map (KeyMask,KeySym) (X ()) -> Value
handshake c keymap = object
  ["type" .= ("configure" :: String),"protocol" .= (1::Int)
  ,"keys" .= [object ["mask" .= m,"sym" .= k] | (m,k) <- M.keys keymap]
  ,"mouseMask" .= modMask c]

-- One line in, one plan out. A protocol error is reported and skipped rather
-- than fatal, so a single bad line cannot take the session down.
loop :: XConf -> M.Map (KeyMask,KeySym) (X ()) -> XState -> IO ()
loop conf keymap s = do
  eof <- hIsEOF stdin
  unless eof $ do
    line <- BS.hGetLine stdin
    when (BS.length line > maxLine) $
      ioError (userError "Protocol line exceeds 1 MiB")
    case eitherDecodeStrict' line of
      Left e -> hPutStrLn stderr ("Protocol error: " ++ e) >> loop conf keymap s
      Right ExitEvent ->
        () <$ runX conf s (catchX (broadcastMessage ReleaseResources) (pure ()))
      Right PingEvent -> do
        emit (object ["type" .= ("pong" :: String)])
        loop conf keymap s
      Right event -> do
        (_,s') <- runX conf s (catchX (handleEvent keymap event) (pure ()))
        -- Before the first snapshot there is no world to plan for.
        if generation s' < 0 then loop conf keymap s' else do
          (plan,s'') <- runX conf s' makePlan
          emit plan
          mapM_ (emit . commandJSON) (commands s'')
          loop conf keymap (s'' {commands=[]})
  where maxLine = 1048576

handleEvent :: M.Map (KeyMask,KeySym) (X ()) -> InputEvent -> X ()
handleEvent keymap event = case event of
  SnapshotEvent snap -> reconcile snap
  MouseFloatEvent w -> floatObservedWindow w
  -- A bound key is the one thing that may ask the helper to change focus.
  KeyEvent m k -> whenJust (M.lookup (m,k) keymap) $ \action -> do
    modify $ \st -> st {focusRequested=True,focusAgeTicks=0,commands=[]}
    action
  _ -> pure ()
