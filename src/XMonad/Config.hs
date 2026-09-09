-- The default config, and the key bindings it installs. Everything here can
-- be replaced field by field from your own xmonad.hs.
module XMonad.Config (def, defaultConfig, defaultKeys) where
import XMonad.Core
import XMonad.Layout
import XMonad.MacOS (quit, recompile)
import XMonad.Operations
import qualified XMonad.StackSet as W
import qualified Data.Map.Strict as M
import Data.Bits ((.|.))

def, defaultConfig :: XConfig (Choose Tall (Choose (Mirror Tall) Full))
def = defaultConfig
defaultConfig = XConfig
  { terminal = "open -a Terminal"
  , modMask = mod1Mask
  , workspaces = map show ([1..9] :: [Int]) ++ ["0"]
  , layoutHook = Tall 1 (3/100) (1/2) ||| Mirror (Tall 1 (3/100) (1/2)) ||| Full
  , keys = defaultKeys
  , manageHook = mempty
  , startupHook = pure ()
  , logHook = pure ()
  , borderWidth = 1
  , focusedBorderColor = "#ff0000"
  , focusFollowsMouse = True
  }

-- Upstream's bindings, with the same keys doing the same things: mod-Return
-- makes the focused window the master, mod-shift-Return launches a terminal.
defaultKeys :: XConfig Layout -> M.Map (KeyMask,KeySym) (X ())
defaultKeys c = M.fromList (windowKeys ++ layoutKeys ++ sessionKeys
                            ++ workspaceKeys ++ screenKeys)
  where
    m = modMask c
    shift = m .|. shiftMask

    windowKeys =
      [ ((m,xK_Return),windows W.swapMaster)
      , ((m,xK_j),windows W.focusDown)
      , ((m,xK_k),windows W.focusUp)
      , ((m,xK_Tab),windows W.focusDown)
      , ((m,xK_m),windows W.focusMaster)
      , ((shift,xK_j),windows W.swapDown)
      , ((shift,xK_k),windows W.swapUp)
      , ((shift,xK_c),kill)
      , ((m,xK_t),withFocused $ windows . W.sink)
      ]

    layoutKeys =
      [ ((m,xK_h),sendMessage Shrink)
      , ((m,xK_l),sendMessage Expand)
      , ((m,xK_comma),sendMessage $ IncMasterN 1)
      , ((m,xK_period),sendMessage $ IncMasterN (-1))
      , ((m,xK_space),sendMessage NextLayout)
      , ((shift,xK_space),setLayout $ layoutHook c)
      , ((m,xK_n),refresh)
      ]

    sessionKeys =
      [ ((shift,xK_Return),spawn $ terminal c)
      , ((m,xK_q),recompile)
      , ((shift,xK_q),quit)
      ]

    -- View a workspace, or send the focused window to it.
    workspaceKeys =
      [ ((m .|. extra,key),windows (action tag))
      | (tag,key) <- zip (workspaces c) ([xK_1..xK_9] ++ [xK_0])
      , (action,extra) <- [(W.greedyView,0),(W.shift,shiftMask)]
      ]

    -- The same, for the workspace showing on another screen.
    screenKeys =
      [ ((m .|. extra,key),screenWorkspace sc >>= flip whenJust (windows . action))
      | (sc,key) <- zip [0..] [xK_w,xK_e,xK_r]
      , (action,extra) <- [(W.view,0),(W.shift,shiftMask)]
      ]
