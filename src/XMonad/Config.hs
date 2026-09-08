module XMonad.Config (def, defaultConfig, defaultKeys) where
import XMonad.Core
import XMonad.Layout
import XMonad.Operations
import qualified XMonad.StackSet as W
import qualified Data.Map.Strict as M
import Data.Bits ((.|.))

def, defaultConfig :: XConfig (Choose Tall (Choose (Mirror Tall) Full))
def = defaultConfig
defaultConfig = XConfig
  {terminal="open -a Terminal", modMask=mod1Mask
  ,workspaces=map show ([1..9] :: [Int]) ++ ["0"]
  ,layoutHook=Tall 1 (3/100) (1/2) ||| Mirror (Tall 1 (3/100) (1/2)) ||| Full
  ,keys=defaultKeys, manageHook=mempty, startupHook=pure (), logHook=pure ()}
defaultKeys :: XConfig Layout -> M.Map (KeyMask,KeySym) (X ())
defaultKeys c = M.fromList $
  [((m,xK_Return),spawn $ terminal c)
  ,((m,xK_j),windows W.focusDown),((m,xK_k),windows W.focusUp)
  ,((m,xK_Tab),windows W.focusDown),((m,xK_m),windows W.focusMaster)
  ,((m .|. shiftMask,xK_j),windows W.swapDown)
  ,((m .|. shiftMask,xK_k),windows W.swapUp)
  ,((m .|. shiftMask,xK_Return),windows W.swapMaster)
  ,((m,xK_h),sendMessage Shrink),((m,xK_l),sendMessage Expand)
  ,((m,xK_comma),sendMessage $ IncMasterN 1)
  ,((m,xK_period),sendMessage $ IncMasterN (-1))
  ,((m,xK_space),sendMessage NextLayout)
  ,((m .|. shiftMask,xK_space),setLayout $ layoutHook c)
  ,((m .|. shiftMask,xK_c),kill)
  ,((m,xK_t),withFocused $ windows . W.sink)
  ,((m,xK_n),refresh)
  ,((m,xK_q),modify $ \s -> s {commands=commands s ++ [Recompile]})
  ,((m .|. shiftMask,xK_q),modify $ \s -> s {commands=commands s ++ [Quit]})
  ] ++
  [((m .|. sm,k),windows $ f t)
    | (t,k) <- zip (workspaces c) ([xK_1..xK_9] ++ [xK_0])
    , (f,sm) <- [(W.greedyView,0),(W.shift,shiftMask)]] ++
  [((m .|. sm,k),screenWorkspace sc >>= flip whenJust (windows . f))
    | (sc,k) <- zip [0..] [xK_w,xK_e,xK_r]
    , (f,sm) <- [(W.view,0),(W.shift,shiftMask)]]
  where m = modMask c
