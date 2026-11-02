module MosaicTests (runMosaicTests) where
import XMonad
import XMonad.Layout.Mosaic
import XMonad.Layout.Spacing (spacing, inset)
import XMonad.Layout.NoBorders (smartBorders)
import XMonad.Layout.MultiToggle (mkToggle, single, Toggle(..))
import XMonad.Layout.Reflect (REFLECTX(..))
import XMonad.MacOS.Engine (initialState, checkpoint, restoreCheckpoint, reconcile)
import XMonad.MacOS.Protocol (Snapshot(..))
import qualified XMonad.StackSet as W
import qualified Data.Map.Strict as M
import Control.Monad (unless, forM_)
import Data.Maybe (fromMaybe, isNothing)
import Text.Read (readMaybe)

check :: String -> Bool -> IO ()
check name ok = unless ok $ ioError $ userError $ "FAIL: " ++ name

rectArea :: Rectangle -> Int
rectArea (Rectangle _ _ w h) = w*h

-- Is the first rectangle wholly within the second?
inside :: Rectangle -> Rectangle -> Bool
inside (Rectangle x y w h) (Rectangle px py pw ph) =
  px >= x && py >= y && px+pw <= x+w && py+ph <= y+h

-- Doubling the first (master) relative size, as `changeMaster (*2)` would.
doubleMaster :: [Rational] -> [Rational]
doubleMaster (x:xs) = 2*x : xs
doubleMaster [] = []

corrected :: Mosaic Window
corrected = mosaic (103/100) [1,1,1]

cfg :: XConfig Layout
cfg = def {layoutHook = Layout corrected, workspaces = ["1", "2"]}

conf :: XConf
conf = XConf cfg

installed :: Rectangle -> Layout Window -> Window -> XState
installed r l focused = base {windowset = W.focusWindow focused $
  foldr W.insertUp (windowset base) [1,2,3]}
  where base = initialState (cfg {layoutHook = l}) [DisplayInfo 10 r]

currentLayout :: XState -> Layout Window
currentLayout = W.layout . W.workspace . W.current . windowset

-- runLayout must install its state before resize messages: Mosaic's nested
-- SlopeMod message needs the aspect bookkeeping established by doLayout.
draw :: Rectangle -> X [(Window, Rectangle)]
draw r = do
  ws <- gets (W.workspace . W.current . windowset)
  (rs, changed) <- runLayout ws r
  maybe (pure ()) setLayout changed
  pure rs

readMosaic :: XState -> IO (Mosaic Window)
readMosaic s = maybe (ioError $ userError "FAIL: installed Mosaic did not parse")
  pure (readMaybe $ show $ currentLayout s)

weights :: XState -> IO (Rational, [Rational])
weights s = do
  Mosaic _ factor shares <- readMosaic s
  pure (factor, shares)

areaOf :: Window -> [(Window, Rectangle)] -> Int
areaOf w = maybe 0 rectArea . lookup w

