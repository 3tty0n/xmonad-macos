import XMonad
import qualified XMonad.StackSet as W
import XMonad.Util.EZConfig
import XMonad.Actions.Navigation2D
import XMonad.Layout.NoBorders
import XMonad.Layout.Spacing
import XMonad.Layout.MultiToggle
import XMonad.Layout.Reflect
import XMonad.Layout.ThreeColumns()
import XMonad.MacOS

main :: IO ()
main = xmonad
  -- Directional navigation, exactly as xmonad-contrib documents it: the
  -- (up, left, down, right) tuple is on the arrow keys, which the default
  -- keymap leaves free. M-<arrow> focuses the window in that direction,
  -- M-S-<arrow> swaps this window with it, and nothing has to be removed
  -- from the defaults (M-h/j/k/l stay Shrink/Expand and focus).
  $ navigation2DP def
      ("<Up>", "<Left>", "<Down>", "<Right>")
      [ ("M-",   windowGo)
      , ("M-S-", windowSwap) ]
      False  -- True wraps around the edge of the desktop arrangement
  $ additionalKeysP
      def
        { terminal = "open -a Ghostty"
        , modMask = mod1Mask -- Cmd: mod4Mask. You can combine multiple keys with .|.
        -- Ten workspaces: M-1..M-9 then M-0; M-S-N moves the focused window.
        , workspaces = map show ([1..9] :: [Int]) ++ ["0"]
        -- spacing 4 means a four-point inset on each window edge (eight between tiles).
        , borderWidth = 1                -- 0 disables this
        , focusedBorderColor = "#ff0000" -- "#61afef"
        , normalBorderColor = "#dddddd"
        , focusFollowsMouse = False      -- Default: True
        -- smartBorders drops the border when a lone window fills the tile.
        -- M-r flips the current layout left to right.
        , layoutHook = smartBorders $ spacing 5 $ mkToggle (single REFLECTX) $
            Tall 1 (3/100) (1/2)
            ||| ThreeColMid 1 (3/100) (1/2)     -- ThreeColMid for a centred master
            ||| Circle
            ||| Mirror (Tall 1 (3/100) (1/2))
            ||| Full
        , manageHook = composeAll
            [ bundleId =? "com.apple.systempreferences" --> doFloat
            -- , bundleId =? "com.mitchellh.ghostty" --> doShift "2"
            -- , title =? "A window to leave alone" --> doIgnore
            ]
        }
      [ ("M-f", toggleFloat)
      , ("M-S-p", pause)
      , ("M-S-m", windows W.shiftMaster)
      , ("M-r", sendMessage (Toggle REFLECTX))
      -- Arrows stay on one layer, so this crosses to the floating layer and
      -- back. M-C-Space is not bound by default.
      , ("M-C-<Space>", switchLayer)
      -- Directional display focus is left out: the default M-w / M-e / M-r
      -- already pick a display by name. To add it, use M-C-<arrow>, which is
      -- also free:
      -- , ("M-C-<Up>", screenGo U False)
      -- , ("M-C-<Down>", screenGo D False)
      -- , ("M-C-<Left>", screenGo L False)
      -- , ("M-C-<Right>", screenGo R False)
      ]
  `additionalMouseBindings`
    [ ((mod1Mask, button2), MouseRaise) ]
