{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE PatternGuards #-}
-- Upstream-derived XMonad.StackSet; adapted code, comments abridged. BSD-3-Clause.
-- Copyright (c) Don Stewart 2007; The Xmonad Community.
-- Source: xmonad/xmonad a9a8b5c1b91b63b0836f5810634c9b28ec0af788.
module XMonad.StackSet
  ( StackSet(..), Workspace(..), Screen(..), Stack(..), RationalRect(..)
  , new, view, greedyView, lookupWorkspace, screens, workspaces, allWindows
  , currentTag, peek, index, integrate, integrate', differentiate
  , focusUp, focusDown, focusUp', focusDown', focusMaster, focusWindow
  , tagMember, renameTag, ensureTags, member, findTag, mapWorkspace, mapLayout
  , insertUp, delete, delete', filter, swapUp, swapDown, swapMaster, shiftMaster
  , modify, modify', float, sink, shift, shiftWin, abort
  ) where

import Prelude hiding (filter)
import Control.Applicative.Backwards (Backwards(..))
import Data.Foldable (toList)
import Data.Maybe (listToMaybe, isJust, fromMaybe)
import qualified Data.List as L
import Data.List ((\\))
import qualified Data.List.NonEmpty as NE
import Data.List.NonEmpty (NonEmpty((:|)))
import qualified Data.Map as M

data StackSet i l a sid sd = StackSet
  { current :: !(Screen i l a sid sd)
  , visible :: [Screen i l a sid sd]
  , hidden :: [Workspace i l a]
  , floating :: M.Map a RationalRect
  } deriving (Show, Read, Eq)
data Screen i l a sid sd = Screen
  { workspace :: !(Workspace i l a), screen :: !sid, screenDetail :: !sd
  } deriving (Show, Read, Eq)
data Workspace i l a = Workspace
  { tag :: !i, layout :: l, stack :: Maybe (Stack a)
  } deriving (Show, Read, Eq)
data RationalRect = RationalRect !Rational !Rational !Rational !Rational
  deriving (Show, Read, Eq)
data Stack a = Stack { focus :: !a, up :: [a], down :: [a] }
  deriving (Show, Read, Eq, Functor)
instance Foldable Stack where
  toList = integrate
  foldr f z = foldr f z . toList
instance Traversable Stack where
  traverse f s = flip Stack
    <$> forwards (traverse (Backwards . f) (up s))
    <*> f (focus s) <*> traverse f (down s)

-- Construction and screens -------------------------------------------------

abort :: String -> a
abort x = error $ "xmonad: StackSet: " ++ x

new :: Integral s => l -> [i] -> [sd] -> StackSet i l a s sd
new l (wid:wids) (m:ms) | length ms <= length wids =
  StackSet cur visi (map ws unseen) M.empty
  where
    ws i = Workspace i l Nothing
    (seen, unseen) = L.splitAt (length ms) wids
    cur :| visi = Screen (ws wid) 0 m :|
      [Screen (ws i) s sd | (i,s,sd) <- zip3 seen [1..] ms]
new _ _ _ = abort "non-positive argument to StackSet.new"

-- Viewing workspaces ---------------------------------------------------------

-- Show workspace i on the current screen. A workspace already on another
-- screen is reached by moving there; a hidden one swaps with the current.
view :: (Eq s, Eq i) => i -> StackSet i l a s sd -> StackSet i l a s sd
view i s
  | i == currentTag s = s
  | Just x <- L.find ((i==) . tag . workspace) (visible s) =
      s { current = x, visible = current s : L.deleteBy (equating screen) x (visible s) }
  | Just x <- L.find ((i==) . tag) (hidden s) =
      s { current = (current s) {workspace = x}
        , hidden = workspace (current s) : L.deleteBy (equating tag) x (hidden s) }
  | otherwise = s
  where equating f x y = f x == f y

-- Like view, except that a workspace on another screen is dragged to this
-- one, swapping the two screens' workspaces.
greedyView :: (Eq s, Eq i) => i -> StackSet i l a s sd -> StackSet i l a s sd
greedyView w ws
  | any wTag (hidden ws) = view w ws
  | Just s <- L.find (wTag . workspace) (visible ws) =
      ws { current = (current ws) {workspace = workspace s}
         , visible = s {workspace = workspace (current ws)}
           : L.filter (not . wTag . workspace) (visible ws) }
  | otherwise = ws
  where wTag = (w==) . tag
lookupWorkspace :: Eq s => s -> StackSet i l a s sd -> Maybe i
lookupWorkspace sc w = listToMaybe
  [tag i | Screen i s _ <- current w : visible w, s == sc]
with :: b -> (Stack a -> b) -> StackSet i l a s sd -> b
with d f = maybe d f . stack . workspace . current

modify :: Maybe (Stack a) -> (Stack a -> Maybe (Stack a))
       -> StackSet i l a s sd -> StackSet i l a s sd
modify d f s = s {current = (current s)
  {workspace = (workspace (current s)) {stack = with d f s}}}
modify' :: (Stack a -> Stack a) -> StackSet i l a s sd -> StackSet i l a s sd
modify' f = modify Nothing (Just . f)

-- The focused window of the current workspace, if any.
peek :: StackSet i l a s sd -> Maybe a
peek = with Nothing (Just . focus)

-- A stack read in screen order: windows above focus, focus, then below.
integrate :: Stack a -> [a]
integrate (Stack x l r) = reverse l ++ x:r

integrate' :: Maybe (Stack a) -> [a]
integrate' = maybe [] integrate

differentiate :: [a] -> Maybe (Stack a)
differentiate [] = Nothing
differentiate (x:xs) = Just $ Stack x [] xs

filter :: (a -> Bool) -> Stack a -> Maybe (Stack a)
filter p (Stack f ls rs) = case L.filter p (f:rs) of
  f':rs' -> Just $ Stack f' (L.filter p ls) rs'
  [] -> case L.filter p ls of
    f':ls' -> Just $ Stack f' ls' []
    [] -> Nothing
index :: StackSet i l a s sd -> [a]
index = with [] integrate

-- Focus and order -------------------------------------------------------------

focusUp, focusDown, swapUp, swapDown :: StackSet i l a s sd -> StackSet i l a s sd
focusUp = modify' focusUp'
focusDown = modify' focusDown'
swapUp = modify' swapUp'
swapDown = modify' (reverseStack . swapUp' . reverseStack)

