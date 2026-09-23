{-# LANGUAGE FlexibleContexts #-}
-- Adapted from xmonad-contrib XMonad.Util.NamedScratchpad (BSD-3-Clause),
-- Copyright (c) 2009 Spencer Janssen and the Xmonad Community. Upstream keeps
-- its scratchpad map in ExtensibleState; this port has none, so the APIs built
-- on it (exclusives, dynamic scratchpads, nsHideOnFocusLoss) are not provided.
module XMonad.Util.NamedScratchpad
  ( NamedScratchpad(..), NamedScratchpads, scratchpadWorkspaceTag
  , nonFloating, defaultFloating, customFloating
  , namedScratchpadAction, customRunNamedScratchpadAction
  , namedScratchpadManageHook
  ) where
import XMonad
import XMonad.Hooks.ManageHelpers (doRectFloat)
import qualified XMonad.StackSet as W
import Control.Monad (filterM, unless)
import Data.List (find)
import Data.List.NonEmpty (NonEmpty(..))
import qualified Data.List.NonEmpty as NE

data NamedScratchpad = NS
  { name :: String
  , cmd :: String
  , query :: Query Bool
  , hook :: ManageHook
  }

type NamedScratchpads = [NamedScratchpad]

-- The workspace a hidden scratchpad is parked on. It is not one of the
-- configured workspaces, so it is never shown.
scratchpadWorkspaceTag :: String
scratchpadWorkspaceTag = "NSP"

nonFloating :: ManageHook
nonFloating = idHook

defaultFloating :: ManageHook
defaultFloating = doFloat

customFloating :: W.RationalRect -> ManageHook
customFloating = doRectFloat

namedScratchpadManageHook :: NamedScratchpads -> ManageHook
namedScratchpadManageHook = composeAll . map (\c -> query c --> hook c)

-- Show the named scratchpad, or hide it if it is already on this workspace.
namedScratchpadAction :: NamedScratchpads -> String -> X ()
namedScratchpadAction = customRunNamedScratchpadAction runApplication

customRunNamedScratchpadAction :: (NamedScratchpad -> X ())
                               -> NamedScratchpads -> String -> X ()
customRunNamedScratchpadAction =
  someNamedScratchpadAction (\action ws -> action (NE.head ws))

someNamedScratchpadAction :: ((Window -> X ()) -> NonEmpty Window -> X ())
                          -> (NamedScratchpad -> X ())
                          -> NamedScratchpads -> String -> X ()
someNamedScratchpadAction f runApp nsps scratchpadName =
  case find ((== scratchpadName) . name) nsps of
    Nothing -> pure ()
    Just conf -> withWindowSet $ \winSet -> do
      here <- filterM (runQuery (query conf)) (W.index winSet)
      case NE.nonEmpty here of
        Just wins -> shiftToNSP (W.workspaces winSet) (\action -> f action wins)
        Nothing -> do
          anywhere <- filterM (runQuery (query conf)) (W.allWindows winSet)
          case NE.nonEmpty anywhere of
            Just wins -> f (windows . W.shiftWin (W.currentTag winSet)) wins
            Nothing -> runApp conf

runApplication :: NamedScratchpad -> X ()
runApplication = spawn . cmd

-- Hiding means moving the window to a workspace that is never shown. Like
-- upstream's addHiddenWorkspace, that workspace is created on demand.
shiftToNSP :: [WindowSpace] -> ((Window -> X ()) -> X ()) -> X ()
shiftToNSP spaces f = do
  unless (any ((== scratchpadWorkspaceTag) . W.tag) spaces) $
    modifyWindowSet $ \ws -> ws {W.hidden = W.Workspace scratchpadWorkspaceTag
      (W.layout (W.workspace (W.current ws))) Nothing : W.hidden ws}
  f (windows . W.shiftWin scratchpadWorkspaceTag)
