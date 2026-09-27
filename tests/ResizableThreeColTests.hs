{-# LANGUAGE FlexibleContexts #-}
module ResizableThreeColTests (runResizableThreeColTests) where
import XMonad
import XMonad.Layout.ResizableThreeCol
import qualified XMonad.StackSet as W
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Control.Monad (unless)
import Data.List (nub)
import Data.Maybe (fromMaybe)

check :: String -> Bool -> IO ()
check name ok = unless ok $ ioError $ userError ("FAIL: " ++ name)

cfg :: XConfig Layout
cfg = def {layoutHook = Layout (layoutHook def)}

conf :: XConf
conf = XConf cfg

-- One display, no observed windows; the layout only reads the window set.
baseState :: XState
baseState = XState
  { windowset = foldr W.insertUp
      (W.new (Layout (plain :: ResizableThreeCol Window)) ["1"]
             [SD (Rectangle 0 24 1000 800) 10])
      ([1..5] :: [Window])
  , windowInfo = M.empty
  , ignoredWindows = S.empty
  , generation = 0
  , epoch = 0
  , pendingFocus = Nothing
  , nextActionId = 0
  , displayAffinity = M.empty
  , borderOverrides = M.empty
  , keyGrab = Nothing
  , commands = []
  , extensibleState = M.empty
  , menuBarText = Nothing
  }
  where plain = ResizableThreeCol 1 (3/100) (1/2) []

-- Same window set, but with the focus on a slave and windows on both sides.
mirrorState :: XState
mirrorState = baseState
  { windowset =
      W.modify' (const (W.Stack (2 :: Window) [1] [3,4,5])) (windowset baseState) }

runResizableThreeColTests :: IO ()
runResizableThreeColTests = do
  let frame = Rectangle 0 24 1000 800
      plain = ResizableThreeCol 1 (3/100) (1/2) [] :: ResizableThreeCol Window
      mid = ResizableThreeColMid 1 (3/100) (1/2) [] :: ResizableThreeCol Window
      stack n = W.Stack (1 :: Window) [] [2..n]
      placed l n = pureLayout l frame (stack n)
      area rs = sum [rect_width r * rect_height r | (_,r) <- rs]
  check "every window is placed" (length (placed plain 5) == 5)
  check "three windows make three columns"
    (length (placed plain 3) == 3
     && length (nub (map (rect_x . snd) (placed plain 3))) == 3)
  check "the tiled area fills the frame" (area (placed plain 5) == 800000)
  -- The mid master column is the focused window's column; Shrink and Expand
  -- move only that fraction.
  let master x = fmap rect_width (lookup 1 (placed x 3))
      midBase = master mid
      midShrunk = master (fromMaybe mid (pureMessage mid (SomeMessage Shrink)))
      midGrown  = master (fromMaybe mid (pureMessage mid (SomeMessage Expand)))
  check "Shrink narrows the ResizableThreeColMid master"
    (midShrunk < midBase && midBase == Just 500)
  check "Expand widens the ResizableThreeColMid master"
    (midGrown > midBase && midGrown == Just 530)
  -- A mirror message reaches the focused slave, whose weight is in the
  -- flattened list, and changes only that window's height.
  let mstack = W.Stack (2 :: Window) [1] [3,4,5]
      heightOf l = fmap rect_height (lookup 2 (pureLayout l frame mstack))
      slaveHeight ml = heightOf (fromMaybe plain ml)
  (shrunkL,_) <- runX conf mirrorState (handleMessage plain (SomeMessage MirrorShrink))
  (grownL,_)  <- runX conf mirrorState (handleMessage plain (SomeMessage MirrorExpand))
  check "the focused slave starts at the even share" (heightOf plain == Just 400)
  check "MirrorShrink makes the focused slave taller"
    (slaveHeight shrunkL > heightOf plain && slaveHeight shrunkL == Just 412)
  check "MirrorExpand makes the focused slave shorter"
    (slaveHeight grownL < heightOf plain && slaveHeight grownL == Just 388)
