#!/usr/bin/env python3
"""Own a test's process groups; drain writers before deleting its temporary files."""
import os
from pathlib import Path
import secrets
import shutil
import signal
import subprocess
import sys
import tempfile
import time


def register(pid):
    # Only callers that just started this PID may register its new process group.
    with open(os.environ['QWB_TEST_GROUPS'], 'a') as record:
        record.write(str(pid) + '\n')


def rows():
    probe = subprocess.Popen(['/bin/ps', '-axo', 'pid=,ppid=,pgid=,stat=,command='],
                             stdout=subprocess.PIPE, text=True)
    output, _ = probe.communicate()
    if probe.returncode:
        raise RuntimeError('cannot inspect owned test processes')
    return [row for line in output.splitlines()
            if (row := line.split(None, 4)) and int(row[0]) != probe.pid]


def drain(groups=None):
    if groups is None:
        groups = {int(os.environ['QWB_TEST_GROUP'])}
        groups.update(int(line) for line in Path(os.environ['QWB_TEST_GROUPS']).read_text().splitlines())
    # A cleanup invoked inside a test must preserve itself and its caller chain.
    snapshot = rows()
    parents = {int(row[0]): int(row[1]) for row in snapshot}
    keep = set()
    pid = os.getpid()
    while pid and pid not in keep:
        keep.add(pid)
        pid = parents.get(pid, 0)
    deadline = time.monotonic() + 5
    hard = time.monotonic() + 1
    while True:
        live = [row for row in rows() if int(row[2]) in groups
                and int(row[0]) not in keep and not row[3].startswith('Z')]
        if not live:
            return
        if time.monotonic() >= deadline:
            raise RuntimeError('owned test processes did not exit: ' + repr(live))
        sig = signal.SIGKILL if time.monotonic() >= hard else signal.SIGTERM
        for row in live:
            try:
                os.kill(int(row[0]), sig)
            except ProcessLookupError:
                pass
        time.sleep(.02)


def release(pid):
    record = Path(os.environ['QWB_TEST_GROUPS'])
    entries = record.read_text().splitlines()
    if str(pid) not in entries:
        raise RuntimeError('cannot release an unregistered process group')
    drain({pid})
    # Retire ended groups immediately so an old PID cannot later be reused as a target.
    temporary = record.with_name('groups.next')
    temporary.write_text(''.join(line + '\n' for line in entries if line != str(pid)))
    temporary.replace(record)


def run(argv, **kwargs):
    result = subprocess.run([sys.executable, str(Path(__file__).resolve()), '--command', *argv], **kwargs)
    result.args = argv
    return result


class TemporaryDirectory(tempfile.TemporaryDirectory):
    def cleanup(self):
        drain()
        super().cleanup()


def main():
    if sys.argv[1] == 'drain':
        drain()
        return 0
    if sys.argv[1] == 'register':
        register(int(sys.argv[2]))
        return 0
    if sys.argv[1] == 'release':
        release(int(sys.argv[2]))
        return 0
    command = sys.argv[1] == '--command'
    script = sys.argv[1]
    base = Path(__file__).resolve().parents[1] / '.qwb-tmp'
    base.mkdir(exist_ok=True)
    # Darwin AF_UNIX paths allow only 103 bytes; keep the fixture parent short.
    while True:
        directory = str(base / secrets.token_hex(2))
        try:
            os.mkdir(directory, 0o700)
            break
        except FileExistsError:
            continue
    records = Path(directory) / 'groups'
    records.touch()
    env = dict(os.environ, QWB_TEST_SCOPE_SCRIPT=script, QWB_TEST_SCOPE_DIR=directory,
               QWB_TEST_GROUPS=str(records))
    env['PYTHONPATH'] = str(Path(__file__).resolve().parent) + os.pathsep + env.get('PYTHONPATH', '')
    child = None
    rc = 1
    def interrupted(signum, _frame):
        raise SystemExit(128 + signum)
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        # This new session contains only this invocation's inherited descendants.
        argv = sys.argv[2:] if command else [env.get('QWB_TEST_SHELL', '/bin/bash'), script, *sys.argv[2:]]
        child = subprocess.Popen(argv, env=env, start_new_session=True)
        os.environ['QWB_TEST_GROUP'] = str(child.pid)
        os.environ['QWB_TEST_GROUPS'] = str(records)
        rc = child.wait()
    except SystemExit as error:
        rc = error.code
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        if child is not None:
            drain()
            child.wait()
        shutil.rmtree(directory)
    return rc if rc >= 0 else 128 - rc


if __name__ == '__main__':
    sys.exit(main())
