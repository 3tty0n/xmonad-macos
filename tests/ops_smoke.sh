#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
FAKE="$TMP/fake-bin"
SUPPORT="$HOME/Library/Application Support/XMonadMac"
KIT="$SUPPORT/build-kit"
HELPER="$HOME/Applications/XMonadMac.app/Contents/MacOS/XMonadMac"
mkdir -p "$FAKE" "$KIT/src" "$HOME/.config/xmonad-mac" "$(dirname "$HELPER")"
touch "$KIT/xmonad-macos.cabal"
echo 'main=putStrLn "config"' > "$HOME/.config/xmonad-mac/xmonad.hs"
echo old > "$SUPPORT/xmonad-engine"
chmod +x "$SUPPORT/xmonad-engine"
cat > "$TMP/fake-engine" <<'ENGINE'
#!/bin/bash
if [ "${1:-}" = --check-config ]; then echo '{"type":"configure","protocol":1,"keys":[]}'; else exit 0; fi
ENGINE
chmod +x "$TMP/fake-engine"
cat > "$FAKE/ghc" <<'EOF_GHC'
#!/bin/bash
exit 0
EOF_GHC
cat > "$FAKE/cabal" <<EOF_CABAL
#!/bin/bash
if [ "\${1:-}" = build ]; then [ "\${FAIL_BUILD:-0}" = 0 ] || exit 33; exit 0; fi
if [ "\${1:-}" = list-bin ]; then printf '%s\\n' '$TMP/fake-engine'; exit 0; fi
exit 2
EOF_CABAL
cat > "$HELPER" <<'EOF_HELPER'
#!/bin/bash
[ "${1:-}" = --validate-config ] || exit 7
exit 0
EOF_HELPER
chmod +x "$FAKE/ghc" "$FAKE/cabal" "$HELPER"
export PATH="$FAKE:/usr/bin:/bin"
"$ROOT/scripts/recompile-installed.sh"
grep -q '^#!/bin/bash' "$SUPPORT/xmonad-engine"
grep -q '"protocol":1' "$SUPPORT/configure.json"
cp "$SUPPORT/xmonad-engine" "$TMP/before-fail"
set +e
FAIL_BUILD=1 "$ROOT/scripts/recompile-installed.sh" >/dev/null 2>&1
rc=$?
set -e
[ "$rc" -eq 33 ]
cmp "$TMP/before-fail" "$SUPPORT/xmonad-engine"
echo 'PASS: installed recompile is atomic and preserves the previous engine on build failure'
