{-# LANGUAGE FlexibleContexts #-}
module MouseResizableTileTests (runMouseResizableTileTests) where
import XMonad
import XMonad.Layout.MouseResizableTile
import qualified XMonad.StackSet as W
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import Control.Monad (unless)
import Data.Maybe (fromMaybe)

check :: String -> Bool -> IO ()
check name ok = unless ok $ ioError $ userError ("FAIL: " ++ name)

conf :: XConf
conf = XConf def {layoutHook = Layout (layoutHook def)}

st0 :: XState
st0 = XState
  { windowset = W.new (Layout (layoutHook def)) ["1"]
      [SD (Rectangle 0 0 1000 800) 10]
  , windowInfo = M.empty, ignoredWindows = S.empty, generation = 0, epoch = 0
  , pendingFocus = Nothing, nextActionId = 0, displayAffinity = M.empty
  , borderOverrides = M.empty, keyGrab = Nothing, commands = []
  , extensibleState = M.empty, menuBarText = Nothing, unconfirmed = M.empty }

fullRect :: Rectangle
fullRect = Rectangle 0 0 1000 800

type MRT = MouseResizableTile Window

-- Focus at index f among windows 1..n.
place :: MRT -> Int -> Int -> IO ([Rectangle], MRT)
place l n f = do
  let ws = [1..fromIntegral n] :: [Window]
      stack = W.Stack (ws !! f) (reverse (take f ws)) (drop (f+1) ws)
  ((rs,ml),_) <- runX conf st0 (doLayout l fullRect stack)
  pure (map snd rs, fromMaybe l ml)

send :: (Message m) => MRT -> m -> IO MRT
send l m = do
  (r,_) <- runX conf st0 (handleMessage l (SomeMessage m))
  pure (fromMaybe l r)

runMouseResizableTileTests :: IO ()
runMouseResizableTileTests = do
  let l0 = mouseResizableTile :: MRT
      get l n = fst <$> place l n 0
      hs = map rect_height
  r1 <- get l0 1
  check "a single window fills the frame" (r1 == [fullRect])
  r3 <- get l0 3
  check "default gap 6: master and two slaves"
    (r3 == [ Rectangle 0 0 497 800, Rectangle 503 0 497 397
           , Rectangle 503 403 497 397 ])
  let slaveHeights l f = hs . drop 1 . fst <$> place l 3 f
  (_,l3) <- place l0 3 1
  ls <- send l3 ShrinkSlave
  check "ShrinkSlave moves the boundary under the focused slave up"
    =<< ((== [373,421]) <$> slaveHeights ls 1)
  le <- send l3 ExpandSlave
  check "ExpandSlave moves it down"
    =<< ((== [421,373]) <$> slaveHeights le 1)
  (_,l3l) <- place l0 3 2
  lsl <- send l3l ShrinkSlave
  check "the last slave adjusts the same boundary as the one above"
    =<< ((== [373,421]) <$> slaveHeights lsl 2)
  (_,l3m) <- place l0 3 0
  lsm <- send l3m ShrinkSlave
  check "ShrinkSlave on a lone master does nothing"
    =<< ((== [397,397]) <$> slaveHeights lsm 0)
  lm <- send l0 (SetMasterFraction (3/5))
  rm <- get lm 2
  check "SetMasterFraction moves the divider" (rect_width (head rm) == 597)
  lx <- send l0 Expand
  rx <- get lx 2
  check "Expand widens the master by fracIncrement"
    (rect_width (head rx) == 527)
  ln <- send l0 (SetRightSlaveFraction 0 (1/4))
  rn <- get ln 3
  check "SetRightSlaveFraction sets the first slave share"
    (map rect_height (drop 1 rn) == [197,597])
  lz <- send l0 (IncMasterN (-1))
  rz <- get lz 2
  check "nmaster 0 puts every window in one column" (map rect_x rz == [0,0])
  lb <- send (l0 {draggerType = BordersDragger}) (SetMasterFraction (1/2))
  rb <- get lb 2
  check "BordersDragger leaves no gap"
    (rb == [Rectangle 0 0 500 800, Rectangle 500 0 500 800])
  rmir <- get mouseResizableTileMirrored 2
  check "mirrored layout stacks top and bottom"
    (rmir == [Rectangle 0 0 1000 397, Rectangle 0 403 1000 397])
  check "mirrored description" (description (mouseResizableTileMirrored :: MRT)
    == "Mirror MouseResizableTile")
