-- Emacs-style key descriptions, as a config writes them: "M-S-<Return>".
-- Single strokes only; an unsupported chord or key name is an error rather
-- than a binding that silently never fires.
module XMonad.Util.EZConfig
  (additionalKeys, additionalKeysP, removeKeys, removeKeysP, parseKey) where
import XMonad.Core
import qualified Data.Map.Strict as M
import Data.Char (ord, toLower)
import Data.Bits ((.|.))
import Data.List (stripPrefix)
import Text.Read (readMaybe)

-- Added bindings win over the defaults they collide with.
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
parseOrFail m s =
  either (error . ("XMonadMac key binding: "++)) id (parseKey m s)

-- "M-" is whatever modMask the config chose; the rest name themselves.
modifierPrefixes :: KeyMask -> [(String,KeyMask)]
modifierPrefixes m =
  [("M-",m),("M1-",mod1Mask),("M4-",mod4Mask)
  ,("C-",controlMask),("S-",shiftMask),("A-",mod1Mask)]

namedKeys :: [(String,KeySym)]
namedKeys =
  [("<Return>",xK_Return),("<Space>",xK_space),("<Tab>",xK_Tab)
  ,("<Escape>",xK_Escape),("<Backspace>",xK_BackSpace),("<Delete>",xK_Delete)
  ,("<Left>",xK_Left),("<Right>",xK_Right),("<Up>",xK_Up),("<Down>",xK_Down)
  ,("<Home>",xK_Home),("<End>",xK_End)
  ,("<Page_Up>",xK_Page_Up),("<Page_Down>",xK_Page_Down)]

-- Modifiers come off the front one at a time; what remains must be a single
-- printable character, a named key, or a function key.
parseKey :: KeyMask -> String -> Either String (KeyMask,KeySym)
parseKey m = go 0
  where
    go mask s = case [(mask .|. bit,rest) | (prefix,bit) <- modifierPrefixes m
                     , Just rest <- [stripPrefix prefix s]] of
      (mask',rest):_ -> go mask' rest
      [] -> (,) mask <$> keySym s

    keySym s
      | [c] <- s, ord c >= 32, ord c < 127 = Right (ord (toLower c))
      | Just k <- lookup s namedKeys = Right k
      | Just n <- functionKey s = Right (0xffbd+n)
      | otherwise = Left ("unsupported single-stroke key: " ++ show s)

    functionKey s = do
      body <- stripPrefix "<F" s
      case reverse body of
        '>':digits -> do
          n <- readMaybe (reverse digits) :: Maybe Int
          if n >= 1 && n <= 20 then Just n else Nothing
        _ -> Nothing
