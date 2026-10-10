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

place :: MRT -> Int -> IO ([Rectangle], MRT)
place l n = do
  ((rs,ml),_) <- runX conf st0 (doLayout l fullRect (W.Stack 1 [] [2..fromIntegral n]))
  pure (map snd rs, fromMaybe l ml)

send :: (Message m) => MRT -> m -> IO MRT
send l m = do
  (r,_) <- runX conf st0 (handleMessage l (SomeMessage m))
  pure (fromMaybe l r)

runMouseResizableTileTests :: IO ()
runMouseResizableTileTests = do
  let l0 = mouseResizableTile {draggerType = FixedDragger 10 10} :: MRT
      get l n = fst <$> place l n
  r1 <- get l0 1
  check "a single window fills the frame" (r1 == [fullRect])
  r3 <- get l0 3
  check "master and two slaves with a gap"
    (r3 == [ Rectangle 0 0 495 800, Rectangle 505 0 495 395
           , Rectangle 505 405 495 395 ])
  (_,l3) <- place l0 3
  ls <- send l3 {focusPos = 1} ShrinkSlave
  rs <- get ls 3
  check "ShrinkSlave shrinks the focused slave"
    (rect_height (rs !! 1) < rect_height (rs !! 2))
  le <- send l3 {focusPos = 1} ExpandSlave
  re <- get le 3
  check "ExpandSlave grows the focused slave"
    (rect_height (re !! 1) > rect_height (re !! 2))
  lm <- send l0 (SetMasterFraction (3/5))
  rm <- get lm 2
  check "SetMasterFraction moves the divider" (rect_width (head rm) == 595)
  lx <- send l0 Expand
  rx <- get lx 2
  check "Expand widens the master" (rect_width (head rx) == 525)
  lz <- send l0 (IncMasterN (-1))
  rz <- get lz 2
  check "nmaster 0 puts every window in one column" (map rect_x rz == [0,0])
  rmir <- get mouseResizableTileMirrored {draggerType = FixedDragger 10 10} 2
  check "mirrored layout stacks top and bottom"
    (rmir == [Rectangle 0 0 1000 395, Rectangle 0 405 1000 395])
