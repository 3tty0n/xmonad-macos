-- | The @xmonad@ command line.
--
-- Upstream xmonad's control flags live in the binary compiled from the user's
-- config, and so do these: the installed engine @is@ that binary, and both
-- @~\/.local\/bin\/xmonad@ and @xmonadctl@ point at it. Source-tree builds of
-- the native app stay in @scripts/@; everything an installed instance does
-- is handled here.
module XMonad.MacOS.CLI (handleCommand, Paths(..), recompileInstalled) where

import Control.Applicative ((<|>))
import Control.Monad (filterM, unless, void, when)
import Data.List (isInfixOf, isPrefixOf)
import Data.Maybe (fromMaybe, isJust, listToMaybe)
import System.Directory
  ( copyFile, createDirectoryIfMissing, doesDirectoryExist, doesFileExist
  , findExecutable, getHomeDirectory, listDirectory, pathIsSymbolicLink
  , removePathForcibly, renameFile )
import System.Environment (getEnv, lookupEnv, setEnv)
import System.Exit (ExitCode (..), exitWith)
import System.FilePath (takeDirectory, (</>))
import System.IO (Handle, hClose, hPutStr, hPutStrLn, openTempFile, stderr, stdout)
import System.IO.Error (tryIOError)
import System.Process
  ( CreateProcess(..), cwd, proc, rawSystem, readCreateProcessWithExitCode
  , readProcess, readProcessWithExitCode )

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
  envCfg <- lookupEnv "XMONAD_CONFIG"
  let known = [home </> ".xmonad" </> "xmonad.hs"
              ,home </> ".config" </> "xmonad-mac" </> "xmonad.hs"]
  case listToMaybe rest <|> envCfg of
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
    "doctor" -> doctor p
    "self-test" -> toHelper p "--self-test"
    "start" -> startApp p rest
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
    "autostart" -> autostart p (fromMaybe "status" (listToMaybe rest))
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

startApp :: Paths -> [String] -> IO ExitCode
startApp p rest = do
  there <- doesDirectoryExist (app p)
  if not there then complain "XMonadMac is not installed." else
    case rest of
      xs | not (null xs || xs == ["--dry-run"]) ->
        hPutStrLn stderr "Usage: xmonad start [--dry-run]" >> pure (ExitFailure 2)
      _ -> do
        up <- helperRunning
        if up then complain "XMonadMac is already running; quit it before changing startup mode."
        else do
          let dry = rest == ["--dry-run"]
          blocked <- if dry then pure Nothing else conflictingWM
          case blocked of
            Just name -> complain (name ++ " is running. Stop its service explicitly before starting XMonadMac.")
            Nothing | dry -> rawSystem "/usr/bin/open" [app p, "--args", "--dry-run"]
                    | otherwise -> rawSystem "/usr/bin/open" [app p]

conflictingWM :: IO (Maybe String)
conflictingWM = do
  yabai <- running "yabai"
  skhd <- running "skhd"
  pure $ if yabai then Just "yabai" else if skhd then Just "skhd" else Nothing
  where running name = do
          (code, _, _) <- readProcessWithExitCode "/usr/bin/pgrep" ["-x", name] ""
          pure (code == ExitSuccess)

recompile :: Paths -> [String] -> IO ExitCode
recompile p rest = configPath rest >>= recompileInstalled p

-- Compile the user's xmonad.hs against the installed build kit and swap the
-- engine only after --check-config and native key validation succeed.
recompileInstalled :: Paths -> FilePath -> IO ExitCode
recompileInstalled p config = do
  let kit = support p </> "build-kit"
  kitOk <- (&&) <$> doesDirectoryExist (kit </> "src") <*> doesFileExist (kit </> "xmonad-macos.cabal")
  cfgOk <- doesFileExist config
  if not kitOk
    then complain "Installed build kit is missing. Re-run make install from the XMonadMac source tree."
    else if not cfgOk then complain ("Config not found: " ++ config) else do
      tools <- ensureToolchain
      case tools of
        Left err -> complain err
        Right () -> do
          stageConfig kit config
          (built, _, err) <- runIn kit "cabal" ["build", "exe:xmonad-engine"]
          case built of
            ExitSuccess -> do
              (listed, out, _) <- runIn kit "cabal" ["list-bin", "exe:xmonad-engine"]
              case listed of
                ExitSuccess | engine <- lastNonEmpty (lines out), not (null engine) ->
                  installBuiltEngine p engine
                _ -> complain "cabal list-bin did not report xmonad-engine"
            _ -> hPutStr stderr err >> pure built

