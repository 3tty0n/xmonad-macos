-- Adapted from xmonad-contrib XMonad.Actions.DynamicWorkspaces (BSD-3-Clause),
-- Copyright (c) David Roundy and the Xmonad Community.
-- The XPConfig-taking entry points are not ported (no XMonad.Prompt): withWorkspace,
-- selectWorkspace, renameWorkspace, addWorkspacePrompt and appendWorkspacePrompt.
-- The non-prompt subset below is complete.
module XMonad.Actions.DynamicWorkspaces
  ( addWorkspace, appendWorkspace, addWorkspaceAt
  , addHiddenWorkspace, addHiddenWorkspaceAt
  , removeWorkspace, removeWorkspaceByTag
  , removeEmptyWorkspace, removeEmptyWorkspaceByTag
  , removeEmptyWorkspaceAfter, removeEmptyWorkspaceAfterExcept
  , renameWorkspaceByName
  , withNthWorkspace, toNthWorkspace
  , setWorkspaceIndex, withWorkspaceIndex, WorkspaceIndex
  ) where
import XMonad hiding (workspaces)
import qualified XMonad.StackSet as W
import XMonad.Util.WorkspaceCompare (getSortByIndex)
import qualified XMonad.Util.ExtensibleState as XS
import qualified Data.Map.Strict as Map
import Control.Monad (when)
import Data.List (find, nub)
import Data.Maybe (isNothing)

-- The workspace index is mapped to a workspace tag by the user and can be
-- updated.
type WorkspaceIndex = Int

-- | Internal dynamic state that stores a mapping between workspace indexes and
--   workspace tags. It persists across a helper restart.
newtype DynamicWorkspaceState =
  DynamicWorkspaceState { workspaceIndexMap :: Map.Map WorkspaceIndex WorkspaceId }
  deriving (Read, Show)

instance ExtensionClass DynamicWorkspaceState where
  initialValue = DynamicWorkspaceState Map.empty
  extensionType = PersistentExtension

-- | Set the index of the current workspace.
setWorkspaceIndex :: WorkspaceIndex -> X ()
setWorkspaceIndex widx = do
  wtag  <- gets (W.currentTag . windowset)
  wmap  <- XS.gets workspaceIndexMap
  XS.modify $ \s -> s { workspaceIndexMap = Map.insert widx wtag wmap }

-- | Run a "view a workspace" action on the workspace registered at an index.
withWorkspaceIndex :: (WorkspaceId -> WindowSet -> WindowSet) -> WorkspaceIndex -> X ()
withWorkspaceIndex job widx = do
  wtag <- ilookup widx
  maybe (return ()) (windows . job) wtag
  where
    ilookup idx = Map.lookup idx <$> XS.gets workspaceIndexMap

-- | Rename the current workspace to the given name, keeping its windows and its
--   registered index.
renameWorkspaceByName :: WorkspaceId -> X ()
renameWorkspaceByName w = do
  old <- gets (W.currentTag . windowset)
  windows $ \s -> let sett wk = wk { W.tag = w }
                      setscr scr = scr { W.workspace = sett $ W.workspace scr }
                      sets q = q { W.current = setscr $ W.current q }
                  in sets $ removeWorkspace' w s
  updateIndexMap old w
  where
    updateIndexMap oldIM newIM = do
      wmap <- XS.gets workspaceIndexMap
      XS.modify $ \s -> s { workspaceIndexMap =
        Map.map (\t -> if t == oldIM then newIM else t) wmap }

-- | Like 'withNthWorkspace' for an action that takes the tag rather than the
--   whole window set.
toNthWorkspace :: (WorkspaceId -> X ()) -> Int -> X ()
toNthWorkspace job wnum = do
  sort <- getSortByIndex
  ws <- gets (map W.tag . sort . W.workspaces . windowset)
  case drop wnum ws of
    (w:_) -> job w
    [] -> return ()

-- | Run a "view a workspace" action on the nth workspace, sorted the way the
--   config lists them.
withNthWorkspace :: (WorkspaceId -> WindowSet -> WindowSet) -> Int -> X ()
withNthWorkspace job wnum = do
  sort <- getSortByIndex
  ws <- gets (map W.tag . sort . W.workspaces . windowset)
  case drop wnum ws of
    (w:_) -> windows $ job w
    [] -> return ()

-- | Add a new workspace with the given name, or do nothing if a workspace with
--   that name already exists; then switch to it.
addWorkspace :: WorkspaceId -> X ()
addWorkspace = addWorkspaceAt (:)

