{-# LANGUAGE OverloadedStrings #-}
module XMonad.MacOS.Protocol where
import XMonad.Core
import Data.Aeson
import Data.Aeson.Types (Parser)

data Snapshot = Snapshot
  { snapGeneration :: Int, snapEpoch :: Int, snapDisplays :: [DisplayInfo]
  , snapWindows :: [WindowInfo], snapFocused :: Maybe Window
  , snapRestore :: Maybe Value
  } deriving (Show)
data InputEvent = SnapshotEvent Snapshot | KeyEvent KeyMask KeySym | MouseFloatEvent Window | PingEvent | ExitEvent
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
data Plan = Plan
  { planGeneration :: Int, planEpoch :: Int
  , planFrames :: [Placement], planHide :: [Window], planFocus :: Maybe Window
  , planWorkspace :: String, planLayout :: String, planCheckpoint :: Value
  , planWorkspaces :: [WorkspaceInfo]
  } deriving (Show)
instance ToJSON Plan where
  toJSON p = object
    ["type" .= ("plan" :: String),"generation" .= planGeneration p,"epoch" .= planEpoch p
    ,"frames" .= planFrames p,"hide" .= planHide p,"focus" .= planFocus p
    ,"workspace" .= planWorkspace p,"layout" .= planLayout p,"checkpoint" .= planCheckpoint p
    ,"workspaces" .= planWorkspaces p]
commandJSON :: NativeCommand -> Value
commandJSON c = case c of
  Close w -> object ["type" .= ("command" :: String),"name" .= ("close" :: String),"wid" .= w]
  Reload -> named "reload"
  Recompile -> named "recompile"
  Quit -> named "quit"
  TogglePause -> named "pause"
  where named n = object ["type" .= ("command" :: String),"name" .= (n :: String)]
