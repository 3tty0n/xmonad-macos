-- Adapted from xmonad-contrib XMonad.Util.SpawnOnce (BSD-3-Clause),
-- Copyright (c) Spencer Janssen and the Xmonad Community.
-- SpawnOn helpers are not ported. Persistence is in-process, not a state file.
module XMonad.Util.SpawnOnce (spawnOnce) where
import Control.Monad (unless)
import Data.IORef
import qualified Data.Set as S
import System.IO.Unsafe (unsafePerformIO)
import XMonad.Core
import XMonad.Operations (spawn)

{-# NOINLINE onceSeen #-}
onceSeen :: IORef (S.Set String)
onceSeen = unsafePerformIO (newIORef S.empty)

spawnOnce :: String -> X ()
spawnOnce cmd = do
  seen <- io (readIORef onceSeen)
  unless (S.member cmd seen) $ do
    io (modifyIORef' onceSeen (S.insert cmd))
    spawn cmd
