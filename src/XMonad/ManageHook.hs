-- Matching new windows, and what to do with them. The queries read the
-- snapshot the helper sent, so they describe macOS windows rather than X11
-- properties: see the module comments on each.
module XMonad.ManageHook
  ( className, resource, appName, title, subrole, queryInfo
  , (=?), (-->), (<&&>), (<||>), composeAll
  , doF, doIgnore, doShift, doFloat
  ) where
import XMonad.Core
import qualified XMonad.StackSet as W
import qualified Data.Map.Strict as M
import Data.List (find)
import Data.Maybe (fromMaybe)

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
  spot <- liftX (observedRect w)
  doF (W.float w spot)

observedRect :: Window -> X W.RationalRect
observedRect w = do
  s <- get
  pure $ fromMaybe centred $ do
    wi <- M.lookup w (windowInfo s)
    sc <- find ((==onDisplay wi) . displayID . W.screenDetail)
            (W.screens $ windowset s)
    let Rectangle sx sy sw sh = screenRect (W.screenDetail sc)
        Rectangle x y ww hh = frame wi
    if sw <= 0 || sh <= 0 then Nothing else Just $ W.RationalRect
      (toRational (x-sx) / toRational sw) (toRational (y-sy) / toRational sh)
      (toRational ww / toRational sw) (toRational hh / toRational sh)
  where centred = W.RationalRect (1/5) (1/5) (3/5) (3/5)
