import XMonad
import qualified XMonad.StackSet as W
import XMonad.Util.EZConfig
import XMonad.Layout.Spacing
import XMonad.MacOS

main :: IO ()
main = xmonad $ def
  { terminal = "open -a Terminal"
  -- M = Option. Option-letter no longer types accented characters for bound
  -- keys; use mod4Mask for Command or controlMask .|. mod4Mask for both.
  , modMask = mod1Mask
  -- Ten workspaces: M-1..M-9 then M-0; M-S-N moves the focused window.
  , workspaces = map show ([1..9] :: [Int]) ++ ["0"]
  -- spacing 4 means a four-point inset on each window edge (eight between tiles).
  , layoutHook = spacing 4 $
      Tall 1 (3/100) (1/2) ||| Mirror (Tall 1 (3/100) (1/2)) ||| Full
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
