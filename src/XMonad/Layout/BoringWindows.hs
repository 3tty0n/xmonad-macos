{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PatternGuards #-}
-- Adapted from xmonad-contrib XMonad.Layout.BoringWindows (BSD-3-Clause),
-- Copyright (c) 2008 David Roundy and the Xmonad Community.
module XMonad.Layout.BoringWindows
  ( boringWindows, boringAuto
  , markBoring, markBoringEverywhere, clearBoring
  , focusUp, focusDown, focusMaster, swapUp, swapDown, siftUp, siftDown
  , UpdateBoring(..), BoringMessage(..), BoringWindows
  ) where
import XMonad.Core
import XMonad.Layout.LayoutModifier
import XMonad.Operations
  (broadcastMessage, sendMessage, windows, withFocused)
import qualified XMonad.StackSet as W
import qualified Data.List.NonEmpty as NE
import qualified Data.Map.Strict as M
import Data.List (find, union, (\\))
import Data.List.NonEmpty (NonEmpty((:|)))
import Data.Maybe (fromMaybe, listToMaybe, maybeToList)

data BoringMessage = FocusUp | FocusDown | FocusMaster
                   | IsBoring Window | ClearBoring
                   | Replace String [Window] | Merge String [Window]
                   | SwapUp | SwapDown | SiftUp | SiftDown
  deriving (Read, Show)

-- Sent before a focus action, so layouts can mark boring windows first.
data UpdateBoring = UpdateBoring deriving (Read, Show)

instance Message BoringMessage
instance Message UpdateBoring

data BoringWindows a = BoringWindows
  { namedBoring :: M.Map String [a]
  , chosenBoring :: [a]
  , hiddenBoring :: Maybe [a]
  } deriving (Show, Read)

-- Everything the current layout treats as boring, in upstream's order.
boring :: BoringWindows a -> [a]
boring bs = concat (chosenBoring bs
                    : (maybeToList (hiddenBoring bs) ++ M.elems (namedBoring bs)))

instance LayoutModifier BoringWindows Window where
  -- Only boringAuto tracks hidden windows; for boringWindows this stays
  -- Nothing and the list is left alone.
  redoLayout bs _ mst wrs = pure (wrs, update)
    where
      hidden = W.integrate' mst \\ map fst wrs
      update = (\_ -> bs {hiddenBoring = Just hidden}) <$> hiddenBoring bs
  handleMess bs mess
    | Just FocusUp <- fromMessage mess = do
        windows $ W.modify' (skipBoring (boring bs) W.focusUp')
        pure Nothing
    | Just FocusDown <- fromMessage mess = do
        windows $ W.modify' (skipBoring (boring bs) W.focusDown')
        pure Nothing
    -- Wiggling the focus through the stack keeps a boring window from ending
    -- up focused when the master itself is boring.
    | Just FocusMaster <- fromMessage mess = do
        windows $ W.modify' (skipBoring (boring bs) W.focusDown'
                             . skipBoring (boring bs) W.focusUp' . focusMaster')
        pure Nothing
    | Just SwapUp <- fromMessage mess = do
        windows $ W.modify' (skipBoringSwapUp (boring bs))
        pure Nothing
    | Just SwapDown <- fromMessage mess = do
        windows $ W.modify' (reverseS . skipBoringSwapUp (boring bs) . reverseS)
        pure Nothing
    | Just SiftUp <- fromMessage mess = do
        windows $ W.modify' (siftUpSkipping (boring bs))
        pure Nothing
    | Just SiftDown <- fromMessage mess = do
        windows $ W.modify' (reverseS . siftUpSkipping (boring bs) . reverseS)
        pure Nothing
    | Just (IsBoring w) <- fromMessage mess =
        pure $ if w `elem` chosenBoring bs
               then Nothing
               else Just bs {chosenBoring = w : chosenBoring bs}
    | Just ClearBoring <- fromMessage mess =
        pure $ if null (chosenBoring bs)
               then Nothing
               else Just bs {namedBoring = M.empty, chosenBoring = []}
    | Just (Replace k ws) <- fromMessage mess =
        pure $ if Just ws == M.lookup k (namedBoring bs)
               then Nothing
               else Just bs {namedBoring =
                     if null ws then M.delete k (namedBoring bs)
                                else M.insert k ws (namedBoring bs)}
    | Just (Merge k ws) <- fromMessage mess =
        pure $ case M.lookup k (namedBoring bs) of
          Just old | null (ws \\ old) -> Nothing
          _ -> Just bs {namedBoring = M.insertWith union k ws (namedBoring bs)}
    | otherwise = pure Nothing

-- Walk @f@ until the focused window is not boring, bounded by the number of
-- windows on the stack so a fully boring stack still terminates.
skipBoring :: Eq a => [a] -> (W.Stack a -> W.Stack a) -> W.Stack a -> W.Stack a
skipBoring bs f st = fromMaybe st $ find (not . (`elem` bs) . W.focus)
  (take (length (W.integrate st)) (drop 1 (iterate f st)))

-- Same, but what lands next to the focus is what must not be boring.
skipBoringSwapUp :: Eq a => [a] -> W.Stack a -> W.Stack a
skipBoringSwapUp bs st = fromMaybe st $ find ok
  (take (length (W.integrate st)) (drop 1 (iterate W.swapUp' st)))
  where ok s = maybe True (`notElem` bs) (listToMaybe (W.down s))

siftUpSkipping :: Eq a => [a] -> W.Stack a -> W.Stack a
siftUpSkipping bs (W.Stack t ls rs)
  | (skips, l:ls') <- span (`elem` bs) ls =
      W.Stack t ls' (reverse skips ++ l : rs)
  | (skips, r:rs') <- span (`elem` bs) (reverse rs) =
      W.Stack t (rs' ++ r : ls) (reverse skips)
  | otherwise = W.Stack t ls rs

reverseS :: W.Stack a -> W.Stack a
reverseS (W.Stack t ls rs) = W.Stack t rs ls

focusMaster' :: W.Stack a -> W.Stack a
focusMaster' c = case c of
  W.Stack _ [] _ -> c
  W.Stack t (l:ls) rs -> W.Stack x [] (xs ++ t:rs)
    where x :| xs = NE.reverse (l :| ls)

boringWindows :: LayoutClass l Window
              => l Window -> ModifiedLayout BoringWindows l Window
boringWindows = ModifiedLayout (BoringWindows M.empty [] Nothing)

-- Windows the layout gives no rectangle to are boring, so focus and swap
-- skip a window that a layout such as TwoPane is not showing.
boringAuto :: LayoutClass l Window
           => l Window -> ModifiedLayout BoringWindows l Window
boringAuto = ModifiedLayout (BoringWindows M.empty [] (Just []))

markBoring :: X ()
markBoring = withFocused (sendMessage . IsBoring)

markBoringEverywhere :: X ()
markBoringEverywhere = withFocused (broadcastMessage . IsBoring)

clearBoring :: X ()
clearBoring = sendMessage ClearBoring

focusUp, focusDown, focusMaster, swapUp, swapDown, siftUp, siftDown :: X ()
focusUp = sendMessage UpdateBoring >> sendMessage FocusUp
focusDown = sendMessage UpdateBoring >> sendMessage FocusDown
focusMaster = sendMessage UpdateBoring >> sendMessage FocusMaster
swapUp = sendMessage UpdateBoring >> sendMessage SwapUp
swapDown = sendMessage UpdateBoring >> sendMessage SwapDown
siftUp = sendMessage UpdateBoring >> sendMessage SiftUp
siftDown = sendMessage UpdateBoring >> sendMessage SiftDown
