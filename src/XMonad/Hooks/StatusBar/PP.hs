-- Adapted from xmonad-contrib XMonad.Hooks.StatusBar.PP (BSD-3-Clause),
-- Copyright (c) Don Stewart, Tomas Janousek and the Xmonad Community.
-- macOS has no urgency hints, so ppUrgent is not ported. stdout carries the
-- helper protocol, so the default ppOutput writes to stderr (bridge.log).
module XMonad.Hooks.StatusBar.PP
  ( PP(..), Default(..), dynamicLogString, dynamicLogWithPP, pprWindowSet
  , xmobarPP, sjanssenPP, wrap, pad, trim, shorten, shorten', shortenLeft
  , xmobarColor, xmobarFont, xmobarRaw, xmobarStrip
  , filterOutWsPP, getSortByIndex, getSortByTag
  ) where
import Data.Char (isSpace)
import Data.List (intercalate, isPrefixOf, sortOn)
import qualified Data.Map.Strict as M
import System.IO (hPutStrLn, stderr)
import XMonad.Core
import XMonad.Config (Default(..))
import qualified XMonad.StackSet as W

data PP = PP
  { ppCurrent, ppVisible, ppHidden, ppHiddenNoWindows :: WorkspaceId -> String
  , ppSep, ppWsSep :: String
  , ppTitle, ppTitleSanitize, ppLayout :: String -> String
  , ppOrder :: [String] -> [String]
  , ppSort :: X ([WindowSpace] -> [WindowSpace])
  , ppExtras :: [X (Maybe String)]
  , ppOutput :: String -> IO ()
  }
instance Default PP where
  def = PP
    { ppCurrent = wrap "[" "]", ppVisible = wrap "<" ">", ppHidden = id
    , ppHiddenNoWindows = const "", ppSep = " : ", ppWsSep = " "
    , ppTitle = shorten 80, ppTitleSanitize = filter (`notElem` "\n\r")
    , ppLayout = id, ppOrder = id, ppSort = getSortByIndex
    , ppExtras = [], ppOutput = hPutStrLn stderr }

dynamicLogWithPP :: PP -> X ()
dynamicLogWithPP pp = dynamicLogString pp >>= io . ppOutput pp

-- The title is the snapshot's AXTitle of the focused window.
dynamicLogString :: PP -> X String
dynamicLogString pp = do
  ws <- gets windowset
  info <- gets windowInfo
  sort' <- ppSort pp
  extras <- mapM (`catchX` pure Nothing) (ppExtras pp)
  let ld = description . W.layout . W.workspace . W.current $ ws
      title = maybe "" titleText (W.peek ws >>= (`M.lookup` info))
  pure $ sepBy (ppSep pp) . ppOrder pp $
    [ pprWindowSet sort' pp ws, ppLayout pp ld
    , ppTitle pp (ppTitleSanitize pp title) ] ++ map (maybe "" id) extras

pprWindowSet :: ([WindowSpace] -> [WindowSpace]) -> PP -> WindowSet -> String
pprWindowSet sort' pp ws = sepBy (ppWsSep pp) . map fmt . sort' $
  map W.workspace (W.current ws : W.visible ws) ++ W.hidden ws
  where
    visibles = map (W.tag . W.workspace) (W.visible ws)
    fmt w | W.tag w == W.currentTag ws = ppCurrent pp (W.tag w)
          | W.tag w `elem` visibles = ppVisible pp (W.tag w)
          | Just _ <- W.stack w = ppHidden pp (W.tag w)
          | otherwise = ppHiddenNoWindows pp (W.tag w)

-- Config order, with generated tags (e.g. "NSP") after it.
getSortByIndex :: X ([WindowSpace] -> [WindowSpace])
getSortByIndex = do
  tags <- asks (workspaces . config)
  let rank t = maybe (length tags) id (lookup t (zip tags [0 :: Int ..]))
  pure (sortOn (rank . W.tag))

getSortByTag :: X ([WindowSpace] -> [WindowSpace])
getSortByTag = pure (sortOn W.tag)

filterOutWsPP :: [WorkspaceId] -> PP -> PP
filterOutWsPP tags pp =
  pp {ppSort = (. filter ((`notElem` tags) . W.tag)) <$> ppSort pp}

sepBy :: String -> [String] -> String
sepBy sep = intercalate sep . filter (not . null)

wrap :: String -> String -> String -> String
wrap _ _ "" = ""
wrap l r m = l ++ m ++ r

pad :: String -> String
pad = wrap " " " "

trim :: String -> String
trim = f . f where f = reverse . dropWhile isSpace

shorten :: Int -> String -> String
shorten = shorten' "..."

shorten' :: String -> Int -> String -> String
shorten' end n xs | length xs < n = xs
                  | otherwise = take (n - length end) xs ++ end

shortenLeft :: Int -> String -> String
shortenLeft n xs | length xs < n = xs
                 | otherwise = "..." ++ reverse (take (n - 3) (reverse xs))

xmobarColor :: String -> String -> String -> String
xmobarColor fg bg = wrap t "</fc>"
  where t = concat ["<fc=", fg, if null bg then "" else "," ++ bg, ">"]

xmobarFont :: Int -> String -> String
xmobarFont index = wrap ("<fn=" ++ show index ++ ">") "</fn>"

xmobarRaw :: String -> String
xmobarRaw "" = ""
xmobarRaw s = concat ["<raw=", show (length s), ":", s, "/>"]

xmobarStrip :: String -> String
xmobarStrip s = case s of
  _ | Just r <- after "<fc=" -> xmobarStrip (drop 1 (dropWhile (/= '>') r))
    | Just r <- after "<fn=" -> xmobarStrip (drop 1 (dropWhile (/= '>') r))
    | Just r <- after "</fc>" -> xmobarStrip r
    | Just r <- after "</fn>" -> xmobarStrip r
  c:cs -> c : xmobarStrip cs
  [] -> []
  where after t = if t `isPrefixOf` s then Just (drop (length t) s) else Nothing

xmobarPP :: PP
xmobarPP = def
  { ppCurrent = xmobarColor "yellow" "" . wrap "[" "]"
  , ppTitle = xmobarColor "green" "" . shorten 40
  , ppVisible = wrap "(" ")"
  , ppTitleSanitize = xmobarStrip . ppTitleSanitize def }

sjanssenPP :: PP
sjanssenPP = def
  { ppCurrent = xmobarColor "white" "black"
  , ppTitle = xmobarColor "#00ee00" "" . shorten 120 }
