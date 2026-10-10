-- Adapted from xmonad-contrib XMonad.Actions.SpawnOn (BSD-3-Clause),
-- Copyright (c) Spencer Janssen and the Xmonad Community.
-- Prompt-based helpers are not ported. A window matches a spawned process
-- when its pid is that process or one of its descendants in the process
-- table; apps started through `open` belong to launchd and never match.
module XMonad.Actions.SpawnOn
  ( Spawner, spawnHere, spawnOn, spawnAndDo
  , manageSpawn, manageSpawnWithGC, spawnedPids, matchSpawned
  ) where
import Control.Exception (SomeException, try)
import Control.Monad.IO.Class (liftIO)
import qualified Data.Map.Strict as M
import Data.List (unfoldr)
import System.Process (readProcess)
import XMonad.Core
import XMonad.ManageHook (doShift, queryInfo)
import XMonad.Operations (spawnPID, withWindowSet)
import qualified XMonad.StackSet as W
import qualified XMonad.Util.ExtensibleState as XS

newtype Spawner = Spawner [(Int, ManageHook)]

instance ExtensionClass Spawner where
  initialValue = Spawner []

spawnHere :: String -> X ()
spawnHere cmd = withWindowSet $ \ws -> spawnOn (W.currentTag ws) cmd

spawnOn :: WorkspaceId -> String -> X ()
spawnOn ws = spawnAndDo (doShift ws)

-- Needs manageSpawn in the manageHook to take effect.
spawnAndDo :: ManageHook -> String -> X ()
spawnAndDo hook cmd = do
  started <- spawnPID cmd
  mapM_ (\p -> XS.modify (\(Spawner ps) -> Spawner ((p, hook) : ps))) started

spawnedPids :: X [Int]
spawnedPids = XS.gets (\(Spawner ps) -> map fst ps)

-- Keeps the 20 most recent spawns.
manageSpawn :: ManageHook
manageSpawn = manageSpawnWithGC (pure . take 20)

manageSpawnWithGC
  :: ([(Int, ManageHook)] -> Query [(Int, ManageHook)]) -> ManageHook
manageSpawnWithGC gc = do
  Spawner pending <- liftX XS.get
  kept <- gc pending
  if null kept then store kept >> mempty else do
    window <- queryInfo pid 0
    parents <- liftIO processParents
    case matchSpawned parents window kept of
      Nothing -> store kept >> mempty
      Just (hook, rest) -> store rest >> hook
  where store = liftX . XS.put . Spawner

-- The window's own pid first, then each ancestor, so the nearest spawn wins.
matchSpawned :: M.Map Int Int -> Int -> [(Int, a)] -> Maybe (a, [(Int, a)])
matchSpawned parents window pending = go (take 64 chain)
  where
    chain = window : unfoldr up window
    up p = case M.lookup p parents of
      Just q | q > 1 && q /= p -> Just (q, q)
      _ -> Nothing
    go [] = Nothing
    go (p:ps) = case lookup p pending of
      Just hook -> Just (hook, filter ((/= p) . fst) pending)
      Nothing -> go ps

processParents :: IO (M.Map Int Int)
processParents = do
  out <- try (readProcess "ps" ["-axo", "pid=,ppid="] "")
  pure $ case out of
    Left e -> const M.empty (e :: SomeException)
    Right t -> M.fromList [ (a, b) | l <- lines t, [x, y] <- [words l]
                          , [(a, "")] <- [reads x], [(b, "")] <- [reads y] ]
