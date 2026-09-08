module XMonad.Util.EZConfig
  (additionalKeys, additionalKeysP, removeKeys, removeKeysP, parseKey) where
import XMonad.Core
import qualified Data.Map.Strict as M
import Data.Char (ord, toLower)
import Data.Bits ((.|.))
import Data.List (stripPrefix)
import Text.Read (readMaybe)

additionalKeys :: XConfig l -> [((KeyMask,KeySym), X ())] -> XConfig l
additionalKeys c ks = c {keys = \base -> M.union (M.fromList ks) (keys c base)}
additionalKeysP :: XConfig l -> [(String,X ())] -> XConfig l
additionalKeysP c ks = c {keys = \base -> M.union
  (M.fromList [(parseOrFail (modMask base) s,a) | (s,a) <- ks]) (keys c base)}
removeKeys :: XConfig l -> [(KeyMask,KeySym)] -> XConfig l
removeKeys c ks = c {keys = \base -> foldr M.delete (keys c base) ks}
removeKeysP :: XConfig l -> [String] -> XConfig l
removeKeysP c ks = c {keys = \base -> foldr M.delete (keys c base)
  (map (parseOrFail $ modMask base) ks)}
parseOrFail :: KeyMask -> String -> (KeyMask,KeySym)
parseOrFail m s = either (error . ("XMonadMac key binding: "++)) id (parseKey m s)
-- Single strokes only. No silent fallback for unsupported chords/key names.
parseKey :: KeyMask -> String -> Either String (KeyMask,KeySym)
parseKey m = go 0 where
  go mask s
    | Just r <- stripPrefix "M-" s = go (mask .|. m) r
    | Just r <- stripPrefix "M1-" s = go (mask .|. mod1Mask) r
    | Just r <- stripPrefix "M4-" s = go (mask .|. mod4Mask) r
    | Just r <- stripPrefix "C-" s = go (mask .|. controlMask) r
    | Just r <- stripPrefix "S-" s = go (mask .|. shiftMask) r
    | Just r <- stripPrefix "A-" s = go (mask .|. mod1Mask) r
    | [c] <- s, ord c >= 32, ord c < 127 = Right (mask,ord $ toLower c)
    | Just k <- lookup s names = Right (mask,k)
    | Just r <- stripPrefix "<F" s
    , not (null r), last r == '>'
    , Just n <- (readMaybe (init r) :: Maybe Int)
    , n >= 1, n <= 20 = Right (mask,0xffbd+n)
    | otherwise = Left $ "unsupported single-stroke key: " ++ show s
  names = [("<Return>",xK_Return),("<Space>",xK_space),("<Tab>",xK_Tab)
    ,("<Escape>",xK_Escape),("<Backspace>",xK_BackSpace),("<Delete>",xK_Delete)
    ,("<Left>",xK_Left),("<Right>",xK_Right),("<Up>",xK_Up),("<Down>",xK_Down)
    ,("<Home>",xK_Home),("<End>",xK_End),("<Page_Up>",xK_Page_Up),("<Page_Down>",xK_Page_Down)]
