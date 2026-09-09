{-# LANGUAGE OverloadedStrings #-}
-- The NDJSON contract with the native helper: what it tells us about the
-- world, and what we tell it to do. docs/PROTOCOL.md is the reference.
module XMonad.MacOS.Protocol where
import XMonad.Core
import Data.Aeson
import Data.Aeson.Types (Parser)

-- One observation of every managed window, and the displays they are on.
data Snapshot = Snapshot
  { snapGeneration :: Int, snapEpoch :: Int, snapDisplays :: [DisplayInfo]
  , snapWindows :: [WindowInfo], snapFocused :: Maybe Window
  , snapRestore :: Maybe Value
  } deriving (Show)
-- Everything the helper can send us.
data InputEvent
  = SnapshotEvent Snapshot     -- the world changed
  | KeyEvent KeyMask KeySym    -- a bound key was pressed
  | MouseFloatEvent Window     -- a mod-drag started on this window
  | PingEvent                  -- liveness check
  | ExitEvent                  -- shut down
  deriving (Show)
instance FromJSON InputEvent where
  parseJSON = withObject "InputEvent" $ \o -> do
    t <- o .: "type" :: Parser String
    case t of
      "snapshot" -> SnapshotEvent <$> (Snapshot
        <$> o .: "generation" <*> o .: "epoch" <*> o .: "screens"
        <*> o .: "windows" <*> o .:? "focused" <*> o .:? "restore")
      "key" -> KeyEvent <$> o .: "mask" <*> o .: "sym"
      "mouseFloat" -> MouseFloatEvent <$> o .: "wid"
      "ping" -> pure PingEvent
      "exit" -> pure ExitEvent
      _ -> fail $ "Unknown input type: " ++ t

-- One entry per workspace, in config order, for a status bar.
data WorkspaceInfo = WorkspaceInfo
  { wsTag :: String, wsWindows :: Int, wsCurrent :: Bool, wsVisible :: Bool }
  deriving (Show,Eq)
instance ToJSON WorkspaceInfo where
  toJSON w = object ["tag" .= wsTag w,"windows" .= wsWindows w
                    ,"current" .= wsCurrent w,"visible" .= wsVisible w]
data Placement = Placement Window Rectangle deriving (Show,Eq)
instance ToJSON Placement where
  toJSON (Placement w r) = object ["wid" .= w,"frame" .= r]
-- What the helper should make true: place these, hide the rest, focus at most
-- one, and show this workspace row.
data Plan = Plan
  { planGeneration :: Int, planEpoch :: Int
  , planFrames :: [Placement], planHide :: [Window], planFocus :: Maybe Window
  , planWorkspace :: String, planLayout :: String, planCheckpoint :: Value
  -- The display the current screen sits on, so the helper can follow it.
  , planScreen :: Int
  , planWorkspaces :: [WorkspaceInfo]
  } deriving (Show)
instance ToJSON Plan where
  toJSON p = object
    ["type" .= ("plan" :: String),"generation" .= planGeneration p,"epoch" .= planEpoch p
    ,"frames" .= planFrames p,"hide" .= planHide p,"focus" .= planFocus p
    ,"workspace" .= planWorkspace p,"layout" .= planLayout p,"checkpoint" .= planCheckpoint p
    ,"screen" .= planScreen p
    ,"workspaces" .= planWorkspaces p]
commandJSON :: NativeCommand -> Value
commandJSON c = case c of
  Close w -> object ["type" .= ("command" :: String),"name" .= ("close" :: String),"wid" .= w]
  Reload -> named "reload"
  Recompile -> named "recompile"
  Quit -> named "quit"
  TogglePause -> named "pause"
  where named n = object ["type" .= ("command" :: String),"name" .= (n :: String)]
