{-# LANGUAGE RankNTypes #-}
-- Adapted from xmonad-contrib XMonad.Actions.Navigation2D (BSD-3-Clause),
-- Copyright (c) 2017 Thomas Hackl, Martin Stone Davis and the Xmonad
-- Community. A window is navigable exactly when the helper last reported it,
-- so rectangles come from that observation rather than from the window
-- server: there is no separate float/tiled geometry to reconcile, and the
-- layout-specific unmappedWindowRect list has no counterpart.
module XMonad.Actions.Navigation2D
  ( Direction2D(..)
  , Navigation2D, lineNavigation, centerNavigation, sideNavigation
  , sideNavigationWithBias, hybridOf
  , Navigation2DConfig(..), withNavigation2DConfig
  , navigation2D, navigation2DP, additionalNav2DKeys, additionalNav2DKeysP
  , switchLayer, windowGo, windowSwap, windowToScreen, screenGo, screenSwap
  ) where
import XMonad.Core
import XMonad.Operations (windows, withWindowSet)
import XMonad.Config (Default(..))
import XMonad.Util.Types (Direction2D(..))
import XMonad.Util.EZConfig (additionalKeys, additionalKeysP)
import qualified XMonad.Util.ExtensibleState as XS
import qualified XMonad.StackSet as W
import qualified Data.List as L
import qualified Data.Map.Strict as M
import Control.Applicative ((<|>))
import Data.List (foldl')
import Data.Maybe (fromJust, fromMaybe, listToMaybe, mapMaybe)

-- A window and where it currently is. The label is a Window or a workspace
-- tag, so screens navigate with the same geometry code.
type Rect a = (a, Rectangle)
type WinRect = Rect Window
type WSRect = Rect WorkspaceId

-- | A navigation strategy: from the current rectangle and the others, which
-- one is in the given direction, if any.
data Navigation2D = N Generality (forall a. Eq a => Direction2D -> Rect a -> [Rect a] -> Maybe a)

runNav :: forall a. Eq a => Navigation2D -> (Direction2D -> Rect a -> [Rect a] -> Maybe a)
runNav (N _ nav) = nav

-- How general a strategy is. A more general one wins when a layout has
-- several, which is what makes hybridOf useful.
type Generality = Int

instance Eq Navigation2D where
  (N x _) == (N y _) = x == y

instance Ord Navigation2D where
  (N x _) <= (N y _) = x <= y

-- | Draw a line through the current window's centre and take the nearest
-- window the line crosses whose far edge is behind the near edge.
lineNavigation :: Navigation2D
lineNavigation = N 1 doLineNavigation

-- | Take the nearest window whose centre lies in the 45-degree cone in the
-- given direction. This is the one to use for floating windows.
centerNavigation :: Navigation2D
centerNavigation = N 2 doCenterNavigation

-- | Push the boundary on that side outwards until it meets another window and
-- take the window nearest the centre of the resulting line. This is the most
-- intuitive strategy for a tiled layout with spacing.
sideNavigation :: Navigation2D
sideNavigation = N 1 (doSideNavigationWithBias 1)

-- | Side navigation with a bias. Without it, two windows stacked in the
-- middle pane are equally good choices when moving inwards from a side pane,
-- so the same one is always picked. A bias of 1 alternates between them.
sideNavigationWithBias :: Int -> Navigation2D
sideNavigationWithBias bias = N 1 (doSideNavigationWithBias bias)

-- | The first strategy that finds a window wins.
hybridOf :: Navigation2D -> Navigation2D -> Navigation2D
hybridOf (N g1 s1) (N g2 s2) = N (max g1 g2) $ \dir cur rects -> s1 dir cur rects <|> s2 dir cur rects

-- | How navigation behaves. A window's layer is which workspace it is on:
-- floating windows and tiled ones are navigated separately.
data Navigation2DConfig = Navigation2DConfig
  { defaultTiledNavigation :: Navigation2D
  , floatNavigation :: Navigation2D
  , screenNavigation :: Navigation2D
  -- Strategies by layout description, for the tiled layer.
  , layoutNavigation :: [(String, Navigation2D)]
  }

instance Default Navigation2DConfig where
  def = Navigation2DConfig
    { defaultTiledNavigation = hybridOf lineNavigation sideNavigation
    , floatNavigation = centerNavigation
    , screenNavigation = lineNavigation
    , layoutNavigation = []
    }

instance ExtensionClass Navigation2DConfig where
  initialValue = def

-- | Make the given configuration the one the navigation actions read.
withNavigation2DConfig :: Navigation2DConfig -> XConfig a -> XConfig a
withNavigation2DConfig navConfig xconf =
  xconf {startupHook = startupHook xconf >> XS.put navConfig}

-- | Store the configuration and add the usual bindings in one step.
navigation2D :: Navigation2DConfig -> (KeySym, KeySym, KeySym, KeySym)
             -> [(KeyMask, Direction2D -> Bool -> X ())] -> Bool -> XConfig l -> XConfig l
navigation2D navConfig keys modifiers wrap =
  additionalNav2DKeys keys modifiers wrap . withNavigation2DConfig navConfig

-- | The same, with Emacs-style key descriptions.
navigation2DP :: Navigation2DConfig -> (String, String, String, String)
              -> [(String, Direction2D -> Bool -> X ())] -> Bool -> XConfig l -> XConfig l
navigation2DP navConfig keys modifiers wrap =
  additionalNav2DKeysP keys modifiers wrap . withNavigation2DConfig navConfig

-- | Bind the four directions, for each modifier and action given.
additionalNav2DKeys :: (KeySym, KeySym, KeySym, KeySym)
                    -> [(KeyMask, Direction2D -> Bool -> X ())] -> Bool -> XConfig l -> XConfig l
additionalNav2DKeys (u,l,d,r) modifiers wrap =
  flip additionalKeys [((mask,key), act dir wrap) | (mask,act) <- modifiers, (key,dir) <- dirKeys]
  where dirKeys = [(u,U),(l,L),(d,D),(r,R)]

additionalNav2DKeysP :: (String, String, String, String)
                     -> [(String, Direction2D -> Bool -> X ())] -> Bool -> XConfig l -> XConfig l
additionalNav2DKeysP (u,l,d,r) modifiers wrap =
  flip additionalKeysP [(prefix ++ key, act dir wrap)
                       | (prefix,act) <- modifiers, (key,dir) <- dirKeys]
  where dirKeys = [(u,U),(l,L),(d,D),(r,R)]

-- The layer the focused window is on, or the other one. Both take the
-- window list first, so the same two actions serve every caller.
thisLayer, otherLayer :: [a] -> [a] -> [a]
thisLayer = const
otherLayer _ other = other

-- | Focus the nearest window in the other layer: floating if the current one
-- is tiled, tiled if it is floating.
switchLayer :: X ()
switchLayer = actOnLayer otherLayer
               (\_ cur wins -> windows (doFocusClosestWindow cur wins))
               (\_ cur wins -> windows (doFocusClosestWindow cur wins))
               (\_ _ _ -> pure ())
               False

-- | Move focus one window in the given direction, within the current layer.
-- The Bool wraps around the edge of the desktop arrangement instead of
-- stopping there.
windowGo :: Direction2D -> Bool -> X ()
windowGo dir = actOnLayer thisLayer
                (\conf cur wins -> windows (doTiledNavigation conf dir W.focusWindow cur wins))
                (\conf cur wins -> windows (doFloatNavigation conf dir W.focusWindow cur wins))
                (\conf cur wspcs -> windows (doScreenNavigation conf dir W.view cur wspcs))

-- | Swap the focused window with the nearest window in that direction.
windowSwap :: Direction2D -> Bool -> X ()
windowSwap dir = actOnLayer thisLayer
                  (\conf cur wins -> windows (doTiledNavigation conf dir swap cur wins))
                  (\conf cur wins -> windows (doFloatNavigation conf dir swap cur wins))
                  (\_ _ _ -> pure ())

-- | Send the focused window to the workspace on the screen in that direction.
windowToScreen :: Direction2D -> Bool -> X ()
windowToScreen dir = actOnScreens $ \conf cur wspcs ->
  windows (doScreenNavigation conf dir W.shift cur wspcs)

-- | Focus the workspace on the screen in that direction.
screenGo :: Direction2D -> Bool -> X ()
screenGo dir = actOnScreens $ \conf cur wspcs ->
  windows (doScreenNavigation conf dir W.view cur wspcs)

-- | Swap this screen's workspace with the one in that direction.
screenSwap :: Direction2D -> Bool -> X ()
screenSwap dir = actOnScreens $ \conf cur wspcs ->
  windows (doScreenNavigation conf dir W.greedyView cur wspcs)

-- The layer the focused window is on, or the other one. `id` keeps the list
-- as it is and `const` drops the other, so the same actions serve both.
actOnLayer :: ([WinRect] -> [WinRect] -> [WinRect])
           -> (Navigation2DConfig -> WinRect -> [WinRect] -> X ())
           -> (Navigation2DConfig -> WinRect -> [WinRect] -> X ())
           -> (Navigation2DConfig -> WSRect -> [WSRect] -> X ())
           -> Bool
           -> X ()
actOnLayer choose tiledAct floatAct emptyAct wrap = withWindowSet $ \winset -> do
  conf <- XS.get
  (floating,tiled) <- navigableWindows wrap winset
  case W.peek winset of
    Nothing -> actOnScreens emptyAct wrap
    Just w
      | Just rect <- L.lookup w tiled -> tiledAct conf (w,rect) (choose tiled floating)
      | Just rect <- L.lookup w floating -> floatAct conf (w,rect) (choose floating tiled)
      | otherwise -> pure ()

actOnScreens :: (Navigation2DConfig -> WSRect -> [WSRect] -> X ()) -> Bool -> X ()
actOnScreens act wrap = withWindowSet $ \winset -> do
  conf <- XS.get
  let rects = visibleWorkspaces winset wrap
      here = W.tag (W.workspace (W.current winset))
  case L.lookup here rects of
    Just rect -> act conf (here,rect) rects
    Nothing -> pure ()

-- Which visible windows are floating and which are not, with the frames the
-- helper last reported. A window it has stopped reporting cannot be reached,
-- which is what keeps a parked window off the navigation graph.
navigableWindows :: Bool -> WindowSet -> X ([WinRect],[WinRect])
navigableWindows wrap winset = do
  info <- gets windowInfo
  let rects = [ (w, frame)
              | sc <- sortedScreens winset
              , w <- W.integrate' (W.stack (W.workspace sc))
              , Just frame <- [frame <$> M.lookup w info] ]
  pure $ L.partition (\(w,_) -> M.member w (W.floating winset)) (addWrapping winset wrap rects)

-- Focus the window whose centre is nearest, breaking ties by stack order.
doFocusClosestWindow :: WinRect -> [WinRect] -> WindowSet -> WindowSet
doFocusClosestWindow (cur,rect) winrects
  | null centres = id
  | otherwise = W.focusWindow . fst $ L.foldl1' closer centres
  where
    here = centerOf rect
    centres = [ (w, centerOf r) | (w,r) <- winrects, w /= cur ]
    closer a@(_,c1) b@(_,c2) = if lDist here c1 > lDist here c2 then b else a

doTiledNavigation :: Navigation2DConfig -> Direction2D -> (Window -> WindowSet -> WindowSet)
                  -> WinRect -> [WinRect] -> WindowSet -> WindowSet
doTiledNavigation conf dir act cur winrects winset
  | Just w <- runNav nav dir cur winrects = act w winset
  | otherwise = winset
  where
    -- Every visible layout may name its own strategy; the most general wins.
    nav = maximum $ map (\d -> fromMaybe (defaultTiledNavigation conf)
                                    (L.lookup d (layoutNavigation conf)))
                        [ description (W.layout (W.workspace sc)) | sc <- W.screens winset ]

doFloatNavigation :: Navigation2DConfig -> Direction2D -> (Window -> WindowSet -> WindowSet)
                  -> WinRect -> [WinRect] -> WindowSet -> WindowSet
doFloatNavigation conf dir act cur winrects
  | Just w <- runNav (floatNavigation conf) dir cur winrects = act w
  | otherwise = id

doScreenNavigation :: Navigation2DConfig -> Direction2D -> (WorkspaceId -> WindowSet -> WindowSet)
                   -> WSRect -> [WSRect] -> WindowSet -> WindowSet
doScreenNavigation conf dir act cur wsrects
  | Just tag <- runNav (screenNavigation conf) dir cur wsrects = act tag
  | otherwise = id

-- Line navigation. Windows that overlap cannot be told apart by a line, so
-- ties go to whichever comes first in the stack.
doLineNavigation :: Eq a => Direction2D -> Rect a -> [Rect a] -> Maybe a
doLineNavigation dir (cur,rect) winrects
  | null candidates = Nothing
  | otherwise = Just . fst $ L.foldl1' closer candidates
  where
    (xc,yc) = centerOf rect
    candidates = filter inDirection [ wr | wr@(w,_) <- winrects, w /= cur ]
    inDirection (_,r) =
      case dir of
        L -> leftOf r rect && intersectsY yc r
        R -> leftOf rect r && intersectsY yc r
        U -> above r rect && intersectsX xc r
        D -> above rect r && intersectsX xc r
    leftOf r1 r2 = rect_x r1 + rect_width r1 <= rect_x r2
    above r1 r2 = rect_y r1 + rect_height r1 <= rect_y r2
    intersectsX x r = rect_x r <= x && rect_x r + rect_width r >= x
    intersectsY y r = rect_y r <= y && rect_y r + rect_height r >= y
    closer a@(_,r1) b@(_,r2) = if distance r1 > distance r2 then b else a
    distance r = case dir of
      L -> xc - rect_x r - rect_width r
      R -> rect_x r - xc
      U -> yc - rect_y r - rect_height r
      D -> rect_y r - yc

-- Center navigation. Points are rotated so the wanted cone becomes the right
-- one, then partitioned into those on the centre and those in the cone.
doCenterNavigation :: Eq a => Direction2D -> Rect a -> [Rect a] -> Maybe a
doCenterNavigation dir (cur,rect) winrects
  | (w,_):_ <- onCentre' = Just w
  | otherwise = closestOffCentre
  where
    (xc,yc) = centerOf rect
    -- Later stack entries are preferred going left or up, earlier ones going
    -- right or down, so a cycle visits everything.
    ordered = if dir == L || dir == U then reverse winrects else winrects
    centres = [ (w, rotate (centerOf r)) | (w,r) <- ordered ]
    rotate (x,y) = case dir of
      R -> (x - xc, y - yc)
      L -> (xc - x, yc - y)
      D -> (y - yc, x - xc)
      U -> (yc - y, xc - x)
    (onCentre, offCentre) = L.partition (\(_,(x,y)) -> x == 0 && y == 0) centres
    onCentre' = drop 1 $ dropWhile ((/= cur) . fst) onCentre
    inCone = [ c | c@(_,(x,y)) <- offCentre, x > 0, y < x, y >= -x ]
    closestOffCentre = if null inCone then Nothing else Just (fst (L.foldl1' closest inCone))
    closest a@(_,p@(_,yp)) b@(_,q@(_,yq))
      | lDist (0,0) q < lDist (0,0) p = b
      | lDist (0,0) p < lDist (0,0) q = a
      | yq < yp = b
      | otherwise = a

-- Side navigation works on (left, right, bottom, top) edges, which makes
-- rotating a rectangle a two-line operation. x1 <= x2 and y1 <= y2 always
-- hold, and every transformation below preserves that.
data SideRect = SideRect { x1 :: Int, x2 :: Int, y1 :: Int, y2 :: Int }

toSideRect :: Rectangle -> SideRect
toSideRect r = SideRect (rect_x r) (rect_x r + rect_width r)
                        (negate (rect_y r + rect_height r)) (negate (rect_y r))

doSideNavigationWithBias :: Eq a => Int -> Direction2D -> Rect a -> [Rect a] -> Maybe a
doSideNavigationWithBias bias dir (cur,rect) winrects =
  fmap fst . listToMaybe . L.sortOn distance . foldr nearestTied [] $
    [ (w, r') | (w,r) <- winrects, w /= cur, let r' = transform r, r' `rightOf` now ]
  where
    now = transform rect
    here = toSideRect rect
    (x0,y0) = ((x1 here + x2 here) `div` 2, (y1 here + y2 here) `div` 2)
    translate r = SideRect (x1 r - x0) (x2 r - x0) (y1 r - y0) (y2 r - y0)
    -- A quarter turn anticlockwise about the origin.
    quarterTurn r = SideRect (negate (y2 r)) (negate (y1 r)) (x1 r) (x2 r)
    -- Turn until the asked-for direction is Right, which is the easy case.
    transform = fromJust . L.lookup dir . zip [R,D,L,U] . iterate quarterTurn . translate . toSideRect
    rightOf r c = x2 r > x2 c && y2 r > y1 c && y1 r < y2 c
    nearestTied (w,r) acc@((_,r'):_) | x1 r == x1 r' = (w,r) : acc
                                     | x1 r >  x1 r' = acc
    nearestTied (w,r) _ = [(w,r)]
    -- How far the window is from the bias line. Zero when it straddles it.
    distance (_,r) | y1 r <= bias && bias <= y2 r = 0
                   | otherwise = min (abs (y1 r - bias)) (abs (y2 r - bias))

-- | Swap two windows' places, across every visible workspace.
swap :: Window -> WindowSet -> WindowSet
swap win winset = W.focusWindow cur $ foldl' (flip W.focusWindow) rebuilt newFocused
  where
    cur = fromJust (W.peek winset)
    screens = W.screens winset
    workspaces = map W.workspace screens
    focused = mapMaybe (fmap W.focus . W.stack) workspaces
    windowLists = map (W.integrate' . W.stack) workspaces
    exchange x | x == cur = win
               | x == win = cur
               | otherwise = x
    newFocused = map exchange focused
    newLists = map (map exchange) windowLists
    newWorkspaces = zipWith (\ws wns -> ws {W.stack = W.differentiate wns}) workspaces newLists
    newScreens = zipWith (\sc ws -> sc {W.workspace = ws}) screens newWorkspaces
    rebuilt = case newScreens of
      (s:ss) -> winset {W.current = s, W.visible = ss}
      [] -> winset

-- | The visible workspaces and their screen rectangles, in physical order.
visibleWorkspaces :: WindowSet -> Bool -> [WSRect]
visibleWorkspaces winset wrap =
  addWrapping winset wrap
    [ (W.tag (W.workspace sc), screenRect (W.screenDetail sc)) | sc <- sortedScreens winset ]

-- Duplicate every rectangle one desktop to each side, so navigating towards
-- an edge lands on the copy that came round the other way.
addWrapping :: WindowSet -> Bool -> [Rect a] -> [Rect a]
addWrapping _ False rects = rects
addWrapping winset True rects =
  [ (w, r {rect_x = rect_x r + fromIntegral x, rect_y = rect_y r + fromIntegral y})
  | (w,r) <- rects
  , (x,y) <- [(0,0), (-xoff,0), (xoff,0), (0,-yoff), (0,yoff)] ]
  where (xoff,yoff) = wrapOffsets winset

wrapOffsets :: WindowSet -> (Integer, Integer)
wrapOffsets winset = (maxX - minX, maxY - minY)
  where
    rects = map snd (visibleWorkspaces winset False)
    minX = fromIntegral (minimum (map rect_x rects))
    minY = fromIntegral (minimum (map rect_y rects))
    maxX = fromIntegral (maximum (map (\r -> rect_x r + rect_width r) rects))
    maxY = fromIntegral (maximum (map (\r -> rect_y r + rect_height r) rects))

-- Displays left to right, then top to bottom.
sortedScreens :: WindowSet -> [WindowScreen]
sortedScreens winset = L.sortBy compareCentre (W.screens winset)
  where
    compareCentre s1 s2 = compare (centerOf (screenRect (W.screenDetail s1)))
                                 (centerOf (screenRect (W.screenDetail s2)))

centerOf :: Rectangle -> (Position, Position)
centerOf r = (rect_x r + rect_width r `div` 2, rect_y r + rect_height r `div` 2)

-- L1 distance, which is what the cone and closest-window tests are written in.
lDist :: (Position, Position) -> (Position, Position) -> Int
lDist (x,y) (x',y') = abs (x - x') + abs (y - y')
