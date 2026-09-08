-- | The @xmonad@ command line.
--
-- Upstream xmonad's control flags live in the binary compiled from the user's
-- config, and so do these: the installed engine @is@ that binary, and both
-- @~\/.local\/bin\/xmonad@ and @xmonadctl@ point at it. Building the config
-- and managing the login agent stay shell scripts, invoked from here.
module XMonad.MacOS.CLI (handleCommand) where

import Control.Applicative ((<|>))
import Control.Monad (filterM)
import Data.Maybe (fromMaybe, listToMaybe)
import System.Directory (doesFileExist, getHomeDirectory)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..), exitWith)
import System.FilePath ((</>))
import System.IO (Handle, hPutStr, hPutStrLn, stderr, stdout)
import System.Process (rawSystem, readProcessWithExitCode)

-- | Arguments the engine itself understands. Anything else is a command for a
-- running or installed XMonadMac, and never starts an engine.
engineFlags :: [String]
engineFlags = ["--check-config", "--no-startup"]

handleCommand :: [String] -> IO ()
handleCommand args
  | all (`elem` engineFlags) args = pure ()
  | otherwise = exitWith =<< run args

data Paths = Paths
  { support :: FilePath
  , app :: FilePath
  , helper :: FilePath
  , logFile :: FilePath
  }

paths :: IO Paths
paths = do
  home <- getHomeDirectory
  let bundle = home </> "Applications" </> "XMonadMac.app"
  pure Paths
    { support = home </> "Library" </> "Application Support" </> "XMonadMac"
    , app = bundle
    , helper = bundle </> "Contents" </> "MacOS" </> "XMonadMac"
    , logFile = home </> "Library" </> "Logs" </> "XMonadMac" </> "bridge.log"
    }

-- Config search order: explicit argument, XMONAD_CONFIG, then the first of
-- ~/.xmonad/xmonad.hs (upstream layout) and the XDG location that exists.
configPath :: [String] -> IO FilePath
configPath rest = do
  home <- getHomeDirectory
  env <- lookupEnv "XMONAD_CONFIG"
  let known = [home </> ".xmonad" </> "xmonad.hs"
              ,home </> ".config" </> "xmonad-mac" </> "xmonad.hs"]
  case listToMaybe rest <|> env of
    Just c -> pure c
    Nothing -> do
      present <- filterM doesFileExist known
      pure (fromMaybe (last known) (listToMaybe present))

run :: [String] -> IO ExitCode
run [] = usage stderr >> pure (ExitFailure 2)
run (cmd:rest) = do
  p <- paths
  case cmd of
    "status" -> do
      let file = support p </> "status.json"
      there <- doesFileExist file
      if there then readFile file >>= putStrLn >> pure ExitSuccess
               else putStrLn "XMonadMac is not running." >> pure ExitSuccess
    "pause" -> toHelper p "--pause"
    "resume" -> toHelper p "--resume"
    "reload" -> toHelper p "--reload"
    "dump" -> toHelper p "--dump"
    "quit" -> toHelper p "--quit"
    "recover" -> toHelper p "--recover"
    "doctor" -> toHelper p "--diagnose"
    "self-test" -> toHelper p "--self-test"
    "--restart" -> restart p
    "--recompile" -> recompile p rest
    -- Upstream's --recompile only builds; the bare command also restarts.
    "recompile" -> andThen (recompile p rest) (restart p)
    "config" -> do
      config <- configPath rest
      there <- doesFileExist config
      if there then rawSystem "/usr/bin/open" [config]
               else complain ("Config not found: " ++ config)
    "log" -> rawSystem "/usr/bin/tail" ["-f", logFile p]
    "autostart" -> do
      let script = support p </> "autostart.sh"
      there <- doesFileExist script
      if there then rawSystem script [fromMaybe "status" (listToMaybe rest)]
               else complain "Installed autostart helper missing; \
                             \re-run scripts/install.sh."
    _ | cmd `elem` ["help", "-h", "--help"] -> usage stdout >> pure ExitSuccess
      | otherwise -> usage stderr >> pure (ExitFailure 2)

toHelper :: Paths -> String -> IO ExitCode
toHelper p flag = do
  there <- doesFileExist (helper p)
  if there then rawSystem (helper p) [flag]
           else complain "XMonadMac is not installed."

restart :: Paths -> IO ExitCode
restart p = do
  up <- helperRunning
  if up then toHelper p "--reload"
        else rawSystem "/usr/bin/open" ["-g", app p]

recompile :: Paths -> [String] -> IO ExitCode
recompile p rest = do
  let script = support p </> "recompile.sh"
  there <- doesFileExist script
  if not there
    then complain "Installed recompiler missing; re-run scripts/install.sh."
    else configPath rest >>= \config -> rawSystem script [config]

helperRunning :: IO Bool
helperRunning = do
  (code, _, _) <- readProcessWithExitCode "/usr/bin/pgrep" ["-x", "XMonadMac"] ""
  pure (code == ExitSuccess)

andThen :: IO ExitCode -> IO ExitCode -> IO ExitCode
andThen first next = first >>= \code ->
  case code of ExitSuccess -> next; _ -> pure code

complain :: String -> IO ExitCode
complain message = hPutStrLn stderr message >> pure (ExitFailure 1)

usage :: Handle -> IO ()
usage h = hPutStr h $ unlines
  ["Usage: xmonad --FLAG | COMMAND [ARGS]"
  ,""
  ,"  --recompile [xmonad.hs]  compile the config; leave the running engine alone"
  ,"  --restart                run the compiled config, starting the app if needed"
  ,""
  ,"  status                   show current bridge status"
  ,"  doctor                   print native diagnostics"
  ,"  log                      follow bridge.log"
  ,"  config                   open xmonad.hs"
  ,"  pause|resume             pause/resume tiling"
  ,"  recover                  restore windows minimized by XMonadMac"
  ,"  quit                     quit XMonadMac"
  ,"  autostart on|off|status  manage login startup"
  ,"  self-test                verify focused-window AX read/write and read-back"
  ,"  dump                     write diagnostic snapshot"
  ,""
  ,"  recompile [xmonad.hs]    --recompile, then --restart"
  ,"  reload                   reload the already-compiled engine"
  ,""
  ,"The app itself is built from the source tree with make; see make help."
  ]
