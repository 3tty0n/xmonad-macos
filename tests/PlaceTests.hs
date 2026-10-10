module PlaceTests (runPlaceTests) where
import XMonad
import XMonad.Hooks.Place
import qualified XMonad.StackSet as W
import Control.Monad (unless)
import qualified Data.Map.Strict as M

check :: String -> Bool -> IO ()
check name ok = unless ok $ ioError $ userError ("FAIL: " ++ name)

screenR, leftScreen :: Rectangle
screenR = Rectangle 0 0 1000 800
leftScreen = Rectangle (-1000) (-300) 1000 800

inside :: Rectangle -> Rectangle -> Bool
inside (Rectangle sx sy sw sh) (Rectangle x y w h) =
  x >= sx && y >= sy && x + w <= sx + sw && y + h <= sy + sh

disjoint :: Rectangle -> Rectangle -> Bool
disjoint (Rectangle ax ay aw ah) (Rectangle bx by bw bh) =
  ax + aw <= bx || bx + bw <= ax || ay + ah <= by || by + bh <= ay

runPlaceTests :: XConf -> XState -> IO ()
runPlaceTests conf initial = do
  let win = Rectangle 5 5 200 100
      place p s ws pnt = purePlaceWindow p s ws pnt win
  check "fixed (0,0) is top-left"
    (place (fixed (0, 0)) screenR [] (0, 0) == Rectangle 0 0 200 100)
  check "fixed (1,1) is bottom-right"
    (place (fixed (1, 1)) screenR [] (0, 0) == Rectangle 800 700 200 100)
  check "fixed centres"
    (place (fixed (1/2, 1/2)) screenR [] (0, 0) == Rectangle 400 350 200 100)
  check "fixed follows a display above and left of the primary"
    (place (fixed (1/2, 1/2)) leftScreen [] (0, 0)
       == Rectangle (-600) 50 200 100)
  check "underMouse centres on the pointer"
    (place (underMouse (1/2, 1/2)) screenR [] (500, 400)
       == Rectangle 400 350 200 100)
  check "underMouse accepts a negative pointer"
    (place (underMouse (0, 0)) leftScreen [] (-500, -100)
       == Rectangle (-500) (-100) 200 100)
  check "inBounds pulls an overhanging window back"
    (place (inBounds (underMouse (1/2, 1/2))) screenR [] (990, 790)
       == Rectangle 800 700 200 100)
  check "inBounds keeps a window inside a negative screen"
    (place (inBounds (underMouse (1/2, 1/2))) leftScreen [] (-1500, -400)
       == Rectangle (-1000) (-300) 200 100)
  check "withGaps respects the gaps"
    (place (withGaps (20, 30, 40, 10) (fixed (1, 1))) screenR [] (0, 0)
       == Rectangle 770 660 200 100
     && place (withGaps (20, 30, 40, 10) (underMouse (0, 0))) screenR [] (-50, -50)
       == Rectangle 10 20 200 100)
  check "smart on an empty screen takes the preferred corner"
    (place (smart (0, 0)) screenR [] (0, 0) == Rectangle 0 0 200 100
     && place (smart (1, 1)) screenR [] (0, 0) == Rectangle 800 700 200 100)
  let busy = [Rectangle 0 0 200 100]
      r = place (smart (0, 0)) screenR busy (0, 0)
  check "smart avoids an occupied corner" (disjoint r (head busy) && inside screenR r)
  let wall = [Rectangle 0 0 1000 800]
  check "smart stays on screen when everything overlaps"
    (inside screenR (place simpleSmart screenR wall (0, 0)))
  let negBusy = [Rectangle (-1000) (-300) 200 100]
      rn = place simpleSmart leftScreen negBusy (0, 0)
  check "smart works on negative coordinates"
    (disjoint rn (head negBusy) && inside leftScreen rn)
  check "smart ignores windows on another display"
    (place (smart (0, 0)) screenR [Rectangle (-1000) 0 500 500] (0, 0)
       == Rectangle 0 0 200 100)
  check "simpleSmart clamps an oversized window to the origin"
    (place simpleSmart (Rectangle 0 0 100 50) [] (0, 0)
       == Rectangle 0 0 200 100)
  let fr = Rectangle 100 80 200 100
      wInfo n f = WindowInfo n 1 "a" "b" "t" 10 f False False "AXStandardWindow"
      info = M.fromList [(7, wInfo 7 fr), (8, wInfo 8 (Rectangle 0 24 300 300))]
      base = initial
        { windowInfo = info
        , windowset = W.insertUp 7 (W.insertUp 8 (windowset initial)) }
      floated = base
        { windowset = W.float 7 (W.RationalRect (1/10) (1/10) (1/5) (1/8))
                        (windowset base) }
      run st x = snd <$> runX conf st x
      floatOf st = M.lookup 7 (W.floating (windowset st))
  hooked <- do
    (Endo f, _) <- runX conf floated (runQuery (placeHook (fixed (1, 1))) 7)
    pure (f (windowset floated))
  check "placeHook rewrites a floating window to its screen corner"
    (M.lookup 7 (W.floating hooked)
       == Just (W.RationalRect (4/5) (7/8) (1/5) (1/8)))
  (Endo g, _) <- runX conf base (runQuery (placeHook (fixed (1, 1))) 7)
  check "placeHook leaves a tiled window alone"
    (M.null (W.floating (g (windowset base))))
  placedNow <- run floated (placeFocused simpleSmart)
  print (floatOf placedNow, W.floating (windowset floated), W.peek (windowset floated))
  check "placeFocused avoids the neighbouring window"
    (case floatOf placedNow of
       Just (W.RationalRect x y w h) ->
         let area = Rectangle 0 24 1000 800
             px = round (x * 1000); py = 24 + round (y * 800)
             r' = Rectangle px py (round (w * 1000)) (round (h * 800))
         in disjoint r' (Rectangle 0 24 300 300) && inside area r'
       Nothing -> False)
  let lowTag = W.tag (W.workspace (head (W.visible (windowset initial))))
      onLeft = floated
        { windowset = W.shiftWin lowTag 7 (windowset floated) }
  (Endo h, _) <- runX conf onLeft (runQuery (placeHook (fixed (1, 1))) 7)
  check "placement is relative to the display the window is on"
    (M.lookup 7 (W.floating (h (windowset onLeft)))
       == Just (W.RationalRect (4/5) (7/8) (1/5) (1/8)))
