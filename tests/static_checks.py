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
for literal in ['--no-startup','--dry-run','--validate-config','--self-test','runToken','checkpoint','O_NOFOLLOW','recompileConfig','--recompile','Open xmonad.hs','PointerTap','mouseFloat']:
    check(literal in app, f'Missing native contract {literal}')
ax=(root/'native/Accessibility.swift').read_text()
check(ax.index('try journal.add(entry)') < ax.index('r.hideRequestedAt=Date()'),'Journal must precede hiding')
check('parkingSpot' in ax and 'onAnyDisplay' in ax,'Off-screen parking missing')
wire=(root/'native/Wire.swift').read_text()
check('workspaceRow' in wire,'Workspace indicator missing')
check('beginPointerDrag' in ax and 'pointerDrag?.wid' in ax,'Native pointer drag safety missing')
check('runAXSelfTest' in ax and 'readBackMatched' in ax,'AX self-test/read-back missing')
check('pointerPendingPoint' in app and 'pointerUpdateInFlight' in app,'Pointer AX updates are not coalesced')
check('reply(toApplicationShouldTerminate' not in app and 'restored.wait(timeout:' in app,
      'Quit must bound its wait instead of replying on the undrained main queue')
border=(root/'native/Border.swift').read_text()
check('overlayWindow' in border and 'orderFrontRegardless' in border,'Focus border must sit above Electron overlay windows')
check('hole(in' in border and 'evenOdd' in border,
      'Unfocused borders must clip out the focused window so a float is not covered')
check('animationBehavior' in border and 'alphaValue' in border,
      'Focus border must not orderOut and fade back in after a workspace switch')
check('tracesFocusBorder' in wire and 'tracesFocusBorder' in app,
      'Focus border visibility is decided by a portable helper')
check('borderPin' in app and 'plan.focus' in app,
      'Focus border pins only to an explicit focus request, not every plan')
check('borderRest' not in app and 'rest.isEmpty ?' not in app,
      'Empty overlay rest must clear unfocused borders instead of reusing the last workspace')
check('_AXUIElementGetWindow' not in ax and not re.search(r'\b_?(?:CGS|SLS)[A-Z]\w*\s*\(', ax),'Private API introduced')
engine=(root/'src/XMonad/MacOS/Engine.hs').read_text()
check('pendingFocus' in engine and 'AckEvent' in engine,'Focus requests use action ids and native acks')
check('rescreenWith' in engine,'Display affinity survives reconnects')
check('normalBorderColor' in (root/'src/XMonad/Config.hs').read_text(),'Unfocused border colour missing')
check('mouseBindings' in (root/'src/XMonad/Config.hs').read_text(),'mouseBindings missing from the default config')
check('0.45' in ax,'Scan total latency budget missing')
check('resizeFloor' in ax and 'AXMinSize' in ax,'Resize floor must read AX minimum size')
check('takeAck' in ax and 'actionFirstSeen' in ax,'Native action acknowledgement missing')
check('session.json' in app or 'Paths.session' in app,'Helper-restart session persistence missing')
check('additionalMouseBindings' in (root/'src/XMonad/Util/EZConfig.hs').read_text(),
      'additionalMouseBindings missing')
check('not (ownedHidden wi)' in engine,'Do not follow WM-owned hide animations')
check('W.findTag w (windowset s)' in engine and '`elem` mapped' in engine,
      'Observed focus must not switch to a hidden workspace')
protocol=(root/'src/XMonad/MacOS/Protocol.hs').read_text()
check('Recompile -> named "recompile"' in protocol,'Recompile command protocol missing')
check('MouseFloatEvent' in protocol,'Mouse float protocol missing')
config=(root/'src/XMonad/Config.hs').read_text()
# Bind-and-reach rather than an exact source line, so refactoring the config
# cannot silently drop the safe recompile path.
check(re.search(r'xK_q\s*\)\s*,\s*recompile', config),'M-q must recompile the config')
check(re.search(r'xK_q\s*\)\s*,\s*quit', config),'M-S-q must quit')
macos=(root/'src/XMonad/MacOS.hs').read_text()
check(re.search(r'recompile\s*=\s*request Recompile', macos),'Recompile must reach the helper')
check(re.search(r'quit\s*=\s*request Quit', macos),'Quit must reach the helper')
native_build=(root/'scripts/build-native.sh').read_text()
check('native/Pointer.swift' in native_build,'Native build omits pointer backend')
install=(root/'scripts/install.sh').read_text()
for literal in ['build-kit']:
    check(literal in install,f'Install integration missing {literal}')
check('scripts/recompile-installed.sh' not in install and 'scripts/autostart.sh' not in install,
      'Installed instance must not copy shell recompile/autostart helpers')
check('rm -f "$SUPPORT/recompile.sh"' in install,
      'Install should remove leftover copied recompile/autostart helpers')
cli=(root/'src/XMonad/MacOS/CLI.hs').read_text()
check("bin/xmonad-engine" not in install and 'xmonad-engine" "$HOME/.local/bin/xmonad"' in install,
      'xmonad must be the compiled config binary')
check('recompileInstalled' in cli and 'launchPlist' in cli,
      'Recompile and autostart must live in the Haskell CLI')
for command in ['status','recompile','--restart','autostart','self-test','recover','start','doctor']:
    check(f'"{command}"' in cli, f'CLI is missing {command}')
for gone in ['recompile-installed.sh','autostart.sh','doctor.sh','recover.sh','reload.sh','run.sh','prepare-config.sh']:
    check(not (root/'scripts'/gone).exists(), f'{gone} belongs in the Haskell CLI, not scripts/')
check(not (root/'tests'/'ops_smoke.sh').exists(), 'Atomic recompile belongs in CoreTests, not ops_smoke.sh')
check('mouseMask' in engine and 'floatObservedWindow' in engine,'Haskell mouse policy integration missing')
check('isDialog --> doFloat' in engine,'Dialogs must float by default')
check('subroleText' in (root/'src/XMonad/MacOS/Types.hs').read_text(),'Window subrole missing from protocol types')
check('isManagedPopupSubrole' in wire and 'cgWindowIsApplicationLayer' in wire,'Popup admission helpers missing')
check('bundleOmitsOnScreenCGWindows' in wire,'Chrome CGWindow omission helper missing')
check('parkedOffDisplay' in wire and 'cgShowsOriginal' in wire,'Hide verification against the window server missing')
check('parksByMinimizing' in wire and 'com.apple.finder' in wire,'Finder must hide by minimizing, not parking')
check('processStartTime' in wire and 'KERN_PROC_PID' in wire,'Process instance identity helper missing')
check('processStartTime(app.processIdentifier)' in app,'Apps without a launch date must still get a process instance')
check('windowEligible' in ax,'Popup window admission missing')
check('focusedAXWindow' in ax and 'frontmostApplication' in ax,'Chromium focus fallback missing')
check('AXEnhancedUserInterface' in ax and 'withImmediateAXGeometry' in ax,'Chromium geometry write fallback missing')
check('AXDialog' in wire and 'AXSystemDialog' in wire,'Popup subroles missing')
check('isDialog' in (root/'src/XMonad/Hooks/ManageHelpers.hs').read_text(),'isDialog helper missing')
for path in (root/'scripts').glob('*.sh'):
    check(path.read_text().startswith('#!/bin/bash'), f'Wrong shell: {path}')
    check(path.stat().st_mode & 0o111, f'Not executable: {path}')
print(f'PASS: {checks} static source/packaging checks (not SDK/GHC compilation)')
