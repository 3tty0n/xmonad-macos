{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PatternGuards #-}
{-# LANGUAGE PatternSynonyms #-}
-- Adapted from xmonad-contrib XMonad.Layout.BinarySpacePartition
-- (BSD-3-Clause), Copyright (c) 2013 Ben Weitzman, 2015 Anton Pirogov and
-- 2019 Mateusz Karbowy. New windows split the focused window in half, as
-- bspwm does.
--
-- Changes for this port: the visual pieces upstream draws through
-- XMonad.Util.XUtils (the focused/selected node border) and the mouse
-- SetGeometry path through XMonad.Layout.WindowArranger have no macOS
-- counterpart here, so they are not ported. The tree and every message are
-- unchanged, so FocusParent/SelectNode/MoveNode still move nodes; only the
-- selected node is not highlighted. XMonad.Util.Stack is not ported either,
-- so the two helpers this module needs from it live here.
module XMonad.Layout.BinarySpacePartition
  ( emptyBSP
  , BinarySpacePartition
  , Rotate(..)
  , Swap(..)
  , ResizeDirectional(.., ExpandTowards, ShrinkFrom, MoveSplit)
  , TreeRotate(..)
  , TreeBalance(..)
  , FocusParent(..)
  , SelectMoveNode(..)
  , Direction2D(..)
  , SplitShiftDirectional(..)
  ) where
import XMonad
import XMonad.Util.Types
import qualified XMonad.StackSet as W
import Control.Monad (foldM, msum, (>=>))
import Data.List (elemIndex, (\\))
import Data.Maybe (fromMaybe, isNothing, mapMaybe)
import Data.Ratio ((%))
import qualified Data.Map.Strict as M

-- | Message for rotating the binary tree around the parent node of the window
-- to the left or right.
data TreeRotate = RotateL | RotateR
instance Message TreeRotate

-- | Balance retiles the windows; Equalize only tunes the split ratios.
data TreeBalance = Balance | Equalize
instance Message TreeBalance

-- | Message for resizing one of the cells in the BSP.
data ResizeDirectional =
        ExpandTowardsBy Direction2D Rational
      | ShrinkFromBy Direction2D Rational
      | MoveSplitBy Direction2D Rational
instance Message ResizeDirectional

-- | @ExpandTowards x@ is the equivalent of @ExpandTowardsBy x 0.05@.
pattern ExpandTowards :: Direction2D -> ResizeDirectional
pattern ExpandTowards d = ExpandTowardsBy d 0.05

-- | @ShrinkFrom x@ is the equivalent of @ShrinkFromBy x 0.05@.
pattern ShrinkFrom :: Direction2D -> ResizeDirectional
pattern ShrinkFrom d = ShrinkFromBy d 0.05

-- | @MoveSplit x@ is the equivalent of @MoveSplitBy x 0.05@.
pattern MoveSplit :: Direction2D -> ResizeDirectional
pattern MoveSplit d = MoveSplitBy d 0.05

-- | Message for rotating a split (horizontal/vertical) in the BSP.
data Rotate = Rotate
instance Message Rotate

-- | Message for swapping the left child of a split with the right child.
data Swap = Swap
instance Message Swap

-- | Cyclically select the parent node instead of the leaf.
data FocusParent = FocusParent
instance Message FocusParent

-- | Move nodes inside the tree.
data SelectMoveNode = SelectNode | MoveNode
instance Message SelectMoveNode

data Axis = Horizontal | Vertical deriving (Show, Read, Eq)

-- | Shift a window by splitting its neighbour.
newtype SplitShiftDirectional = SplitShift Direction1D
instance Message SplitShiftDirectional

oppositeDirection :: Direction2D -> Direction2D
oppositeDirection U = D
oppositeDirection D = U
oppositeDirection L = R
oppositeDirection R = L

oppositeAxis :: Axis -> Axis
oppositeAxis Vertical = Horizontal
oppositeAxis Horizontal = Vertical

toAxis :: Direction2D -> Axis
toAxis U = Horizontal
toAxis D = Horizontal
toAxis L = Vertical
toAxis R = Vertical

split :: Axis -> Rational -> Rectangle -> (Rectangle, Rectangle)
split Horizontal r (Rectangle sx sy sw sh) = (r1, r2)
  where r1 = Rectangle sx sy sw sh'
        r2 = Rectangle sx (sy + sh') sw (sh - sh')
        sh' = floor (fromIntegral sh * r)
split Vertical r (Rectangle sx sy sw sh) = (r1, r2)
  where r1 = Rectangle sx sy sw' sh
        r2 = Rectangle (sx + sw') sy (sw - sw') sh
        sw' = floor (fromIntegral sw * r)

data Split = Split { axis :: Axis, ratio :: Rational }
  deriving (Show, Read, Eq)

oppositeSplit :: Split -> Split
oppositeSplit (Split d r) = Split (oppositeAxis d) r

increaseRatio :: Split -> Rational -> Split
increaseRatio (Split d r) delta = Split d (min 0.9 (max 0.1 (r + delta)))

data Tree a = Leaf Int | Node { value :: a, left :: Tree a, right :: Tree a }
  deriving (Show, Read, Eq)

numLeaves :: Tree a -> Int
numLeaves (Leaf _) = 1
numLeaves (Node _ l r) = numLeaves l + numLeaves r

-- Right or left rotation of a (sub)tree; no effect if rotation is not possible.
rotTree :: Direction2D -> Tree a -> Tree a
rotTree _ (Leaf n) = Leaf n
rotTree R n@(Node _ (Leaf _) _) = n
rotTree L n@(Node _ _ (Leaf _)) = n
rotTree R (Node sp (Node sp2 l2 r2) r) = Node sp2 l2 (Node sp r2 r)
rotTree L (Node sp l (Node sp2 l2 r2)) = Node sp2 (Node sp l l2) r2
rotTree _ t = t

data Crumb a = LeftCrumb a (Tree a) | RightCrumb a (Tree a)
  deriving (Show, Read, Eq)

swapCrumb :: Crumb a -> Crumb a
swapCrumb (LeftCrumb s t) = RightCrumb s t
swapCrumb (RightCrumb s t) = LeftCrumb s t

parentVal :: Crumb a -> a
parentVal (LeftCrumb s _) = s
parentVal (RightCrumb s _) = s

modifyParentVal :: (a -> a) -> Crumb a -> Crumb a
modifyParentVal f (LeftCrumb s t) = LeftCrumb (f s) t
modifyParentVal f (RightCrumb s t) = RightCrumb (f s) t

-- The zipper upstream's XMonad.Util.Stack provides, kept local to this port.
type Zipper a = (Tree a, [Crumb a])

toZipper :: Tree a -> Zipper a
toZipper t = (t, [])

goLeft :: Zipper a -> Maybe (Zipper a)
goLeft (Leaf _, _) = Nothing
goLeft (Node x l r, bs) = Just (l, LeftCrumb x r : bs)

goRight :: Zipper a -> Maybe (Zipper a)
goRight (Leaf _, _) = Nothing
goRight (Node x l r, bs) = Just (r, RightCrumb x l : bs)

goUp :: Zipper a -> Maybe (Zipper a)
goUp (_, []) = Nothing
goUp (t, LeftCrumb x r : cs) = Just (Node x t r, cs)
goUp (t, RightCrumb x l : cs) = Just (Node x l t, cs)

goSibling :: Zipper a -> Maybe (Zipper a)
goSibling (_, []) = Nothing
goSibling z@(_, LeftCrumb _ _ : _) = Just z >>= goUp >>= goRight
goSibling z@(_, RightCrumb _ _ : _) = Just z >>= goUp >>= goLeft

top :: Zipper a -> Zipper a
top z = maybe z top (goUp z)

toTree :: Zipper a -> Tree a
toTree = fst . top

goToNthLeaf :: Int -> Zipper a -> Maybe (Zipper a)
goToNthLeaf _ z@(Leaf _, _) = Just z
goToNthLeaf n z@(t, _)
  | numLeaves (left t) > n = goLeft z >>= goToNthLeaf n
  | otherwise = goRight z >>= goToNthLeaf (n - numLeaves (left t))

toggleSplits :: Tree Split -> Tree Split
toggleSplits (Leaf l) = Leaf l
toggleSplits (Node s l r) = Node (oppositeSplit s) (toggleSplits l) (toggleSplits r)

splitCurrent :: Zipper Split -> Maybe (Zipper Split)
splitCurrent (Leaf _, []) = Just (Node (Split Vertical 0.5) (Leaf 0) (Leaf 0), [])
splitCurrent (Leaf _, crumb:cs) =
  Just (Node (Split (oppositeAxis . axis . parentVal $ crumb) 0.5) (Leaf 0) (Leaf 0), crumb:cs)
splitCurrent (n, []) = Just (Node (Split Vertical 0.5) (Leaf 0) (toggleSplits n), [])
splitCurrent (n, crumb:cs) =
  Just (Node (Split (oppositeAxis . axis . parentVal $ crumb) 0.5) (Leaf 0) (toggleSplits n), crumb:cs)

removeCurrent :: Zipper a -> Maybe (Zipper a)
removeCurrent (Leaf _, LeftCrumb _ r:cs) = Just (r, cs)
removeCurrent (Leaf _, RightCrumb _ l:cs) = Just (l, cs)
removeCurrent (Leaf _, []) = Nothing
removeCurrent (Node _ (Leaf _) r@Node{}, cs) = Just (r, cs)
removeCurrent (Node _ l@Node{} (Leaf _), cs) = Just (l, cs)
removeCurrent (Node _ (Leaf _) (Leaf _), cs) = Just (Leaf 0, cs)
removeCurrent z@(Node{}, _) = goLeft z >>= removeCurrent

rotateCurrent :: Zipper Split -> Maybe (Zipper Split)
rotateCurrent l@(_, []) = Just l
rotateCurrent (n, c:cs) = Just (n, modifyParentVal oppositeSplit c : cs)

swapCurrent :: Zipper a -> Maybe (Zipper a)
swapCurrent l@(_, []) = Just l
swapCurrent (n, c:cs) = Just (n, swapCrumb c : cs)

insertLeftLeaf :: Tree Split -> Zipper Split -> Maybe (Zipper Split)
insertLeftLeaf (Leaf n) (Node x l r, crumb:cs) =
  Just (Node (Split (oppositeAxis . axis . parentVal $ crumb) 0.5) (Leaf n) (Node x l r), crumb:cs)
insertLeftLeaf (Leaf n) (Leaf x, crumb:cs) =
  Just (Node (Split (oppositeAxis . axis . parentVal $ crumb) 0.5) (Leaf n) (Leaf x), crumb:cs)
insertLeftLeaf Node{} z = Just z
insertLeftLeaf _ _ = Nothing

insertRightLeaf :: Tree Split -> Zipper Split -> Maybe (Zipper Split)
insertRightLeaf (Leaf n) (Node x l r, crumb:cs) =
  Just (Node (Split (oppositeAxis . axis . parentVal $ crumb) 0.5) (Node x l r) (Leaf n), crumb:cs)
insertRightLeaf (Leaf n) (Leaf x, crumb:cs) =
  Just (Node (Split (oppositeAxis . axis . parentVal $ crumb) 0.5) (Leaf x) (Leaf n), crumb:cs)
insertRightLeaf Node{} z = Just z
insertRightLeaf _ _ = Nothing

findRightLeaf :: Zipper Split -> Maybe (Zipper Split)
findRightLeaf n@(Node{}, _) = goRight n >>= findRightLeaf
findRightLeaf l@(Leaf _, _) = Just l

findLeftLeaf :: Zipper Split -> Maybe (Zipper Split)
findLeftLeaf n@(Node{}, _) = goLeft n
findLeftLeaf l@(Leaf _, _) = Just l

findTheClosestLeftmostLeaf :: Zipper Split -> Maybe (Zipper Split)
findTheClosestLeftmostLeaf s@(_, RightCrumb _ _ : _) = goUp s >>= goLeft >>= findRightLeaf
findTheClosestLeftmostLeaf s@(_, LeftCrumb _ _ : _) = goUp s >>= findTheClosestLeftmostLeaf
findTheClosestLeftmostLeaf _ = Nothing

findTheClosestRightmostLeaf :: Zipper Split -> Maybe (Zipper Split)
findTheClosestRightmostLeaf s@(_, RightCrumb _ _ : _) = goUp s >>= findTheClosestRightmostLeaf
findTheClosestRightmostLeaf s@(_, LeftCrumb _ _ : _) = goUp s >>= goRight >>= findLeftLeaf
findTheClosestRightmostLeaf _ = Nothing

splitShiftLeftCurrent :: Zipper Split -> Maybe (Zipper Split)
splitShiftLeftCurrent l@(_, []) = Just l
splitShiftLeftCurrent l@(_, RightCrumb _ _ : _) = Just l -- swap is the better action here
splitShiftLeftCurrent l@(n, _) = removeCurrent l >>= findTheClosestLeftmostLeaf >>= insertRightLeaf n

splitShiftRightCurrent :: Zipper Split -> Maybe (Zipper Split)
splitShiftRightCurrent l@(_, []) = Just l
splitShiftRightCurrent l@(_, LeftCrumb _ _ : _) = Just l -- swap is the better action here
splitShiftRightCurrent l@(n, _) = removeCurrent l >>= findTheClosestRightmostLeaf >>= insertLeftLeaf n

isAllTheWay :: Direction2D -> Zipper Split -> Bool
isAllTheWay _ (_, []) = True
isAllTheWay R (_, LeftCrumb s _ : _) | axis s == Vertical = False
isAllTheWay L (_, RightCrumb s _ : _) | axis s == Vertical = False
isAllTheWay D (_, LeftCrumb s _ : _) | axis s == Horizontal = False
isAllTheWay U (_, RightCrumb s _ : _) | axis s == Horizontal = False
isAllTheWay dir z = fromMaybe False $ goUp z >>= Just . isAllTheWay dir

expandTreeTowards :: Direction2D -> Rational -> Zipper Split -> Maybe (Zipper Split)
expandTreeTowards _ _ z@(_, []) = Just z
expandTreeTowards dir diff z
  | isAllTheWay dir z = shrinkTreeFrom (oppositeDirection dir) diff z
expandTreeTowards R diff (t, LeftCrumb s r:cs)
  | axis s == Vertical = Just (t, LeftCrumb (increaseRatio s diff) r:cs)
expandTreeTowards L diff (t, RightCrumb s l:cs)
  | axis s == Vertical = Just (t, RightCrumb (increaseRatio s (-diff)) l:cs)
expandTreeTowards D diff (t, LeftCrumb s r:cs)
  | axis s == Horizontal = Just (t, LeftCrumb (increaseRatio s diff) r:cs)
expandTreeTowards U diff (t, RightCrumb s l:cs)
  | axis s == Horizontal = Just (t, RightCrumb (increaseRatio s (-diff)) l:cs)
expandTreeTowards dir diff z = goUp z >>= expandTreeTowards dir diff

shrinkTreeFrom :: Direction2D -> Rational -> Zipper Split -> Maybe (Zipper Split)
shrinkTreeFrom _ _ z@(_, []) = Just z
shrinkTreeFrom R diff z@(_, LeftCrumb s _:_)
  | axis s == Vertical = Just z >>= goSibling >>= expandTreeTowards L diff
shrinkTreeFrom L diff z@(_, RightCrumb s _:_)
  | axis s == Vertical = Just z >>= goSibling >>= expandTreeTowards R diff
shrinkTreeFrom D diff z@(_, LeftCrumb s _:_)
  | axis s == Horizontal = Just z >>= goSibling >>= expandTreeTowards U diff
shrinkTreeFrom U diff z@(_, RightCrumb s _:_)
  | axis s == Horizontal = Just z >>= goSibling >>= expandTreeTowards D diff
shrinkTreeFrom dir diff z = goUp z >>= shrinkTreeFrom dir diff

-- Direction2D is which way the divider should move.
autoSizeTree :: Direction2D -> Rational -> Zipper Split -> Maybe (Zipper Split)
autoSizeTree _ _ z@(_, []) = Just z
autoSizeTree d f z = Just z >>= getSplit (toAxis d) >>= resizeTree d f

-- Resize once the correct split has been found.
resizeTree :: Direction2D -> Rational -> Zipper Split -> Maybe (Zipper Split)
resizeTree _ _ z@(_, []) = Just z
resizeTree R diff z@(_, LeftCrumb _ _:_) = Just z >>= expandTreeTowards R diff
resizeTree L diff z@(_, LeftCrumb _ _:_) = Just z >>= shrinkTreeFrom    R diff
resizeTree U diff z@(_, LeftCrumb _ _:_) = Just z >>= shrinkTreeFrom    D diff
resizeTree D diff z@(_, LeftCrumb _ _:_) = Just z >>= expandTreeTowards D diff
resizeTree R diff z@(_, RightCrumb _ _:_) = Just z >>= shrinkTreeFrom    L diff
resizeTree L diff z@(_, RightCrumb _ _:_) = Just z >>= expandTreeTowards L diff
resizeTree U diff z@(_, RightCrumb _ _:_) = Just z >>= expandTreeTowards U diff
resizeTree D diff z@(_, RightCrumb _ _:_) = Just z >>= shrinkTreeFrom    U diff

getSplit :: Axis -> Zipper Split -> Maybe (Zipper Split)
getSplit _ (_, []) = Nothing
getSplit d z =
 do let fs = findSplit d z
    if isNothing fs then findClosest d z else fs

findClosest :: Axis -> Zipper Split -> Maybe (Zipper Split)
findClosest _ z@(_, []) = Just z
findClosest d z@(_, LeftCrumb s _:_) | axis s == d = Just z
findClosest d z@(_, RightCrumb s _:_) | axis s == d = Just z
findClosest d z = goUp z >>= findClosest d

findSplit :: Axis -> Zipper Split -> Maybe (Zipper Split)
findSplit _ (_, []) = Nothing
findSplit d z@(_, LeftCrumb s _:_) | axis s == d = Just z
findSplit d z = goUp z >>= findSplit d

-- Takes a list of indices and numerates the leaves of the given tree.
numerate :: [Int] -> Tree a -> Tree a
numerate ns t = snd $ num ns t
  where num (n:nns) (Leaf _) = (nns, Leaf n)
        num [] (Leaf _) = ([], Leaf 0)
        num n (Node s l r) = (n'', Node s nl nr)
          where (n', nl)  = num n l
                (n'', nr) = num n' r

-- The leaf labels from left to right.
flatten :: Tree a -> [Int]
flatten (Leaf n) = [n]
flatten (Node _ l r) = flatten l ++ flatten r

-- Adjust ratios so every window gets an equal area.
equalize :: Zipper Split -> Maybe (Zipper Split)
equalize (t, cs) = Just (eql t, cs)
  where eql (Leaf n) = Leaf n
        eql n@(Node s l r) = Node s{ratio=fromIntegral (numLeaves l) % fromIntegral (numLeaves n)}
                                  (eql l) (eql r)

-- A symmetrical balanced tree for n leaves, preserving leaf labels.
balancedTree :: Zipper Split -> Maybe (Zipper Split)
balancedTree (t, cs) = Just (numerate (flatten t) $ balanced (numLeaves t), cs)
  where balanced 1 = Leaf 0
        balanced 2 = Node (Split Horizontal 0.5) (Leaf 0) (Leaf 0)
        balanced m = Node (Split Horizontal 0.5) (balanced (m `div` 2)) (balanced (m - m `div` 2))

-- Rotate splits optimally so the rectangles come out more quad-like.
optimizeOrientation :: Rectangle -> Zipper Split -> Maybe (Zipper Split)
optimizeOrientation rct (t, cs) = Just (opt t rct, cs)
  where opt (Leaf v) _ = Leaf v
        opt (Node sp l r) rect = Node sp' (opt l lrect) (opt r rrect)
         where (Rectangle _ _ w1 h1, Rectangle _ _ w2 h2) = split (axis sp) (ratio sp) rect
               (Rectangle _ _ w3 h3, Rectangle _ _ w4 h4) = split (axis $ oppositeSplit sp) (ratio sp) rect
               f w h = if w > h then w'/h' else h'/w'
                 where (w',h') = (fromIntegral w :: Double, fromIntegral h :: Double)
               wratio = min (f w1 h1) (f w2 h2)
               wratio' = min (f w3 h3) (f w4 h4)
               sp' = if wratio < wratio' then sp else oppositeSplit sp
               (lrect, rrect) = split (axis sp') (ratio sp') rect

-- Initially focused leaf, path from root to the selected node, window ids of
-- the selection border (kept for the Show/Read shape; nothing draws it here).
data NodeRef = NodeRef { refLeaf :: Int, refPath :: [Direction2D], refWins :: [Window] }
  deriving (Show, Read, Eq)
noRef :: NodeRef
noRef = NodeRef (-1) [] []

goToNode :: NodeRef -> Zipper a -> Maybe (Zipper a)
goToNode (NodeRef _ dirs _) z = foldM gofun z dirs
  where gofun z' L = goLeft z'
        gofun z' R = goRight z'
        gofun _ _ = Nothing

toNodeRef :: Int -> Maybe (Zipper Split) -> NodeRef
toNodeRef _ Nothing = noRef
toNodeRef l (Just (_, cs)) = NodeRef l (reverse $ map crumbToDir cs) []
  where crumbToDir (LeftCrumb _ _) = L
        crumbToDir (RightCrumb _ _) = R

leafToNodeRef :: Int -> BinarySpacePartition a -> NodeRef
leafToNodeRef l b = toNodeRef l (makeZipper b >>= goToNthLeaf l)

data BinarySpacePartition a = BinarySpacePartition
  { getOldRects :: [(Window,Rectangle)]
  , getFocusedNode :: NodeRef
  , getSelectedNode :: NodeRef
  , getTree :: Maybe (Tree Split)
  } deriving (Show, Read, Eq)

-- | An empty BinarySpacePartition, the default new windows are added to.
emptyBSP :: BinarySpacePartition a
emptyBSP = BinarySpacePartition [] noRef noRef Nothing

makeBSP :: Tree Split -> BinarySpacePartition a
makeBSP = BinarySpacePartition [] noRef noRef . Just

makeZipper :: BinarySpacePartition a -> Maybe (Zipper Split)
makeZipper (BinarySpacePartition _ _ _ Nothing) = Nothing
makeZipper (BinarySpacePartition _ _ _ (Just t)) = Just . toZipper $ t

size :: BinarySpacePartition a -> Int
size = maybe 0 numLeaves . getTree

zipperToBinarySpacePartition :: Maybe (Zipper Split) -> BinarySpacePartition b
zipperToBinarySpacePartition Nothing = emptyBSP
zipperToBinarySpacePartition (Just z) = BinarySpacePartition [] noRef noRef . Just . toTree . top $ z

rectangles :: BinarySpacePartition a -> Rectangle -> [Rectangle]
rectangles (BinarySpacePartition _ _ _ Nothing) _ = []
rectangles (BinarySpacePartition _ _ _ (Just (Leaf _))) rootRect = [rootRect]
rectangles (BinarySpacePartition _ _ _ (Just node)) rootRect =
    rectangles (makeBSP . left $ node) leftBox ++
    rectangles (makeBSP . right $ node) rightBox
    where (leftBox, rightBox) = split (axis info) (ratio info) rootRect
          info = value node

doToNth :: (Zipper Split -> Maybe (Zipper Split)) -> BinarySpacePartition a -> BinarySpacePartition a
doToNth f b = b{getTree=getTree $ zipperToBinarySpacePartition $
  makeZipper b >>= goToNode (getFocusedNode b) >>= f}

splitNth :: BinarySpacePartition a -> BinarySpacePartition a
splitNth (BinarySpacePartition _ _ _ Nothing) = makeBSP (Leaf 0)
splitNth b = doToNth splitCurrent b

removeNth :: BinarySpacePartition a -> BinarySpacePartition a
removeNth (BinarySpacePartition _ _ _ Nothing) = emptyBSP
removeNth (BinarySpacePartition _ _ _ (Just (Leaf _))) = emptyBSP
removeNth b = doToNth removeCurrent b

rotateNth :: BinarySpacePartition a -> BinarySpacePartition a
rotateNth (BinarySpacePartition _ _ _ Nothing) = emptyBSP
rotateNth b@(BinarySpacePartition _ _ _ (Just (Leaf _))) = b
rotateNth b = doToNth rotateCurrent b

swapNth :: BinarySpacePartition a -> BinarySpacePartition a
swapNth (BinarySpacePartition _ _ _ Nothing) = emptyBSP
swapNth b@(BinarySpacePartition _ _ _ (Just (Leaf _))) = b
swapNth b = doToNth swapCurrent b

splitShiftNth :: Direction1D -> BinarySpacePartition a -> BinarySpacePartition a
splitShiftNth _ (BinarySpacePartition _ _ _ Nothing) = emptyBSP
splitShiftNth _ b@(BinarySpacePartition _ _ _ (Just (Leaf _))) = b
splitShiftNth Prev b = doToNth splitShiftLeftCurrent b
splitShiftNth Next b = doToNth splitShiftRightCurrent b

growNthTowards :: Direction2D -> Rational -> BinarySpacePartition a -> BinarySpacePartition a
growNthTowards _ _ (BinarySpacePartition _ _ _ Nothing) = emptyBSP
growNthTowards _ _ b@(BinarySpacePartition _ _ _ (Just (Leaf _))) = b
growNthTowards dir diff b = doToNth (expandTreeTowards dir diff) b

shrinkNthFrom :: Direction2D -> Rational -> BinarySpacePartition a -> BinarySpacePartition a
shrinkNthFrom _ _ (BinarySpacePartition _ _ _ Nothing) = emptyBSP
shrinkNthFrom _ _ b@(BinarySpacePartition _ _ _ (Just (Leaf _))) = b
shrinkNthFrom dir diff b = doToNth (shrinkTreeFrom dir diff) b

autoSizeNth :: Direction2D -> Rational -> BinarySpacePartition a -> BinarySpacePartition a
autoSizeNth _ _ (BinarySpacePartition _ _ _ Nothing) = emptyBSP
autoSizeNth _ _ b@(BinarySpacePartition _ _ _ (Just (Leaf _))) = b
autoSizeNth dir diff b = doToNth (autoSizeTree dir diff) b

-- Rotate the tree left or right around the parent of the nth leaf.
rotateTreeNth :: Direction2D -> BinarySpacePartition a -> BinarySpacePartition a
rotateTreeNth _ (BinarySpacePartition _ _ _ Nothing) = emptyBSP
rotateTreeNth U b = b
rotateTreeNth D b = b
rotateTreeNth dir b@(BinarySpacePartition _ _ _ (Just _)) =
  doToNth (\t -> case goUp t of
                   Nothing -> Just t
                   Just (t', c) -> Just (rotTree dir t', c)) b

equalizeNth :: BinarySpacePartition a -> BinarySpacePartition a
equalizeNth (BinarySpacePartition _ _ _ Nothing) = emptyBSP
equalizeNth b@(BinarySpacePartition _ _ _ (Just (Leaf _))) = b
equalizeNth b = doToNth equalize b

rebalanceNth :: BinarySpacePartition a -> Rectangle -> BinarySpacePartition a
rebalanceNth (BinarySpacePartition _ _ _ Nothing) _ = emptyBSP
rebalanceNth b@(BinarySpacePartition _ _ _ (Just (Leaf _))) _ = b
rebalanceNth b r = doToNth (balancedTree >=> optimizeOrientation r) b

flattenLeaves :: BinarySpacePartition a -> [Int]
flattenLeaves (BinarySpacePartition _ _ _ Nothing) = []
flattenLeaves (BinarySpacePartition _ _ _ (Just t)) = flatten t

-- Before an action, so the leaves can be compared afterwards.
numerateLeaves :: BinarySpacePartition a -> BinarySpacePartition a
numerateLeaves b@(BinarySpacePartition _ _ _ Nothing) = b
numerateLeaves b@(BinarySpacePartition _ _ _ (Just t)) = b{getTree=Just $ numerate ns t}
  where ns = [0..numLeaves t - 1]

-- If a focused and a selected node are set and the focused is not part of the
-- selected, move the selected node under the focused one.
moveNode :: BinarySpacePartition a -> BinarySpacePartition a
moveNode b@(BinarySpacePartition _ (NodeRef (-1) _ _) _ _) = b
moveNode b@(BinarySpacePartition _ _ (NodeRef (-1) _ _) _) = b
moveNode b@(BinarySpacePartition _ _ _ Nothing) = b
moveNode b@(BinarySpacePartition _ f s (Just ot)) =
  case makeZipper b >>= goToNode s of
    Just (n, LeftCrumb _ t:cs)  -> b{getTree=Just $ insert n $ top (t, cs)}
    Just (n, RightCrumb _ t:cs) -> b{getTree=Just $ insert n $ top (t, cs)}
    _ -> b
  where insert t z = case goToNode f z of
          Nothing -> ot -- abort and keep the original tree
          Just (n, c:cs) -> toTree (Node (Split (oppositeAxis . axis . parentVal $ c) 0.5) t n, c:cs)
          Just (n, []) -> toTree (Node (Split Vertical 0.5) t n, [])

-- The focused window's index in the current workspace's stack, 0 if empty.
index :: W.Stack a -> Int
index = length . W.up

-- The stack and the focused index, or Nothing for an empty stack. This and
-- fromIndex are the parts of XMonad.Util.Stack that the layout uses.
toIndex :: Maybe (W.Stack a) -> ([a], Maybe Int)
toIndex Nothing = ([], Nothing)
toIndex (Just s) = (W.integrate s, Just (length $ W.up s))

-- A stack from a list with the focus at the given index; out of bounds puts
-- the focus on the first element.
fromIndex :: [a] -> Int -> Maybe (W.Stack a)
fromIndex [] _ = Nothing
fromIndex as i
  | i < 0 || i >= length as = W.differentiate as
  | otherwise = Just (W.Stack (as !! i) (reverse (take i as)) (drop (i + 1) as))

-- Move windows to new positions according to the tree transformation, keeping
-- focus on the window that had it.
adjustStack :: Maybe (W.Stack Window) -> Maybe (W.Stack Window) -> [Window]
            -> Maybe (BinarySpacePartition Window) -> Maybe (W.Stack Window)
adjustStack orig Nothing _ _ = orig
adjustStack orig _ _ Nothing = orig
adjustStack orig s fw (Just b) =
  if length ls < length ws then orig
  else fromIndex ws' fid'
  where ws' = mapMaybe (`M.lookup` wsmap) ls ++ fw
        fid' = fromMaybe 0 $ elemIndex focused ws'
        wsmap = M.fromList $ zip [0..] ws
        ls = flattenLeaves b
        (ws, fid) = toIndex s
        focused = ws !! fromMaybe 0 fid

-- Replace the current workspace's stack with the modified one.
replaceStack :: Maybe (W.Stack Window) -> X ()
replaceStack s = do
  st <- get
  let wset = windowset st
      cur  = W.current wset
      wsp  = W.workspace cur
  put st{windowset=wset{W.current=cur{W.workspace=wsp{W.stack=s}}}}

getStackSet :: X (Maybe (W.Stack Window))
getStackSet = W.stack . W.workspace . W.current <$> gets windowset

getFloating :: X [Window]
getFloating = M.keys . W.floating <$> gets windowset

getScreenRect :: X Rectangle
getScreenRect = screenRect . W.screenDetail . W.current <$> gets windowset

-- The stack without the floating windows, or Nothing when the focus is one.
-- User-minimized windows are already absent from the engine's observation, so
-- the hidden-window filter upstream needs has nothing to remove here.
withoutFloating :: [Window] -> Maybe (W.Stack Window) -> Maybe (W.Stack Window)
withoutFloating fs = maybe Nothing (unfloat fs)

unfloat :: [Window] -> W.Stack Window -> Maybe (W.Stack Window)
unfloat fs s
  | W.focus s `elem` fs = Nothing
  | otherwise = Just s{W.up = W.up s \\ fs, W.down = W.down s \\ fs}

instance LayoutClass BinarySpacePartition Window where
  doLayout b r s = do
    let b' = layout b
    b'' <- updateNodeRef b' (size b /= size b')
    let rs = rectangles b'' r
        wrs = zip ws rs
    return (wrs, Just b''{getOldRects=wrs})
    where
      ws = W.integrate s
      l = length ws
      layout bsp
        | l == sz = bsp
        | l > sz = layout $ splitNth bsp
        | otherwise = layout $ removeNth bsp
        where sz = size bsp

  handleMessage b_orig m
   | Just FocusParent <- fromMessage m = do
       let n = getFocusedNode b
       let n' = toNodeRef (refLeaf n) (makeZipper b >>= goToNode n >>= goUp)
       return $ Just b{getFocusedNode=n'{refWins=refWins n}}
   | Just SelectNode <- fromMessage m = do
       let n = getFocusedNode b
       let s = getSelectedNode b
       let s' = if refLeaf n == refLeaf s && refPath n == refPath s
                then noRef else n{refWins=[]}
       return $ Just b{getSelectedNode=s'}
   | otherwise = do
       ws <- getStackSet
       fs <- getFloating
       r <- getScreenRect
       let lws = withoutFloating fs ws
           lfs = maybe [] W.integrate ws \\ maybe [] W.integrate lws
           b'  = handleMesg r
           ws' = adjustStack ws lws lfs b'
       replaceStack ws'
       return b'
    where
      handleMesg r = msum
        [ fmap resize       (fromMessage m)
        , fmap rotate       (fromMessage m)
        , fmap swap         (fromMessage m)
        , fmap rotateTr     (fromMessage m)
        , fmap (balanceTr r)(fromMessage m)
        , fmap move         (fromMessage m)
        , fmap splitShift   (fromMessage m)
        ]
      resize (ExpandTowardsBy dir diff) = growNthTowards dir diff b
      resize (ShrinkFromBy dir diff) = shrinkNthFrom dir diff b
      resize (MoveSplitBy dir diff) = autoSizeNth dir diff b
      rotate Rotate = resetFoc $ rotateNth b
      swap Swap = resetFoc $ swapNth b
      rotateTr RotateL = resetFoc $ rotateTreeNth L b
      rotateTr RotateR = resetFoc $ rotateTreeNth R b
      balanceTr _ Equalize = resetFoc $ equalizeNth b
      balanceTr r Balance  = resetFoc $ rebalanceNth b r
      move MoveNode = resetFoc $ moveNode b
      move SelectNode = b -- handled above; it needs the X monad
      splitShift (SplitShift dir) = resetFoc $ splitShiftNth dir b

      b = numerateLeaves b_orig
      resetFoc bsp = bsp{getFocusedNode=(getFocusedNode bsp){refLeaf= -1}
                        ,getSelectedNode=(getSelectedNode bsp){refLeaf= -1}}

  description _ = "BSP"

-- Recompute the node the focused window sits on after a layout pass.
updateNodeRef :: BinarySpacePartition Window -> Bool -> X (BinarySpacePartition Window)
updateNodeRef b force = do
    let n = getFocusedNode b
    l <- getCurrFocused
    b' <- if refLeaf n /= l || refLeaf n == (-1) || force
            then return b{getFocusedNode=leafToNodeRef l b}
            else return b
    if force then return b'{getSelectedNode=noRef} else return b'
  where getCurrFocused = maybe 0 index <$>
          (withoutFloating <$> getFloating <*> getStackSet)
