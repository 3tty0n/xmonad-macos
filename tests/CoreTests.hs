{-# LANGUAGE OverloadedStrings #-}
module Main where
import XMonad
import qualified XMonad.StackSet as W
import XMonad.MacOS.Engine
import XMonad.MacOS.Protocol
import XMonad.Util.EZConfig (parseKey)
import XMonad.Layout.Grid
import XMonad.Layout.Simplest
import XMonad.Layout.ResizableTile
import XMonad.Actions.CycleWS
import XMonad.Actions.WithAll
import XMonad.Actions.RotSlaves
import XMonad.Actions.SwapWorkspaces
import XMonad.Actions.DwmPromote
import XMonad.Layout.Renamed
import XMonad.Layout.Reflect
import XMonad.Layout.TwoPane
import XMonad.Layout.Accordion
import XMonad.Hooks.ManageHelpers (isDialog)
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.List (sort,nub)
import Data.Maybe (fromMaybe,listToMaybe)
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
  (Rectangle (if d==10 then 0 else -1000) 24 500 800) False False "AXStandardWindow"
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
  -- ThreeCol: master column plus two stacks, filling the frame without gaps.
  let frame3=Rectangle 0 24 1000 800
      cols n=tile3 False (1/2) frame3 1 n
      mids n=tile3 True (1/2) frame3 1 n
  check "ThreeCol one window fills the frame" (cols 1==[frame3])
  check "ThreeCol three columns" (length (cols 3)==3)
  check "ThreeCol area" (sum [rect_width a*rect_height a | a<-cols 3]==800000)
  check "ThreeCol columns do not overlap"
    (sort (map rect_x (cols 3))==map rect_x (cols 3) &&
     and [rect_x a+rect_width a<=rect_x b | (a,b) <- zip (cols 3) (drop 1 (cols 3))])
  check "ThreeCol master is left, ThreeColMid master is centred"
    (rect_x (head (cols 3))==0 && rect_x (head (mids 3)) > 0)
  check "ThreeCol splits the stacks evenly" (length (cols 5)==5)
  -- Circle: a centred master, satellites around it, focused window last.
  let circle=pureLayout Circle frame3 (W.Stack 2 [1] [3,4])
  check "Circle places every window" (length circle==4)
  check "Circle raises the focused window last" (fst (last circle)==2)
  let bigger=fromMaybe Circle (pureMessage Circle (SomeMessage Expand))
      wide=lookup 1 (pureLayout bigger frame3 (W.Stack 2 [1] [3,4]))
      base=lookup 1 circle
  check "Circle master grows with Expand" (fmap rect_width wide > fmap rect_width base)
  check "Circle master shrinks with Shrink"
    (fmap rect_width (lookup 1 (pureLayout (fromMaybe Circle $ pureMessage Circle (SomeMessage Shrink))
       frame3 (W.Stack 2 [1] [3,4]))) < fmap rect_width base)
  check "Circle centres the master"
    (let Just c=lookup 1 circle
     in rect_x c > 0 && rect_y c > 24 && rect_width c < 1000)
  -- Ported contrib layouts: same frame, no gaps, no overlap.
  let grid n = map snd (pureLayout Grid frame3 (W.Stack 0 [] [1..n-1]))
  check "Grid places every window" (length (grid 4)==4)
  check "Grid area" (sum [rect_width a*rect_height a | a <- grid 4]==800000)
  check "Grid single window fills the frame" (grid 1==[frame3])
  check "Simplest gives every window the frame"
    (map snd (pureLayout Simplest frame3 (W.Stack 0 [] [1,2]))==replicate 3 frame3)
  let rt = ResizableTall 1 (3/100) (1/2) []
      heights l = map (rect_height . snd) (pureLayout l frame3 (W.Stack 1 [] [2,3]))
  check "ResizableTall splits the stack evenly" (heights rt==[800,400,400])
  check "ResizableTall honours per-window weights"
    (heights (ResizableTall 1 (3/100) (1/2) [1,1.5,1])==[800,480,320])
  (resized,_) <- runX conf initial $ do
    modify $ \st -> st {windowset=W.insertUp 3 $ W.insertUp 2 $ W.insertUp 1 (windowset st)}
    handleMessage rt (SomeMessage MirrorExpand)
  check "MirrorExpand records a weight for the focused window"
    (maybe False ((>0) . length . resizableSlaves) resized)
  check "MirrorExpand leaves the other weights alone"
    (maybe False (all (==1) . drop 1 . resizableSlaves) resized)
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
  -- One screen, so a neighbour workspace is hidden rather than on a monitor.
  let single=initialState cfg [head displays]
  -- More ported contrib layouts.
  let stack3 = W.Stack 2 [1] [3]
      rects l = map snd (pureLayout l frame3 stack3)
  check "TwoPane shows master and focus only" (length (rects (TwoPane (3/100) (1/2)))==2)
  check "TwoPane splits the frame"
    (sum [rect_width r*rect_height r | r <- rects (TwoPane (3/100) (1/2))]==800000)
  check "Accordion places every window" (length (rects Accordion)==3)
  check "Accordion gives the focused window the most room"
    (let hs=map rect_height (rects Accordion) in maximum hs==hs !! 1)
  check "Accordion fills the frame exactly"
    (sum (map rect_height (rects Accordion))==800)
  (reflected,_) <- runX conf initial $
    runLayout (W.Workspace "1" (reflectHoriz (Tall 1 (3/100) (1/2))) (Just stack3)) frame3
  check "reflectHoriz mirrors the master to the right"
    (maximum [rect_x r | (_,r) <- fst reflected]==500)
  check "renamed replaces the description"
    (description (renamed [Replace "custom"] (Tall 1 (3/100) (1/2)))=="custom")
  check "renamed can wrap the old description"
    (description (renamed [Prepend "[",Append "]"] (Tall 1 (3/100) (1/2)))=="[Tall]")
  -- Ported contrib actions.
  (_,rotated) <- runX conf s1 rotSlavesDown
  check "rotSlaves keeps the master in place"
    (take 1 (W.integrate' (W.stack $ W.workspace $ W.current $ windowset rotated))
     == take 1 (W.integrate' (W.stack $ W.workspace $ W.current $ windowset s1)))
  (_,promoted) <- runX conf s1 dwmpromote
  check "dwmpromote makes the focused window master"
    (Just (W.focus <$> W.stack (W.workspace $ W.current $ windowset s1))
     == Just (listToMaybe (W.integrate' (W.stack $ W.workspace $ W.current $ windowset promoted))))
  -- Tags are exchanged in place, so the windows you are looking at stay put
  -- and take the other workspace's name with them.
  let swapped = swapWithCurrent "2" (windowset s1)
  check "swapWithCurrent renames the current workspace"
    (W.currentTag swapped=="2")
  check "swapWithCurrent keeps the visible windows"
    (sort (W.integrate' (W.stack $ W.workspace $ W.current swapped))==[1,2])
  check "swapWithCurrent gives the old tag to the other workspace"
    (W.findTag 3 swapped==Just "1")
  -- Two displays: a workspace each, laid out in that display's own frame.
  check "each display shows its own workspace"
    (map (W.tag . W.workspace) (W.screens $ windowset s1)==["1","2"])
  (twoScreen,_) <- runX conf s1 makePlan
  let onDisplay10=[r | Placement w r <- planFrames twoScreen, w `elem` [1,2]]
      onDisplay20=[r | Placement w r <- planFrames twoScreen, w == 3]
  check "windows are placed on the display they appeared on"
    (all ((>=0) . rect_x) onDisplay10 && all ((<0) . rect_x) onDisplay20)
  check "nothing is hidden while both displays are visible" (null (planHide twoScreen))
  -- Sending a window to the other screen's workspace moves it there.
  (_,acrossScreens) <- runX conf s1 $ do
    target <- screenWorkspace 1
    whenJust target (windows . W.shift)
  check "shift to another screen moves the window"
    (W.findTag 1 (windowset acrossScreens)==Just "2")
  (_,cycled) <- runX conf single (nextWS >> nextWS)
  check "nextWS walks the config order" (W.currentTag (windowset cycled)=="3")
  (_,wrapped) <- runX conf single prevWS
  check "prevWS wraps to the last workspace" (W.currentTag (windowset wrapped)=="0")
  (_,back) <- runX conf single (nextWS >> toggleWS)
  check "toggleWS returns to the previous workspace" (W.currentTag (windowset back)=="1")
  (_,killed) <- runX conf s1 killAll
  check "killAll closes every window on the workspace"
    (length [w | Close w <- commands killed]==2)
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
  let lingering=snapshot {snapGeneration=5,snapFocused=Just 1
        ,snapWindows=[wi 1 10,wi 2 10,wi 3 20]}
  (_,noPull) <- runX conf s3 (reconcile lingering)
  check "visible window on a hidden workspace cannot change current tag"
    (W.currentTag (windowset noPull)=="3")
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
  let dialog=(wi 4 10){subroleText="AXDialog",frame=Rectangle 120 80 320 180}
      dialogSnap=snapshot {snapWindows=[wi 1 10,dialog],snapFocused=Just 4}
  (dialogPlan,dialogSt) <- runX conf initial (reconcile dialogSnap >> makePlan)
  check "dialog is floated" (M.member 4 (W.floating $ windowset dialogSt))
  check "dialog keeps observed geometry"
    (lookup 4 [(w,r) | Placement w r <- planFrames dialogPlan] == Just (Rectangle 120 80 320 180))
  check "dialog can hold focus" (W.peek (windowset dialogSt)==Just 4)
  check "standard window stays tiled" (M.notMember 1 (W.floating $ windowset dialogSt))
  (_,ignoredDialog) <- runX (XConf (cfg {manageHook=isDialog --> doIgnore})) initial (reconcile dialogSnap)
  check "doIgnore still wins for dialogs"
    (not (W.member 4 (windowset ignoredDialog)) && S.member 4 (ignoredWindows ignoredDialog)
     && W.member 1 (windowset ignoredDialog))
  check "JSON window subrole parse" (case eitherDecode
    "{\"type\":\"snapshot\",\"generation\":1,\"epoch\":1,\"screens\":[],\"windows\":[{\"wid\":1,\"pid\":1,\"app\":\"A\",\"bundle\":\"b\",\"titleText\":\"t\",\"onDisplay\":0,\"frame\":{\"x\":0,\"y\":0,\"width\":10,\"height\":10},\"minimized\":false,\"ownedHidden\":false,\"subrole\":\"AXDialog\"}],\"focused\":null}" :: Either String InputEvent of
      Right (SnapshotEvent s) -> fmap subroleText (listToMaybe (snapWindows s))==Just "AXDialog"
      _ -> False)
  check "JSON window subrole default" (case eitherDecode
    "{\"type\":\"snapshot\",\"generation\":1,\"epoch\":1,\"screens\":[],\"windows\":[{\"wid\":1,\"pid\":1,\"app\":\"A\",\"bundle\":\"b\",\"titleText\":\"t\",\"onDisplay\":0,\"frame\":{\"x\":0,\"y\":0,\"width\":10,\"height\":10},\"minimized\":false,\"ownedHidden\":false}],\"focused\":null}" :: Either String InputEvent of
      Right (SnapshotEvent s) -> fmap subroleText (listToMaybe (snapWindows s))==Just "AXStandardWindow"
      _ -> False)
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