installBuiltEngine :: Paths -> FilePath -> IO ExitCode
installBuiltEngine p engine = do
  let dest = support p </> "xmonad-engine"
      previous = dest ++ ".previous"
      confDest = support p </> "configure.json"
  createDirectoryIfMissing True (support p)
  tmpEngine <- namedTemp (support p) "xmonad-engine.new"
  tmpConf <- namedTemp (support p) "configure.new"
  let cleanup = mapM_ removePathForcibly [tmpEngine, tmpConf]
  copyFile engine tmpEngine
  void $ rawSystem "/bin/chmod" ["755", tmpEngine]
  (checked, handshake, checkErr) <- readProcessWithExitCode tmpEngine ["--check-config"] ""
  case checked of
    ExitSuccess -> do
      writeFile tmpConf handshake
      validated <- validateHandshake p tmpConf
      case validated of
        ExitSuccess -> do
          had <- doesFileExist dest
          when had $ copyFile dest previous
          -- The running engine may still hold the old inode; rename replaces atomically.
          renameFile tmpEngine dest
          copyFile tmpConf confDest
          cleanup
          putStrLn ("Installed compiled config: " ++ dest)
          pure ExitSuccess
        code -> cleanup >> pure code
    code -> hPutStr stderr checkErr >> cleanup >> pure code

validateHandshake :: Paths -> FilePath -> IO ExitCode
validateHandshake p conf = do
  there <- doesFileExist (helper p)
  if there then rawSystem (helper p) ["--validate-config", conf]
           else pure ExitSuccess

stageConfig :: FilePath -> FilePath -> IO ()
stageConfig kit config = do
  let staged = kit </> "build" </> "config"
      libDest = staged </> "lib"
      libSrc = takeDirectory config </> "lib"
  createDirectoryIfMissing True staged
  removePathForcibly libDest
  createDirectoryIfMissing True libDest
  copyFile config (staged </> "Main.hs")
  lib <- doesDirectoryExist libSrc
  when lib $ copyTree libSrc libDest
  writeFile (kit </> "build" </> "config-source.txt") (config ++ "\n")

copyTree :: FilePath -> FilePath -> IO ()
copyTree src dest = do
  createDirectoryIfMissing True dest
  names <- listDirectory src
  mapM_ (\n -> do
    let from = src </> n; to = dest </> n
    dir <- doesDirectoryExist from
    link <- if dir then pure False else pathIsSymbolicLink from
    if dir then copyTree from to
      else unless link $ copyFile from to) names

namedTemp :: FilePath -> String -> IO FilePath
namedTemp dir prefix = do
  createDirectoryIfMissing True dir
  (path, h) <- openTempFile dir prefix
  hClose h
  removePathForcibly path
  pure path

runIn :: FilePath -> String -> [String] -> IO (ExitCode, String, String)
runIn dir cmd args = readCreateProcessWithExitCode (proc cmd args) { cwd = Just dir } ""

lastNonEmpty :: [String] -> String
lastNonEmpty xs = case reverse (filter (not . null) xs) of
  (y:_) -> y
  [] -> ""

ensureToolchain :: IO (Either String ())
ensureToolchain = do
  present <- haveTools
  unless present $ do
    path <- fromMaybe "/usr/bin:/bin" <$> lookupEnv "PATH"
    setEnv "PATH" ("/opt/homebrew/bin:/usr/local/bin:" ++ path)
  present' <- haveTools
  unless present' $ do
    r <- tryIOError $ readProcessWithExitCode "brew" ["--prefix", "ghc@9.12"] ""
    case r of
      Right (ExitSuccess, out, _) | prefix <- filter (/= '\n') out, not (null prefix) -> do
        path <- getEnv "PATH"
        setEnv "PATH" (prefix </> "bin" ++ ":" ++ path)
      _ -> pure ()
  ok <- haveTools
  pure $ if ok then Right () else Left "Missing command: ghc or cabal"
  where haveTools = (&&) <$> has "ghc" <*> has "cabal"
        has n = isJust <$> findExecutable n

