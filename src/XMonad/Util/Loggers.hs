-- Adapted from xmonad-contrib XMonad.Util.Loggers (BSD-3-Clause),
-- Copyright (c) 2007-2010 Spencer Janssen, Andrea Rossato and the Xmonad
-- Community. The urgency-aware variants (logTitles', TitlesFormat) are not
-- ported: macOS has no urgency hints, which is why StatusBar.PP omits ppUrgent
-- too. aumixVolume, battery and loadAvg are Linux tools; logCmd covers them
-- here, e.g. logCmd "pmset -g batt" or logCmd "uptime".
module XMonad.Util.Loggers
  ( Logger
  -- System
  , date, logCmd, logFileCount, maildirNew, maildirUnread
  -- What the helper last observed
  , logCurrent, logLayout, logTitle, logTitles, logClassname, logClassnames
  , logConst, logDefault, (.|)
  -- One display at a time
  , logCurrentOnScreen, logLayoutOnScreen, logWhenActive
  , logTitleOnScreen, logClassnameOnScreen
  , logTitlesOnScreen, logClassnamesOnScreen
  -- Formatting
  , onLogger, wrapL, fixedWidthL, logSp, padL, shortenL, xmobarColorL
  , Align(..)
  ) where
import XMonad.Core
import XMonad.Operations (withWindowSet)
import XMonad.Hooks.StatusBar.PP (wrap, pad, shorten, xmobarColor)
import XMonad.Util.Types (Align(..))
import qualified XMonad.StackSet as W
import qualified Data.Map.Strict as M
import qualified Control.Exception as E
import Data.List (find, isPrefixOf, isSuffixOf)
import Data.Maybe (fromMaybe)
import Data.Time (defaultTimeLocale, formatTime, getCurrentTime)
import System.Directory (getDirectoryContents)
import System.IO (hGetLine)
import System.Process (runInteractiveCommand)

-- A logger is an action producing a string, or Nothing when it has nothing to
-- show. This is exactly what PP's ppExtras takes, so any of these can go
-- straight into a bar's configuration.
type Logger = X (Maybe String)

-- The current date and time, formatted with strftime's directives.
date :: String -> Logger
date fmt = io $ Just . formatTime defaultTimeLocale fmt <$> getCurrentTime

-- The first line of a command's output. A command that fails, or prints
-- nothing, is not an error: the logger just says nothing.
logCmd :: String -> Logger
logCmd command = io $ do
  (_, out, _, _) <- runInteractiveCommand command
  let firstLine :: IO (Either E.SomeException String)
      firstLine = E.try (hGetLine out)
  either (const Nothing) Just <$> firstLine

-- How many entries of a directory match, or Nothing when none do.
logFileCount :: FilePath -> (String -> Bool) -> Logger
logFileCount directory matches = do
  names <- io (getDirectoryContents directory)
  pure $ case length (filter matches names) of
    0 -> Nothing
    n -> Just (show n)

maildirUnread :: FilePath -> Logger
maildirUnread mdir = logFileCount (mdir ++ "/cur/") (isSuffixOf ",")

maildirNew :: FilePath -> Logger
maildirNew mdir = logFileCount (mdir ++ "/new/") (not . isPrefixOf ".")

-- The snapshot only carries the windows the helper still reports, so one it
-- has dropped reads as an empty name rather than failing the whole bar.
observed :: (WindowInfo -> String) -> Window -> X String
observed field w = gets (maybe "" field . M.lookup w . windowInfo)

titleOf, classnameOf :: Window -> X String
titleOf = observed titleText
-- Upstream shows WM_CLASS, which is what an application calls itself. The
-- bundle identifier is the stable half of that on macOS, but the localized
-- display name is the half a person recognises in a bar.
classnameOf = observed app

logCurrent :: Logger
logCurrent = withWindowSet (pure . Just . W.currentTag)

logLayout :: Logger
logLayout = withWindowSet (pure . Just . layoutName . W.current)
  where layoutName = description . W.layout . W.workspace

logTitle :: Logger
logTitle = logFocusedWindow titleOf

logClassname :: Logger
logClassname = logFocusedWindow classnameOf

logTitlesOnScreen :: ScreenId -> (String -> String) -> (String -> String) -> Logger
logTitlesOnScreen sid focused unfocused =
  logWindowNamesOnScreen titleOf sid focused unfocused

logClassnamesOnScreen :: ScreenId -> (String -> String) -> (String -> String) -> Logger
logClassnamesOnScreen sid focused unfocused =
  logWindowNamesOnScreen classnameOf sid focused unfocused

logTitles :: (String -> String) -> (String -> String) -> Logger
logTitles focused unfocused = currentScreen >>= \sid ->
  logTitlesOnScreen sid focused unfocused

logClassnames :: (String -> String) -> (String -> String) -> Logger
logClassnames focused unfocused = currentScreen >>= \sid ->
  logClassnamesOnScreen sid focused unfocused

logTitleOnScreen :: ScreenId -> Logger
logTitleOnScreen = logFocusedWindowOnScreen titleOf

logClassnameOnScreen :: ScreenId -> Logger
logClassnameOnScreen = logFocusedWindowOnScreen classnameOf

logCurrentOnScreen :: ScreenId -> Logger
logCurrentOnScreen = withScreen (logConst . W.tag . W.workspace)

logLayoutOnScreen :: ScreenId -> Logger
logLayoutOnScreen =
  withScreen (logConst . description . W.layout . W.workspace)

-- Show this logger only while the given display is the active one.
logWhenActive :: ScreenId -> Logger -> Logger
logWhenActive sid logger = do
  active <- withWindowSet (pure . W.screen . W.current)
  if sid == active then logger else pure Nothing

logConst :: String -> Logger
logConst = pure . Just

-- Fall back to the second logger when the first has nothing to show.
logDefault :: Logger -> Logger -> Logger
logDefault logger fallback = logger >>= maybe fallback logConst

(.|) :: Logger -> Logger -> Logger
(.|) = logDefault

logFocusedWindow :: (Window -> X String) -> Logger
logFocusedWindow field = withWindowSet (traverse field . W.peek)

-- Every window on the display's workspace, focused one marked, in stack order.
logWindowNamesOnScreen
  :: (Window -> X String) -> ScreenId -> (String -> String) -> (String -> String) -> Logger
logWindowNamesOnScreen field sid focused unfocused = withScreen render sid
  where
    render screen = do
      let stack = W.stack (W.workspace screen)
          windows = maybe [] W.integrate stack
      names <- traverse field windows
      pure . Just . unwords $
        zipWith (\w n -> if Just w == (W.focus <$> stack) then focused n else unfocused n)
                windows names

logFocusedWindowOnScreen :: (Window -> X String) -> ScreenId -> Logger
logFocusedWindowOnScreen field =
  withScreen (traverse field . (W.focus <$>) . W.stack . W.workspace)

withScreen :: (WindowScreen -> Logger) -> ScreenId -> Logger
withScreen f sid = do
  screens <- withWindowSet (pure . W.screens)
  case find ((== sid) . W.screen) screens of
    Just screen -> f screen
    Nothing -> pure Nothing

currentScreen :: X ScreenId
currentScreen = withWindowSet (pure . W.screen . W.current)

-- Format a logger's output, or format nothing when it has none.
onLogger :: (String -> String) -> Logger -> Logger
onLogger = fmap . fmap

wrapL :: String -> String -> Logger -> Logger
wrapL left right = onLogger (wrap left right)

-- Pad to a fixed width, so a title that grows and shrinks does not move the
-- rest of the bar. Padding is cycled, and reversed on the left of the centre.
fixedWidthL :: Align -> String -> Int -> Logger -> Logger
fixedWidthL align padding width logger = do
  value <- logger
  let text = fromMaybe "" value
      cycle' = cycle padding
      half = reverse (take ((width - length text) `div` 2) cycle')
  pure . Just $ case align of
    AlignCenter -> take width (half ++ text ++ cycle')
    AlignRight -> reverse (take width (reverse text ++ cycle'))
    AlignLeft -> take width (text ++ cycle')

logSp :: Int -> Logger
logSp n = pure . Just . take n $ cycle " "

padL :: Logger -> Logger
padL = onLogger pad

shortenL :: Int -> Logger -> Logger
shortenL = onLogger . shorten

xmobarColorL :: String -> String -> Logger -> Logger
xmobarColorL foreground background = onLogger (xmobarColor foreground background)
