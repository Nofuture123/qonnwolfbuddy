#!/usr/bin/env python3
"""Check exit-code preservation and cleanup of an owned, TERM-resistant writer."""
from pathlib import Path
import os
import json
import signal
import shutil
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
from process_fixture import run

ROOT = Path(__file__).resolve().parents[1]
if 'QWB_TEST_SOCKET_DIRS' not in os.environ:
    os.execv(sys.executable, [sys.executable, str(ROOT / 'tests/process_fixture.py'),
                             '--command', sys.executable, __file__])
with tempfile.TemporaryDirectory(dir=os.environ['QWB_TEST_SCOPE_DIR']) as temporary:
    directory = Path(temporary)
    pidfile = directory / 'writer.pid'
    script = directory / 'shell.sh'
    script.write_text('. "$1"\nqwb_test_scope "$@"\nprintf "%s\\n" "$BASH_VERSION"\n')
    for shell in ['/bin/bash', 'bash']:
        original = subprocess.run([shell, '-c', 'printf "%s\\n" "$BASH_VERSION"'],
                                  capture_output=True, text=True, check=True)
        wrapped = subprocess.run([shell, str(script), str(ROOT / 'tests/process-fixture.sh')],
                                 capture_output=True, text=True)
        assert wrapped.returncode == 0 and wrapped.stdout == original.stdout, wrapped
    print('PASS Bash 3.2 and PATH Bash retain the invoking interpreter')
    command = ['/bin/bash', '-c', '''
/bin/bash -c 'trap "" TERM; echo "$BASHPID" > "$1"; while :; do sleep .02; done' writer "$1" &
while [[ ! -s "$1" ]]; do sleep .01; done
printf 'original output\n'
exit 7
''', 'fixture', str(pidfile)]
    result = run(command, capture_output=True, text=True)
    assert result.returncode == 7 and result.stdout == 'original output\n', result
    pid = pidfile.read_text().strip()
    observation = subprocess.run(['/bin/ps', '-p', pid, '-o', 'stat='], capture_output=True, text=True)
    assert not observation.stdout.strip() or observation.stdout.strip().startswith('Z'), observation.stdout
    print('PASS original failure/output preserved; TERM-resistant descendant ended before return')

    # Real TERM at the record-publication boundary, before a child may be launched.
    helper = ROOT / 'tests/process_fixture.py'
    marker = directory / 'unexpected-child'
    setup_signal = '''
from pathlib import Path
import os,signal,sys
sys.path.insert(0,sys.argv[1])
import process_fixture
print('SETUP_PID='+str(os.getpid()),flush=True)
original_touch=Path.touch
def touch(path,*args,**kwargs):
    result=original_touch(path,*args,**kwargs)
    if path.name=='socket-directories':
        print('OWNED_SCOPE='+str(path.parent),flush=True)
        os.kill(os.getpid(),signal.SIGTERM)
    return result
Path.touch=touch
marker=sys.argv[2]
sys.argv=[process_fixture.__file__,'--command','/bin/bash','-c','printf reached > "$1"','fixture',marker]
raise SystemExit(process_fixture.main())
'''
    interrupted = subprocess.run([sys.executable, '-B', '-c', setup_signal, str(helper.parent), str(marker)],
                                 capture_output=True, text=True, timeout=20)
    owned_scope = Path(next(line.split('=', 1)[1] for line in interrupted.stdout.splitlines()
                            if line.startswith('OWNED_SCOPE=')))
    assert owned_scope.parent == ROOT / '.qwb-tmp'
    try:
        assert interrupted.returncode == 143, interrupted
        assert not marker.exists() and not owned_scope.exists()
        print('PASS real TERM during scope records returns 143, launches no child, leaves no directory; '+interrupted.stdout.splitlines()[0])
    finally:
        if owned_scope.exists():
            shutil.rmtree(owned_scope)

    pidfile.unlink()
    process = subprocess.Popen([sys.executable, str(ROOT / 'tests/process_fixture.py'), '--command',
                                '/bin/bash', '-c', 'echo "$$" > "$1"; sleep 60', 'fixture', str(pidfile)])
    try:
        deadline = time.monotonic() + 20
        while not pidfile.exists():
            assert process.poll() is None and time.monotonic() < deadline
            time.sleep(.01)
        pid = pidfile.read_text().strip()
        process.send_signal(signal.SIGTERM)
        assert process.wait(timeout=20) == 143
        observation = subprocess.run(['/bin/ps', '-p', pid, '-o', 'stat='], capture_output=True, text=True)
        assert not observation.stdout.strip() or observation.stdout.strip().startswith('Z'), observation.stdout
        print('PASS TERM propagated; recorded child exited before supervisor return')
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=20)

    # Kill a nested supervisor after its real child starts. The outer owner must
    # drain the recorded group and reclaim the nested scope without its finally.
    observation = directory / 'nested.json'
    command = '''
import json,os,signal,subprocess,sys,time
from pathlib import Path
from process_fixture import register
leaf="import json,os,time; from pathlib import Path; Path(os.environ['NESTED_RECORD']).write_text(json.dumps(dict(pid=os.getpid(),scope=os.environ['QWB_TEST_SCOPE_DIR']))); time.sleep(60)"
child=subprocess.Popen([sys.executable,sys.argv[1],'--command',sys.executable,'-c',leaf])
deadline=time.monotonic()+20
while not Path(os.environ['NESTED_RECORD']).exists():
    assert child.poll() is None and time.monotonic()<deadline
    time.sleep(.01)
record=json.loads(Path(os.environ['NESTED_RECORD']).read_text())
register(record['pid'])
child.kill();child.wait()
'''
    result = run([sys.executable, '-c', command, str(ROOT / 'tests/process_fixture.py')],
                 env=dict(os.environ, NESTED_RECORD=str(observation)), capture_output=True, text=True)
    assert result.returncode == 0, (result.returncode, result.stdout, result.stderr)
    record = json.loads(observation.read_text())
    assert not Path(record['scope']).exists(), record
    child_status = subprocess.run(['/bin/ps', '-p', str(record['pid']), '-o', 'stat='],
                                  capture_output=True, text=True).stdout.strip()
    assert not child_status or child_status.startswith('Z'), child_status
    print('PASS killed nested supervisor scope and recorded child are reclaimed')

    reused = directory / 'reused'; reused.mkdir()
    (reused / 'scope-owner').write_text('new-owner')
    result = run([sys.executable, '-c', '''
import os,sys
from pathlib import Path
with open(os.environ['QWB_TEST_SOCKET_DIRS'],'a') as record:record.write(sys.argv[1]+'\\told-owner\\n')
''', str(reused)], capture_output=True, text=True)
    assert result.returncode == 0 and (reused / 'scope-owner').read_text() == 'new-owner', result
    shutil.rmtree(reused)
    print('PASS stale scope receipt preserves a replacement owner')

    jobs = directory / 'jobs'; jobs.mkdir()
    counter = jobs / 'counter.json'
    body = '''
import fcntl,json,os,sys,time
from pathlib import Path
counter=Path(os.environ['COLLAB_COUNTER'])
def update(delta):
    with counter.open('r+') as record:
        fcntl.flock(record,fcntl.LOCK_EX)
        state=json.load(record);state['active']+=delta
        state['max']=max(state['max'],state['active'])
        if delta<0:state['completed']+=1
        record.seek(0);record.truncate();json.dump(state,record)
update(1)
if int(Path(__file__).stem)<6:
    deadline=time.monotonic()+20
    while True:
        with counter.open() as record:
            fcntl.flock(record,fcntl.LOCK_SH)
            if json.load(record)['max']>=6:break
        assert time.monotonic()<deadline
        time.sleep(.01)
time.sleep(.1);update(-1)
sys.exit(7 if Path(__file__).stem=='2' else 0)
'''
    scripts = []
    for index in range(8):
        path = jobs / f'{index}.py'; path.write_text(body); scripts.append(str(path))
    for shell in ['bash', '/bin/bash']:
        counter.write_text(json.dumps(dict(active=0, max=0, completed=0)))
        result = subprocess.run([shell, str(ROOT / 'tests/collab-all.sh'), *scripts],
                                env=dict(os.environ, COLLAB_COUNTER=str(counter)),
                                capture_output=True, text=True, timeout=20)
        state = json.loads(counter.read_text())
        assert result.returncode == 1 and state == dict(active=0, max=6, completed=8), (result, state)
        rows = [line for line in result.stdout.splitlines() if line.startswith(('PASS  ', 'FAIL  '))]
        assert len(rows) == 8 and all(path in row for path, row in zip(scripts, rows)), rows
        assert rows[2].startswith('FAIL') and sum(row.startswith('PASS') for row in rows) == 7, rows
        assert result.stdout.splitlines()[-1] == 'COLLAB-ALL FAIL（1/8 项）', result.stdout
    print('PASS collab pool bounds six slots, reports all eight jobs in order and preserves failure')
