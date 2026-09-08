-- Adapted from xmonad-contrib XMonad.Actions.PhysicalScreens (BSD-3-Clause),
-- Copyright (c) Nelson Elhage and the Xmonad Community. Screens are numbered
-- left to right, then top to bottom, rather than in the order macOS reports
-- them.
module XMonad.Actions.PhysicalScreens
  (PhysicalScreen(..), getScreen, viewScreen, sendToScreen) where
import XMonad.Core
import XMonad.Operations (windows)
import qualified XMonad.StackSet as W
import Data.List (sortOn)

newtype PhysicalScreen = P Int deriving (Eq, Ord, Show, Read)

-- The ScreenId at that physical position, if a display is there.
getScreen :: PhysicalScreen -> X (Maybe ScreenId)
getScreen (P n) = do
  screens <- gets (W.screens . windowset)
  let ordered = sortOn corner screens
      corner sc = let r = screenRect (W.screenDetail sc) in (rect_x r,rect_y r)
  pure $ if n < 0 || n >= length ordered
    then Nothing
    else Just (W.screen (ordered !! n))

viewScreen :: PhysicalScreen -> X ()
viewScreen p = onScreen p W.view

sendToScreen :: PhysicalScreen -> X ()
sendToScreen p = onScreen p W.shift

onScreen :: PhysicalScreen -> (WorkspaceId -> WindowSet -> WindowSet) -> X ()
onScreen p f = do
  target <- getScreen p
  whenJust target $ \sid -> do
    tag <- gets (W.lookupWorkspace sid . windowset)
    whenJust tag (windows . f)
