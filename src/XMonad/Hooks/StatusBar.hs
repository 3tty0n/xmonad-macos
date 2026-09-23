-- Adapted from xmonad-contrib XMonad.Hooks.StatusBar (BSD-3-Clause),
-- Copyright (c) Yecine Megdiche and the Xmonad Community.
-- There are no X11 root-window properties, struts or cleanup hooks here, so
-- statusBarProp, withEasySB and sbCleanupHook are not ported. The bar reads
-- a pipe, a file, a spawned command's argument, or the macOS menu bar.
module XMonad.Hooks.StatusBar
  ( StatusBarConfig(..), withSB, statusBarGeneric, statusBarPipe
  , statusBarFile, statusBarSpawn, macMenuBarPP, shellQuote
  , module XMonad.Hooks.StatusBar.PP
  ) where
import qualified Control.Exception as E
import Control.Monad (unless, when)
import Data.IORef
import System.Directory (renameFile)
import System.IO
import System.Process
import XMonad.Core
import XMonad.Operations (spawn)
import XMonad.Hooks.StatusBar.PP

data StatusBarConfig = StatusBarConfig
  { sbLogHook :: X (), sbStartupHook :: X () }
instance Semigroup StatusBarConfig where
  StatusBarConfig l s <> StatusBarConfig l' s' = StatusBarConfig (l >> l') (s >> s')
instance Monoid StatusBarConfig where
  mempty = StatusBarConfig (pure ()) (pure ())
instance Default StatusBarConfig where def = mempty

withSB :: StatusBarConfig -> XConfig l -> XConfig l
withSB sb c = c { logHook = logHook c >> sbLogHook sb
                , startupHook = startupHook c >> sbStartupHook sb }

statusBarGeneric :: String -> X () -> StatusBarConfig
statusBarGeneric cmd lh = StatusBarConfig lh (unless (null cmd) (spawn cmd))

-- The engine plans on every observation, so each sink below writes only when
-- the rendered text changed.
changed :: IORef String -> String -> X Bool
changed ref s = io $ atomicModifyIORef' ref (\old -> (s, old /= s))

-- Start cmd at startup and feed each rendered line to its stdin.
statusBarPipe :: String -> X PP -> IO StatusBarConfig
statusBarPipe cmd xpp = do
  hRef <- newIORef Nothing
  last' <- newIORef ""
  let start = io $ do
        (Just h,_,_,_) <- createProcess (shell cmd)
          { std_in=CreatePipe, std_out=UseHandle stderr, std_err=UseHandle stderr
          , create_group=True, close_fds=True }
        hSetBuffering h LineBuffering
        writeIORef hRef (Just h)
      out s = readIORef hRef >>= maybe (pure ())
        (\h -> hPutStrLn h s `E.catch` \e -> const (writeIORef hRef Nothing) (e :: E.IOException))
  pure $ StatusBarConfig (sinkPP last' out xpp) start

-- Replace path with the latest line; readers never see a half-written file.
statusBarFile :: FilePath -> X PP -> IO StatusBarConfig
statusBarFile path xpp = do
  last' <- newIORef ""
  let out s = do
        writeFile (path ++ ".tmp") (s ++ "\n")
        renameFile (path ++ ".tmp") path
  pure $ StatusBarConfig (sinkPP last' out xpp) (pure ())

-- Run a shell command for each new line, e.g. to trigger a SketchyBar event.
statusBarSpawn :: (String -> String) -> X PP -> IO StatusBarConfig
statusBarSpawn mk xpp = do
  last' <- newIORef ""
  pure $ StatusBarConfig (sinkPP' last' (spawn . mk) xpp) (pure ())

-- Show the rendered PP as the XMonadMac menu bar title.
macMenuBarPP :: X PP -> StatusBarConfig
macMenuBarPP xpp = StatusBarConfig
  (xpp >>= dynamicLogString >>= \s -> modify (\st -> st {menuBarText = Just s}))
  (pure ())

sinkPP :: IORef String -> (String -> IO ()) -> X PP -> X ()
sinkPP ref out = sinkPP' ref (io . out)

sinkPP' :: IORef String -> (String -> X ()) -> X PP -> X ()
sinkPP' ref out xpp = do
  pp <- xpp
  s <- dynamicLogString pp
  new <- changed ref s
  when new (out s)

shellQuote :: String -> String
shellQuote s = "'" ++ concatMap (\c -> if c == '\'' then "'\\''" else [c]) s ++ "'"
