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
        plan = key(32); assert plan['layout'] == 'Mirror Tall', plan
        # Full hides other tiled windows; the floating window 1 stays visible.
        plan = key(32)
        assert plan['layout'] == 'Full' and plan['hide'] == [], plan
        assert sorted(x['wid'] for x in plan['frames']) == [1, 2], plan
        plan = key(ord('2')); assert plan['workspace'] == '2' and sorted(plan['hide']) == [1,2]
        plan = key(ord('1')); assert plan['workspace'] == '1'
        plan = key(ord('2'), mod | 1); assert plan['workspace'] == '1'
        plan = key(ord('2')); assert plan['workspace'] == '2' and len(plan['frames']) == 1
        checkpoint = plan['checkpoint']
        assert checkpoint['savedVersion'] == 1
        assert send({'type':'ping'})['type'] == 'pong'
        p.stdin.write('{"type":"exit"}\n'); p.stdin.flush(); p.wait(timeout=5)
        assert p.returncode == 0
        print('PASS: compiled xmonad.hs NDJSON integration (focus/mouse-float/layout/shift/view/checkpoint/ping)')
    finally:
        if p.poll() is None:
            p.kill(); p.wait()

if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: tests/integration.py /path/to/xmonad-engine')
    run(os.path.abspath(sys.argv[1]))
