"""Runs every regression case through the desktop CLI's serve and the Wasm
engine with the same requests, and compares the answers."""
import json, pathlib, subprocess, sys, time

REPO = pathlib.Path(__file__).resolve().parents[2]
PATTERNS = REPO / 'tests' / 'patterns'
ENGINE = pathlib.Path(__file__).resolve().parent

def requests(prefix, pattern, mset):
    calls = [
        ('open', {'path': f'{prefix}{pattern}', 'measurements': f'{prefix}{mset}'}),
        ('list_objects', {}),
        ('check', {}),
        ('render', {'format': 'svg'}),
    ]
    return ''.join(json.dumps({'jsonrpc': '2.0', 'id': i + 1, 'method': m, 'params': p}) + '\n'
                   for i, (m, p) in enumerate(calls))

def run(cmd, text):
    start = time.perf_counter()
    out = subprocess.run(cmd, input=text, capture_output=True, text=True, timeout=120).stdout
    return [json.loads(line) for line in out.splitlines() if line.strip()], time.perf_counter() - start

def diff(a, b, path, found):
    if isinstance(a, dict) and isinstance(b, dict):
        for k in sorted(set(a) | set(b)):
            if k in ('path', 'measurements', 'identity'):
                continue
            diff(a.get(k), b.get(k), f'{path}.{k}', found)
    elif isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            found.append(f'{path}: {len(a)} items vs {len(b)}')
        for i, (x, y) in enumerate(zip(a, b)):
            diff(x, y, f'{path}[{i}]', found)
    elif isinstance(a, (int, float)) and isinstance(b, (int, float)) and not isinstance(a, bool):
        if abs(a - b) > 1e-6 * max(1, abs(a)):
            found.append(f'{path}: {a} vs {b}')
    elif a != b:
        found.append(f'{path}: {str(a)[:80]!r} vs {str(b)[:80]!r}')

total = 0
for expected in sorted(PATTERNS.glob('*.expected.json')):
    pattern, mset = expected.name[:-len('.expected.json')].split('.', 1)
    pattern += '.sloper'; mset += '.slm'
    desk, tdesk = run([str(REPO / 'release' / 'opensloper-cli'), 'serve'], requests(f'{PATTERNS}/', pattern, mset))
    wasm, twasm = run(['node', '--no-warnings', str(ENGINE / 'run.mjs'), str(PATTERNS)], requests('/data/', pattern, mset))
    found = []
    diff(desk, wasm, '', found)
    total += len(found)
    print(f'{pattern} + {mset}: {len(found)} differences; desktop {tdesk*1000:.0f} ms, wasm {twasm*1000:.0f} ms')
    for f in found[:15]:
        print('   ', f)
sys.exit(1 if total else 0)