focusUp' :: Stack a -> Stack a
focusUp' (Stack t (l:ls) rs) = Stack l ls (t:rs)
focusUp' (Stack t [] rs) = Stack x xs [] where x :| xs = NE.reverse (t :| rs)

focusDown' :: Stack a -> Stack a
focusDown' = reverseStack . focusUp' . reverseStack

swapUp' :: Stack a -> Stack a
swapUp' (Stack t (l:ls) rs) = Stack t ls (l:rs)
swapUp' (Stack t [] rs) = Stack t (reverse rs) []

reverseStack :: Stack a -> Stack a
reverseStack (Stack t ls rs) = Stack t rs ls

focusWindow :: (Eq s, Eq a, Eq i) => a -> StackSet i l a s sd -> StackSet i l a s sd
focusWindow w s
  | Just w == peek s = s
  | otherwise = fromMaybe s $ do
      n <- findTag w s
      pure $ until ((Just w ==) . peek) focusUp (view n s)
screens :: StackSet i l a s sd -> [Screen i l a s sd]
screens s = current s : visible s

workspaces :: StackSet i l a s sd -> [Workspace i l a]
workspaces s = workspace (current s) : map workspace (visible s) ++ hidden s

allWindows :: Eq a => StackSet i l a s sd -> [a]
allWindows = L.nub . concatMap (integrate' . stack) . workspaces

currentTag :: StackSet i l a s sd -> i
currentTag = tag . workspace . current

tagMember :: Eq i => i -> StackSet i l a s sd -> Bool
tagMember t = elem t . map tag . workspaces

renameTag :: Eq i => i -> i -> StackSet i l a s sd -> StackSet i l a s sd
renameTag o n = mapWorkspace $ \w -> if tag w == o then w {tag=n} else w

ensureTags :: Eq i => l -> [i] -> StackSet i l a s sd -> StackSet i l a s sd
ensureTags l allt st = et allt (map tag (workspaces st) \\ allt) st where
  et [] _ s = s
  et (i:is) rn s | i `tagMember` s = et is rn s
  et (i:is) [] s = et is [] (s {hidden = Workspace i l Nothing : hidden s})
  et (i:is) (r:rs) s = et is rs $ renameTag r i s
mapWorkspace :: (Workspace i l a -> Workspace i l a)
             -> StackSet i l a s sd -> StackSet i l a s sd
mapWorkspace f s = s
  {current=upd (current s), visible=map upd (visible s), hidden=map f (hidden s)}
  where upd sc = sc {workspace=f (workspace sc)}
mapLayout :: (l -> l') -> StackSet i l a s sd -> StackSet i l' a s sd
mapLayout f (StackSet v vs hs m) = StackSet (fs v) (map fs vs) (map fw hs) m
  where fs (Screen ws s sd) = Screen (fw ws) s sd
        fw (Workspace t l s) = Workspace t (f l) s
member :: Eq a => a -> StackSet i l a s sd -> Bool
member a = isJust . findTag a

findTag :: Eq a => a -> StackSet i l a s sd -> Maybe i
findTag a s = listToMaybe
  [tag w | w <- workspaces s, a `elem` integrate' (stack w)]
-- Adding, removing and moving windows -----------------------------------------

-- A new window goes above the focused one and takes focus.
insertUp :: Eq a => a -> StackSet i l a s sd -> StackSet i l a s sd
insertUp a s | member a s = s
             | otherwise = modify (Just $ Stack a [] [])
                 (\(Stack t l r) -> Just $ Stack a l (t:r)) s
delete :: Ord a => a -> StackSet i l a s sd -> StackSet i l a s sd
delete w = sink w . delete' w

delete' :: Eq a => a -> StackSet i l a s sd -> StackSet i l a s sd
delete' w = mapWorkspace $ \ws -> ws {stack = stack ws >>= filter (/=w)}

-- Floating geometry is relative to its screen, so it survives a resolution
-- change or a move to another display.
float :: Ord a => a -> RationalRect -> StackSet i l a s sd -> StackSet i l a s sd
float w r s = s {floating=M.insert w r (floating s)}

sink :: Ord a => a -> StackSet i l a s sd -> StackSet i l a s sd
sink w s = s {floating=M.delete w (floating s)}

swapMaster, shiftMaster, focusMaster :: StackSet i l a s sd -> StackSet i l a s sd
swapMaster = modify' $ \c -> case c of
  Stack _ [] _ -> c
  Stack t (l:ls) rs -> Stack t [] (xs ++ x:rs) where x :| xs = NE.reverse (l :| ls)
shiftMaster = modify' $ \c -> case c of
  Stack _ [] _ -> c
  Stack t ls rs -> Stack t [] (reverse ls ++ rs)
focusMaster = modify' $ \c -> case c of
  Stack _ [] _ -> c
  Stack t (l:ls) rs -> Stack x [] (xs ++ t:rs) where x :| xs = NE.reverse (l :| ls)
-- Move the focused window to workspace n, staying where we are.
shift :: (Ord a, Eq s, Eq i) => i -> StackSet i l a s sd -> StackSet i l a s sd
shift n s = maybe s (\w -> shiftWin n w s) (peek s)

shiftWin :: (Ord a, Eq s, Eq i) => i -> a -> StackSet i l a s sd -> StackSet i l a s sd
shiftWin n w s = case findTag w s of
  Just from | n `tagMember` s && n /= from ->
    onWorkspace n (insertUp w) . onWorkspace from (delete' w) $ s
  _ -> s
onWorkspace :: (Eq i, Eq s) => i
            -> (StackSet i l a s sd -> StackSet i l a s sd)
            -> StackSet i l a s sd -> StackSet i l a s sd
onWorkspace n f s = view (currentTag s) . f . view n $ s
