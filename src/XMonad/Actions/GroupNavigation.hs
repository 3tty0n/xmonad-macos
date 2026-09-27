-- Adapted from xmonad-contrib XMonad.Actions.GroupNavigation (BSD-3-Clause),
-- Copyright (c) nzeh@cs.dal.ca and the Xmonad Community.
-- deepseq is not a dependency here, so historyHook stores the history as-is
-- rather than a forced value; keysyms and the Window type come from
-- XMonad.Core instead of Graphics.X11.Types.
module XMonad.Actions.GroupNavigation
  ( Direction(..)
  , nextMatch
  , nextMatchOrDo
  , nextMatchWithThis
  , historyHook
  , isOnAnyVisibleWS
  ) where
import Control.Monad ((>=>))
import qualified Data.List as L
import Data.Map ((!))
import qualified Data.Map as Map
import Data.Sequence (Seq, ViewL(EmptyL, (:<)), viewl, (<|), (><), (|>))
import qualified Data.Sequence as Seq
import qualified Data.Set as Set
import XMonad.Core
import XMonad.ManageHook
import XMonad.Operations (windows, withFocused, withWindowSet)
import qualified XMonad.StackSet as SS
import qualified XMonad.Util.ExtensibleState as XS

-- Basic cyclic navigation based on queries -------------------------

-- | The direction in which to look for the next match.
data Direction = Forward  -- ^ Forward from current window or workspace
               | Backward -- ^ Backward from current window or workspace
               | History  -- ^ Backward in history

-- | Focuses the next window for which the given query produces the same
-- result as the currently focused window. Does nothing if there is no
-- focused window (i.e., the current workspace is empty).
nextMatchWithThis :: Eq a => Direction -> Query a -> X ()
nextMatchWithThis dir qry = withFocused $ \win -> do
  prop <- runQuery qry win
  nextMatch dir (qry =? prop)

-- | Focuses the next window that matches the given boolean query. Does
-- nothing if there is no such window. This is the same as 'nextMatchOrDo'
-- with alternate action @return ()@.
nextMatch :: Direction -> Query Bool -> X ()
nextMatch dir qry = nextMatchOrDo dir qry (return ())

-- | Focuses the next window that matches the given boolean query. If there
-- is no such window, perform the given action instead.
nextMatchOrDo :: Direction -> Query Bool -> X () -> X ()
nextMatchOrDo dir qry act = orderedWindowList dir
                            >>= focusNextMatchOrDo qry act

-- Produces the action to perform depending on whether there is a matching
-- window.
focusNextMatchOrDo :: Query Bool -> X () -> Seq Window -> X ()
focusNextMatchOrDo qry act = findM (runQuery qry)
                             >=> maybe act (windows . SS.focusWindow)

-- Returns the list of windows ordered by workspace as specified in
-- @xmonad.hs@.
orderedWindowList :: Direction -> X (Seq Window)
orderedWindowList History = fmap (\(HistoryDB w ws) -> maybe ws (ws |>) w) XS.get
orderedWindowList dir     = withWindowSet $ \ss -> do
  wsids <- asks (Seq.fromList . workspaces . config)
  let wspcs = orderedWorkspaceList ss wsids
      wins  = dirfun dir
              $ L.foldl' (><) Seq.empty
              $ fmap (Seq.fromList . SS.integrate' . SS.stack) wspcs
      cur   = SS.peek ss
  return $ maybe wins (rotfun wins) cur
  where
    dirfun Backward = Seq.reverse
    dirfun _        = id
    rotfun wins x   = rotate $ rotateTo (== x) wins

-- Returns the ordered workspace list as specified in @xmonad.hs@.
orderedWorkspaceList :: WindowSet -> Seq String -> Seq WindowSpace
orderedWorkspaceList ss wsids = rotateTo isCurWS wspcs'
    where
      wspcs      = SS.workspaces ss
      wspcsMap   = L.foldl' (\m ws -> Map.insert (SS.tag ws) ws m) Map.empty wspcs
      wspcs'     = fmap (wspcsMap !) wsids
      isCurWS ws = SS.tag ws == SS.tag (SS.workspace $ SS.current ss)

-- History navigation -------------------------------------------------

-- The state extension that holds the history information.
data HistoryDB = HistoryDB (Maybe Window) -- currently focused window
                           (Seq Window)   -- previously focused windows
               deriving (Read, Show)

instance ExtensionClass HistoryDB where
    initialValue  = HistoryDB Nothing Seq.empty
    extensionType = PersistentExtension

-- | Action that needs to be executed as a logHook to maintain the focus
-- history of all windows as the WindowSet changes.
historyHook :: X ()
historyHook = XS.put =<< updateHistory =<< XS.get

-- Updates the history in response to a WindowSet change.
updateHistory :: HistoryDB -> X HistoryDB
updateHistory (HistoryDB oldcur oldhist) = withWindowSet $ \ss ->
  let newcur   = SS.peek ss
      wins     = Set.fromList $ SS.allWindows ss
      newhist  = Seq.filter (`Set.member` wins) (ins oldcur oldhist)
  in pure $ HistoryDB newcur (del newcur newhist)
  where
    ins x xs = maybe xs (<| xs) x
    del x xs = maybe xs (\x' -> Seq.filter (/= x') xs) x

-- Some sequence helpers ----------------------------------------------

-- Rotates the sequence by one position.
rotate :: Seq a -> Seq a
rotate xs = rotate' (viewl xs)
  where
    rotate' EmptyL      = Seq.empty
    rotate' (x' :< xs') = xs' |> x'

-- Rotates the sequence until an element matching the given condition is at
-- the beginning of the sequence.
rotateTo :: (a -> Bool) -> Seq a -> Seq a
rotateTo cond xs = let (lxs, rxs) = Seq.breakl cond xs in rxs >< lxs

-- A monadic find ------------------------------------------------------

-- Applies the given action to every sequence element in turn until the first
-- element is found for which the action returns true. The remaining elements
-- in the sequence are ignored.
findM :: Monad m => (a -> m Bool) -> Seq a -> m (Maybe a)
findM cond xs = findM' cond (viewl xs)
  where
    findM' _   EmptyL      = return Nothing
    findM' qry (x' :< xs') = do
      isMatch <- qry x'
      if isMatch
        then return (Just x')
        else findM qry xs'

-- Utilities -----------------------------------------------------------

-- | A query that matches all unfocused windows on visible workspaces. This
-- is useful for configurations with multiple screens, and matches even
-- invisible windows.
isOnAnyVisibleWS :: Query Bool
isOnAnyVisibleWS = do
  w <- ask
  ws <- liftX $ gets windowset
  let allVisible = concatMap (maybe [] SS.integrate . SS.stack . SS.workspace) (SS.current ws:SS.visible ws)
      visibleWs = w `elem` allVisible
      unfocused = Just w /= SS.peek ws
  return $ visibleWs && unfocused
