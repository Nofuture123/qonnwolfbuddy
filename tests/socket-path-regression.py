#!/usr/bin/env python3
"""Export this commit at the socket budget boundary and exercise real test entries."""
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
# /.xx/s takes six bytes. Put the exported checkout exactly at the 97-byte root budget.
width = 97 - len(os.fsencode(BASE)) - 1
if width < 1:
    sys.exit('本回归需在仓库根不超过 86 字节的位置运行，以在仓内导出边界副本')
while True:
    directory = BASE / secrets.token_hex((width + 1) // 2)[:width]
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
    for interpreter, script, arguments in [('/bin/bash', 'tests/smoke.sh', ['root-tab-missing']),
                                           (sys.executable, 'tests/worktree-space.py', []),
                                           ('/bin/bash', 'tests/collab-herdr.sh', [])]:
        env = os.environ.copy()
        env.pop('QWB_TEST_SOCKET_DIRS', None)
        runner = subprocess.run if interpreter == sys.executable else run
        result = runner([interpreter, script, *arguments], cwd=directory, env=env,
                        capture_output=True, text=True)
        assert result.returncode == 0, (script, result.stdout, result.stderr)
        assert not any(line.startswith('FAIL') for line in result.stdout.splitlines()), result.stdout
        print(f'PASS {script}: root={len(os.fsencode(directory))} bytes, socket=103 bytes', flush=True)

    longer = directory / 'x'
    longer.mkdir()
    export(longer)
    result = run(['/bin/bash', 'tests/smoke.sh'], cwd=longer, capture_output=True, text=True)
    assert result.returncode == 2, (result.returncode, result.stdout, result.stderr)
    assert '实际 105 字节' in result.stderr and '上限 103 字节' in result.stderr, result.stderr
    assert '最多 97 字节' in result.stderr, result.stderr
    assert not result.stdout and 'FAIL' not in result.stderr, (result.stdout, result.stderr)
    print('PASS over-budget checkout exits 2 before assertions: ' + result.stderr.strip(), flush=True)

    # Check bytes rather than characters with a multibyte checkout path as well.
    unicode_root = directory / '长'
    unicode_root.mkdir()
    export(unicode_root)
    result = run(['/bin/bash', 'tests/collab-herdr.sh'], cwd=unicode_root, capture_output=True, text=True)
    assert result.returncode == 2 and '实际 107 字节' in result.stderr, (result.returncode, result.stderr)
    assert not result.stdout and 'FAIL' not in result.stderr, (result.stdout, result.stderr)
    print('PASS UTF-8 root uses byte length and fails before assertions', flush=True)
finally:
    shutil.rmtree(directory)
