#!/usr/bin/env python3
"""Check exit-code preservation and cleanup of an owned, TERM-resistant writer."""
from pathlib import Path
import signal
import shutil
import subprocess
import sys
import tempfile
import time

sys.dont_write_bytecode = True
from process_fixture import run

ROOT = Path(__file__).resolve().parents[1]
(ROOT / '.qwb-tmp').mkdir(exist_ok=True)
with tempfile.TemporaryDirectory(dir=ROOT / '.qwb-tmp') as temporary:
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
    helper = directory / 'tests/process_fixture.py'
    helper.parent.mkdir()
    shutil.copy2(ROOT / 'tests/process_fixture.py', helper)
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
    if path.name=='socket-directories':os.kill(os.getpid(),signal.SIGTERM)
    return result
Path.touch=touch
marker=sys.argv[2]
sys.argv=[process_fixture.__file__,'--command','/bin/bash','-c','printf reached > "$1"','fixture',marker]
raise SystemExit(process_fixture.main())
'''
    interrupted = subprocess.run([sys.executable, '-B', '-c', setup_signal, str(helper.parent), str(marker)],
                                 capture_output=True, text=True, timeout=20)
    assert interrupted.returncode == 143, interrupted
    assert not marker.exists() and not list((directory / '.qwb-tmp').iterdir())
    print('PASS real TERM during scope records returns 143, launches no child, leaves no directory; '+interrupted.stdout.strip())

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
