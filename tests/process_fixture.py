#!/usr/bin/env python3
"""Own a test's process groups; drain writers before deleting its temporary files."""
import os
import json
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
                             stdout=subprocess.PIPE)
    output, _ = probe.communicate()
    if probe.returncode:
        raise RuntimeError('cannot inspect owned test processes')
    return [row for line in output.decode('utf-8', errors='replace').splitlines()
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
    protected = set()
    for entry in Path(os.environ['QWB_TEST_GROUPS']).with_name('socket-directories').read_text().splitlines():
        path, _, owner = entry.partition('\t')
        marker = Path(path) / 'scope-owner'
        supervisor = Path(path) / 'supervisor-pid'
        if owner and marker.exists() and marker.read_text() == owner and supervisor.exists():
            protected.add(int(supervisor.read_text()))
    while True:
        live = [row for row in rows() if int(row[2]) in groups
                and int(row[0]) not in keep and not row[3].startswith('Z')]
        if not live:
            return
        if time.monotonic() >= deadline:
            raise RuntimeError('owned test processes did not exit: ' + repr(live))
        sig = signal.SIGKILL if time.monotonic() >= hard else signal.SIGTERM
        for row in live:
            if sig == signal.SIGKILL and int(row[0]) in protected:
                continue # Registered supervisors drain their own detached child groups.
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


def check_socket_path(path):
    size = len(os.fsencode(path))
    if size > 103:
        root = Path(path).parents[2]
        raise ValueError(f'测试 socket 路径超限：实际 {size} 字节，上限 103 字节；'
                         f'仓库根实际 {len(os.fsencode(root))} 字节，最多 89 字节'
                         f'（固定后缀 14 字节）：{path}')


def socket_path():
    # The existing supervisor owns both the processes and these ignored directories.
    root = Path(__file__).resolve().parents[1]
    base = root / '.qwb-tmp'
    check_socket_path(base / '00' / 's')
    record = Path(os.environ['QWB_TEST_SOCKET_DIRS'])
    while True:
        directory = base / secrets.token_hex(1)
        try:
            directory.mkdir(mode=0o700)
            break
        except FileExistsError:
            continue
    try:
        with record.open('a') as output:
            output.write(str(directory) + '\n')
    except BaseException:
        directory.rmdir()
        raise
    return str(directory / 's')


def main():
    if sys.argv[1] == 'socket':
        print(socket_path())
        return 0
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
    root = Path(__file__).resolve().parents[1]
    try:
        check_socket_path(root / '.qwb-tmp' / '00' / 's')
    except ValueError as error:
        print(error, file=sys.stderr)
        return 2
    base = root / '.qwb-tmp'
    base.mkdir(exist_ok=True)
    child = None
    directory = None
    socket_dirs = None
    rc = 1
    preparing = True
    pending_signal = None
    def interrupted(signum, _frame):
        nonlocal pending_signal
        if preparing:
            pending_signal = signum
        else:
            raise SystemExit(128 + signum)
    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)
    try:
        # Defer interruption until each new directory/PID has an owned cleanup handle.
        while True:
            if pending_signal is not None:
                raise SystemExit(128 + pending_signal)
            # ponytail: 256 concurrent scopes; shorten the base before increasing name length.
            candidate = str(base / secrets.token_hex(1))
            try:
                os.mkdir(candidate, 0o700)
                directory = candidate
                break
            except FileExistsError:
                continue
        records = Path(directory) / 'groups'
        records.touch()
        socket_dirs = Path(directory) / 'socket-directories'
        socket_dirs.touch()
        parent_record = os.environ.get('QWB_TEST_GROUPS')
        parent_owner = os.environ.get('QWB_TEST_SCOPE_OWNER')
        parents = json.loads(os.environ.get('QWB_TEST_SCOPE_ANCESTORS', '[]'))
        if parent_record and [parent_record, parent_owner] not in parents:
            parents.append([parent_record, parent_owner])
        scope_owner = secrets.token_hex(16)
        (Path(directory) / 'scope-owner').write_text(scope_owner)
        (Path(directory) / 'supervisor-pid').write_text(str(os.getpid()))
        env = dict(os.environ, QWB_TEST_SCOPE_SCRIPT=script, QWB_TEST_SCOPE_DIR=directory,
                   QWB_TEST_GROUPS=str(records), QWB_TEST_SOCKET_DIRS=str(socket_dirs),
                   QWB_TEST_SUPERVISOR_PID=str(os.getpid()), QWB_TEST_SCOPE_OWNER=scope_owner,
                   QWB_TEST_SCOPE_ANCESTORS=json.dumps(parents + [[str(records), scope_owner]]))
        env['PYTHONDONTWRITEBYTECODE'] = '1'
        env['PYTHONPATH'] = str(Path(__file__).resolve().parent) + os.pathsep + env.get('PYTHONPATH', '')
        # A killed nested supervisor may not reach its own finally. Its parent
        # keeps a generation-bound directory receipt and drains processes first.
        for parent_record, parent_owner in parents:
            marker = Path(parent_record).with_name('scope-owner')
            if not parent_owner or not marker.exists() or marker.read_text() != parent_owner:
                raise RuntimeError('parent test scope has retired or changed owner')
            with Path(parent_record).with_name('socket-directories').open('a') as record:
                record.write(directory + '\t' + scope_owner + '\n')
        if pending_signal is not None:
            raise SystemExit(128 + pending_signal)
        # This new session contains only this invocation's inherited descendants.
        argv = sys.argv[2:] if command else [env.get('QWB_TEST_SHELL', '/bin/bash'), script, *sys.argv[2:]]
        child = subprocess.Popen(argv, env=env, start_new_session=True)
        os.environ['QWB_TEST_GROUP'] = str(child.pid)
        os.environ['QWB_TEST_GROUPS'] = str(records)
        preparing = False
        if pending_signal is not None:
            raise SystemExit(128 + pending_signal)
        rc = child.wait()
    except SystemExit as error:
        rc = error.code
    finally:
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        if child is not None:
            drain()
            child.wait()
        if socket_dirs is not None and socket_dirs.exists():
            for entry in socket_dirs.read_text().splitlines():
                path, _, owner = entry.partition('\t')
                marker = Path(path) / 'scope-owner'
                if owner and (not marker.exists() or marker.read_text() != owner):
                    continue
                # Entries may retire their owned exports before their supervisor exits.
                if Path(path).exists():
                    shutil.rmtree(path)
        if directory is not None:
            shutil.rmtree(directory)
    return rc if rc >= 0 else 128 - rc


if __name__ == '__main__':
    sys.exit(main())
