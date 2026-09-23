-- Emacs-style key descriptions, as a config writes them: "M-S-<Return>", or
-- a sequence of strokes such as "M-x M-s" that becomes a submap. An
-- unsupported key name, or a key that is also a prefix, is an error rather
-- than a binding that silently never fires.
module XMonad.Util.EZConfig
  (additionalKeys, additionalKeysP, removeKeys, removeKeysP
  , additionalMouseBindings, mkKeymap, checkKeymap, keymapProblems
  , parseKey, parseKeySequence) where
import XMonad.Core
import XMonad.Actions.Submap (submap)
import qualified Data.Map.Strict as M
import Data.Char (ord, toLower)
import Data.Bits ((.|.))
import Data.Function (on)
import Data.List (stripPrefix, groupBy, nub, isPrefixOf)
import System.IO (hPutStrLn, stderr)
import Text.Read (readMaybe)

-- Added bindings win over the defaults they collide with.
additionalKeys :: XConfig l -> [((KeyMask,KeySym), X ())] -> XConfig l
additionalKeys c ks = c {keys = \base -> M.union (M.fromList ks) (keys c base)}

additionalKeysP :: XConfig l -> [(String,X ())] -> XConfig l
additionalKeysP c ks = c {keys = \base -> M.union (mkKeymap base ks) (keys c base)}

removeKeys :: XConfig l -> [(KeyMask,KeySym)] -> XConfig l
removeKeys c ks = c {keys = \base -> foldr M.delete (keys c base) ks}

removeKeysP :: XConfig l -> [String] -> XConfig l
-- As upstream, a sequence removes its whole first stroke.
removeKeysP c ks = c {keys = \base ->
  M.difference (keys c base) (mkKeymap base [(k,pure ()) | k <- ks])}

-- Added mouse gestures win over the defaults they collide with.
additionalMouseBindings :: XConfig l -> [((KeyMask, Button), MouseAction)] -> XConfig l
additionalMouseBindings c ms =
  c {mouseBindings = \base -> M.union (M.fromList ms) (mouseBindings c base)}

-- Strokes sharing a first key share one submap; a repeated sequence keeps
-- its last action, as M.fromList would.
mkKeymap :: XConfig l -> [(String,X ())] -> M.Map (KeyMask,KeySym) (X ())
mkKeymap c ks = either (error . ("XMonadMac key binding: "++)) id $ do
  seqs <- parseKeymap c ks
  mapM_ Left (take 1 (prefixProblems (zip (map fst ks) seqs)))
  pure (build (M.toList (M.fromList (zip seqs (map snd ks)))))
  where
    build bs = M.fromList
      [ (k, case g of [([_],a)] -> a; _ -> submap (build [(ss,a) | (_:ss,a) <- g]))
      | g@((k:_,_):_) <- groupBy ((==) `on` (take 1 . fst)) bs ]

-- Upstream reports through xmessage; here the engine's log is stderr.
checkKeymap :: XConfig l -> [(String,a)] -> X ()
checkKeymap c ks = io $ mapM_ (hPutStrLn stderr . ("XMonadMac key binding: "++))
  (keymapProblems c ks)

keymapProblems :: XConfig l -> [(String,a)] -> [String]
keymapProblems c ks = case parseKeymap c ks of
  Left p -> [p]
  Right seqs -> let named = zip (map fst ks) seqs in
    ["duplicate binding " ++ show s | (i,(s,x)) <- zip [0..] named, x `elem` take i seqs]
    ++ prefixProblems named

parseKeymap :: XConfig l -> [(String,a)] -> Either String [[(KeyMask,KeySym)]]
parseKeymap c = mapM (parseKeySequence (modMask c) . fst)

prefixProblems :: [(String,[(KeyMask,KeySym)])] -> [String]
prefixProblems named = nub
  [ show a ++ " is also the prefix of " ++ show b
  | (a,x) <- named, (b,y) <- named, length x < length y, x `isPrefixOf` y ]

parseKeySequence :: KeyMask -> String -> Either String [(KeyMask,KeySym)]
parseKeySequence m s = case words s of
  [] -> Left ("empty key binding: " ++ show s)
  ws -> mapM (parseKey m) ws

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
