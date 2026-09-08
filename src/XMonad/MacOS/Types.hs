{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}
-- Types shared by policy and protocol. Deliberately free of X11: geometry is
-- logical points with a top-left origin, as AX and Quartz use, and a Window
-- is a handle the helper hands out, not an XID.
module XMonad.MacOS.Types where
import Data.Aeson
import Data.Word (Word64)
import GHC.Generics (Generic)

-- Logical AX handle, NOT an XID or CGWindowID. Valid for one bridge session.
type Window = Word64
type WorkspaceId = String
type ScreenId = Int
type KeyMask = Int
type KeySym = Int
-- Signed coordinates, logical points, Quartz global top-left origin.
type Position = Int
type Dimension = Int
data Rectangle = Rectangle
  { rect_x :: !Position, rect_y :: !Position
  , rect_width :: !Dimension, rect_height :: !Dimension
  } deriving (Eq, Ord, Read, Show)
instance ToJSON Rectangle where
  toJSON (Rectangle x y w h) = object ["x" .= x,"y" .= y,"width" .= w,"height" .= h]
instance FromJSON Rectangle where
  parseJSON = withObject "Rectangle" $ \o ->
    Rectangle <$> o .: "x" <*> o .: "y" <*> o .: "width" <*> o .: "height"
data ScreenDetail = SD { screenRect :: !Rectangle, displayID :: !Int }
  deriving (Show, Read, Eq)
data DisplayInfo = DisplayInfo { display :: !Int, usable :: !Rectangle }
  deriving (Show, Eq, Generic)
instance FromJSON DisplayInfo
instance ToJSON DisplayInfo
data WindowInfo = WindowInfo
  { wid :: !Window, pid :: !Int, app :: !String, bundle :: !String
  , titleText :: !String, onDisplay :: !Int, frame :: !Rectangle
  , minimized :: !Bool, ownedHidden :: !Bool
  } deriving (Show, Eq, Generic)
instance FromJSON WindowInfo
instance ToJSON WindowInfo

-- Numerically compatible with the commonly used X modifier masks.
shiftMask, lockMask, controlMask, mod1Mask, mod2Mask, mod3Mask, mod4Mask, mod5Mask :: KeyMask
shiftMask=1
lockMask=2
controlMask=4
mod1Mask=8
mod2Mask=16
mod3Mask=32
mod4Mask=64
mod5Mask=128
xK_Return, xK_space, xK_Tab, xK_Escape, xK_BackSpace, xK_Delete :: KeySym
xK_Return=0xff0d
xK_space=0x20
xK_Tab=0xff09
xK_Escape=0xff1b
xK_BackSpace=0xff08
xK_Delete=0xffff
xK_Left, xK_Up, xK_Right, xK_Down, xK_Home, xK_End, xK_Page_Up, xK_Page_Down :: KeySym
xK_Left=0xff51
xK_Up=0xff52
xK_Right=0xff53
xK_Down=0xff54
xK_Home=0xff50
xK_End=0xff57
xK_Page_Up=0xff55
xK_Page_Down=0xff56
xK_j,xK_k,xK_h,xK_l,xK_m,xK_q,xK_c,xK_t,xK_f,xK_n,xK_p,xK_w,xK_e,xK_r :: KeySym
xK_j=106
xK_k=107
xK_h=104
xK_l=108
xK_m=109
xK_q=113
xK_c=99
xK_t=116
xK_f=102
xK_n=110
xK_p=112
xK_w=119
xK_e=101
xK_r=114
xK_1,xK_2,xK_3,xK_4,xK_5,xK_6,xK_7,xK_8,xK_9,xK_0,xK_comma,xK_period :: KeySym
xK_1=49
xK_2=50
xK_3=51
xK_4=52
xK_5=53
xK_6=54
xK_7=55
xK_8=56
xK_9=57
xK_0=48
xK_comma=44
xK_period=46
