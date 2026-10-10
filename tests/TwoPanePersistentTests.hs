{-# LANGUAGE FlexibleContexts #-}
module TwoPanePersistentTests (runTwoPanePersistentTests) where
import XMonad
import XMonad.Layout.TwoPanePersistent
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

runTwoPanePersistentTests :: IO ()
runTwoPanePersistentTests = do
  let l0 = TwoPanePersistent Nothing (3/100) (1/2) :: TwoPanePersistent Window
      lay l s = fst <$> runX conf st0 (doLayout l fullRect s)
  (p1,Just l1) <- lay l0 (W.Stack 1 [] [2,3])
  check "master focus without slave pairs with the next window"
    (map fst p1 == [1,2] && slaveWindow l1 == Just 2)
  (p2,Just l2) <- lay l1 (W.Stack 3 [2,1] [])
  check "focusing a slave records it"
    (map fst p2 == [1,3] && slaveWindow l2 == Just 3)
  (p3,Just l3) <- lay l2 (W.Stack 1 [] [2,3])
  check "refocusing the master keeps the last slave"
    (map fst p3 == [1,3] && slaveWindow l3 == Just 3)
  (p4,_) <- lay l3 (W.Stack 1 [] [2])
  check "a vanished slave falls back to the next window" (map fst p4 == [1,2])
  (p5,_) <- lay l3 (W.Stack 1 [] [])
  check "a single window fills the frame" (p5 == [(1,fullRect)])
  let widthOf l = rect_width . snd . head . fst
        <$> lay' l
      lay' l = lay l (W.Stack 1 [] [2]) >>= \r -> pure r
      shifted m = fromMaybe l0 (pureMessage l0 (SomeMessage m))
  w0 <- widthOf l0
  w1 <- widthOf (shifted Shrink)
  w2 <- widthOf (shifted Expand)
  check "Shrink and Expand move the split" (w0 == 500 && w1 == 470 && w2 == 530)
