-- Adapted from xmonad-contrib XMonad.Util.Run (BSD-3-Clause).
-- X11-facing helpers (dzen, runInTerm that talks to X) are not ported.
module XMonad.Util.Run (safeSpawn, safeSpawnProg, unsafeSpawn) where
import Control.Concurrent (forkIO)
import Control.Monad (void)
import Control.Monad.IO.Class (MonadIO, liftIO)
import System.IO (stderr)
import System.Process
import XMonad.Core (X)
import XMonad.Operations (spawn)

safeSpawn :: MonadIO m => FilePath -> [String] -> m ()
safeSpawn path args = liftIO $ do
  (_,_,_,handle) <- createProcess (proc path args)
    { std_in=NoStream, std_out=UseHandle stderr, std_err=UseHandle stderr
    , create_group=True, close_fds=True }
  void $ forkIO $ void $ waitForProcess handle

safeSpawnProg :: MonadIO m => FilePath -> m ()
safeSpawnProg path = safeSpawn path []

unsafeSpawn :: String -> X ()
unsafeSpawn = spawn
