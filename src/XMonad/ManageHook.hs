module XMonad.ManageHook where
import XMonad.Core
import qualified XMonad.StackSet as W
import qualified Data.Map.Strict as M
import Data.List (find)
import Data.Maybe (fromMaybe)

queryInfo :: (WindowInfo -> a) -> a -> Query a
queryInfo f fallback = do
  w <- ask
  liftX $ gets (maybe fallback f . M.lookup w . windowInfo)
className, resource, appName, title :: Query String
className = queryInfo app ""
resource = queryInfo bundle ""
appName = resource
title = queryInfo titleText ""
(=?) :: Eq a => Query a -> a -> Query Bool
q =? v = (==v) <$> q
infix 4 =?
(-->) :: Query Bool -> ManageHook -> ManageHook
cond --> action = cond >>= \b -> if b then action else mempty
infixr 0 -->
(<&&>), (<||>) :: Query Bool -> Query Bool -> Query Bool
(<&&>) = liftA2Q (&&)
(<||>) = liftA2Q (||)
infixr 3 <&&>
infixr 2 <||>
liftA2Q :: (a -> b -> c) -> Query a -> Query b -> Query c
liftA2Q f a b = f <$> a <*> b
composeAll :: [ManageHook] -> ManageHook
composeAll = mconcat
doF :: (WindowSet -> WindowSet) -> ManageHook
doF = pure . Endo
doIgnore :: ManageHook
doIgnore = ask >>= doF . W.delete
doShift :: WorkspaceId -> ManageHook
doShift t = ask >>= doF . W.shiftWin t
doFloat :: ManageHook
doFloat = do
  w <- ask
  rr <- liftX $ do
    s <- get
    let fallback = W.RationalRect (1/5) (1/5) (3/5) (3/5)
    pure $ fromMaybe fallback $ do
      wi <- M.lookup w (windowInfo s)
      sc <- find ((==onDisplay wi) . displayID . W.screenDetail) (W.screens $ windowset s)
      let Rectangle sx sy sw sh = screenRect (W.screenDetail sc)
          Rectangle x y ww hh = frame wi
      if sw <= 0 || sh <= 0 then Nothing else Just $ W.RationalRect
        (toRational (x-sx) / toRational sw) (toRational (y-sy) / toRational sh)
        (toRational ww / toRational sw) (toRational hh / toRational sh)
  doF (W.float w rr)
