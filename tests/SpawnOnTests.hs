module SpawnOnTests (runSpawnOnTests) where
import XMonad
import XMonad.Actions.SpawnOn
import XMonad.MacOS.Engine (initialState)
import qualified Data.Map.Strict as M
import qualified XMonad.StackSet as W
import Control.Monad (unless)

check :: String -> Bool -> IO ()
check name ok = unless ok $ ioError $ userError ("FAIL: " ++ name)

cfg :: XConfig Layout
cfg = def { layoutHook = Layout (layoutHook def), workspaces = ["1","2","3"] }

conf :: XConf
conf = XConf cfg

info :: Int -> WindowInfo
info p = WindowInfo 7 p "App" "org.app" "t" 10 (Rectangle 0 24 100 100)
                    False False "AXStandardWindow"

-- Window 7 sits on workspace "1" and belongs to process p.
withWindow :: Int -> XState
withWindow p = s { windowInfo = M.singleton 7 (info p)
                 , windowset = W.insertUp 7 (windowset s) }
  where s = initialState cfg [DisplayInfo 10 (Rectangle 0 24 1000 800)]

runSpawnOnTests :: IO ()
runSpawnOnTests = do
  let parents = M.fromList [(30,20),(20,10),(10,1),(5,5)]
  check "a descendant matches its spawned ancestor"
    (fmap fst (matchSpawned parents 30 [(10,"a")]) == Just "a")
  check "the nearest spawned ancestor wins"
    (fmap fst (matchSpawned parents 30 [(10,"far"),(20,"near")]) == Just "near")
  check "a match is consumed"
    (fmap snd (matchSpawned parents 30 [(10,"a"),(99,"b")]) == Just [(99,"b")])
  check "an unrelated pid does not match"
    (null (matchSpawned parents 30 [(99,"a")]))
  check "launchd is never treated as an ancestor"
    (null (matchSpawned parents 10 [(1,"a")]))
  check "a self-parented pid terminates"
    (null (matchSpawned parents 5 [(99,"a")]))

  (pids, st) <- runX conf (withWindow 0) (spawnOn "2" "sleep 1" >> spawnedPids)
  check "spawnOn records the spawned pid" (length pids == 1)
  let p = head pids
  (Endo f, st') <- runX conf st { windowInfo = M.singleton 7 (info p) }
                     (runQuery manageSpawn 7)
  check "manageSpawn applies the hook for the spawned pid"
    (W.findTag 7 (f (windowset st')) == Just "2")
  (rest, _) <- runX conf st' spawnedPids
  check "manageSpawn consumes the matched spawn" (null rest)
  (Endo g, st'') <- runX conf (withWindow 0) (runQuery manageSpawn 7)
  check "manageSpawn without a spawn leaves the window alone"
    (W.findTag 7 (g (windowset st'')) == Just "1")
