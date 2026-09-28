{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE OverloadedStrings #-}
module Main where
import XMonad
import qualified XMonad.StackSet as W
import XMonad.MacOS.Engine
import XMonad.MacOS.Protocol
import XMonad.Util.EZConfig (parseKey, parseKeySequence, mkKeymap, keymapProblems, additionalMouseBindings)
import XMonad.Actions.Submap (submap)
import XMonad.Layout.Grid
import XMonad.Layout.Simplest
import XMonad.Layout.ResizableTile
import XMonad.Layout.BinarySpacePartition
import XMonad.Actions.CycleWS
import XMonad.Actions.CycleRecentWS
import XMonad.Actions.DynamicWorkspaces
import XMonad.Actions.GroupNavigation
import XMonad.Layout.Mosaic
import XMonad.Layout.ResizableThreeCol
import CycleRecentWSTests (runCycleRecentWSTests)
import DynamicWorkspacesTests (runDynamicWorkspacesTests)
import GroupNavigationTests (runGroupNavigationTests)
import MosaicTests (runMosaicTests)
import ResizableThreeColTests (runResizableThreeColTests)
import XMonad.Actions.UpdatePointer (updatePointer)
import XMonad.Actions.Navigation2D
import XMonad.Util.Loggers
import XMonad.Util.WorkspaceCompare
import XMonad.Operations (windows)
import Data.Bits ((.|.))
import XMonad.Actions.WithAll
import XMonad.Actions.RotSlaves
import XMonad.Actions.SwapWorkspaces
import XMonad.Actions.DwmPromote
import XMonad.Layout.Renamed
import XMonad.Layout.Reflect
import qualified XMonad.Layout.MultiToggle as MT
import XMonad.Layout.TwoPane
import XMonad.Layout.Accordion
import XMonad.Hooks.ManageHelpers (isDialog)
import XMonad.Layout.Column
import XMonad.Layout.Spiral
import XMonad.Layout.OneBig
import XMonad.Layout.StackTile
import XMonad.Layout.Dishes
import XMonad.Layout.ToggleLayouts
import XMonad.Actions.CopyWindow (copy)
import XMonad.Actions.FocusNth (focusNth')
import XMonad.Layout.BoringWindows
  (boringAuto, boringWindows, clearBoring, focusUp, markBoring)
import qualified XMonad.Layout.BoringWindows as BW
import XMonad.Layout.Magnifier
  (magnifiercz, magnifiercz', MagnifyMsg(MagnifyMore, ToggleOff))
import XMonad.Layout.NoBorders
  (noBorders, smartBorders, withBorder, lessBorders, hasBorder
  ,Ambiguity(Screen, OnlyFloat, Combine), With(Difference), BorderMessage(ResetBorder))
import XMonad.Util.NamedScratchpad
  (NamedScratchpad(NS), customFloating, namedScratchpadAction
  ,namedScratchpadManageHook, nonFloating, scratchpadWorkspaceTag)
import XMonad.Hooks.StatusBar
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Data.List (isInfixOf,isPrefixOf,nub,sort,(\\))
import Data.Maybe (fromMaybe,listToMaybe,isJust)
import Data.Aeson
import qualified XMonad.Util.ExtensibleState as XS
import XMonad.Hooks.WorkspaceHistory
import qualified Data.Aeson.KeyMap as KM
import Control.Exception (finally)
import Control.Monad (forM_,unless)
import System.Directory
  ( copyFile, createDirectoryIfMissing, getPermissions, getTemporaryDirectory
  , removeFile, removePathForcibly, setOwnerExecutable, setPermissions )
import System.Environment (getEnv, lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode(..))
import System.FilePath (takeDirectory, (</>))
import System.IO (hClose, openTempFile)
import XMonad.MacOS.CLI (Paths(..), recompileInstalled)

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
newtype Counter = Counter Int deriving (Eq, Read, Show)
instance ExtensionClass Counter where
  initialValue = Counter 0
  extensionType = PersistentExtension
newtype Scratch = Scratch Int deriving (Eq, Show)
instance ExtensionClass Scratch where initialValue = Scratch 0
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
  -- BinarySpacePartition: new windows split the focused window in half and the
  -- leaves tile the frame. It is stateful, so it is driven through runLayout.
  let bsp = emptyBSP :: BinarySpacePartition Window
      bspStack = W.Stack (3::Window) [] [2,1]
      bspState = initial
        {windowset=W.insertUp 3 $ W.insertUp 2 $ W.insertUp 1 (windowset initial)}
  (bspPlan,_) <- runX conf bspState $
    runLayout (W.Workspace "1" bsp (Just bspStack)) frame3
  let bspRects = map snd (fst bspPlan)
  check "BSP places every window" (length bspRects==3)
  check "BSP tiles the frame without gaps"
    (sum [rect_width r*rect_height r | r<-bspRects]
     == rect_width frame3*rect_height frame3)
  check "BSP keeps every rectangle inside the frame"
    (all (\r -> rect_x r>=rect_x frame3 && rect_y r>=rect_y frame3
             && rect_x r+rect_width r<=rect_x frame3+rect_width frame3
             && rect_y r+rect_height r<=rect_y frame3+rect_height frame3) bspRects)
  check "BSP survives Show and Read"
    (maybe False (\b -> read (show b) == b) (snd bspPlan))
  -- A message rewrites the tree; run the layout again to see the geometry move.
  let bspAfter msg = do
        (r1,m1) <- runLayout (W.Workspace "1" bsp (Just bspStack)) frame3
        case m1 of
          Nothing -> pure (map snd r1, [])
          Just b -> do
            mb <- handleMessage b (SomeMessage msg)
            case mb of
              Nothing -> pure (map snd r1, [])
              Just b' -> do
                (r2,_) <- runLayout (W.Workspace "1" b' (Just bspStack)) frame3
                pure (map snd r1, map snd r2)
  (bsExpand,_) <- runX conf bspState (bspAfter (ExpandTowards R))
  check "BSP ExpandTowards widens the focused side, shrinking the other"
    (length (fst bsExpand) == 3 && length (snd bsExpand) == 3
     && rect_width (snd bsExpand !! 0) > rect_width (fst bsExpand !! 0)
     && rect_width (snd bsExpand !! 2) < rect_width (fst bsExpand !! 2))
  (bsRotate,_) <- runX conf bspState (bspAfter Rotate)
  check "BSP Rotate turns the focused split" (fst bsRotate /= snd bsRotate)
  (_,s1) <- runX conf initial (reconcile snapshot)
  check "initial display assignment" (W.findTag 3 (windowset s1)==Just "2")
  check "observed focus" (W.peek (windowset s1)==Just 1)
  (p1,s2) <- runX conf s1 makePlan
  -- StatusBar.PP renders from the window set and the snapshot's titles.
  (ppLine,_) <- runX conf s1 (dynamicLogString def)
  check "PP default line" (ppLine=="[1] <2> : Tall : 1")
  (ppXm,_) <- runX conf s1 $ dynamicLogString (filterOutWsPP ["2"] xmobarPP
    {ppOrder=take 1, ppHiddenNoWindows=id, ppWsSep=""})
  check "PP xmobar helpers and filter" (ppXm=="<fc=yellow>[1]</fc>34567890")
  check "PP helpers" (shorten 5 "abcdefgh"=="ab..." && wrap "<" ">" ""=="" &&
    xmobarStrip "<fc=red>a</fc>b"=="ab" && shellQuote "it's"=="'it'\\''s'")
  let menuCfg=withSB (macMenuBarPP (pure def {ppOrder=take 2})) cfg
  (menuPlan,_) <- runX (XConf menuCfg) s1 makePlan
  check "macMenuBarPP drives the plan status" (planStatus menuPlan==Just "[1] <2> : Tall")
  check "plan without a PP has no status" (planStatus p1==Nothing)
  sbTmp <- getTemporaryDirectory
  let sbFile=sbTmp </> "xmonad-pp-test.txt"
  sbc <- statusBarFile sbFile (pure def {ppOrder=take 1})
  _ <- runX (XConf (withSB sbc cfg)) s1 makePlan
  sbOut <- readStrict sbFile
  check "statusBarFile writes the rendered line" (sbOut=="[1] <2>\n")
  removeFile sbFile
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
  let toggled=MT.mkToggle (MT.single REFLECTX) (Tall 1 (3/100) (1/2))
      masterX l=do
        (res,_) <- runX conf initial $
          runLayout (W.Workspace "1" l (Just stack3)) frame3
        pure (maybe (-1) rect_x (lookup 1 (fst res)))
      flip' l=do
        (res,_) <- runX conf initial $
          handleMessage l (SomeMessage (MT.Toggle REFLECTX))
        pure (fromMaybe l res)
  on <- flip' toggled
  off <- flip' on
  xs <- mapM masterX [toggled,on,off]
  check "Toggle REFLECTX flips the layout and flips it back" (xs==[0,500,0])
  check "a toggled layout survives Show and Read"
    (description (read (show on) `asTypeOf` on)==description on)
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
  -- an ack or an observation of the requested window clears it, and a WM-hide
  -- animation cannot reverse a view.
  (focusPlan,pending) <- runX conf s2 (windows W.focusDown >> makePlan)
  let oldFocus=snapshot {snapGeneration=2}
      previous=W.peek (windowset s2)
      desired=W.peek (windowset pending)
      aid=maybe 0 fst (pendingFocus pending)
  check "plan carries a native action id"
    (isJust (planAction focusPlan) && planFocus focusPlan==desired && planFocusForMs focusPlan==400)
  (_,retried) <- runX conf pending (reconcile oldFocus)
  check "pending focus survives stale observation" (W.peek (windowset retried)==desired && focusRequested retried)
  (_,acked) <- runX conf retried (reconcile $ oldFocus {snapFocused=desired,snapGeneration=3})
  check "focus acknowledgement clears request" (not $ focusRequested acked)
  (_,expired) <- runX conf pending (handleEvent M.empty (AckEvent aid previous True))
  check "expired ack clears request" (not $ focusRequested expired)
  check "expired ack does not revert focus" (W.peek (windowset expired)==desired)
  (_,took) <- runX conf pending (handleEvent M.empty (AckEvent aid (Just 3) False))
  check "takeover ack follows a different shown window" (W.peek (windowset took)==Just 3 && not (focusRequested took))
  let ownedAnimation=snapshot {snapGeneration=4,snapFocused=Just 1
        ,snapWindows=[(wi 1 10){ownedHidden=True},(wi 2 10){ownedHidden=True},wi 3 20]}
  (_,noBounce) <- runX conf s3 (reconcile ownedAnimation)
  check "hide animation cannot change workspace" (W.currentTag (windowset noBounce)=="3")
  let lingering=snapshot {snapGeneration=5,snapFocused=Just 1
        ,snapWindows=[wi 1 10,wi 2 10,wi 3 20]}
  (_,noPull) <- runX conf s3 (reconcile lingering)
  check "visible window on a hidden workspace cannot change current tag"
    (W.currentTag (windowset noPull)=="3")
  -- A native Space epoch bump rebuilds window membership, but a layout the user
  -- chose per workspace is not part of that world and must survive.
  (_,chosen) <- runX conf s3 (setLayout (Layout Circle))
  check "epoch fixture: the current workspace holds the chosen layout"
    (W.currentTag (windowset chosen)=="3")
  let bumped=snapshot {snapGeneration=9,snapEpoch=2}
  (_,carried) <- runX conf chosen (reconcile bumped)
  check "an epoch bump keeps a workspace's layout"
    (lookup "3" [(W.tag w,description (W.layout w))
                | w <- W.workspaces (windowset carried)] == Just "Circle")
  let saved=checkpoint s3
  case restoreCheckpoint cfg 1 displays (windowInfo s3) saved of
    Left e -> ioError $ userError e
    Right restored -> do
      check "checkpoint membership" (sort (W.allWindows restored)==sort (W.allWindows $ windowset s3))
      check "checkpoint workspace" (W.currentTag restored==W.currentTag (windowset s3))
  case restoreCheckpoint cfg 99 displays (windowInfo s3) saved of
    Left _ -> pure ()
    Right _ -> ioError $ userError "FAIL: wrong epoch checkpoint accepted"
  (_,xs) <- runX conf s3 $ do
    XS.modify (\(Counter n) -> Counter (n+2))
    XS.put (Scratch 7)
  (sc,_) <- runX conf xs (XS.gets (\(Scratch n) -> n))
  check "extensible state get after put" (sc==7)
  (gone,_) <- runX conf xs (XS.remove (Scratch 0) >> XS.get)
  check "extensible state remove" (gone==Scratch 0)
  let restart=snapshot {snapRestore=Just (checkpoint xs)}
  (back,_) <- runX conf initial (reconcile restart >> ((,) <$> XS.get <*> XS.get))
  check "persistent extension survives restart" (back==(Counter 2,Scratch 0))
  let older=case checkpoint s3 of
        Object o -> Object (KM.delete "savedExtensions" o)
        v -> v
  check "checkpoint without extensions still loads"
    (either (const False) (const True) (restoreCheckpoint cfg 1 displays (windowInfo s3) older))
  (hist,_) <- runX conf s3 $ do
    workspaceHistoryHook
    windows (W.view "1") >> workspaceHistoryHook
    windows (W.view "3") >> workspaceHistoryHook
    (,) <$> workspaceHistory <*> workspaceHistoryByScreen
  check "workspace history is most recent first"
    (take 2 (fst hist)==["3","1"] && length (snd hist)==2)
  let unplugged=rescreen [displays !! 1] (windowset s2)
      plugged=rescreen (displays ++ [DisplayInfo 30 r]) unplugged
  check "hotplug loses no windows" (sort (W.allWindows plugged)==[1,2,3])
  check "hotplug screens unique" (length (nub $ map (W.tag . W.workspace) $ W.screens plugged)==3)
  check "retained display keeps its workspace" (W.tag (W.workspace $ W.current unplugged)=="2")
  let aff=[(displayID (W.screenDetail sc), W.tag (W.workspace sc)) | sc <- W.screens (windowset s2)]
      (unpluggedRemembered,aff1)=rescreenWith [displays !! 1] (windowset s2) aff
      (replugged,_)=rescreenWith displays unpluggedRemembered aff1
  check "replug restores the remembered workspace"
    (lookup 10 [(displayID (W.screenDetail sc), W.tag (W.workspace sc)) | sc <- W.screens replugged]
     == Just "1")
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
  check "EZConfig sequence" (parseKeySequence 68 "M-x  C-a <F1>"==Right [(68,120),(4,97),(0,0xffbe)])
  let mark n=modify (\st -> st {nextActionId=n})
      seqMap=mkKeymap cfg [("M-x a",mark 1),("M-x M-s b",mark 2),("M-j",mark 3)]
      press st m k g=snd <$> runX conf st (handleEvent seqMap (KeyEvent m k g))
      bare=initial {commands=[]}
  check "sequences share one prefix" (M.keys seqMap==[(8,106),(8,120)])
  check "prefix conflict reported"
    (not (null (keymapProblems cfg [("M-x",()),("M-x a",())])))
  check "duplicate binding reported" (keymapProblems cfg [("M-a",()),("M-A",())]==["duplicate binding \"M-A\""])
  armed <- press bare 8 120 False
  check "submap grabs the next stroke" (commands armed==[GrabKeyboard] && isJust (keyGrab armed))
  fired <- press armed 0 97 True
  check "grabbed stroke runs the submap action" (nextActionId fired==1 && not (isJust (keyGrab fired)))
  nested <- press armed 8 115 True >>= \st -> press st {commands=[]} 0 98 True
  check "nested submap grabs again" (nextActionId nested==2)
  aborted <- press armed 0 xK_Escape True >>= \st -> press st 0 97 True
  check "unbound stroke aborts the submap" (nextActionId aborted==0)
  lapsed <- press armed 8 106 False
  check "ungrabbed stroke drops a stale submap" (nextActionId lapsed==3 && not (isJust (keyGrab lapsed)))
  (_,once) <- runX conf bare (submap M.empty >> submap M.empty)
  check "one grab per stroke" (commands once==[GrabKeyboard])
  check "grab command protocol" (commandJSON GrabKeyboard == object ["type" .= ("command" :: String),"name" .= ("grab" :: String)])
  check "JSON key grabbed parse" (case eitherDecode "{\"type\":\"key\",\"mask\":0,\"sym\":97,\"grabbed\":true}" :: Either String InputEvent of
    Right (KeyEvent 0 97 True) -> True; _ -> False)
  check "recompile command protocol" (commandJSON Recompile == object ["type" .= ("command" :: String),"name" .= ("recompile" :: String)])
  check "bad protocol rejected" (case eitherDecode "{\"type\":\"wrong\"}" :: Either String InputEvent of Left _ -> True; _ -> False)
  check "JSON snapshot parse" (case eitherDecode
    "{\"type\":\"snapshot\",\"generation\":1,\"epoch\":1,\"screens\":[],\"windows\":[],\"focused\":null}" :: Either String InputEvent of
      Right (SnapshotEvent _) -> True; _ -> False)
  check "JSON ack parse" (case eitherDecode
    "{\"type\":\"ack\",\"action\":7,\"focused\":2,\"expired\":true}" :: Either String InputEvent of
      Right (AckEvent 7 (Just 2) True) -> True; _ -> False)
  check "additionalMouseBindings overrides"
    (M.lookup (mod1Mask,button1) (mouseBindings (additionalMouseBindings cfg [((mod1Mask,button1),MouseRaise)]) cfg)
     == Just MouseRaise)
  let colRect=Rectangle 0 0 100 900
      colStack=W.Stack (1::Int) [] [2,3]
  check "Column even split" (map snd (pureLayout (Column 1) colRect colStack)
    == [Rectangle 0 0 100 300, Rectangle 0 300 100 300, Rectangle 0 600 100 300])
  check "OneBig master occupies the fraction"
    (case pureLayout (OneBig 0.75 0.75) (Rectangle 0 0 1000 800) (W.Stack (1::Int) [] [2,3,4]) of
       (_,Rectangle 0 0 750 600):_ -> True; _ -> False)
  check "StackTile masters sit on top"
    (length (pureLayout (StackTile 1 (3/100) (1/2)) (Rectangle 0 0 1000 800) (W.Stack (1::Int) [] [2,3]))==3)
  check "Dishes stacks extras below"
    (length (pureLayout (Dishes 1 (1/6)) (Rectangle 0 0 1000 800) (W.Stack (1::Int) [] [2,3]))==3)
  check "spiral produces one rectangle per window"
    (length (pureLayout (spiral (6/7)) (Rectangle 0 0 1000 800) (W.Stack (1::Int) [] [2,3,4]))==4)
  check "ToggleLayouts starts on the second layout"
    (description (toggleLayouts Full (Tall 1 (3/100) (1/2) :: Tall Int))=="Tall")
  let copied=copy "2" (W.insertUp (1::Int) (W.new () ["1","2"] [()]))
  check "copyWindow tags a window onto another workspace"
    (W.member 1 (W.view "2" copied) && W.member 1 copied)
  check "focusNth' selects by index"
    (focusNth' 0 (W.Stack (2::Int) [1] [3])==W.Stack 1 [] [2,3])
  -- Magnifier scales the focused window about its centre, clips it to the
  -- frame, and lists it last, which is the top of the stack here.
  let magStack = W.Stack (1::Window) [] [2,3]
      tallW = Tall 1 (3/100) (1/2) :: Tall Window
      magLayout = magnifiercz 1.2 tallW
  check "magnifier names itself" (description magLayout=="Magnifier Tall")
  ((magRects,_),_) <- runX conf s1 $
    runLayout (W.Workspace "1" magLayout (Just magStack)) frame3
  check "magnifier grows the focused window" (lookup 1 magRects==Just (Rectangle 0 24 600 800))
  check "magnifier leaves the others to the layout"
    (lookup 2 magRects==lookup 2 (pureLayout tallW frame3 magStack)
     && lookup 3 magRects==lookup 3 (pureLayout tallW frame3 magStack))
  check "the magnified window is listed last" (fst (last magRects)==1)
  (magMore,_) <- runX conf s1 (handleMessage magLayout (SomeMessage MagnifyMore))
  ((magBigger,_),_) <- runX conf s1 $
    runLayout (W.Workspace "1" (fromMaybe magLayout magMore) (Just magStack)) frame3
  check "MagnifyMore zooms it further"
    (fmap rect_width (lookup 1 magBigger)==Just 650)
  (magOff,_) <- runX conf s1 (handleMessage magLayout (SomeMessage ToggleOff))
  check "ToggleOff turns the magnifier off"
    (fmap description magOff==Just "Magnifier (off) Tall")
  ((magOffRects,_),_) <- runX conf s1 $
    runLayout (W.Workspace "1" (fromMaybe magLayout magOff) (Just magStack)) frame3
  check "a magnifier that is off changes nothing"
    (magOffRects==pureLayout tallW frame3 magStack)
  ((magNoMaster,_),_) <- runX conf s1 $
    runLayout (W.Workspace "1" (magnifiercz' 1.2 tallW) (Just magStack)) frame3
  check "magnifier' leaves a focused master alone"
    (magNoMaster==pureLayout tallW frame3 magStack)
  -- BoringWindows: navigation skips what the user marked boring, and what
  -- the layout is not showing at all.
  let bLayout = Layout (boringWindows tallW)
      bStack = W.Stack (1::Window) [] [2,3]
      bState = s1 {windowset=W.modify' (const bStack)
                     (W.mapWorkspace (\w -> w {W.layout=bLayout}) (windowset s1))}
  (_,boringSkipped) <- runX conf bState $
    sendMessage (BW.Replace "test" [3]) >> focusUp
  check "focusUp skips a window marked boring"
    (W.peek (windowset boringSkipped)==Just 2)
  -- clearBoring clears the windows the user marked, so the walk comes back to
  -- the one it skipped before.
  (_,boringCleared) <- runX conf bState $
    markBoring >> clearBoring >> focusUp >> focusUp >> focusUp
  check "clearBoring stops the skipping" (W.peek (windowset boringCleared)==Just 1)
  (_,boringMarked) <- runX conf bState $
    markBoring >> focusUp >> focusUp >> focusUp
  check "a boring window does not take focus"
    (W.peek (windowset boringMarked)/=Just 1)
  ((bAutoRects,bAuto),_) <- runX conf bState $
    runLayout (W.Workspace "1" (boringAuto (TwoPane (3/100) (1/2))) (Just bStack)) frame3
  let unarranged = W.integrate bStack \\ map fst bAutoRects
  (_,boringAutoSkipped) <- runX conf bState $ handleMessage
    (fromMaybe (boringAuto (TwoPane (3/100) (1/2))) bAuto) (SomeMessage BW.FocusUp)
  check "boringAuto marks the window the layout hides boring"
    (unarranged==[3] && W.peek (windowset boringAutoSkipped)==Just 2)
  -- NamedScratchpad: the manage hook places the window, the action toggles it
  -- between this workspace and a hidden NSP workspace created on demand.
  let pads=[NS "term" "true" (title =? "1")
               (customFloating (W.RationalRect 0 0 (1/2) 1))]
  (_,padded) <- runX (XConf (cfg {manageHook=namedScratchpadManageHook pads})) initial
    (reconcile snapshot)
  check "the scratchpad manage hook floats its window"
    (M.lookup 1 (W.floating (windowset padded))==Just (W.RationalRect 0 0 (1/2) 1))
  check "the scratchpad manage hook leaves the rest tiled"
    (M.notMember 2 (W.floating (windowset padded)))
  (_,padHidden) <- runX conf padded (namedScratchpadAction pads "term")
  check "the scratchpad action hides it on the NSP workspace"
    (W.findTag 1 (windowset padHidden)==Just scratchpadWorkspaceTag)
  check "the NSP workspace is created on demand"
    (W.tagMember scratchpadWorkspaceTag (windowset padHidden))
  check "a hidden scratchpad does not keep focus"
    (W.peek (windowset padHidden)/=Just 1)
  check "the status summary reports the NSP workspace"
    (any ((==scratchpadWorkspaceTag) . wsTag) (workspaceSummary cfg (windowset padHidden)))
  (_,padShown) <- runX conf padHidden (namedScratchpadAction pads "term")
  check "the same action brings it back to this workspace"
    (W.findTag 1 (windowset padShown)==Just "1")
  check "the summoned scratchpad takes focus" (W.peek (windowset padShown)==Just 1)
  (_,padNone) <- runX conf padded $
    namedScratchpadAction [NS "none" "true" (title =? "nothing") nonFloating] "none"
  check "an absent scratchpad only spawns"
    (W.allWindows (windowset padNone)==W.allWindows (windowset padded)
     && W.currentTag (windowset padNone)==W.currentTag (windowset padded))
  -- NoBorders: a layout decides per-window border widths, and the plan the
  -- helper receives carries them to the overlay it draws.
  let base1 = initialState cfg [head displays]
      ws3 = W.focusWindow 1 (foldl (flip W.insertUp) (windowset base1) [1,2,3])
      borderState l ws = base1 {windowset=W.mapWorkspace (\w -> w {W.layout=Layout l}) ws}
      widthOf w p = lookup w [(borderWindow b,borderPixels b) | b <- planBorders p]
  (planSolo,_) <- runX conf (borderState (smartBorders tallW)
                               (W.modify' (const (W.Stack 1 [] [])) ws3)) makePlan
  check "smartBorders drops a lone window's border"
    (planBorders planSolo==[BorderWidth 1 0])
  (planThree,_) <- runX conf (borderState (smartBorders tallW) ws3) makePlan
  check "smartBorders keeps borders when windows share the screen"
    (null (planBorders planThree))
  (planNone,_) <- runX conf (borderState (noBorders tallW) ws3) makePlan
  check "noBorders drops every border"
    (length (planBorders planNone)==3 && all ((==0) . borderPixels) (planBorders planNone))
  (planWide,_) <- runX conf (borderState (withBorder 3 tallW) ws3) makePlan
  check "withBorder asks for its own width"
    (length (planBorders planWide)==3 && all ((==3) . borderPixels) (planBorders planWide))
  -- hasBorder marks one window wherever it is shown, ResetBorder forgets it.
  (planAsked,_) <- runX conf (borderState (smartBorders tallW) ws3) $ do
    runQuery (hasBorder False) 1
    makePlan
  check "hasBorder hides one window's border" (widthOf 1 planAsked==Just 0)
  check "hasBorder leaves the other borders alone" (widthOf 2 planAsked==Nothing)
  (planReset,_) <- runX conf (borderState (smartBorders tallW) ws3) $ do
    runQuery (hasBorder False) 1
    broadcastMessage (ResetBorder 1)
    makePlan
  check "ResetBorder forgets the request" (null (planBorders planReset))
  -- Floats: a full-screen float is ambiguous, and a combined rule can subtract.
  let fullFloat st = st {windowset=W.float 2 (W.RationalRect 0 0 1 1) (windowset st)}
  (planFloat,_) <- runX conf (fullFloat (borderState (lessBorders OnlyFloat tallW) ws3)) makePlan
  check "OnlyFloat hides a floating window's border" (widthOf 2 planFloat==Just 0)
  (planDiff,_) <- runX conf
    (fullFloat (borderState (lessBorders (Combine Difference OnlyFloat Screen) tallW) ws3)) makePlan
  check "Combine Difference subtracts the second rule" (widthOf 2 planDiff==Nothing)
  testDirectionalNavigation
  testNavigation2DBindings
  testLoggers
  testWorkspacePredicates
  testAtomicRecompile
  runGroupNavigationTests
  runDynamicWorkspacesTests
  runCycleRecentWSTests
  runMosaicTests
  runResizableThreeColTests
  testUpdatePointer
  putStrLn "PASS: StackSet invariants, layouts, lifecycle, workspaces, hotplug, checkpoints, extensible state, magnifier, boring windows, scratchpads, no borders, key parser, protocol, directional navigation, loggers, workspace predicates and atomic recompile"

-- Three tiles side by side on the first display, as Tall with three would
-- place them. Navigation reads these from the helper's observation, so the
-- layout is never consulted.
navTiles :: XState
navTiles = base {windowInfo = info, windowset = tiled}
  where
    base = initialState cfg [head displays]
    info = M.fromList
      [ (w, (wi w 10) {frame = r})
      | (w,r) <- [ (1, Rectangle 0 24 320 800)
                 , (2, Rectangle 340 24 320 800)
                 , (3, Rectangle 680 24 320 800) ] ]
    tiled = W.focusWindow 1 (foldl (flip W.insertUp) (windowset base) [1,2,3])

-- The same, with the last window floating over the bottom left, so the two
-- layers can be told apart and "nearest" has one answer.
navFloating :: XState
navFloating = navTiles
  { windowset = W.float 3 (W.RationalRect 0 (3/4) (1/3) (1/4)) (windowset navTiles)
  , windowInfo = M.adjust (\i -> i {frame = Rectangle 0 600 320 200}) 3
                         (windowInfo navTiles) }

tiledOrder :: XState -> [Window]
tiledOrder = W.integrate' . W.stack . W.workspace . W.current . windowset

focusedWindow :: XState -> Maybe Window
focusedWindow = W.peek . windowset

testDirectionalNavigation :: IO ()
testDirectionalNavigation = do
  (_,twoScreens) <- runX conf initial (reconcile snapshot)
  (_,far) <- runX conf navTiles (windowGo R False >> windowGo R False)
  check "windowGo walks to the far tile" (focusedWindow far==Just 3)
  (_,stopped) <- runX conf navTiles (windowGo L False)
  check "windowGo stops at the edge unless wrapping" (focusedWindow stopped==Just 1)
  (_,wrapped) <- runX conf navTiles (windowGo L True)
  check "windowGo wraps when asked" (focusedWindow wrapped==Just 3)
  (_,vertical) <- runX conf navTiles (windowGo U False)
  check "windowGo U finds nothing above a full-height row" (focusedWindow vertical==Just 1)
  -- Swap: 1 and 2 trade places, and nothing else moves.
  (_,moved) <- runX conf navTiles (windowGo R False)
  check "windowGo R focuses the tile to the right" (focusedWindow moved==Just 2)
  (_,swapped) <- runX conf moved (windowSwap L False)
  let exchange w | w == 1 = 2
                 | w == 2 = 1
                 | otherwise = w
  check "windowSwap exchanges the two windows and leaves the rest alone"
    (tiledOrder swapped==map exchange (tiledOrder moved))
  check "windowSwap keeps focus on the window that moved" (focusedWindow swapped==Just 2)
  -- The float layer is navigated separately, and switchLayer crosses over.
  (_,crossed) <- runX conf navFloating switchLayer
  check "switchLayer crosses to the float layer" (focusedWindow crossed==Just 3)
  (_,back) <- runX conf navFloating (switchLayer >> switchLayer)
  check "switchLayer returns to the nearest window on the tiled layer"
    (focusedWindow back==Just 1)
  (_,noFloat) <- runX conf navTiles switchLayer
  check "switchLayer does nothing when nothing is floating" (focusedWindow noFloat==Just 1)
  -- Screens: display 20 sits to the left of display 10.
  (_,screen) <- runX conf initial (screenGo L False)
  check "screenGo L shows the workspace on the display to the left"
    (W.currentTag (windowset screen)=="2")
  (_,nothing) <- runX conf initial (screenGo R False)
  check "screenGo R finds no display to the right" (W.currentTag (windowset nothing)=="1")
  (_,sent) <- runX conf twoScreens (windowToScreen L False)
  check "windowToScreen moves the window to that display"
    (W.findTag 1 (windowset sent)==Just "2")
  -- A window the helper stopped reporting is off the navigation graph.
  let gone = navTiles {windowInfo = M.delete 3 (windowInfo navTiles)}
  (_,unreported) <- runX conf gone (windowGo R False >> windowGo R False)
  check "a window the helper stopped reporting drops off the navigation graph"
    (focusedWindow unreported==Just 2)

testLoggers :: IO ()
testLoggers = do
  (name,_) <- runX conf navTiles logCurrent
  check "logCurrent is the workspace tag" (name==Just "1")
  (title,_) <- runX conf navTiles logTitle
  check "logTitle is the observed window title" (title==Just "1")
  (layoutName,_) <- runX conf navTiles logLayout
  check "logLayout describes the current layout" (layoutName==Just "Tall")
  (classname,_) <- runX conf navTiles logClassname
  check "logClassname is the application" (classname==Just "Terminal")
  -- Stack order runs from the master, so the focused window is last here.
  (titles,_) <- runX conf navTiles (logTitles (\s -> "[" ++ s ++ "]") id)
  check "logTitles marks the focused window" (titles==Just "3 2 [1]")
  (classes,_) <- runX conf navTiles (logClassnames id id)
  check "logClassnames lists every window" (classes==Just "Terminal Terminal Terminal")
  (absent,_) <- runX conf navTiles (logConst "x" .| logConst "y")
  check "logConst ignores the fallback" (absent==Just "x")
  (fallback,_) <- runX conf initial (logDefault logTitle (logConst "none"))
  check "logDefault falls back when a logger has nothing" (fallback==Just "none")
  (spaced,_) <- runX conf navTiles (logSp 3)
  check "logSp makes a spacer" (spaced==Just "   ")
  (wrapped,_) <- runX conf navTiles (wrapL "<" ">" logCurrent)
  check "wrapL delimits a logger" (wrapped==Just "<1>")
  (cut,_) <- runX conf navTiles (shortenL 1 (logConst "abcdef"))
  check "shortenL truncates with an ellipsis" (cut==Just "...")
  (wide,_) <- runX conf navTiles (fixedWidthL AlignLeft "." 5 (logConst "ab"))
  check "fixedWidthL pads to a fixed width" (wide==Just "ab...")
  (centred,_) <- runX conf navTiles (fixedWidthL AlignCenter "." 6 (logConst "ab"))
  check "fixedWidthL centres" (centred==Just "..ab..")
  (rightAligned,_) <- runX conf navTiles (fixedWidthL AlignRight "." 5 (logConst "ab"))
  check "fixedWidthL right-aligns" (rightAligned==Just "...ab")
  (missingScreen,_) <- runX conf navTiles (logCurrentOnScreen 99)
  check "a logger for a display that is not attached says nothing" (missingScreen==Nothing)
  (onScreen,_) <- runX conf navTiles (logCurrentOnScreen 0)
  check "logCurrentOnScreen reads that display" (onScreen==Just "1")
  (active,_) <- runX conf navTiles (logWhenActive 0 (logConst "*"))
  check "logWhenActive shows only on its own display" (active==Just "*")
  (inactive,_) <- runX conf navTiles (logWhenActive 1 (logConst "*"))
  check "logWhenActive hides on another display" (inactive==Nothing)
  (command,_) <- runX conf navTiles (logCmd "echo hello")
  check "logCmd reads the first line of a command" (command==Just "hello")
  (failed,_) <- runX conf navTiles (logCmd "exit 1")
  check "a command that prints nothing is not an error" (failed==Nothing)

testWorkspacePredicates :: IO ()
testWorkspacePredicates = do
  (_,twoScreens) <- runX conf initial (reconcile snapshot)
  -- Windows 1 and 2 on "1"; the focused one is sent to the hidden "5", so the
  -- predicates have workspaces that agree and disagree about.
  (_,spread) <- runX conf navTiles (windows (W.shift "5"))
  check "the window left the visible workspace"
    (W.findTag 1 (windowset spread)==Just "5")
  -- s1 shows "1" and "2", so the next hidden workspace after "1" is "3".
  (_,hidden) <- runX conf twoScreens (moveTo Next hiddenWS)
  check "moveTo hiddenWS lands on a workspace that is not shown"
    (W.currentTag (windowset hidden)=="3")
  (_,empty) <- runX conf spread (moveTo Next emptyWS)
  check "moveTo emptyWS lands on a workspace with no windows"
    (W.currentTag (windowset empty)=="2")
  (_,nonEmpty) <- runX conf spread (moveTo Next (Not emptyWS))
  check "Not inverts a predicate" (W.currentTag (windowset nonEmpty)=="5")
  (union,_) <- runX conf spread
    (findWorkspace getSortByIndex Next (onlyTag "4" :|: onlyTag "7") 2)
  check "the :|: combinator accepts either predicate" (union=="7")
  (intersect,_) <- runX conf spread
    (findWorkspace getSortByIndex Next (onlyTag "5" :&: hiddenWS) 1)
  check "the :&: combinator requires both" (intersect=="5")
  (neither,_) <- runX conf spread
    (findWorkspace getSortByIndex Next (onlyTag "5" :&: emptyWS) 1)
  check "a WSType no workspace satisfies stays put" (neither=="1")
  (_,skipped) <- runX conf spread (moveTo Next (ignoringWSs ["2","3","4"]))
  check "ignoringWSs steps over every tag it names"
    (W.currentTag (windowset skipped)=="5")
  -- A group is everything up to the first separator.
  let grouped = cfg {workspaces = ["web-1","web-2","mail-1"]}
      groupedState = initialState grouped [head displays]
  (_,group) <- runX (XConf grouped) groupedState (moveTo Next (wsTagGroup '-'))
  check "wsTagGroup stays inside the group" (W.currentTag (windowset group)=="web-2")
  -- The sort given to doTo decides the order, not the config.
  (_,byTag) <- runX conf twoScreens
    (doTo Next anyWS (mkWsSort (pure (flip compare))) (windows . W.view))
  check "doTo cycles in the order its sort gives" (W.currentTag (windowset byTag)=="0")
  (places,_) <- runX conf twoScreens (findWorkspace getSortByIndex Next anyWS 2)
  check "findWorkspace counts places, not steps" (places=="3")
  (_,viewed) <- runX conf twoScreens (toggleOrView "5")
  check "toggleOrView views a workspace that is not current"
    (W.currentTag (windowset viewed)=="5")
  (_,toggled) <- runX conf twoScreens (toggleOrView "1")
  check "toggleOrView leaves the workspace showing on the other display"
    (W.currentTag (windowset toggled) `notElem` ["1","2"])
  let shown = map W.tag (W.hidden (windowset twoScreens))
      configOrder = workspaces cfg
  check "skipTags drops the named tags"
    (map W.tag (skipTags (W.hidden (windowset twoScreens)) ["3","4"])
      ==filter (`notElem` ["3","4"]) shown)
  (sortByIndex,_) <- runX conf twoScreens getSortByIndex
  check "getSortByIndex keeps the config order"
    (map W.tag (sortByIndex (W.hidden (windowset twoScreens)))
      ==drop 2 configOrder)
  (xinerama,_) <- runX conf twoScreens getSortByXineramaRule
  check "the xinerama rule puts the shown workspaces first, in display order"
    (map W.tag (xinerama (W.workspaces (windowset twoScreens)))
      ==["2","1","0","3","4","5","6","7","8","9"])
  check "filterOutWs drops the named tags"
    (map W.tag (filterOutWs ["3"] (W.hidden (windowset twoScreens)))
      ==filter (/= "3") shown)
  (compareByIndex,_) <- runX conf twoScreens getWsCompare
  check "getWsCompare puts a tag the config does not name last"
    (compareByIndex "1" "_screen_1"==LT && compareByIndex "_screen_1" "1"==GT)

testNavigation2DBindings :: IO ()
testNavigation2DBindings = do
  let custom = def {defaultTiledNavigation = centerNavigation}
      paired = navigation2DP custom ("k","h","j","l")
                 [("M-", windowGo), ("M-S-", windowSwap)] True cfg
      bound = M.keys (keys paired paired)
      directions = [xK_k, xK_h, xK_j, xK_l]
  check "additionalNav2DKeysP binds all four directions for each modifier"
    (all (`elem` bound) ([(mod1Mask,d) | d <- directions]
                       ++ [(mod1Mask .|. shiftMask, d) | d <- directions]))
  (stored,_) <- runX conf navTiles
    (startupHook (withNavigation2DConfig custom cfg) >> XS.gets defaultTiledNavigation)
  check "withNavigation2DConfig stores the strategy the actions read"
    (stored==centerNavigation)
  (_,moved) <- runX conf navTiles (windowGo R True)
  check "the default configuration navigates without being stored first"
    (focusedWindow moved==Just 2)

-- UpdatePointer: the pointer follows the focused window through a
-- MovePointer command, and is not re-issued while the focus is unchanged.
testUpdatePointer :: IO ()
testUpdatePointer = do
  let info = M.fromList [(1, (wi 1 10) {frame = Rectangle 100 100 200 200})]
      st = initial {windowInfo = info, windowset = W.insertUp 1 (windowset initial)}
  (_, after) <- runX conf st (updatePointer (0.5, 0.5) (0, 0))
  check "updatePointer moves the pointer to the focused window's centre"
    (case commands after of
       [MovePointer (Rectangle x y w h) rect'] ->
         (x, y, w, h) == (200, 200, 1, 1) && rect' == Rectangle 100 100 200 200
       _ -> False)
  (_, again) <- runX conf (after {commands=[]}) (updatePointer (0.5, 0.5) (0, 0))
  check "updatePointer does not move again while the focus is unchanged"
    (null (commands again))
  (_, corner) <- runX conf st (updatePointer (0, 0) (0, 0))
  check "updatePointer honours the reference point"
    (case commands corner of
       [MovePointer (Rectangle x y _ _) _] -> (x, y) == (100, 100)
       _ -> False)

-- A predicate that accepts exactly one tag.
onlyTag :: WorkspaceId -> WSType
onlyTag t = WSIs (pure (\w -> W.tag w == t))

testAtomicRecompile :: IO ()
testAtomicRecompile = do
  tmpRoot <- getTemporaryDirectory
  (marker, h) <- openTempFile tmpRoot "xmonad-recompile"
  hClose h
  removeFile marker
  let tmp = marker ++ ".d"
  createDirectoryIfMissing True tmp
  testAtomicRecompileAt tmp `finally` removePathForcibly tmp

testAtomicRecompileAt :: FilePath -> IO ()
testAtomicRecompileAt tmp = do
  path0 <- getEnv "PATH"
  fail0 <- lookupEnv "FAIL_BUILD"
  let bin = tmp </> "bin"
      kit = tmp </> "support" </> "build-kit"
      helperBin = tmp </> "XMonadMac.app" </> "Contents" </> "MacOS" </> "XMonadMac"
      engine = tmp </> "fake-engine"
      dest = tmp </> "support" </> "xmonad-engine"
      configHs = tmp </> "xmonad.hs"
      p = Paths (tmp </> "support") (tmp </> "XMonadMac.app") helperBin (tmp </> "bridge.log")
      restore = do
        setEnv "PATH" path0
        maybe (unsetEnv "FAIL_BUILD") (setEnv "FAIL_BUILD") fail0
      exec path contents = do
        writeFile path contents
        perm <- getPermissions path
        setPermissions path (setOwnerExecutable True perm)
  (do
    createDirectoryIfMissing True bin
    createDirectoryIfMissing True (kit </> "src")
    createDirectoryIfMissing True (takeDirectory helperBin)
    writeFile (kit </> "xmonad-macos.cabal") "name: xmonad-macos\n"
    writeFile configHs "main = putStrLn \"config\"\n"
    writeFile dest "old\n"
    exec engine $ unlines
      ["#!/bin/bash"
      ,"if [ \"${1:-}\" = --check-config ]; then echo '{\"type\":\"configure\",\"protocol\":1,\"keys\":[]}'; else exit 0; fi"]
    exec (bin </> "ghc") "#!/bin/bash\nexit 0\n"
    exec (bin </> "cabal") $ unlines
      ["#!/bin/bash"
      ,"if [ \"${1:-}\" = build ]; then [ \"${FAIL_BUILD:-0}\" = 0 ] || exit 33; exit 0; fi"
      ,"if [ \"${1:-}\" = list-bin ]; then printf '%s\\n' '" ++ engine ++ "'; exit 0; fi"
      ,"exit 2"]
    exec helperBin $ unlines
      ["#!/bin/bash"
      ,"[ \"${1:-}\" = --validate-config ] || exit 7"
      ,"exit 0"]
    setEnv "PATH" (bin ++ ":" ++ path0)
    unsetEnv "FAIL_BUILD"
    ok <- recompileInstalled p configHs
    check "installed recompile succeeds" (ok == ExitSuccess)
    compiled <- readStrict dest
    handshake <- readStrict (tmp </> "support" </> "configure.json")
    check "recompile installs the built engine" ("#!/bin/bash" `isPrefixOf` compiled)
    check "recompile writes a validated handshake" ("\"protocol\":1" `isInfixOf` handshake)
    copyFile dest (tmp </> "before-fail")
    setEnv "FAIL_BUILD" "1"
    failed <- recompileInstalled p configHs
    check "failed cabal build is not success" (failed == ExitFailure 33)
    after <- readStrict dest
    before <- readStrict (tmp </> "before-fail")
    check "failed recompile leaves the previous engine" (after == before)
    ) `finally` restore

readStrict :: FilePath -> IO String
readStrict path = do
  contents <- readFile path
  length contents `seq` pure contents
