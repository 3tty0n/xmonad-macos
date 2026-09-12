-- Matching new windows, and what to do with them. The queries read the
-- snapshot the helper sent, so they describe macOS windows rather than X11
-- properties: see the module comments on each.
module XMonad.ManageHook
  ( className, resource, appName, title, subrole, queryInfo
  , (=?), (-->), (<&&>), (<||>), (<+>), composeAll, idHook
  , doF, doIgnore, doShift, doFloat
  ) where
import XMonad.Core
import XMonad.Operations (floatLocation)
import qualified XMonad.StackSet as W
import qualified Data.Map.Strict as M

-- Read one field of the window's snapshot entry, with a value to use for a
-- window we have no entry for.
queryInfo :: (WindowInfo -> a) -> a -> Query a
queryInfo f fallback = do
  w <- ask
  liftX $ gets (maybe fallback f . M.lookup w . windowInfo)

-- className is the application's display name, which is localized; resource
-- and appName are its bundle identifier, which is not. title is AXTitle.
-- subrole is the AX subrole (AXStandardWindow, AXDialog, ...).
className, resource, appName, title, subrole :: Query String
className = queryInfo app ""
resource = queryInfo bundle ""
appName = resource
title = queryInfo titleText ""
subrole = queryInfo subroleText "AXStandardWindow"

(=?) :: Eq a => Query a -> a -> Query Bool
q =? v = (==v) <$> q
infix 4 =?

(-->) :: Query Bool -> ManageHook -> ManageHook
cond --> action = cond >>= \matched -> if matched then action else mempty
infixr 0 -->

(<&&>), (<||>) :: Query Bool -> Query Bool -> Query Bool
(<&&>) = liftQ2 (&&)
(<||>) = liftQ2 (||)
infixr 3 <&&>
infixr 2 <||>

liftQ2 :: (a -> b -> c) -> Query a -> Query b -> Query c
liftQ2 f a b = f <$> a <*> b

idHook :: ManageHook
idHook = mempty

(<+>) :: ManageHook -> ManageHook -> ManageHook
(<+>) = mappend
infixr 1 <+>

composeAll :: [ManageHook] -> ManageHook
composeAll = mconcat

doF :: (WindowSet -> WindowSet) -> ManageHook
doF = pure . Endo

-- Removing the window from the set is how a hook says "not mine": the engine
-- remembers it and stops adopting it.
doIgnore :: ManageHook
doIgnore = ask >>= doF . W.delete

doShift :: WorkspaceId -> ManageHook
doShift t = ask >>= doF . W.shiftWin t

-- Float the window where it already is, so an app that positions its own
-- windows keeps that position. A window we cannot place gets a centred fifth.
doFloat :: ManageHook
doFloat = do
  w <- ask
  spot <- liftX (floatLocation w)
  doF (W.float w spot)
