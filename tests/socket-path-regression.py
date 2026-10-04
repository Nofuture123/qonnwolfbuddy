#!/usr/bin/env python3
"""Check affected entries and exported paths against the ignored socket directory budget."""
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
from process_fixture import run

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / '.qwb-tmp'
BASE.mkdir(exist_ok=True)
# /.qwb-tmp/xx/s takes fourteen bytes; nested exports must fit the 89-byte root budget.
width = 89 - len(os.fsencode(BASE)) - 1
while True:
    directory = BASE / secrets.token_hex((max(width, 1) + 1) // 2)[:max(width, 1)]
    try:
        directory.mkdir()
        break
    except FileExistsError:
        continue


def export(destination):
    with subprocess.Popen(['git', '-C', str(ROOT), 'archive', 'HEAD'], stdout=subprocess.PIPE) as archive:
        result = subprocess.run(['tar', '-x', '-C', str(destination)], stdin=archive.stdout)
        archive.stdout.close()
        assert archive.wait() == result.returncode == 0, '源码导出失败'


try:
    export(directory)
    positive = directory if width >= 1 else ROOT
    if positive == ROOT:
        print(f'仓内最短导出根 {len(os.fsencode(directory))} 字节超过 89；'
              '正例使用当前源码根，导出副本验证断言前早报', flush=True)
    for interpreter, script, arguments in [('/bin/bash', 'tests/smoke.sh', ['root-tab-missing']),
                                           (sys.executable, 'tests/worktree-space.py', []),
                                           ('/bin/bash', 'tests/collab-herdr.sh', [])]:
        env = os.environ.copy()
        env.pop('QWB_TEST_SOCKET_DIRS', None)
        runner = subprocess.run if interpreter == sys.executable else run
        result = runner([interpreter, script, *arguments], cwd=positive, env=env,
                        capture_output=True, text=True)
        assert result.returncode == 0, (script, result.stdout, result.stderr)
        assert not any(line.startswith('FAIL') for line in result.stdout.splitlines()), result.stdout
        size = len(os.fsencode(positive)) + 14
        print(f'PASS {script}: root={len(os.fsencode(positive))} bytes, socket={size} bytes', flush=True)

    # Exercise the native 103-byte limit within an owned, ignored socket directory.
    probe = '''
from pathlib import Path
import os,socket
from process_fixture import check_socket_path,socket_path
parent=Path(socket_path()).parent
path=str(parent/('s'*(103-len(os.fsencode(parent))-1)))
check_socket_path(path)
with socket.socket(socket.AF_UNIX) as server, socket.socket(socket.AF_UNIX) as client:
    server.bind(path); server.listen(); client.connect(path)
    connection,_=server.accept(); connection.close()
print('PASS native 103-byte bind/connect inside .qwb-tmp: '+path)
'''
    result = run([sys.executable, '-B', '-c', probe], capture_output=True, text=True)
    assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
    print(result.stdout.strip(), flush=True)

    longer = directory / 'x' if width >= 1 else directory
    if width >= 1:
        longer.mkdir()
        export(longer)
    result = run(['/bin/bash', 'tests/smoke.sh'], cwd=longer, capture_output=True, text=True)
    size = len(os.fsencode(longer)) + 14
    assert result.returncode == 2, (result.returncode, result.stdout, result.stderr)
    assert f'实际 {size} 字节' in result.stderr and '上限 103 字节' in result.stderr, result.stderr
    assert '最多 89 字节' in result.stderr and '固定后缀 14 字节' in result.stderr, result.stderr
    assert not result.stdout and 'FAIL' not in result.stderr, (result.stdout, result.stderr)
    print('PASS over-budget checkout exits 2 before assertions: ' + result.stderr.strip(), flush=True)

    unicode_root = directory / '长'
    unicode_root.mkdir()
    export(unicode_root)
    result = run(['/bin/bash', 'tests/collab-herdr.sh'], cwd=unicode_root, capture_output=True, text=True)
    size = len(os.fsencode(unicode_root)) + 14
    assert result.returncode == 2 and f'实际 {size} 字节' in result.stderr, (result.returncode, result.stderr)
    assert not result.stdout and 'FAIL' not in result.stderr, (result.stdout, result.stderr)
    print('PASS UTF-8 root uses bytes before assertions: ' + result.stderr.strip(), flush=True)
finally:
    shutil.rmtree(directory)
