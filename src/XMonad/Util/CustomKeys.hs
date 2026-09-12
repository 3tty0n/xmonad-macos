-- Adapted from xmonad-contrib XMonad.Util.CustomKeys (BSD-3-Clause),
-- Copyright (c) Valery V. Vorotyntsev and the Xmonad Community.
module XMonad.Util.CustomKeys (customKeys, customKeysFrom) where
import Control.Monad.Reader
import qualified Data.Map.Strict as M
import XMonad.Config (def)
import XMonad.Core

customKeys :: (XConfig Layout -> [(KeyMask, KeySym)])
           -> (XConfig Layout -> [((KeyMask, KeySym), X ())])
           -> XConfig Layout -> M.Map (KeyMask, KeySym) (X ())
customKeys = customKeysFrom def

customKeysFrom :: XConfig l
               -> (XConfig Layout -> [(KeyMask, KeySym)])
               -> (XConfig Layout -> [((KeyMask, KeySym), X ())])
               -> XConfig Layout -> M.Map (KeyMask, KeySym) (X ())
customKeysFrom conf dels ins c = runReader (customize conf dels ins) c

customize :: XConfig l
          -> (XConfig Layout -> [(KeyMask, KeySym)])
          -> (XConfig Layout -> [((KeyMask, KeySym), X ())])
          -> Reader (XConfig Layout) (M.Map (KeyMask, KeySym) (X ()))
customize conf dels ins = asks (keys conf) >>= deleteKeys dels >>= insertKeys ins

deleteKeys :: (XConfig Layout -> [(KeyMask, KeySym)])
           -> M.Map (KeyMask, KeySym) (X ())
           -> Reader (XConfig Layout) (M.Map (KeyMask, KeySym) (X ()))
deleteKeys dels kmap = asks dels >>= \ks -> pure (foldr M.delete kmap ks)

insertKeys :: (XConfig Layout -> [((KeyMask, KeySym), X ())])
           -> M.Map (KeyMask, KeySym) (X ())
           -> Reader (XConfig Layout) (M.Map (KeyMask, KeySym) (X ()))
insertKeys ins kmap = asks ins >>= \ks -> pure (foldr (uncurry M.insert) kmap ks)
