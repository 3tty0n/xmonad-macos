#!/usr/bin/env python3
"""Static packaging/protocol guards; not a Haskell compiler or macOS runtime test."""
from pathlib import Path
import plistlib, re
root=Path(__file__).resolve().parents[1]
checks=0
def check(value, message):
    global checks
    assert value, message
    checks += 1
for path in (root/'src').rglob('*.hs'):
    src=path.read_text()
    for module in re.findall(r'^import\s+(?:qualified\s+)?(XMonad(?:\.[A-Za-z0-9_]+)*)',src,re.M):
        check((root/'src'/(module.replace('.','/')+'.hs')).is_file(),f'{path}: missing {module}')
    check('import Graphics.X11' not in src, f'X11 dependency leaked into {path}')
for name in ['README.md','LICENSE','CHANGELOG.md','docs/DESIGN.md','docs/COMPATIBILITY.md','docs/PROTOCOL.md','docs/TESTING.md','docs/UPSTREAM.md','native/Pointer.swift']:
    check((root/name).is_file(), f'Missing deliverable {name}')
info=plistlib.loads((root/'native/Info.plist').read_bytes())
check(info['CFBundleIdentifier']=='org.xmonad.XMonadMac','Bundle identity changed')
check(info['LSUIElement'] is True,'Menu bar app flag missing')
check(info['LSMinimumSystemVersion']=='13.0','Deployment targets disagree')
app=(root/'native/App.swift').read_text()
for literal in ['--no-startup','--dry-run','--validate-config','--self-test','runToken','checkpoint','O_NOFOLLOW','recompileConfig','Paths.recompile','Open xmonad.hs','PointerTap','mouseFloat']:
    check(literal in app, f'Missing native contract {literal}')
ax=(root/'native/Accessibility.swift').read_text()
check(ax.index('try journal.add(entry)') < ax.index('r.hideRequestedAt=Date()'),'Journal must precede hiding')
check('parkingSpot' in ax and 'onAnyDisplay' in ax,'Off-screen parking missing')
wire=(root/'native/Wire.swift').read_text()
check('workspaceRow' in wire,'Workspace indicator missing')
check('beginPointerDrag' in ax and 'pointerDrag?.wid' in ax,'Native pointer drag safety missing')
check('runAXSelfTest' in ax and 'readBackMatched' in ax,'AX self-test/read-back missing')
check('pointerPendingPoint' in app and 'pointerUpdateInFlight' in app,'Pointer AX updates are not coalesced')
check('_AXUIElementGetWindow' not in ax and not re.search(r'\b_?(?:CGS|SLS)[A-Z]\w*\s*\(', ax),'Private API introduced')
engine=(root/'src/XMonad/MacOS/Engine.hs').read_text()
check('focusAgeTicks base < 4' in engine,'Bound focus retry lifetime')
check('not (ownedHidden wi)' in engine,'Do not follow WM-owned hide animations')
protocol=(root/'src/XMonad/MacOS/Protocol.hs').read_text()
check('Recompile -> named "recompile"' in protocol,'Recompile command protocol missing')
check('MouseFloatEvent' in protocol,'Mouse float protocol missing')
config=(root/'src/XMonad/Config.hs').read_text()
check('commands=commands s ++ [Recompile]' in config,'M-q must safely recompile config')
native_build=(root/'scripts/build-native.sh').read_text()
check('native/Pointer.swift' in native_build,'Native build omits pointer backend')
install=(root/'scripts/install.sh').read_text()
for literal in ['build-kit','recompile-installed.sh','xmonadctl.sh','autostart.sh']:
    check(literal in install,f'Install integration missing {literal}')
check('mouseMask' in engine and 'floatObservedWindow' in engine,'Haskell mouse policy integration missing')
for name in ['scripts/recompile-installed.sh','scripts/xmonadctl.sh','scripts/autostart.sh']:
    check((root/name).is_file(),f'Missing operations helper {name}')
for path in (root/'scripts').glob('*.sh'):
    check(path.read_text().startswith('#!/bin/bash'), f'Wrong shell: {path}')
    check(path.stat().st_mode & 0o111, f'Not executable: {path}')
print(f'PASS: {checks} static source/packaging checks (not SDK/GHC compilation)')