-- | Same as 'addWorkspace', but adds the workspace to the end of the list.
appendWorkspace :: WorkspaceId -> X ()
appendWorkspace = addWorkspaceAt (flip (++) . return)

-- | Add a new workspace with the given name to the current list. The caller
--   supplies a function that inserts the new workspace at an arbitrary spot.
addWorkspaceAt :: (WindowSpace -> [WindowSpace] -> [WindowSpace]) -> WorkspaceId -> X ()
addWorkspaceAt add newtag = addHiddenWorkspaceAt add newtag >> windows (W.greedyView newtag)

-- | Add a new hidden workspace with the given name, or do nothing if a
--   workspace with that name already exists. The insertion function places it.
addHiddenWorkspaceAt :: (WindowSpace -> [WindowSpace] -> [WindowSpace]) -> WorkspaceId -> X ()
addHiddenWorkspaceAt add newtag =
  whenX (gets (not . W.tagMember newtag . windowset)) $ do
    l <- asks (layoutHook . config)
    windows (addHiddenWorkspace' add newtag l)

-- | Add a new hidden workspace with the given name, or do nothing if a
--   workspace with that name already exists.
addHiddenWorkspace :: WorkspaceId -> X ()
addHiddenWorkspace = addHiddenWorkspaceAt (:)

-- | Remove the current workspace if it contains no windows.
removeEmptyWorkspace :: X ()
removeEmptyWorkspace = gets (W.currentTag . windowset) >>= removeEmptyWorkspaceByTag

-- | Remove the current workspace. Its windows, if any, are merged into another
--   (hidden) workspace.
removeWorkspace :: X ()
removeWorkspace = gets (W.currentTag . windowset) >>= removeWorkspaceByTag

-- | Remove the workspace with the given tag if it contains no windows.
removeEmptyWorkspaceByTag :: WorkspaceId -> X ()
removeEmptyWorkspaceByTag t = whenX (isEmpty t) $ removeWorkspaceByTag t

-- | Remove the workspace with the given tag. When it is the current one, first
--   switch to the workspace it merges into.
removeWorkspaceByTag :: WorkspaceId -> X ()
removeWorkspaceByTag torem = do
  s <- gets windowset
  case W.hidden s of
    (w:_) -> do
      when (torem == W.currentTag s) $ windows $ W.view (W.tag w)
      windows $ removeWorkspace' torem
    _ -> return ()

-- | Remove the current workspace after an operation, if it becomes empty and
--   hidden. The operation may change workspace at most once.
removeEmptyWorkspaceAfter :: X () -> X ()
removeEmptyWorkspaceAfter = removeEmptyWorkspaceAfterExcept []

-- | Like 'removeEmptyWorkspaceAfter', but never removes a sticky workspace.
removeEmptyWorkspaceAfterExcept :: [WorkspaceId] -> X () -> X ()
removeEmptyWorkspaceAfterExcept sticky f = do
  before <- gets (W.currentTag . windowset)
  f
  after <- gets (W.currentTag . windowset)
  when (before /= after && before `notElem` sticky) $ removeEmptyWorkspaceByTag before

isEmpty :: WorkspaceId -> X Bool
isEmpty t = do
  wsl <- gets $ W.workspaces . windowset
  let mws = find (\ws -> W.tag ws == t) wsl
  return $ maybe True (isNothing . W.stack) mws

addHiddenWorkspace' :: (WindowSpace -> [WindowSpace] -> [WindowSpace])
                    -> WorkspaceId -> Layout Window -> WindowSet -> WindowSet
addHiddenWorkspace' add newtag l s@W.StackSet{ W.hidden = ws } =
  s { W.hidden = add (W.Workspace newtag l Nothing) ws }

-- | Remove the workspace with the given tag from the StackSet, if it exists.
--   All the windows in that workspace move to the current one.
removeWorkspace' :: WorkspaceId -> WindowSet -> WindowSet
removeWorkspace' torem s@W.StackSet{ W.current = scr@W.Screen{ W.workspace = wc }
                                  , W.hidden = hs }
  = let (xs, ys) = break ((== torem) . W.tag) hs
    in removeWorkspace'' xs ys
  where
    meld Nothing Nothing = Nothing
    meld x Nothing = x
    meld Nothing x = x
    meld (Just x) (Just y) = W.differentiate . nub $ W.integrate x ++ W.integrate y
    removeWorkspace'' xs (y:ys) =
      s { W.current = scr { W.workspace = wc { W.stack = meld (W.stack y) (W.stack wc) } }
        , W.hidden = xs ++ ys }
    removeWorkspace'' _ _ = s
