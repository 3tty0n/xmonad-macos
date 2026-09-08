{-# LANGUAGE OverloadedStrings #-}
module Main where
import XMonad
import qualified XMonad.StackSet as W
import XMonad.MacOS.Engine
import XMonad.MacOS.Protocol
import XMonad.Util.EZConfig (parseKey)
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.List (sort,nub)
import Data.Aeson
import Control.Monad (forM_,unless)

check :: String -> Bool -> IO ()
check name ok = unless ok $ ioError $ userError $ "FAIL: " ++ name
cfg :: XConfig Layout
cfg = def {layoutHook=Layout (layoutHook def)}
displays :: [DisplayInfo]
displays=[DisplayInfo 10 (Rectangle 0 24 1000 800),DisplayInfo 20 (Rectangle (-1000) 24 1000 800)]
wi :: Window -> Int -> WindowInfo
wi w d=WindowInfo w 123 "Terminal" "com.apple.Terminal" (show w) d
  (Rectangle (if d==10 then 0 else -1000) 24 500 800) False False
snapshot :: Snapshot
snapshot=Snapshot 1 1 displays [wi 1 10,wi 2 10,wi 3 20] (Just 1) Nothing
initial :: XState
initial=initialState cfg displays
conf :: XConf
conf=XConf cfg
main :: IO ()
main = do
  forM_ [1..30::Int] $ \n -> do
    let empty=W.new () ["1","2","3"] [(),()] :: W.StackSet String () Int Int ()
        ws=foldl (flip W.insertUp) empty [1..n]
        variants=[ws,W.focusUp ws,W.focusDown ws,W.swapUp ws,W.swapDown ws,
          W.swapMaster ws,W.shiftMaster ws,W.shift "2" ws,W.greedyView "2" ws,
          W.greedyView "3" ws,W.focusWindow n ws]
    check "focus inverse" (W.focusDown (W.focusUp ws)==ws)
    forM_ variants $ \v -> do
      check "membership preserved" (sort (W.allWindows v)==[1..n])
      check "global uniqueness" (let ids=concatMap (W.integrate' . W.stack) (W.workspaces v)
                                 in length ids==length (nub ids))
      check "screen and workspace uniqueness" (length (nub $ map W.tag $ W.workspaces v)==3)
    check "shift keeps current tag" (W.currentTag (W.shift "2" ws)==W.currentTag ws)
    check "delete removes exactly one" (sort (W.allWindows $ W.delete n ws)==[1..n-1])
  let r=Rectangle 0 24 1000 800
      st=W.Stack (1::Window) [] [2,3]
      tall=Tall 1 (3/100) (1/2) :: Tall Window
  check "Tall geometry" (pureLayout tall r st==
    [(1,Rectangle 0 24 500 800),(2,Rectangle 500 24 500 400),(3,Rectangle 500 424 500 400)])
  -- Full stacks every window at the same frame, focused last, so switching to
  -- it never minimizes windows into the macOS Dock.
  check "Full stacks all windows, focused last"
    (pureLayout Full r st==[(2,r),(3,r),(1,r)])
  forM_ [1..30] $ \n -> forM_ [0..4] $ \masters -> forM_ [1/4,1/2,3/4] $ \ratio -> do
    let rs=tile ratio r masters n
    check "tile count" (length rs==n)
    check "tile area" (sum [rect_width a*rect_height a | a<-rs]==800000)
  (_,s1) <- runX conf initial (reconcile snapshot)
  check "initial display assignment" (W.findTag 3 (windowset s1)==Just "2")
  check "observed focus" (W.peek (windowset s1)==Just 1)
  (p1,s2) <- runX conf s1 makePlan
  check "passive snapshot never requests focus" (planFocus p1==Nothing)
  check "three windows laid out" (length (planFrames p1)==3 && null (planHide p1))
  (_,mouseFloat) <- runX conf s2 (floatObservedWindow 2)
  check "mouse drag floats observed window" (M.member 2 (W.floating $ windowset mouseFloat))
  check "mouse drag focuses observed window" (W.peek (windowset mouseFloat)==Just 2 && focusRequested mouseFloat)
  (mousePlan,_) <- runX conf mouseFloat makePlan
  check "mouse float preserves observed geometry"
    (lookup 2 [(w,r) | Placement w r <- planFrames mousePlan] == Just (frame $ wi 2 10))
  let movedAcross=snapshot {snapGeneration=2,snapWindows=[wi 1 10,(wi 2 20){frame=Rectangle (-900) 100 500 600},wi 3 20],snapFocused=Just 2}
  (_,crossDisplay) <- runX conf mouseFloat (reconcile movedAcross)
  check "floating drag across displays follows visible workspace" (W.findTag 2 (windowset crossDisplay)==Just "2")
  (crossPlan,_) <- runX conf crossDisplay makePlan
  check "cross-display float keeps observed geometry"
    (lookup 2 [(w,r) | Placement w r <- planFrames crossPlan] == Just (Rectangle (-900) 100 500 600))
  (p2,s3) <- runX conf s2 $ windows (W.greedyView "3") >> makePlan
  check "logical workspace hides old workspace only" (sort (planHide p2)==[1,2])
  check "other monitor remains visible" (map (\(Placement w _) -> w) (planFrames p2)==[3])
  let ownSnapshot=snapshot {snapGeneration=2,snapWindows=[(wi 1 10){minimized=True,ownedHidden=True},wi 2 10,wi 3 20],snapFocused=Nothing}
  (_,sOwn) <- runX conf s3 (reconcile ownSnapshot)
  check "WM-minimized window remains managed" (W.member 1 $ windowset sOwn)
  let userSnapshot=ownSnapshot {snapGeneration=3,snapWindows=[(wi 1 10){minimized=True,ownedHidden=False},wi 2 10,wi 3 20]}
  (_,sUser) <- runX conf sOwn (reconcile userSnapshot)
  check "user-minimized window is not managed" (not $ W.member 1 $ windowset sUser)
  (_,cycleState) <- runX conf s2 $ sendMessage NextLayout >> sendMessage NextLayout >> sendMessage NextLayout
  check "Choose cycles and wraps" (description (W.layout (W.workspace $ W.current $ windowset cycleState))=="Tall")
  -- A dropped/stale plan must not lose the user's focus intent. Conversely,
  -- the retry is bounded and a WM-hide animation cannot reverse a view.
  (_,pending) <- runX conf s2 (windows W.focusDown)
  let oldFocus=snapshot {snapGeneration=2}
      desired=W.peek (windowset pending)
  (_,retried) <- runX conf pending (reconcile oldFocus)
  check "pending focus survives stale observation" (W.peek (windowset retried)==desired && focusRequested retried)
  (_,acked) <- runX conf retried (reconcile $ oldFocus {snapFocused=desired,snapGeneration=3})
  check "focus acknowledgement clears request" (not $ focusRequested acked)
  (_,expired) <- runX conf pending (mapM_ reconcile (replicate 5 oldFocus))
  check "focus retry has bounded lifetime" (not $ focusRequested expired)
  let ownedAnimation=snapshot {snapGeneration=4,snapFocused=Just 1
        ,snapWindows=[(wi 1 10){ownedHidden=True},(wi 2 10){ownedHidden=True},wi 3 20]}
  (_,noBounce) <- runX conf s3 (reconcile ownedAnimation)
  check "hide animation cannot change workspace" (W.currentTag (windowset noBounce)=="3")
  let saved=checkpoint s3
  case restoreCheckpoint cfg 1 displays (windowInfo s3) saved of
    Left e -> ioError $ userError e
    Right restored -> do
      check "checkpoint membership" (sort (W.allWindows restored)==sort (W.allWindows $ windowset s3))
      check "checkpoint workspace" (W.currentTag restored==W.currentTag (windowset s3))
  case restoreCheckpoint cfg 99 displays (windowInfo s3) saved of
    Left _ -> pure ()
    Right _ -> ioError $ userError "FAIL: wrong epoch checkpoint accepted"
  let unplugged=rescreen [displays !! 1] (windowset s2)
      plugged=rescreen (displays ++ [DisplayInfo 30 r]) unplugged
  check "hotplug loses no windows" (sort (W.allWindows plugged)==[1,2,3])
  check "hotplug screens unique" (length (nub $ map (W.tag . W.workspace) $ W.screens plugged)==3)
  check "retained display keeps its workspace" (W.tag (W.workspace $ W.current unplugged)=="2")
  (_,ignored) <- runX (XConf (cfg {manageHook=className =? "Terminal" --> doIgnore})) initial (reconcile snapshot)
  check "doIgnore persistent" (null (W.allWindows $ windowset ignored) && S.size (ignoredWindows ignored)==3)
  check "EZConfig modifiers" (parseKey 68 "M-S-<Return>"==Right (69,xK_Return))
  check "EZConfig rejects multistroke" (case parseKey 68 "M-x M-y" of Left _ -> True; _ -> False)
  check "recompile command protocol" (commandJSON Recompile == object ["type" .= ("command" :: String),"name" .= ("recompile" :: String)])
  check "bad protocol rejected" (case eitherDecode "{\"type\":\"wrong\"}" :: Either String InputEvent of Left _ -> True; _ -> False)
  check "JSON snapshot parse" (case eitherDecode
    "{\"type\":\"snapshot\",\"generation\":1,\"epoch\":1,\"screens\":[],\"windows\":[],\"focused\":null}" :: Either String InputEvent of
      Right (SnapshotEvent _) -> True; _ -> False)
  check "mouse float protocol parse" (case eitherDecode "{\"type\":\"mouseFloat\",\"wid\":2}" :: Either String InputEvent of
      Right (MouseFloatEvent 2) -> True; _ -> False)
  putStrLn "PASS: StackSet invariants, layouts, lifecycle, workspaces, hotplug, checkpoints, key parser and protocol"
