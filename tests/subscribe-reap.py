#!/usr/bin/env python3
"""Catch subscription readers before any test-owned process-group cleanup runs."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shlex
import signal
import shutil
import subprocess
import sys
import tempfile
import time
from process_fixture import drain, register, release

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]


def processes(pids=()):
    args = ['/bin/ps', '-axo', 'pid=,ppid=,pgid=,stat=,command=']
    result = subprocess.run(args, capture_output=True, check=True)
    rows = [line.split(None, 4) for line in result.stdout.decode('utf-8', errors='replace').splitlines()]
    return [row for row in rows if not row[3].startswith('Z') and
            (not pids or int(row[0]) in pids)]


def cli(binary, project, *args, env):
    result = subprocess.run(['/bin/bash', str(binary), args[0], '--project', str(project), *args[1:]],
                            env=env, capture_output=True, text=True)
    assert result.returncode == 0, (args, result.returncode, result.stdout, result.stderr)
    return result.stdout


class MissedWindow(RuntimeError):
    pass


def probe(source, mode, immediate=False, wait_seconds=5, report=None, measure=False):
    read_ages = []
    attempts = 5
    for attempt in range(1, attempts + 1):
        try:
            outcome = probe_once(source, mode, immediate, wait_seconds, report, measure, attempt)
        except MissedWindow as error:
            outcome = error.args[0]
            read_ages.append(outcome['reader_age'])
            outcome.update(attempts=attempt, reader_ages=read_ages)
            if report:
                Path(report).write_text(json.dumps(outcome, ensure_ascii=False, indent=2))
            print(f'INCONCLUSIVE subscribe {mode}: attempt={attempt}/{attempts} '
                  f'reader_age={outcome["reader_age"]:.6f}s; missed product 2s window', flush=True)
            continue
        outcome.update(attempts=attempt, reader_ages=read_ages + [outcome['reader_age']])
        if report:
            Path(report).write_text(json.dumps(outcome, ensure_ascii=False, indent=2))
        return outcome
    raise AssertionError(f'未能验证（测量环境问题，非产品缺陷）：机器负载过高，{attempts} 次都没能'
                         f'在产品 2 秒超时前建立观察窗口；模式={mode}，各次读龄={read_ages}')


def probe_once(source, mode, immediate=False, wait_seconds=5, report=None, measure=False, attempt=1):
    base = ROOT / '.qwb-tmp'
    base.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='reap-', dir=base) as temporary:
        directory = Path(temporary)
        project = directory / 'project'
        (project / 'tasks').mkdir(parents=True)
        qw = project / 'qwbuddy'
        shutil.copytree(source, qw / 'bin')
        shutil.copytree(ROOT / 'templates/roles', qw / 'roles')
        for name in ['TASK.md', 'QWBUDDY.md']:
            shutil.copy(ROOT / 'templates' / name, qw / name)
        (qw / '.controller.lock').mkdir()
        (qw / '.controller.lock/owner').write_text('fixture ctl\n')
        (qw / 'config.sh').write_text('QWB_WAKE_INTERVAL_MS=1000\nQWB_REWAKE_MS=60000\n')
        ticket = project / 'tasks/case.md'
        ticket.write_text('state: running\n')
        stub = directory / 'stub'
        stub.mkdir()
        (stub / 'lsof').write_text('#!/bin/sh\nexit 1\n')
        (stub / 'herdr').write_text('#!/bin/sh\nprintf \'{"result":{"type":"ok"}}\\n\'\n')
        env = dict(os.environ, PATH=str(stub)+':'+os.environ['PATH'], HERDR_PANE_ID='ctl',
                   HERDR_SOCKET_PATH='/dev/null/qwb-test.sock', TMPDIR=str(directory),
                   GIT_CEILING_DIRECTORIES=str(directory), PYTHONDONTWRITEBYTECODE='1')
        for path in stub.iterdir():
            path.chmod(0o755)
        migration = directory / 'migration.json'
        migration.write_text(json.dumps(dict(task_sha256=hashlib.sha256(ticket.read_bytes()).hexdigest(),
            confirm={key:'owned temporary fixture; no external writers' for key in
                     ['run','wake','worktree','worker','controller','old-fds','external-actions']})))
        ledger = qw / 'bin/qwb-ledger.sh'
        cli(ledger, project, 'migrate', '--task', str(ticket), '--', str(migration), env=env)
        fifo = directory / 'reader-gate'
        os.mkfifo(fifo)
        gate = os.open(fifo, os.O_RDWR | os.O_NONBLOCK)
        ready = directory / 'reader.json'
        waiting = directory / 'wake-waiting'
        armed = directory / 'reader-armed'
        round_fifo = directory / 'round-gate'
        os.mkfifo(round_fifo)
        round_gate = os.open(round_fifo, os.O_RDWR | os.O_NONBLOCK)
        # This existing sleep hook is reached only after startup reconciliation.
        # Hold the next round until a fresh subscriber read is blocked and progress is published.
        # Advance only wake's wait clock after release; subscribe retains its real 2s timeout.
        advanced = directory / 'round-advanced'
        clock = stub / 'round-clock'
        clock.write_text('#!/bin/sh\nexec perl -MTime::HiRes=time -e \'printf "%d", '
                         'time()*1000 + (-e $ARGV[0] ? 1000 : 0)\' '+shlex.quote(str(advanced))+'\n')
        clock.chmod(0o755)
        env['QWB_NOW_MS_CMD'] = str(clock)
        hook = stub / 'round-sleep'
        hook.write_text(f'''#!{sys.executable}
import time,sys
from pathlib import Path
marker=Path({str(waiting)!r})
if not marker.exists():
    marker.touch()
    with open({str(round_fifo)!r}) as gate:gate.readline()
    Path({str(advanced)!r}).touch()
else:time.sleep(int(sys.argv[1])/1000)
''')
        hook.chmod(0o755)
        env['QWB_SLEEP_CMD'] = str(hook)
        # Transparent argv exec: only the subscriber's ledger read waits on an owned FIFO.
        (stub / 'bash').write_text(f'''#!/bin/sh
if [ "${{2:-}}" != read ] || [ ! -e {shlex.quote(str(armed))} ]; then
    exec /bin/bash "$@"
fi
exec {shlex.quote(sys.executable)} - "$@" <<'PY'
import json,os,subprocess,sys,time
from pathlib import Path
parent=subprocess.run(['/bin/ps','-p',str(os.getppid()),'-o','command='],capture_output=True,text=True).stdout
if len(sys.argv)>2 and sys.argv[2]=='read' and 'subscribe --project' in parent and Path({str(armed)!r}).exists():
    details=dict(pid=os.getpid(),ppid=os.getppid(),pgid=os.getpgrp(),started=time.monotonic(),argv=sys.argv[1:],subscriber=parent.strip())
    saved=Path({(str(ready)+'.tmp')!r})
    saved.write_text(json.dumps(details));saved.replace({str(ready)!r})
    with open({str(fifo)!r}) as waiting:waiting.readline()
os.execv('/bin/bash',['/bin/bash',*sys.argv[1:]])
PY
''')
        (stub / 'bash').chmod(0o755)
        # Migration creates a real handoff; consume its first transport before testing interruption.
        cli(qw/'bin/qwb-wake.sh', project, '--once', '--pane', 'ctl', env=env)
        wake = None
        reader = None
        outcome = None
        groups = set()
        scoped = bool(os.environ.get('QWB_TEST_GROUPS'))
        def own(group):
            if group not in groups:
                groups.add(group)
                if scoped:
                    register(group)
        try:
            wake = subprocess.Popen(['/bin/bash', str(qw/'bin/qwb-wake.sh'), '--project', str(project),
                                     '--block', '--max-ms', '10000'], env=env,
                                    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                                    start_new_session=True,
                                    preexec_fn=lambda:signal.signal(signal.SIGINT,signal.SIG_DFL))
            own(wake.pid)
            deadline = time.monotonic()+10
            while not waiting.exists():
                assert wake.poll() is None and time.monotonic()<deadline, ('wake did not reach wait hook', wake.poll())
                time.sleep(.001)
            if mode == 'normal':
                # Publish while wake is parked, before arming a fresh blocked read.
                started = time.monotonic()
                cli(ledger, project, 'append', '--task', str(ticket), '--event-id', 'reap-progress',
                    '--', 'done: subscription reap fixture progress', env=env)
                wanted = 2
            armed.touch()
            while not ready.exists():
                assert wake.poll() is None and time.monotonic()<deadline, ('reader did not reach FIFO', wake.poll(), wake.communicate() if wake.poll() is not None else '')
                time.sleep(.001)
            reader = json.loads(ready.read_text())
            own(reader['pgid'])
            event_dir = Path(shlex.split(reader['subscriber'])[-1]).parent
            if mode != 'normal':
                if not immediate:
                    time.sleep(.1)
                started = time.monotonic()
                wake.send_signal(signal.SIGTERM if mode=='term' else signal.SIGINT)
                wanted = 143 if mode=='term' else 130
            os.write(round_gate, b'continue\n')
            out, err = wake.communicate(timeout=5)
            elapsed = time.monotonic()-started
            assert wake.returncode == wanted, (mode, wake.returncode, out, err)
            live = [row for row in processes() if int(row[2]) in {wake.pid,reader['pgid']}]
            read_age = time.monotonic()-reader['started']
            missed = read_age >= 2 or 'timed out after 2 seconds' in err
            # Observe before finally or shared cleanup; a missed window proves nothing about leaks.
            outcome = dict(mode=mode, immediate=immediate, rc=wake.returncode, seconds=elapsed,
                           reader=reader, reader_age=read_age, live_after_wake=live, event_dir=str(event_dir),
                           event_dir_exists=event_dir.exists(), stdout=out, stderr=err, attempts=attempt,
                           result='inconclusive' if missed else ('residual' if live else 'clean'))
            if report:
                Path(report).write_text(json.dumps(outcome, ensure_ascii=False, indent=2))
            if missed:
                raise MissedWindow(outcome)
            print(f'OBSERVED subscribe {mode}: attempts={attempt} reader_age={read_age:.6f}s '
                  f'result={outcome["result"]}', flush=True)
            if measure:
                return outcome
            assert not live, '测到了且有残留（产品缺陷）: subscription reader survived before test cleanup: '+json.dumps(live,ensure_ascii=False)
            assert not event_dir.exists(), 'EVENT_DIR survived wake cleanup'
            if mode=='normal':
                assert 'subscription reap fixture progress' in out and '看账本：' in out, out
            lock = ticket.with_name(ticket.name+'.qwb-lock')
            if lock.exists():
                lock.unlink()
            os.write(gate,b'continue\n')
            until = time.monotonic()+wait_seconds
            while time.monotonic()<until:
                assert not lock.exists(), 'reader recreated sidecar after wake exit'
                time.sleep(.02)
            outcome['lock_recreated'] = lock.exists()
            if report:
                Path(report).write_text(json.dumps(outcome, ensure_ascii=False, indent=2))
            return outcome
        finally:
            # Cleanup never runs until the independent product assertions above have finished.
            if wake and wake.poll() is None:
                os.write(round_gate,b'cleanup\n')
                wake.terminate()
                wake.wait(timeout=5)
            if ready.exists():
                own(json.loads(ready.read_text())['pgid'])
            if scoped:
                for group in groups:
                    release(group)
            else:
                drain(groups)
            os.close(gate)
            os.close(round_gate)


def query_cleanup(source, timeout):
    """A status query's grandchild must end on both return and the existing 2s timeout."""
    with tempfile.TemporaryDirectory(prefix='query-', dir=ROOT/'.qwb-tmp') as temporary:
        directory = Path(temporary)
        project = directory/'project'
        (project/'tasks').mkdir(parents=True)
        (project/'tasks/observer.md').write_text('state: verified\ndispatch: now pane=w:p0\n')
        stub = directory/'stub'
        stub.mkdir()
        ready = directory/'query.json'
        notice = directory/'notice'
        scans = directory/'ps.jsonl'
        # Audit the real public helper in its interpreter, including absolute /bin/ps calls.
        (stub/'python3').write_text(f'''#!{sys.executable}
import json,sys
from pathlib import Path
def audit(event,args):
    if event=='subprocess.Popen' and args[0]=='/bin/ps':
        with Path({str(scans)!r}).open('a') as log:log.write(json.dumps(args[1])+'\\n')
sys.addaudithook(audit)
sys.argv=['-',*sys.argv[3:]]
exec(compile(sys.stdin.read(),'<stdin>','exec'),{{'__name__':'__main__'}})
''')
        (stub/'python3').chmod(0o755)
        (stub/'herdr').write_text(f'''#!{sys.executable}
import json,os,subprocess,time
from pathlib import Path
child=subprocess.Popen([{sys.executable!r},'-c','import time;time.sleep(60)'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
Path({str(ready)!r}).write_text(json.dumps(dict(pid=os.getpid(),child=child.pid,pgid=os.getpgrp(),started=time.monotonic())))
if {timeout!r}:time.sleep(60)
print(json.dumps(dict(server=dict(socket='/dev/null/qwb-test.sock',session=os.environ.get('HERDR_SESSION')))))
''')
        (stub/'herdr').chmod(0o755)
        env = dict(os.environ, PATH=str(stub)+':'+os.environ['PATH'],
                   HERDR_SOCKET_PATH='/dev/null/qwb-test.sock', TMPDIR=str(directory))
        child = None
        groups = set()
        scoped = bool(os.environ.get('QWB_TEST_GROUPS'))
        started = time.monotonic()
        try:
            child = subprocess.Popen(['/bin/bash',str(source/'qwb-herdr.sh'),'subscribe',
                '--project',str(project),'--notice',str(notice)], env=env,
                stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
            groups.add(child.pid)
            if scoped:register(child.pid)
            deadline = time.monotonic()+5
            while not notice.exists():
                assert child.poll() is None and time.monotonic()<deadline, 'query did not degrade'
                time.sleep(.005)
            query = json.loads(ready.read_text())
            groups.add(query['pgid'])
            if scoped:register(query['pgid'])
            age = time.monotonic()-query['started']
            data = json.loads(notice.read_text())
            assert (data['seq'],data['phase'],data['panes'])==(1,'fallback',['w:p0']), data
            live = [row for row in processes() if int(row[2])==query['pgid']]
            assert not live, ('query grandchild survived before test cleanup',query,live)
            ps_calls = scans.read_text().splitlines() if scans.exists() else []
            assert bool(ps_calls)==timeout, ('normal query must not scan; timeout must confirm group',ps_calls)
            child.terminate()
            out,err = child.communicate(timeout=3)
            assert child.returncode==143 and out=='', (child.returncode,out,err)
            assert 'Herdr timely subscription gap; bounded MD scan: ' in err,err
            if timeout:
                assert 2 <= time.monotonic()-started < 3.5 and 'timed out after 2 seconds' in err,(age,err)
            else:
                assert age < 1 and 'timed out' not in err,(age,err)
            print('PASS subscribe query '+('timeout' if timeout else 'return')+
                  ': child and grandchild ended; normal has no ps; timeout confirms group; 2s budget preserved',flush=True)
        finally:
            if child and child.poll() is None:
                child.terminate()
                child.communicate(timeout=3)
            if ready.exists():
                group = json.loads(ready.read_text())['pgid']
                if group not in groups:
                    groups.add(group)
                    if scoped:register(group)
            if scoped:
                for group in groups:release(group)
            else:drain(groups)


def main():
    def interrupted(signum, _frame):
        raise SystemExit(128+signum)
    signal.signal(signal.SIGTERM, interrupted)
    parser=argparse.ArgumentParser()
    parser.add_argument('--source',type=Path,default=ROOT/'bin')
    parser.add_argument('--mode',choices=['all','normal','term','int'],default='all')
    parser.add_argument('--races',type=int,default=0)
    parser.add_argument('--report',type=Path)
    parser.add_argument('--timings',type=int,default=0)
    args=parser.parse_args()
    results=[]
    modes=['normal','term','int'] if args.mode=='all' else [args.mode]
    for mode in modes:
        r=probe(args.source,mode,report=args.report)
        results.append(r)
        print('PASS subscribe '+mode+': public exit code/output preserved; no reader before test cleanup',flush=True)
        print('PASS subscribe '+mode+': EVENT_DIR removed and 5-second FIFO release creates no lock',flush=True)
    for i in range(args.races):
        mode='term' if i%2==0 else 'int'
        r=probe(args.source,mode,immediate=True,wait_seconds=0)
        results.append(r)
        print('PASS subscribe launch race '+str(i+1)+' '+json.dumps(r,ensure_ascii=False),flush=True)
    for i in range(args.timings):
        r=probe(args.source,'normal',wait_seconds=0)
        results.append(r)
        print('PASS subscribe exit timing '+str(i+1)+' seconds='+str(r['seconds']),flush=True)
    if args.mode=='all':
        query_cleanup(args.source,False)
        query_cleanup(args.source,True)
    if args.report:
        args.report.write_text(json.dumps(results,ensure_ascii=False,indent=2))


if __name__=='__main__':
    main()