autostart :: Paths -> String -> IO ExitCode
autostart p verb = do
  home <- getHomeDirectory
  uid <- fmap (filter (/= '\n')) (readProcess "/usr/bin/id" ["-u"] "")
          `catchIO` (\_ -> pure "0")
  let label = "org.xmonad.XMonadMac.autostart"
      plist = home </> "Library" </> "LaunchAgents" </> (label ++ ".plist")
      domain = "gui/" ++ uid
      loaded = domain ++ "/" ++ label
  case verb of
    v | v `elem` ["on", "install", "enable"] -> do
      there <- doesDirectoryExist (app p)
      if not there then complain ("XMonadMac is not installed at " ++ app p) else do
        createDirectoryIfMissing True (takeDirectory plist)
        writeFile plist (launchPlist label (app p))
        void $ rawSystem "/bin/chmod" ["600", plist]
        void $ readProcessWithExitCode "/bin/launchctl" ["bootout", loaded] ""
        code <- rawSystem "/bin/launchctl" ["bootstrap", domain, plist]
        when (code == ExitSuccess) $ putStrLn "XMonadMac will start at login."
        pure code
    v | v `elem` ["off", "uninstall", "disable"] -> do
      void $ readProcessWithExitCode "/bin/launchctl" ["bootout", loaded] ""
      removePathForcibly plist
      putStrLn "XMonadMac login start disabled."
      pure ExitSuccess
    "status" -> do
      there <- doesFileExist plist
      if not there then putStrLn "disabled" >> pure ExitSuccess else do
        putStrLn ("enabled: " ++ plist)
        (code, out, _) <- readProcessWithExitCode "/bin/launchctl" ["print", loaded] ""
        putStr (if code == ExitSuccess then unlines (take 20 (lines out)) else "not currently loaded\n")
        pure ExitSuccess
    _ -> hPutStrLn stderr "Usage: xmonad autostart on|off|status" >> pure (ExitFailure 2)

launchPlist :: String -> FilePath -> String
launchPlist label bundle = unlines
  ["<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
  ,"<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">"
  ,"<plist version=\"1.0\"><dict>"
  ,"  <key>Label</key><string>" ++ xmlEscape label ++ "</string>"
  ,"  <key>ProgramArguments</key><array>"
  ,"    <string>/usr/bin/open</string><string>-g</string>"
  ,"    <string>" ++ xmlEscape bundle ++ "</string>"
  ,"  </array>"
  ,"  <key>RunAtLoad</key><true/>"
  ,"  <key>ProcessType</key><string>Interactive</string>"
  ,"</dict></plist>"]

xmlEscape :: String -> String
xmlEscape = concatMap esc
  where esc '&' = "&amp;"; esc '<' = "&lt;"; esc '>' = "&gt;"
        esc '"' = "&quot;"; esc '\'' = "&apos;"; esc c = [c]

doctor :: Paths -> IO ExitCode
doctor p = do
  void $ rawSystem "/usr/bin/sw_vers" []
  helperCode <- toHelper p "--diagnose"
  status <- doesFileExist (support p </> "status.json")
  when status $ do
    readFile (support p </> "status.json") >>= putStrLn
    putStrLn ""
  putStrLn "Potential conflicting processes:"
  void $ rawSystem "/usr/bin/pgrep" ["-fl", "(^|/)(yabai|skhd)( |$)"]
  putStrLn "\nSignature:"
  void $ rawSystem "/usr/bin/codesign" ["-dv", app p]
  (_, req, _) <- readProcessWithExitCode "/usr/bin/codesign" ["-d", "-r-", app p] ""
  let designated = filter ("designated" `isPrefixOf`) (lines req)
  mapM_ putStrLn designated
  unless (any ("certificate leaf" `isInfixOf`) designated) $
    putStrLn "Ad-hoc signed: rebuilding invalidates the Accessibility grant."
  putStrLn "\nRecent log (may contain application names/window titles):"
  void $ rawSystem "/usr/bin/tail" ["-n", "30", logFile p]
  pure helperCode

helperRunning :: IO Bool
helperRunning = do
  (code, _, _) <- readProcessWithExitCode "/usr/bin/pgrep" ["-x", "XMonadMac"] ""
  pure (code == ExitSuccess)

andThen :: IO ExitCode -> IO ExitCode -> IO ExitCode
andThen first next = first >>= \code ->
  case code of ExitSuccess -> next; _ -> pure code

complain :: String -> IO ExitCode
complain message = hPutStrLn stderr message >> pure (ExitFailure 1)

catchIO :: IO a -> (IOError -> IO a) -> IO a
catchIO action handler = either handler pure =<< tryIOError action

usage :: Handle -> IO ()
usage h = hPutStr h $ unlines
  ["Usage: xmonad --FLAG | COMMAND [ARGS]"
  ,""
  ,"  --recompile [xmonad.hs]  compile the config; leave the running engine alone"
  ,"  --restart                run the compiled config, starting the app if needed"
  ,"  start [--dry-run]        launch the app (read-only with --dry-run)"
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
