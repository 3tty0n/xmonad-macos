{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE DeriveGeneric #-}
module XMonad.MacOS.Engine
  ( xmonad, initialState, reconcile, floatObservedWindow, makePlan, rescreen, checkpoint, restoreCheckpoint ) where
import XMonad.Core
import XMonad.MacOS.Protocol
import XMonad.Operations (broadcastMessage)
import qualified XMonad.StackSet as W
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import qualified Data.ByteString as BS
import qualified Data.ByteString.Lazy.Char8 as BL
import Data.Aeson
import Data.List (find, nub, foldl', (\\))
import Data.Maybe (fromMaybe, mapMaybe)
import Control.Monad (forM, forM_, when, unless)
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
-- New displays cannot steal a workspace from a display retained later in the list.
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

reconcile :: Snapshot -> X ()
reconcile snap = do
  c <- asks config
  old <- get
  let differentEpoch = snapEpoch snap /= epoch old
      base = if differentEpoch then initialState c (snapDisplays snap) else old
      infos = M.fromList [(wid wi,wi) | wi <- snapWindows snap
                         , not (minimized wi) || ownedHidden wi]
      live = M.keysSet infos
      ws0 = rescreen (snapDisplays snap) (windowset base)
      ws1 = foldr W.delete ws0 [w | w <- W.allWindows ws0, S.notMember w live]
  put base {windowset=ws1,windowInfo=infos
           ,ignoredWindows=S.intersection live (ignoredWindows base)
           ,generation=snapGeneration snap,epoch=snapEpoch snap
           ,focusRequested=focusRequested base && focusAgeTicks base < 4
           ,focusAgeTicks=if focusRequested base then focusAgeTicks base+1 else 0
           ,commands=[]}
  when (generation old < 0) $ whenJust (snapRestore snap) $ \saved -> do
    s <- get
    case restoreCheckpoint c (snapEpoch snap) (snapDisplays snap) infos saved of
      Left problem -> trace $ "Checkpoint ignored: " ++ problem
      Right restored -> put s {windowset=restored}
  -- Float drags update relative geometry only when the observed frame changed.
  -- A queued, unchanged snapshot cannot undo a programmatic W.float operation.
  unless differentEpoch $ forM_ (M.elems infos) $ \wi -> do
    s <- get
    when (M.member (wid wi) (W.floating $ windowset s)
          && not (ownedHidden wi) && not (minimized wi)
          && maybe False ((/=frame wi) . frame) (M.lookup (wid wi) $ windowInfo old)) $
      whenJust (find ((==onDisplay wi) . displayID . W.screenDetail)
                (W.screens $ windowset s)) $ \sc ->
        modify $ \st ->
          let targetTag=W.tag (W.workspace sc)
              moved=W.shiftWin targetTag (wid wi) (windowset st)
          in st {windowset=W.float (wid wi)
            (rationalRect (screenRect $ W.screenDetail sc) (frame wi)) moved}
  forM_ (M.elems infos) $ \wi -> do
    s <- get
    let w = wid wi
    unless (W.member w (windowset s) || S.member w (ignoredWindows s)) $ do
      let ws = windowset s
          currentTag = W.currentTag ws
          target = fromMaybe currentTag $ W.tag . W.workspace <$>
            find ((==onDisplay wi) . displayID . W.screenDetail) (W.screens ws)
          inserted = W.view currentTag . W.insertUp w . W.view target $ ws
      put s {windowset=inserted}
      Endo f <- runQuery (manageHook c) w
      modify $ \st -> let ws' = f (windowset st) in st
        {windowset=ws',ignoredWindows=if W.member w ws' then ignoredWindows st
                                      else S.insert w (ignoredWindows st)}
  -- Follow observed focus unless a user focus request is still pending. Keep
  -- requests across stale/dropped native plans, acknowledge on observed focus,
  -- and abandon after four reconciliation ticks so a refusing app cannot lock
  -- the policy focus forever. WM-minimization animations must not switch back
  -- to the workspace we have just hidden.
  whenJust (snapFocused snap) $ \w -> do
    s <- get
    when (W.member w (windowset s)
          && maybe False (\wi -> not (minimized wi) && not (ownedHidden wi)) (M.lookup w infos)
          && (not (focusRequested s) || W.peek (windowset s) == Just w)) $
      put s {windowset=W.focusWindow w (windowset s),focusRequested=False,focusAgeTicks=0}
  unless differentEpoch $
    forM_ [w | w <- W.allWindows (windowset old), S.notMember w live] $
      broadcastMessage . WindowRemoved

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

makePlan :: X Plan
makePlan = do
  wsBefore <- gets windowset
  let floats = W.floating wsBefore
  placements <- fmap concat . forM (W.screens wsBefore) $ \sc -> do
    let w = W.workspace sc
        r = screenRect (W.screenDetail sc)
        tiled = w {W.stack=W.stack w >>= W.filter (`M.notMember` floats)}
    (rs,ml) <- runLayout tiled r
    whenJust ml $ \l -> modify $ \s -> s {windowset=W.mapWorkspace
      (\cw -> if W.tag cw == W.tag w then cw {W.layout=l} else cw) (windowset s)}
    let frs = [(fw,fromRationalRect r rr) | fw <- W.integrate' (W.stack w)
              , Just rr <- [M.lookup fw floats]]
    pure [Placement fw rect | (fw,rect) <- rs ++ frs]
  c <- asks config
  catchX (logHook c) (pure ())
  s <- get
  let ws=windowset s
      shown=[w | Placement w _ <- placements]
      focused=case (focusRequested s,W.peek ws) of
        (True,Just w) | w `elem` shown -> Just w
        _ -> Nothing
  pure $ Plan (generation s) (epoch s) placements
    (W.allWindows ws \\ shown) focused (W.currentTag ws)
    (description $ W.layout $ W.workspace $ W.current ws) (checkpoint s)

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
restoreCheckpoint :: XConfig Layout -> Int -> [DisplayInfo]
                  -> M.Map Window WindowInfo -> Value -> Either String WindowSet
restoreCheckpoint c ep ds infos value = case fromJSON value of
  Error e -> Left e
  Success saved
    | savedVersion saved /= 1 -> Left "unsupported version"
    | savedEpoch saved /= ep -> Left "different native Space epoch"
    | otherwise -> Right $ restore saved
  where
    restore saved = W.view (savedCurrent saved) result
      where
        base = windowset (initialState c ds)
        tags = map W.tag (W.workspaces base)
        (_,restored) = foldl' one (S.empty,[]) tags
        one (used,acc) t = case find ((==t) . savedTag) (savedWorkspaces saved) of
          Nothing -> (used,acc ++ [W.Workspace t (layoutHook c) Nothing])
          Just sw ->
            let ids=nub [w | w <- savedWindows sw,M.member w infos,S.notMember w used]
                st=case savedFocus sw of
                     Just f -> case break (==f) ids of
                       (before,_:after) -> Just (W.Stack f (reverse before) after)
                       _ -> W.differentiate ids
                     Nothing -> W.differentiate ids
                l=case readsLayout (layoutHook c) (savedLayout sw) of
                    [(a,"")] -> a
                    _ -> layoutHook c
            in (S.union used $ S.fromList ids,acc ++ [W.Workspace t l st])
        -- Rebuild display assignments without allowing a duplicate workspace.
        requested=[(d,t) | (d,t) <- savedDisplays saved,t `elem` tags]
        retainedIDs=S.fromList (map display ds)
        wanted=[t | (d,t) <- requested,S.member d retainedIDs]
        pool=filter ((`notElem` wanted) . W.tag) restored
        (_,scrs) = foldl' alloc (pool,[]) (zip [0..] ds)
        alloc (p,acc) (n,d) =
          let used=map (W.tag . W.workspace) acc
              chosen=lookup (display d) requested >>= \t ->
                find (\w -> W.tag w == t && t `notElem` used) restored
              fallback=find ((`notElem` used) . W.tag) (p ++ restored)
              w=fromMaybe (error "checkpoint display allocation") (case chosen of
                  Just a -> Just a; Nothing -> fallback)
          in (filter ((/=W.tag w) . W.tag) p,acc ++ [W.Screen w n (SD (usable d) (display d))])
        usedTags=map (W.tag . W.workspace) scrs
        withScreens=case scrs of
          [] -> base
          sc:rest -> base {W.current=sc,W.visible=rest
                          ,W.hidden=filter ((`notElem` usedTags) . W.tag) restored}
        floating=M.fromList [(w,W.RationalRect (toRational x) (toRational y)
                       (toRational rw) (toRational rh))
          | SavedFloat w x y rw rh <- savedFloats saved,W.member w withScreens
          , all (\a -> not (isNaN a || isInfinite a)) [x,y,rw,rh],rw>0,rh>0]
        result=withScreens {W.floating=floating}

emit :: ToJSON a => a -> IO ()
emit a = BL.hPutStrLn stdout (encode a) >> hFlush stdout

xmonad :: (LayoutClass l Window, Read (l Window)) => XConfig l -> IO ()
xmonad user = do
  hSetBuffering stdin LineBuffering
  hSetBuffering stdout LineBuffering
  hSetBuffering stderr LineBuffering
  hSetEncoding stderr utf8
  let c=user {layoutHook=Layout (layoutHook user)}
      conf=XConf c
      keymap=keys c c
      configure=object ["type" .= ("configure" :: String),"protocol" .= (1::Int)
        ,"keys" .= [object ["mask" .= m,"sym" .= k] | (m,k) <- M.keys keymap]
        ,"mouseMask" .= modMask c]
  when (null (workspaces c) || any null (workspaces c)
        || length (nub $ workspaces c) /= length (workspaces c)) $
    ioError $ userError "workspaces must be nonempty, distinct, nonempty names"
  args <- getArgs
  if "--check-config" `elem` args then emit configure else do
    emit configure
    (_,s) <- runX conf (initialState c [])
      (unless ("--no-startup" `elem` args) $ catchX (startupHook c) (pure ()))
    loop conf keymap s
  where
    loop conf keymap s = do
      eof <- hIsEOF stdin
      unless eof $ do
        line <- BS.hGetLine stdin
        if BS.length line > 1048576 then ioError (userError "Protocol line exceeds 1 MiB") else
          case eitherDecodeStrict' line of
            Left e -> hPutStrLn stderr ("Protocol error: " ++ e) >> loop conf keymap s
            Right ExitEvent -> do
              _ <- runX conf s (catchX (broadcastMessage ReleaseResources) (pure ()))
              pure ()
            Right PingEvent -> emit (object ["type" .= ("pong" :: String)]) >> loop conf keymap s
            Right event -> do
              (_,s') <- runX conf s $ catchX (case event of
                SnapshotEvent snap -> reconcile snap
                KeyEvent m k -> whenJust (M.lookup (m,k) keymap) $ \action -> do
                  modify $ \st -> st {focusRequested=True,focusAgeTicks=0,commands=[]}
                  action
                MouseFloatEvent w -> floatObservedWindow w
                _ -> pure ()) (pure ())
              if generation s' < 0 then loop conf keymap s' else do
                (plan,s'') <- runX conf s' makePlan
                emit plan
                mapM_ (emit . commandJSON) (commands s'')
                loop conf keymap (s'' {commands=[]})