runResizeTests :: IO ()
runResizeTests = do
  forM_ [Rectangle 0 24 1000 800, Rectangle (-1512) (-982) 1512 982,
         Rectangle (-3000) 0 3000 2000] $ \r ->
    forM_ [1,2,3] $ \focused -> do
      (before, ready) <- runX conf (installed r (Layout corrected) focused) (draw r)
      (after, expanded) <- runX conf ready (sendMessage Expand >> draw r)
      (twice, expandedTwice) <- runX conf expanded (sendMessage Expand >> draw r)
      (back, restored) <- runX conf expanded (sendMessage Shrink >> draw r)
      (factor, shares) <- weights expanded
      (_, twiceShares) <- weights expandedTwice
      (restoredFactor, restoredShares) <- weights restored
      let expected = [if w == focused then 103/100 else 1 | w <- [1,2,3]]
          expectedTwice = [if w == focused then (103/100)^ (2 :: Int) else 1 | w <- [1,2,3]]
          beforeArea = areaOf focused before
          afterArea = areaOf focused after
          -- A 3% weight increase yields ~1.98% more area for three equal
          -- windows, not an additive 3 percentage-point share increase.
          expectedArea = fromIntegral (rectArea r) * (103/303) :: Rational
          pixelTolerance = fromIntegral (3 * (rect_width r + rect_height r))
      check "Expand dispatches nested SlopeMod to the installed focused weight"
        (factor == 103/100 && shares == expected)
      check "repeated Expand compounds only the selected weight"
        (twiceShares == expectedTwice && areaOf focused twice > afterArea)
      check "Expand grows the focused area gently after normalization"
        (afterArea > beforeArea && afterArea * 100 < beforeArea * 104 &&
         abs (fromIntegral afterArea - expectedArea) <= pixelTolerance)
      check "unfocused weights stay fixed while their normalized areas decrease"
        (all (\w -> w == focused || areaOf w after < areaOf w before) [1,2,3])
      check "Expand still tiles signed-origin frames without gaps"
        (all (inside r . snd) after && sum (map (rectArea . snd) after) == rectArea r)
      check "Shrink reciprocally restores exact weights and rectangles"
        (restoredFactor == 103/100 && restoredShares == [1,1,1] && back == before)
      (_, shrunk) <- runX conf ready (sendMessage Shrink >> draw r)
      (_, shrinkShares) <- weights shrunk
      check "standalone Shrink divides only the focused weight"
        (shrinkShares == [if w == focused then 100/103 else 1 | w <- [1,2,3]])

  -- The shipped spacing wrapper must retain the nested side effect even
  -- though Mosaic.handleMessage Expand itself returns Nothing.
  let r = Rectangle (-1512) (-982) 1512 982
  (plainBefore, plainReady) <- runX conf (installed r (Layout corrected) 2) (draw r)
  (plainAfter, _) <- runX conf plainReady (sendMessage Expand >> draw r)
  (spacedBefore, spacedReady) <- runX conf
    (installed r (Layout $ spacing 5 corrected) 2) (draw r)
  (spacedAfter, spacedExpanded) <- runX conf spacedReady (sendMessage Expand >> draw r)
  (spacedBack, _) <- runX conf spacedExpanded (sendMessage Shrink >> draw r)
  check "spacing preserves recursive focused resize and negative origins"
    (spacedBefore == map (fmap $ inset 5) plainBefore &&
     spacedAfter == map (fmap $ inset 5) plainAfter && spacedBack == spacedBefore)

  -- Recompiling is not permission to discard an old persisted layout. Show
  -- that the old factor keeps its upstream semantics until the user invokes
  -- the ordinary M-S-Space layout reset (not Mosaic's Aspect.Reset).
  let old = mosaic (3/100) [1,1,1] :: Mosaic Window
  (_, oldReady) <- runX conf (installed r (Layout old) 1) (draw r)
  (_, oldExpanded) <- runX conf oldReady (sendMessage Expand >> draw r)
  (_, oldTwice) <- runX conf oldExpanded (sendMessage Expand >> draw r)
  oldSettings <- weights oldTwice
  check "old persisted factor is preserved, including two pathological expands"
    (oldSettings == (3/100, [9/10000,1,1]))
  let serializedOld = show $ currentLayout oldTwice
      saved = checkpoint oldTwice
      live = M.fromList [(w, WindowInfo w 123 "Test" "test" "" 10 r
                               False False "AXStandardWindow" False) | w <- [1,2,3]]
  restoredWS <- either (ioError . userError) pure $
    restoreCheckpoint cfg (epoch oldTwice) [DisplayInfo 10 r] live saved
  let loaded = oldTwice {windowset = restoredWS}
  check "checkpoint restore keeps the old factor despite the corrected config"
    (show (currentLayout loaded) == serializedOld &&
      W.allWindows restoredWS == W.allWindows (windowset oldTwice))
  (_, refactored) <- runX conf loaded $
    broadcastMessage (SetMosaicResizeFactor (103/100))
  correctedSettings <- weights refactored
  check "factor override repairs a restored multiplier without resetting shares"
    (correctedSettings == (103/100, [9/10000,1,1])
     && W.stack (W.workspace $ W.current $ windowset refactored) ==
        W.stack (W.workspace $ W.current $ windowset loaded))
  (_, gentlyResized) <- runX conf refactored (sendMessage Expand >> draw r)
  gentlyResizedSettings <- weights gentlyResized
  check "restored Mosaic uses corrected multiplier on the next Expand"
    (gentlyResizedSettings == (103/100, [9/10000 * 103/100,1,1]))
  (_, invalidOverride) <- runX conf refactored $
    broadcastMessage (SetMosaicResizeFactor (3/100))
  check "factor override rejects pathological multipliers"
    (show (currentLayout invalidOverride) == show (currentLayout refactored))
  let reset = M.lookup (modMask cfg .|. shiftMask, xK_space) (keys cfg cfg)
  resetAction <- maybe (ioError $ userError "FAIL: default layout reset key missing") pure reset
  (_, resetState) <- runX conf loaded (resetAction >> draw r)
  resetSettings <- weights resetState
  check "explicit default layout reset installs the corrected factor and shares"
    (resetSettings == (103/100, [1,1,1]) &&
     W.stack (W.workspace $ W.current $ windowset resetState) ==
     W.stack (W.workspace $ W.current $ windowset loaded) &&
     show (currentLayout oldTwice) == serializedOld)

runMosaicTests :: IO ()
runMosaicTests = do
  runResizeTests
  runWrappedResizeTests
  runWeightRepairTests
  let r = Rectangle 0 0 1000 800
      st = W.Stack (1 :: Window) [] [2,3]
      m = mosaic 1.5 [1,1,1] :: Mosaic Window
      rs = pureLayout m r st
  check "Mosaic description" (description m == "Mosaic")
  check "Mosaic places every window" (map fst rs == [1,2,3])
  check "Mosaic tiles the frame with no gaps or overlap"
    (all (inside r . snd) rs && sum (map (rectArea . snd) rs) == 1000*800)
  -- The aspect-index override is a pure message; the geometry change is pure.
  let m0 = Mosaic (Just (False, 0, 0)) 1.5 [1,1,1] :: Mosaic Window
      grown = fromMaybe m0 $
        pureMessage m0 (SomeMessage (SlopeMod doubleMaster))
      largest :: Mosaic Window -> Int
      largest l = maximum (map (rectArea . snd) (pureLayout l r st))
  check "SlopeMod grows the largest window"
    (largest grown > largest m0 &&
     sum (map (rectArea . snd) (pureLayout grown r st)) == 1000*800)
  check "Taller advances the aspect index"
    (case pureMessage (Mosaic (Just (False, 0, 5)) 1.5 [1,1,1]) (SomeMessage Taller) of
       Just (Mosaic (Just (False, 1, 5)) _ _) -> True
       _ -> False)
  check "Wider at the first aspect is a no-op"
    (isNothing (pureMessage (Mosaic (Just (False, 0, 5)) 1.5 [1,1,1] :: Mosaic Window)
       (SomeMessage Wider)))
  check "Reset drops the aspect override"
    (case pureMessage (Mosaic (Just (False, 1, 5)) 1.5 [1,1,1]) (SomeMessage Reset) of
       Just (Mosaic Nothing _ _) -> True
       _ -> False)

-- Engine.placeScreen removes floating windows before running a tiled layout.
-- Resize must use the same index space, even inside the example's wrappers.
runWrappedResizeTests :: IO ()
runWrappedResizeTests = do
  let r = Rectangle 0 24 1000 800
      wrapped = Layout $ smartBorders $ spacing 5 $ mkToggle (single REFLECTX) $
        Tall 1 (3/100) (1/2) ||| corrected ||| Full
      c = cfg {layoutHook=wrapped}
      xconf = XConf c
      start = installed r wrapped 3
      floated = start {windowset=W.float 1 (W.RationalRect 0 0 (1/4) (1/4)) (windowset start)}
      drawTiled = do
        ws <- gets (W.workspace . W.current . windowset)
        floats <- gets (W.floating . windowset)
        let tiled = ws {W.stack=W.stack ws >>= W.filter (`M.notMember` floats)}
        (rs, changed) <- runLayout tiled r
        maybe (pure ()) setLayout changed
        pure rs
  forM_ [False, True] $ \reflected -> do
    (before, ready) <- runX xconf floated $ do
      sendMessage (JumpToLayout "Mosaic")
      if reflected then sendMessage (Toggle REFLECTX) else pure ()
      drawTiled
    (after, shrunk) <- runX xconf ready (sendMessage Shrink >> drawTiled)
    (back, _) <- runX xconf shrunk (sendMessage Expand >> drawTiled)
    check "wrapped Mosaic Shrink uses the tiled index despite an earlier float"
      (areaOf 3 after < areaOf 3 before && areaOf 2 after > areaOf 2 before)
    check "wrapped Mosaic Shrink/Expand round trip restores geometry"
      (back==before)
    let focusedFloat = ready {windowset=W.focusWindow 1 (windowset ready)}
    (_, ignored) <- runX xconf focusedFloat (sendMessage Shrink)
    check "Mosaic resize ignores focus on a floating window"
      (show (currentLayout ignored)==show (currentLayout focusedFloat))

runWeightRepairTests :: IO ()
runWeightRepairTests = do
  let r = Rectangle 0 24 1000 800
      damaged = Mosaic (Just (False,1,1)) (103/100) [3/100,100/3,9/10000]
      start = (installed r (Layout damaged) 3) {epoch=1, generation=1}
      originalStack = W.stack . W.workspace . W.current $ windowset start
  (_, repaired) <- runX conf start (sendMessage RepairMosaicWeights >> draw r)
  repairSettings <- weights repaired
  check "one-time Mosaic repair equalizes only shares"
    (repairSettings == (103/100,[1,1,1]) &&
     W.stack (W.workspace $ W.current $ windowset repaired) == originalStack)
  (_, resized) <- runX conf repaired (sendMessage Shrink >> draw r)
  resizedSettings <- weights resized
  (_, repeated) <- runX conf resized (sendMessage RepairMosaicWeights)
  repeatedSettings <- weights repeated
  check "repeated repair hook preserves subsequent user resizing"
    (repeatedSettings == resizedSettings && resizedSettings /= repairSettings)
  let live = [WindowInfo w 123 "Test" "test" "" 10 r False False "AXStandardWindow" False
             | w <- [1,2,3]]
      snap = Snapshot 2 1 [DisplayInfo 10 r] live (Just 3) (Just $ checkpoint resized)
  (_, restarted) <- runX conf (initialState cfg [DisplayInfo 10 r]) $
    reconcile snap >> sendMessage RepairMosaicWeights
  restartedSettings <- weights restarted
  check "completed Mosaic repair survives checkpoint restart"
    (restartedSettings == resizedSettings)
  (_, reset) <- runX conf restarted (sendMessage ResetMosaicWeights)
  resetSettings <- weights reset
  check "explicit Mosaic reset remains available after one-time repair"
    (resetSettings == (103/100,[1,1,1]))
