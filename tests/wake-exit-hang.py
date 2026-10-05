#!/usr/bin/env python3
"""Bound wake cleanup and retain a stop request swallowed by Python deallocation."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
from process_fixture import TemporaryDirectory, drain, register, release, socket_path

ROOT = Path(__file__).resolve().parents[1]


def wake_cases(baseline):
    with TemporaryDirectory(prefix='wake-exit-', dir=ROOT/'.qwb-tmp') as temporary:
        p = Path(temporary)
        subprocess.run(['/bin/bash', str(ROOT/'bin/qwb-init.sh'), str(p)], check=True,
                       stdout=subprocess.DEVNULL)
        wake = p/'qwbuddy/bin/qwb-wake.sh'
        if os.environ.get('QWB_TEST_WAKE_SOURCE'):
            wake.write_bytes(Path(os.environ['QWB_TEST_WAKE_SOURCE']).read_bytes())
        current = wake.read_bytes()
        subscriber = p/'qwbuddy/bin/qwb-herdr.sh'
        ticket = p/'tasks/case.md'
        ready = p/'ready.json'
        terms = p/'terms'
        clock = p/'clock'
        now = p/'now'
        now.write_text('#!/bin/sh\ncat "$EXIT_CLOCK"\n')
        now.chmod(0o755)
        sleeper = p/'sleep-hook'
        sleeper.write_text('#!/bin/sh\ntouch "$EXIT_WAITING"\nsleep .01\n')
        sleeper.chmod(0o755)
        subscriber.write_text('''#!/usr/bin/env bash
exec python3 -B - "$@" <<'STUB'
import json,os,signal,sys,time
from pathlib import Path
count=0
def stop(signum,_frame):
    global count
    count+=1
    with Path(os.environ['EXIT_TERMS']).open('a') as f:f.write(str(signum)+'\\n')
    if os.environ['EXIT_MODE']=='normal' or (os.environ['EXIT_MODE']=='retry' and count>1):
        raise SystemExit(128+signum)
signal.signal(signal.SIGTERM,stop)
def publish(path,raw):
    path=Path(path); tmp=path.with_suffix('.tmp');tmp.write_text(raw);tmp.replace(path)
publish(sys.argv[-1],'{"seq":1}\\n')
publish(os.environ['EXIT_CLOCK'],'1')
publish(os.environ['EXIT_READY'],json.dumps(dict(pid=os.getpid())))
while True:time.sleep(.01)
STUB
''')
        env = dict(os.environ, TMPDIR=str(p), EXIT_READY=str(ready), EXIT_TERMS=str(terms),
                   EXIT_CLOCK=str(clock), QWB_NOW_MS_CMD=str(now),
                   QWB_SLEEP_CMD=str(sleeper), EXIT_WAITING=str(p/'waiting'),
                   HERDR_SOCKET_PATH='/dev/null/qwb-test.sock')
        for key in ['HERDR_PANE_ID', 'QWB_WATCH_PARENT_PID', 'QWB_SUPERVISOR_GUARDED']:
            env.pop(key, None)
        results = {}
        def run(mode, outcome='timeout', source=current):
            wake.write_bytes(source)
            for f in [ready, terms, p/'waiting']:
                if f.exists(): f.unlink()
            clock.write_text('0')
            ticket.write_text('state: '+('verified' if outcome=='empty' else 'running')+'\n'
                              +('done: cleanup result\n' if outcome=='changed' else 'working: pending\n'))
            child = subprocess.Popen(['/bin/bash', str(wake), '--project', str(p), '--block',
                                      '--max-ms', '1' if outcome=='timeout' else '60000'],
                                     env=env|{'EXIT_MODE': mode}, stdout=subprocess.PIPE,
                                     stderr=subprocess.PIPE, start_new_session=True,
                                     preexec_fn=lambda: signal.signal(signal.SIGINT, signal.SIG_DFL))
            register(child.pid)
            try:
                deadline = time.monotonic()+10
                while not ready.exists():
                    assert child.poll() is None and time.monotonic()<deadline, 'subscriber startup failed'
                    time.sleep(.005)
                pid = json.loads(ready.read_text())['pid']
                started = time.monotonic()
                if outcome in ['term', 'int']:
                    # Startup readiness alone precedes Bash installing/using its wait loop.
                    while not (p/'waiting').exists():
                        assert child.poll() is None and time.monotonic()<deadline, 'wake did not reconcile'
                        time.sleep(.001)
                    child.send_signal(signal.SIGTERM if outcome=='term' else signal.SIGINT)
                try:
                    out, err = child.communicate(timeout=6)
                except subprocess.TimeoutExpired as error:
                    raise AssertionError(f'FAIL wake {mode}/{outcome}: cleanup exceeded 4s + 2s') from error
                elapsed = time.monotonic()-started
                wanted = dict(timeout=124, changed=2, empty=0, term=143, int=130)[outcome]
                assert child.returncode==wanted, (mode,outcome,child.returncode,out,err)
                try: os.kill(pid, 0)
                except ProcessLookupError: pass
                else: raise AssertionError(f'FAIL subscriber survived wake exit: {pid}')
                assert not list(p.glob('qwb-events.*')), 'notice directory survived cleanup'
                signals = terms.read_text().splitlines() if terms.exists() else []
                print(f'OBSERVED wake {mode}/{outcome}: rc={child.returncode} seconds={elapsed:.6f} '
                      f'terms={signals} stdout={out!r} stderr={err!r}', flush=True)
                if mode=='retry':
                    assert len(signals)==2 and b'retrying TERM' in err and b'SIGKILL' not in err, (signals,err)
                elif mode=='kill':
                    assert len(signals)==2 and b'SIGKILL' in err, (signals,err)
                else:
                    assert b'retrying TERM' not in err and b'SIGKILL' not in err, err
                return out, err, child.returncode, elapsed
            finally:
                if child.poll() is None:
                    drain()
                    child.communicate(timeout=3)
                release(child.pid)
        for outcome in ['timeout', 'changed', 'empty', 'term', 'int']:
            sources = [baseline.read_bytes(), current] if baseline else [current]
            pair = [run('normal', outcome, source) for source in sources]
            if baseline:
                assert pair[0][:3]==pair[1][:3], (outcome,pair)
                assert pair[1][3]-pair[0][3]<.15, ('normal cleanup slowed perceptibly',outcome,pair)
            results[outcome] = pair[-1]
        print('PASS wake normal: 124/2/0/143/130 outputs preserved; baseline bytes/timing checked' if baseline
              else 'PASS wake normal: 124/2/0/143/130; no escalation diagnostics', flush=True)
        for mode in ['retry', 'kill']:
            r = run(mode)
            assert r[0]==results['timeout'][0] and r[2]==results['timeout'][2], (mode,r)
            assert r[1].startswith(results['timeout'][1]), (mode,r)
            print('PASS wake '+mode+': bounded exit 124; subscriber absent before fixture cleanup', flush=True)
        wake.write_bytes(current)


def subscriber_cases(baseline):
    with TemporaryDirectory(prefix='subscribe-stop-', dir=ROOT/'.qwb-tmp') as temporary:
        p = Path(temporary)
        (p/'tasks').mkdir()
        (p/'tasks/case.md').write_text('state: verified\ndispatch: now pane=w:p0\n')
        stub = p/'stub'; stub.mkdir()
        notice = p/'notice'
        (stub/'herdr').write_text('#!/bin/sh\nprintf \'{"server":{"socket":"/dev/null/qwb-test.sock"}}\\n\'\n')
        (stub/'herdr').chmod(0o755)
        # Interpreter-side fault injection keeps the public helper and real command/reap intact.
        # CPython itself ignores the exception raised by this Popen deallocator.
        (stub/'python3').write_text(f'''#!{sys.executable}
import json,os,signal,subprocess,sys,time
from pathlib import Path
from process_fixture import register
original_init=subprocess.Popen.__init__
def create(child,*args,**kwargs):
    original_init(child,*args,**kwargs)
    if kwargs.get('start_new_session'):
        register(child.pid)
        with Path(os.environ['STOP_QUERIES']).open('a') as f:f.write(str(child.pid)+'\\n')
subprocess.Popen.__init__=create
original=subprocess.Popen.__del__
fired=False
def deallocate(child):
    global fired
    original(child)
    notice=Path(os.environ['STOP_NOTICE'])
    phase=os.environ['STOP_PHASE']
    eligible=child.args[0]=='herdr' if phase=='outer' else (child.args[0]=='bash' and len(child.args)>2 and child.args[2]=='read' and notice.exists() and json.loads(notice.read_text()).get('phase')=='subscribed')
    if os.environ['STOP_SWALLOW']=='1' and eligible and not fired:
        fired=True
        marker=Path(os.environ['STOP_FIRED']);tmp=marker.with_suffix('.tmp')
        tmp.write_text(str(time.monotonic()));tmp.replace(marker)
        os.kill(os.getpid(),int(os.environ['STOP_SIGNAL']))
subprocess.Popen.__del__=deallocate
sys.argv=['-',*sys.argv[3:]]
exec(compile(sys.stdin.read(),'<stdin>','exec'),{{'__name__':'__main__'}})
''')
        (stub/'python3').chmod(0o755)
        socket_file = socket_path()
        # Own one fake wire server; never fall back to a real Herdr endpoint.
        server = p/'server.py'
        server.write_text('''import json,socket,sys
s=socket.socket(socket.AF_UNIX);s.bind(sys.argv[1]);s.listen()
while True:
    c,_=s.accept()
    with c:
        c.recv(65536)
        c.sendall(b'{"id":"qwb-herdr","result":{"type":"subscription_started"}}\\n')
        while c.recv(65536):pass
''')
        daemon = subprocess.Popen([sys.executable, '-B', str(server), socket_file],start_new_session=True)
        register(daemon.pid)
        try:
            deadline=time.monotonic()+5
            while not Path(socket_file).exists():
                assert daemon.poll() is None and time.monotonic()<deadline
                time.sleep(.005)
            ledger = p/'qwb-ledger.sh'
            ledger.write_text('#!/bin/sh\nprintf \'{"workers":{"w:p0":{}}}\\n\'\n')
            source = p/'qwb-herdr.sh'
            for phase in ['outer', 'inner']:
                for signum in [signal.SIGTERM, signal.SIGINT]:
                    for swallow in [False, True]:
                        for f in [notice,p/'fired',p/'queries']:
                            if f.exists():f.unlink()
                        (p/'tasks/case.md').write_text('<!-- qwb-collab-fixture -->\n' if phase=='inner' else
                                                      'state: verified\ndispatch: now pane=w:p0\n')
                        (stub/'herdr').write_text('#!/bin/sh\nprintf \'%s\\n\' '+
                            "'"+json.dumps({'server':{'socket':socket_file if phase=='inner' else '/dev/null/qwb-test.sock'}})+"'\n")
                        source.write_bytes(baseline.read_bytes() if baseline else (ROOT/'bin/qwb-herdr.sh').read_bytes())
                        env = dict(os.environ,PATH=str(stub)+':'+os.environ['PATH'], STOP_NOTICE=str(notice),
                                   STOP_FIRED=str(p/'fired'), STOP_QUERIES=str(p/'queries'),
                                   STOP_PHASE=phase, STOP_SIGNAL=str(signum),
                                   STOP_SWALLOW=str(int(swallow)), TMPDIR=str(p),
                                   HERDR_SOCKET_PATH='/dev/null/qwb-test.sock')
                        child = subprocess.Popen(['/bin/bash',str(source),'subscribe','--project',str(p),
                                                  '--notice',str(notice)],env=env,stdout=subprocess.PIPE,
                                                 stderr=subprocess.PIPE,start_new_session=True)
                        register(child.pid)
                        try:
                            deadline=time.monotonic()+5
                            marker=p/'fired' if swallow else notice
                            while not marker.exists():
                                assert child.poll() is None and time.monotonic()<deadline, ('not ready',phase,swallow)
                                time.sleep(.005)
                            started=float(marker.read_text()) if swallow else time.monotonic()
                            if not swallow:child.send_signal(signum)
                            try:out,err=child.communicate(timeout=2)
                            except subprocess.TimeoutExpired as error:
                                raise AssertionError(f'FAIL subscriber {phase}/{signum}: swallowed signal kept loop alive') from error
                            elapsed=time.monotonic()-started
                            assert child.returncode==128+signum and not out, (child.returncode,out,err)
                            assert elapsed<1.3, (phase,swallow,elapsed)
                            if swallow:
                                assert b'Exception ignored' in err and b'SystemExit' in err, err
                                assert json.loads(notice.read_text())['seq']==1, 'subscriber ran another outer iteration'
                            queries={int(x) for x in (p/'queries').read_text().splitlines()}
                            rows=subprocess.check_output(['/bin/ps','-axo','pgid=,stat=']).decode('utf-8',errors='replace')
                            assert not any(int(row[0]) in queries and not row[1].startswith('Z')
                                           for line in rows.splitlines() if (row:=line.split())), 'query survived subscriber exit'
                            print(f'PASS subscriber {phase} signal={signum} swallowed={swallow}: '
                                  f'rc={child.returncode} seconds={elapsed:.6f} stderr={err!r}',flush=True)
                        finally:
                            if child.poll() is None:
                                drain()
                                child.communicate(timeout=3)
                            release(child.pid)
                            if (p/'queries').exists():
                                for group in {int(x) for x in (p/'queries').read_text().splitlines()}:release(group)
        finally:
            release(daemon.pid)
            daemon.wait(timeout=3)


if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--only',choices=['wake','subscriber','all'],default='all')
    parser.add_argument('--baseline-wake',type=Path)
    parser.add_argument('--baseline-subscriber',type=Path)
    args=parser.parse_args()
    assert os.environ.get('QWB_TEST_GROUPS'), 'run through process_fixture.py --command'
    os.environ['QWB_TEST_GROUP'] = str(os.getpgrp())
    if args.only in ['wake','all']:wake_cases(args.baseline_wake)
    if args.only in ['subscriber','all']:subscriber_cases(args.baseline_subscriber)
