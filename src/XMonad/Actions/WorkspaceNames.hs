-- Adapted from xmonad-contrib XMonad.Actions.WorkspaceNames (BSD-3-Clause),
-- Copyright (c) Tim McIver and the Xmonad Community.
-- renameWorkspace needs Prompt and workspaceNamesEwmh needs EWMH; neither is
-- ported. Show the names in the menu bar with
-- @macMenuBarPP (workspaceNamesPP def)@.
module XMonad.Actions.WorkspaceNames
  ( workspaceNamesPP, getWorkspaceNames, getWorkspaceNames', getWorkspaceName
  , getCurrentWorkspaceName, setWorkspaceName, setCurrentWorkspaceName
  , swapTo, swapTo', swapWithCurrent
  ) where
import qualified Data.Map.Strict as M
import Data.Maybe (fromMaybe)
import XMonad.Actions.CycleWS (WSType(..), findWorkspace)
import qualified XMonad.Actions.SwapWorkspaces as Swap
import XMonad.Core
import XMonad.Hooks.StatusBar.PP (PP(..))
import XMonad.Operations (refresh, windows)
import XMonad.Util.Types (Direction1D)
import XMonad.Util.WorkspaceCompare (getSortByIndex)
import qualified XMonad.StackSet as W
import qualified XMonad.Util.ExtensibleState as XS

newtype WorkspaceNames = WorkspaceNames (M.Map WorkspaceId String)
  deriving (Read, Show)

instance ExtensionClass WorkspaceNames where
  initialValue = WorkspaceNames M.empty
  extensionType = PersistentExtension

-- The name of a workspace, if it has one.
getWorkspaceNames' :: X (WorkspaceId -> Maybe String)
getWorkspaceNames' = do
  WorkspaceNames m <- XS.get
  pure (`M.lookup` m)

-- The tag, followed by @:name@ when the workspace is named.
getWorkspaceNames :: X (WorkspaceId -> String)
getWorkspaceNames = do
  names <- getWorkspaceNames'
  pure $ \i -> i ++ maybe "" (':' :) (names i)

getWorkspaceName :: WorkspaceId -> X (Maybe String)
getWorkspaceName w = ($ w) <$> getWorkspaceNames'

getCurrentWorkspaceName :: X (Maybe String)
getCurrentWorkspaceName = getWorkspaceName =<< gets (W.currentTag . windowset)

-- An empty name removes the name.
setWorkspaceName :: WorkspaceId -> String -> X ()
setWorkspaceName w name = do
  XS.modify $ \(WorkspaceNames m) -> WorkspaceNames (store w name m)
  refresh

setCurrentWorkspaceName :: String -> X ()
setCurrentWorkspaceName name = do
  t <- gets (W.currentTag . windowset)
  setWorkspaceName t name

workspaceNamesPP :: PP -> X PP
workspaceNamesPP pp = do
  names <- getWorkspaceNames
  pure pp
    { ppCurrent = ppCurrent pp . names
    , ppVisible = ppVisible pp . names
    , ppHidden = ppHidden pp . names
    , ppHiddenNoWindows = ppHiddenNoWindows pp . names }

-- Swap the current workspace with the next or previous one, names included.
swapTo :: Direction1D -> X ()
swapTo dir = swapTo' dir AnyWS

swapTo' :: Direction1D -> WSType -> X ()
swapTo' dir which =
  findWorkspace getSortByIndex dir which 1 >>= swapWithCurrent

swapWithCurrent :: WorkspaceId -> X ()
swapWithCurrent t = do
  cur <- gets (W.currentTag . windowset)
  XS.modify $ \(WorkspaceNames m) ->
    let at w = fromMaybe "" (M.lookup w m)
    in WorkspaceNames (store t (at cur) (store cur (at t) m))
  windows (Swap.swapWithCurrent t)

store :: WorkspaceId -> String -> M.Map WorkspaceId String
      -> M.Map WorkspaceId String
store w name | null name = M.delete w
             | otherwise = M.insert w name
