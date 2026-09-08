{-# LANGUAGE ExistentialQuantification #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
-- LayoutClass/Message API derived from xmonad Core.hs (BSD-3-Clause).
-- The X11-dependent execution environment is replaced, not emulated.
module XMonad.Core
  ( module XMonad.Core, module XMonad.MacOS.Types
  , MonadIO(..), MonadState(..), MonadReader(..), gets, modify, asks
  , Endo(..), All(..), Typeable
  ) where
import XMonad.MacOS.Types
import qualified XMonad.StackSet as W
import Control.Monad.IO.Class
import Control.Monad.Reader
import Control.Monad.State.Strict
import qualified Control.Exception as E
import Data.Typeable
import Data.Monoid (Endo(..), All(..))
import qualified Data.Map.Strict as M
import qualified Data.Set as S
import System.IO (hPutStrLn, stderr)

type WindowSet = W.StackSet WorkspaceId (Layout Window) Window ScreenId ScreenDetail
-- The same aliases upstream uses, so signatures stay readable.
type WindowSpace = W.Workspace WorkspaceId (Layout Window) Window
type WindowScreen = W.Screen WorkspaceId (Layout Window) Window ScreenId ScreenDetail
newtype X a = X { unX :: ReaderT XConf (StateT XState IO) a }
  deriving (Functor, Applicative, Monad, MonadIO, MonadReader XConf, MonadState XState)
newtype Query a = Query { unQuery :: ReaderT Window X a }
  deriving (Functor, Applicative, Monad, MonadIO, MonadReader Window)
instance Semigroup a => Semigroup (Query a) where
  a <> b = (<>) <$> a <*> b
instance Monoid a => Monoid (Query a) where mempty = pure mempty

type ManageHook = Query (Endo WindowSet)
data XConfig l = XConfig
  { terminal :: String
  , modMask :: KeyMask
  , workspaces :: [WorkspaceId]
  , layoutHook :: l Window
  , keys :: XConfig Layout -> M.Map (KeyMask, KeySym) (X ())
  , manageHook :: ManageHook
  , startupHook :: X ()
  , logHook :: X ()
  }
data XConf = XConf { config :: XConfig Layout }
data NativeCommand = Close Window | Reload | Recompile | Quit | TogglePause
  deriving (Eq, Show)
data XState = XState
  { windowset :: WindowSet
  , windowInfo :: M.Map Window WindowInfo
  , ignoredWindows :: S.Set Window
  , generation :: Int
  , epoch :: Int
  , focusRequested :: Bool
  , focusAgeTicks :: Int
  , commands :: [NativeCommand]
  }
runX :: XConf -> XState -> X a -> IO (a, XState)
runX c s (X a) = runStateT (runReaderT a c) s
io :: IO a -> X a
io = liftIO
runQuery :: Query a -> Window -> X a
runQuery (Query q) = runReaderT q
liftX :: X a -> Query a
liftX = Query . lift
catchX :: X a -> X a -> X a
catchX action fallback = X $ ReaderT $ \c -> StateT $ \s ->
  runX c s action `E.catch` \e -> case E.fromException e :: Maybe E.AsyncException of
    Just async -> E.throwIO async
    Nothing -> hPutStrLn stderr ("xmonad-mac action failed: " ++ E.displayException (e :: E.SomeException))
               >> runX c s fallback
trace :: String -> X ()
trace = io . hPutStrLn stderr
whenJust :: Monad m => Maybe a -> (a -> m ()) -> m ()
whenJust = flip $ maybe (pure ())

-- The upstream layout interface, including stateful runLayout and messages.
data Layout a = forall l. (LayoutClass l a, Read (l a)) => Layout (l a)
readsLayout :: Layout a -> String -> [(Layout a, String)]
readsLayout (Layout l) s = [(Layout (asTypeOf x l), rest) | (x,rest) <- reads s]
class (Show (layout a), Typeable layout) => LayoutClass layout a where
  runLayout :: W.Workspace WorkspaceId (layout a) a -> Rectangle
            -> X ([(a,Rectangle)], Maybe (layout a))
  runLayout (W.Workspace _ l ms) r = maybe (emptyLayout l r) (doLayout l r) ms
  doLayout :: layout a -> Rectangle -> W.Stack a -> X ([(a,Rectangle)],Maybe (layout a))
  doLayout l r s = pure (pureLayout l r s, Nothing)
  pureLayout :: layout a -> Rectangle -> W.Stack a -> [(a,Rectangle)]
  pureLayout _ r s = [(W.focus s,r)]
  emptyLayout :: layout a -> Rectangle -> X ([(a,Rectangle)], Maybe (layout a))
  emptyLayout _ _ = pure ([],Nothing)
  handleMessage :: layout a -> SomeMessage -> X (Maybe (layout a))
  handleMessage l = pure . pureMessage l
  pureMessage :: layout a -> SomeMessage -> Maybe (layout a)
  pureMessage _ _ = Nothing
  description :: layout a -> String
  description = show
instance LayoutClass Layout Window where
  runLayout (W.Workspace t (Layout l) s) r = do
    (rs,ml) <- runLayout (W.Workspace t l s) r
    pure (rs, Layout <$> ml)
  handleMessage (Layout l) m = fmap Layout <$> handleMessage l m
  description (Layout l) = description l
instance Show (Layout a) where show (Layout l) = show l
class Typeable a => Message a
data SomeMessage = forall a. Message a => SomeMessage a
fromMessage :: Message a => SomeMessage -> Maybe a
fromMessage (SomeMessage a) = cast a
data LayoutMessages = Hide | ReleaseResources deriving (Eq, Show)
instance Message LayoutMessages
-- Only a lifecycle message, not a counterfeit X11 Event API.
data WindowRemoved = WindowRemoved Window deriving (Show)
instance Message WindowRemoved
