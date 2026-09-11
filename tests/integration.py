#!/usr/bin/env python3
"""Black-box NDJSON test against the actually compiled example Haskell config."""
import json, os, select, subprocess, sys

def run(engine: str) -> None:
    p = subprocess.Popen([engine, '--no-startup'], stdin=subprocess.PIPE,
                         stdout=subprocess.PIPE, stderr=None, text=True, encoding='utf-8', bufsize=1)
    def read():
        ready, _, _ = select.select([p.stdout], [], [], 10)
        if not ready:
            raise AssertionError('Engine response timeout')
        line = p.stdout.readline()
        if not line:
            raise AssertionError(f'Engine exited with {p.poll()}')
        return json.loads(line)
    def send(obj):
        p.stdin.write(json.dumps(obj, ensure_ascii=False) + '\n'); p.stdin.flush()
        return read()
    def key(sym, mask=None):
        mask = mod if mask is None else mask
        out = send({'type':'key', 'sym':sym, 'mask':mask})
        assert out['type'] == 'plan', out
        assert set(x['wid'] for x in out['frames']).isdisjoint(out['hide'])
        return out
    try:
        hello = read(); assert hello['type'] == 'configure' and hello['protocol'] == 1
        mod = hello['mouseMask']  # Follows config/xmonad.hs instead of a fixed mask.
        def win(wid):
            return dict(wid=wid,pid=123,app='Terminal',bundle='com.apple.Terminal',
                        titleText=f'test {wid}',onDisplay=10,
                        frame=dict(x=0,y=24,width=800,height=700),minimized=False,ownedHidden=False)
        snapshot = dict(type='snapshot',generation=1,epoch=1,
                        screens=[dict(display=10,usable=dict(x=0,y=24,width=1600,height=1000))],
                        windows=[win(1),win(2)],focused=1)
        plan = send(snapshot)
        assert plan['type'] == 'plan' and len(plan['frames']) == 2 and plan['focus'] is None
        plan = send({'type':'mouseFloat','wid':1})
        assert plan['focus'] == 1, plan
        assert any(x['wid'] == 1 and x['frame'] == win(1)['frame'] for x in plan['frames']), plan
        plan = key(ord('j')); assert plan['focus'] == 2, plan
        # The layout list belongs to the config being tested, which anyone may
        # edit, so assert that NextLayout cycles rather than naming layouts.
        first = plan['layout']
        seen = []
        for _ in range(12):
            plan = key(32)
            if plan['layout'] == first:
                break
            assert plan['layout'] not in seen, ('layout repeats early', seen, plan)
            seen.append(plan['layout'])
            if plan['layout'] == 'Full':
                # Full hides nothing: the floating window 1 stays visible too.
                assert plan['hide'] == [], plan
                assert sorted(x['wid'] for x in plan['frames']) == [1, 2], plan
        assert seen, 'NextLayout did not change the layout'
        assert plan['layout'] == first, ('NextLayout did not wrap', plan)
        plan = key(ord('2')); assert plan['workspace'] == '2' and sorted(plan['hide']) == [1,2]
        plan = key(ord('1')); assert plan['workspace'] == '1'
        plan = key(ord('2'), mod | 1); assert plan['workspace'] == '1'
        plan = key(ord('2')); assert plan['workspace'] == '2' and len(plan['frames']) == 1
        # Status-bar row: every workspace with windows, current one marked.
        row = [(w['tag'], w['windows'], w['current']) for w in plan['workspaces']]
        assert ('2', 1, True) in row and ('1', 1, False) in row, plan['workspaces']
        assert [w['tag'] for w in plan['workspaces']][:3] == ['1', '2', '3'], plan
        plan = send({'type':'pointerFocus','wid':1}); assert plan['focus'] == 1, plan
        plan = send({'type':'pointerFocus','wid':2}); assert plan['focus'] == 2, plan
        # M-w / M-e follow the physical screens on a multi-display setup.
        two = dict(type='snapshot',generation=2,epoch=1,
                   screens=[dict(display=10,usable=dict(x=0,y=24,width=1600,height=1000)),
                            dict(display=20,usable=dict(x=1600,y=0,width=1200,height=800))],
                   windows=[win(1),win(2)],focused=1)
        plan = send(two)
        assert plan['screen'] == 10, plan
        plan = key(ord('e')); assert plan['screen'] == 20, plan
        plan = key(ord('w')); assert plan['screen'] == 10, plan
        popup = dict(wid=3,pid=123,app='Terminal',bundle='com.apple.Terminal',
                     titleText='Save',onDisplay=10,subrole='AXDialog',
                     frame=dict(x=120,y=80,width=320,height=180),
                     minimized=False,ownedHidden=False)
        plan = send(dict(type='snapshot',generation=3,epoch=1,
                         screens=two['screens'],
                         windows=[win(1),win(2),popup],focused=3))
        frames = {x['wid']: x['frame'] for x in plan['frames']}
        assert frames.get(3) == popup['frame'], plan
        assert 3 not in plan.get('hide', []), plan
        checkpoint = plan['checkpoint']
        assert checkpoint['savedVersion'] == 1
        assert send({'type':'ping'})['type'] == 'pong'
        p.stdin.write('{"type":"exit"}\n'); p.stdin.flush(); p.wait(timeout=5)
        assert p.returncode == 0
        print('PASS: compiled xmonad.hs NDJSON integration (focus/mouse-float/dialog-float/layout/shift/view/checkpoint/ping)')
    finally:
        if p.poll() is None:
            p.kill(); p.wait()

if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: tests/integration.py /path/to/xmonad-engine')
    run(os.path.abspath(sys.argv[1]))
