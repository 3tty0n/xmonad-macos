module MosaicTests (runMosaicTests) where
import XMonad
import XMonad.Layout.Mosaic
import qualified XMonad.StackSet as W
import Control.Monad (unless)
import Data.Maybe (fromMaybe, isNothing)

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

runMosaicTests :: IO ()
runMosaicTests = do
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
