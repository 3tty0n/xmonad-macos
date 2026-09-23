-- Adapted from xmonad-contrib XMonad.Util.ExtensibleState (BSD-3-Clause),
-- Copyright (c) Daniel Schoepe and the Xmonad Community.
-- Only the X monad is supported. PersistentExtension values ride in the
-- restart checkpoint instead of an X11 property.
module XMonad.Util.ExtensibleState
  ( put, modify, modifyM, modifyM', remove, get, gets, modified
  ) where
import Data.Maybe (fromMaybe)
import Data.Typeable (cast, typeOf)
import qualified Data.Map.Strict as M
import qualified Control.Monad.State.Strict as St
import XMonad.Core hiding (get, gets, modify, put)

modifyStateExts :: (M.Map String (Either String StateExtension)
                    -> M.Map String (Either String StateExtension)) -> X ()
modifyStateExts f = St.modify $ \s -> s {extensibleState=f (extensibleState s)}

modify :: ExtensionClass a => (a -> a) -> X ()
modify f = put . f =<< get

modifyM :: ExtensionClass a => (a -> X a) -> X ()
modifyM f = put =<< f =<< get

modifyM' :: ExtensionClass a => (a -> X a) -> X a
modifyM' f = do
  v <- f =<< get
  v <$ put v

put :: ExtensionClass a => a -> X ()
put v = modifyStateExts . M.insert (show . typeOf $ v) . Right . extensionType $ v

get :: ExtensionClass a => X a
get = getState' undefined
  where
    toValue val = fromMaybe initialValue (cast val)
    getState' :: ExtensionClass a => a -> X a
    getState' k = do
      v <- St.gets $ M.lookup (show . typeOf $ k) . extensibleState
      case v of
        Just (Right (StateExtension val)) -> pure (toValue val)
        Just (Right (PersistentExtension val)) -> pure (toValue val)
        Just (Left str) | PersistentExtension x <- extensionType k -> do
          let val = fromMaybe initialValue (cast . (`asTypeOf` x) =<< safeRead str)
          put (val `asTypeOf` k)
          pure val
        _ -> pure initialValue
    safeRead str = case reads str of
      [(x,"")] -> Just x
      _ -> Nothing

gets :: ExtensionClass a => (a -> b) -> X b
gets = flip fmap get

remove :: ExtensionClass a => a -> X ()
remove wit = modifyStateExts $ M.delete (show . typeOf $ wit)

modified :: (ExtensionClass a, Eq a) => (a -> a) -> X Bool
modified f = do
  v <- get
  case f v of
    v' | v' == v -> pure False
       | otherwise -> True <$ put v'
