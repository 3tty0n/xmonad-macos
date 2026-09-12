import XMonad
import qualified XMonad.StackSet as W
import XMonad.Util.EZConfig
import XMonad.Layout.Spacing
import XMonad.Layout.ThreeColumns()
import XMonad.MacOS

main :: IO ()
main = xmonad $ def
  { terminal = "open -a Ghostty"
  , modMask = mod1Mask -- Cmd: mod4Mask. You can combine multiple keys with .|.
  -- Ten workspaces: M-1..M-9 then M-0; M-S-N moves the focused window.
  , workspaces = map show ([1..9] :: [Int]) ++ ["0"]
  -- spacing 4 means a four-point inset on each window edge (eight between tiles).
  , borderWidth = 1                -- 0 disables this
  , focusedBorderColor = "#ff0000" -- "#61afef"
  , normalBorderColor = "#dddddd"
  , focusFollowsMouse = False      -- Default: True
  , layoutHook = spacing 5 $
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
  `additionalKeysP`
    [ ("M-f", toggleFloat)
    , ("M-S-p", pause)
    , ("M-S-m", windows W.shiftMaster)
    ]
  `additionalMouseBindings`
    [ ((mod1Mask, button2), MouseRaise) ]
