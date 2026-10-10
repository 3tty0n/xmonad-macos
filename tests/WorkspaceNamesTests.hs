-- Tests for XMonad.Actions.WorkspaceNames: naming, the PP transformation that
-- feeds the menu bar, and swapping names along with workspaces.
module WorkspaceNamesTests (runWorkspaceNamesTests) where
import XMonad
import XMonad.Actions.WorkspaceNames
import XMonad.Hooks.StatusBar (StatusBarConfig(..), macMenuBarPP)
import XMonad.Hooks.StatusBar.PP
import XMonad.MacOS.Engine (initialState)
import XMonad.Util.Types (Direction1D(..))
import Control.Monad (unless)
import Data.List (isInfixOf)

check :: String -> Bool -> IO ()
check name ok = unless ok $ ioError $ userError ("FAIL: " ++ name)

cfg :: XConfig Layout
cfg = def { layoutHook = Layout (layoutHook def), workspaces = ["1","2","3"] }

conf :: XConf
conf = XConf cfg

start :: XState
start = initialState cfg [DisplayInfo 10 (Rectangle 0 24 1000 800)]

runWorkspaceNamesTests :: IO ()
runWorkspaceNamesTests = do
  ((n2, cur, n3, tagged), st) <- runX conf start $ do
    setWorkspaceName "2" "web"
    setCurrentWorkspaceName "main"
    (,,,) <$> getWorkspaceName "2" <*> getCurrentWorkspaceName
          <*> getWorkspaceName "3" <*> (($ "2") <$> getWorkspaceNames)
  check "names are stored per workspace" (n2 == Just "web" && cur == Just "main")
  check "unnamed workspaces have no name" (n3 == Nothing)
  check "getWorkspaceNames appends the name to the tag" (tagged == "2:web")
  (cleared, _) <- runX conf st $ do
    setWorkspaceName "2" ""
    getWorkspaceName "2"
  check "an empty name clears it" (cleared == Nothing)

  (out, _) <- runX conf st (workspaceNamesPP def {ppHiddenNoWindows = id} >>= dynamicLogString)
  check "the PP shows names" ("[1:main]" `isInfixOf` out && "2:web" `isInfixOf` out)
  (_, menu) <- runX conf st (sbLogHook (macMenuBarPP (workspaceNamesPP def)))
  check "the menu bar text carries the names"
    (maybe False ("1:main" `isInfixOf`) (menuBarText menu))

  (_, swapped) <- runX conf st (swapWithCurrent "2")
  (sw, _) <- runX conf swapped $
    (,) <$> getWorkspaceName "1" <*> getWorkspaceName "2"
  check "swapWithCurrent swaps the names" (sw == (Just "web", Just "main"))
  (_, nxt) <- runX conf st (swapTo Next)
  (nw, _) <- runX conf nxt $
    (,) <$> getWorkspaceName "1" <*> getWorkspaceName "2"
  check "swapTo swaps with the next workspace" (nw == (Just "web", Just "main"))
