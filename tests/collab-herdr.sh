#!/usr/bin/env bash
# Offline public-entry contract: real temporary Git/MD, fake Herdr CLI + Unix stream.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/process-fixture.sh"
qwb_test_scope "$@"
export TMPDIR="${QWB_TEST_SCOPE_DIR}"
mkdir -p "$TMPDIR" || exit 1
export GIT_CEILING_DIRECTORIES="$TMPDIR"
# Fail closed even if the PATH stub disappears.
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
# The focused mode also runs in full: real PID/start evidence through both public close paths.
python3 -B - "$ROOT" <<'PY'
from process_fixture import TemporaryDirectory
import json, os, shutil, subprocess, sys
from pathlib import Path
ROOT=Path(sys.argv[1]).resolve()
source=(ROOT/'tests/worktree-space.py').read_text()
prefix=source.split("with tempfile.TemporaryDirectory(prefix='s-')")[0]
exec(prefix.replace('ROOT = Path(__file__).resolve().parents[1]','ROOT = Path(sys.argv[1]).resolve()'))
BASE='ded7d889ff3fef9c7b9fe142612177c4bedff011'
# Faults wrap only this test interpreter's subprocess.run, never the system ps file.
fault_runner=r'''
import os, subprocess, sys
from pathlib import Path
from unittest.mock import patch
script, fault, marker, *args=sys.argv[1:]
text=Path(script).read_text()
if script.endswith('qwb-herdr.sh'):
    code=text.split("<<'PY'\n",1)[1].rsplit('\nPY',1)[0]
    os.environ['QWB_HERDR_BINDIR']=str(Path(script).parent)
else:
    code=text.split('\nwriters_stopped() {',1)[1].split("<<'PY'\n",1)[1].split('\nPY',1)[0]
sys.argv=[script,*args]; real_run=subprocess.run
calls=[]
def run(argv,**kw):
    if argv[0] not in ('ps','/bin/ps'): return real_run(argv,**kw)
    assert argv[0]=='/bin/ps' and kw['timeout']==2,argv
    calls.append(argv); Path(marker).write_text(repr(calls))
    if fault=='timeout': raise subprocess.TimeoutExpired(argv,2)
    rc,out,err={
        'stderr-dead':(1,'','probe failed'),
        'stderr-reused':(0,'different start','probe failed'),
        'status-3':(3,'',''),
        'empty-live':(0,'',''),
        'output-dead':(1,'unexpected output',''),
    }[fault]
    return subprocess.CompletedProcess(argv,rc,out,err)
with patch('subprocess.run',side_effect=run): exec(compile(code,script,'exec'),{'__name__':'__main__'})
'''
for mode in ['dead','live','reused','invalid','missing','fake-ps','boolean']:
    with TemporaryDirectory(prefix='s-') as d:
        os.environ['TMPDIR']=d
        b=Path(d); repo,ticket,state,log,env=project(b); wt=repo/'.worktrees/case'
        assert call('git','-C',str(repo),'worktree','add','-qb','case',str(wt),env=env).returncode==0
        child=subprocess.Popen([sys.executable,'-u','-c','import sys; print("ready",flush=True); sys.stdin.readline()'],
                               cwd=b,stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
        try:
            assert child.stdout.readline().strip()=='ready'
            stamp=call('/bin/ps','-p',str(child.pid),'-o','lstart=',env=env)
            assert stamp.returncode==0 and stamp.stdout.strip() and not stamp.stderr
            evidence=dict(pid=child.pid,pid_start=stamp.stdout.strip())
            if mode=='dead': child.communicate('exit\n',timeout=10); assert child.returncode==0
            if mode=='reused': evidence['pid_start']='recorded older incarnation'
            if mode=='invalid': evidence['pid']=-1
            if mode=='missing': evidence.pop('pid_start')
            if mode=='boolean': evidence['pid']=True
            if mode=='fake-ps':
                fake=b/'stub/ps'; fake.write_text('#!/bin/sh\nexit 1\n'); fake.chmod(0o755)
            text=f'state: verified\nworktree-space: id=wTask root-tab=wTask:t1 path={wt}\n'
            text+=f'dispatch: now op_id=launch worker=pi pane=wTask:p1 dir={wt}\n'
            text+='working: worker-activity op=launch pane=wTask:p1 evidence='+json.dumps(evidence)+'\n'
            ticket.write_text(text); before=ticket.read_bytes()
            refs=call('git','-C',str(repo),'show-ref',env=env).stdout
            baseline=b/'baseline-bin'; baseline.mkdir()
            (baseline/'qwb-herdr.sh').write_bytes(subprocess.check_output(['git','-C',str(ROOT),'show',BASE+':bin/qwb-herdr.sh']))
            shutil.copy(ROOT/'bin/qwb-lib.sh',baseline/'qwb-lib.sh')
            selected=ROOT/'bin/qwb-herdr.sh'
            if os.environ.get('QWB_DEATH_HERDR_REV'):
                selected=baseline/'qwb-herdr.sh'
            args=['close','--project',str(repo),'--task',str(ticket),'--space','wTask']
            def close(script):
                state.write_text(str(wt)); log.write_text('')
                return call('bash',str(script),*args,env=env)
            old=close(baseline/'qwb-herdr.sh') if mode in ('dead','fake-ps') else None
            got=close(selected); expected=mode in ('dead','reused')
            print('DEATH-PROOF',mode,'herdr_rc=',got.returncode,'stdout=',repr(got.stdout),'stderr=',repr(got.stderr),flush=True)
            if mode=='dead':
                assert (got.returncode,got.stdout,got.stderr)==(old.returncode,old.stdout,old.stderr),'normal close changed bytes'
            if mode=='fake-ps':
                assert old.returncode==0
                print('BASELINE fake-ps herdr_rc=',old.returncode,'stdout=',repr(old.stdout),'stderr=',repr(old.stderr),flush=True)
            assert ticket.read_bytes()==before and wt.is_dir() and call('git','-C',str(repo),'show-ref',env=env).stdout==refs
            preserved=state.exists() and not any(json.loads(x)==['workspace','close','wTask'] or isinstance(json.loads(x),dict) for x in log.read_text().splitlines())
            # Faults reach the same full close body; no system executable is substituted.
            if mode=='live':
                marker=b/'fault-calls'
                for fault in ['stderr-dead','stderr-reused','status-3','timeout','empty-live','output-dead']:
                    state.write_text(str(wt)); log.write_text(''); marker.unlink(missing_ok=True)
                    bad=call(sys.executable,'-B','-c',fault_runner,str(ROOT/'bin/qwb-herdr.sh'),fault,str(marker),*args,env=env)
                    assert marker.exists() and bad.returncode==1 and not bad.stdout,(fault,bad.stdout,bad.stderr)
                    assert bad.stderr=='Herdr refusal/unknown: old native PID still alive or death unknown\n',bad.stderr
                    assert state.exists() and ticket.read_bytes()==before and wt.is_dir()
                    assert not any(json.loads(x)==['workspace','close','wTask'] or isinstance(json.loads(x),dict) for x in log.read_text().splitlines())
                    marker.unlink()
                    other=call(sys.executable,'-B','-c',fault_runner,str(ROOT/'bin/qwb-worktree.sh'),fault,str(marker),str(ticket),str(wt),'',env=env)
                    assert marker.exists() and other.returncode==1,(fault,other.stdout,other.stderr)
                    print('PASS death-proof fault '+fault+': both reject; herdr stderr='+repr(bad.stderr),flush=True)
            state.write_text(str(wt)); log.write_text('')
            finished=call('bash',str(ROOT/'bin/qwb-worktree.sh'),'finish','case','--merged','--project',str(repo),env=env)
            print('DEATH-PROOF',mode,'worktree_rc=',finished.returncode,'stdout=',repr(finished.stdout),'stderr=',repr(finished.stderr),flush=True)
            assert (got.returncode==0)==(finished.returncode==0)==expected,(mode,got.stdout,got.stderr,finished.stdout,finished.stderr)
            if expected:
                assert not wt.exists() and not state.exists()
            else:
                assert preserved and wt.is_dir() and state.exists() and ticket.read_bytes()==before
                if mode in ('live','fake-ps'): assert got.stderr=='Herdr refusal/unknown: old native PID still alive or death unknown\n',got.stderr
                assert call('git','-C',str(repo),'show-ref',env=env).stdout==refs
                assert not any(json.loads(x)==['workspace','close','wTask'] for x in log.read_text().splitlines())
            if child.poll() is None: assert call('/bin/ps','-p',str(child.pid),'-o','lstart=',env=env).stdout.strip()==stamp.stdout.strip()
            print('PASS death-proof '+mode+': herdr/worktree agree '+('allow' if expected else 'refuse'),flush=True)
        finally:
            if child.poll() is None: child.terminate(); child.wait(timeout=10)
            child.stdin.close(); child.stdout.close()
PY
if [[ "${1:-}" == death-proof ]]; then exit 0; fi
if [[ "${1:-}" != not-sent ]]; then
python3 -B - "$ROOT" <<'PY'
from process_fixture import TemporaryDirectory, socket_path
import json, os, socket, subprocess, tempfile, threading, time
from pathlib import Path
ROOT=Path(__import__('sys').argv[1])
with TemporaryDirectory(prefix='s-') as tmp:
    os.environ["TMPDIR"] = tmp
    b=Path(tmp); p=b/'project'; p.mkdir(); (p/'tasks').mkdir(); (p/'qwbuddy').mkdir()
    subprocess.run(['git','init','-q',str(p)],check=True)
    (p/'qwbuddy/config.sh').write_text('QWB_REWAKE_MS=0\n')
    lock=p/'qwbuddy/.controller.lock'; lock.mkdir(); (lock/'owner').write_text('now ctl\n')
    for n in range(3):
        (p/f'tasks/{n}.md').write_text(f'state: running\ndispatch: 2099-01-0{n+1} pane=w:p{n} dir={p}\nworking: initial\n')
    roles=p/'qwbuddy/.roles'; roles.mkdir()
    (roles/'planner.json').write_text(json.dumps(dict(version=1,root=str(p.resolve()),phase='active',pane='w:role')))
    stub=b/'stub'; stub.mkdir(); sockpath=socket_path(); log=b/'calls'; requests=[]
    (stub/'herdr').write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
a=sys.argv[1:]
with open(os.environ['LOG'],'a') as f: f.write(json.dumps(a)+'\\n')
if a[:2]==['status','--json']: print(json.dumps({'server':{'socket':os.environ['SOCKET']}}))
elif a[:2]==['pane','get']: print(json.dumps({'result':{'pane':{'pane_id':a[2],'agent':'pi'}}}))
else: print(json.dumps({'result':{'type':'ok'}}))
'''); (stub/'herdr').chmod(0o755)
    env={**os.environ,'PATH':str(stub)+':'+os.environ['PATH'],'HERDR_PANE_ID':'ctl','LOG':str(log),'SOCKET':sockpath}
    wake=['bash',str(ROOT/'bin/qwb-wake.sh'),'--project',str(p),'--interval','15000']
    # Consume initial legacy facts through the same public entry, not fabricated fingerprints.
    prime=subprocess.run(wake+['--once','--pane','ctl'],env=env,capture_output=True,text=True)
    assert prime.returncode==0,prime.stderr
    server=socket.socket(socket.AF_UNIX); server.bind(sockpath); server.listen(); server.settimeout(8)
    ready=threading.Event(); errors=[]
    def emit():
        try:
            c,_=server.accept()
            with c:
                f=c.makefile('rb'); req=json.loads(f.readline()); requests.append(req)
                c.sendall((json.dumps({'id':req['id'],'result':{'type':'subscription_started'}})+'\n').encode())
                ready.set(); time.sleep(.15)
                with (p/'tasks/0.md').open('a') as t: t.write('done: older worker completed\n')
                c.sendall((json.dumps({'event':'pane.agent_status_changed','data':{'pane_id':'w:p0','workspace_id':'w','agent_status':'done'}})+'\n').encode())
                time.sleep(.2)
        except Exception as e: errors.append(str(e)); ready.set()
    thread=threading.Thread(target=emit,daemon=True); thread.start()
    start=time.monotonic()
    got=subprocess.run(wake+['--block','--max-ms','12000'],env=env,capture_output=True,text=True,timeout=15)
    latency=time.monotonic()-start
    server.close(); thread.join(timeout=1)
    assert got.returncode==2 and 'older worker completed' in got.stdout,(got.returncode,got.stdout,got.stderr)
    assert latency<10,('non-latest completion waited for polling interval',latency,got.stderr)
    assert requests and {s['pane_id'] for s in requests[0]['params']['subscriptions']}=={'w:p0','w:p1','w:p2','w:role'},requests
    assert not errors,errors
    print(f'PASS non-latest registered worker subscribed; delivery latency={latency:.3f}s')
PY
python3 -B - "$ROOT" <<'PY'
from process_fixture import TemporaryDirectory, socket_path
from contextlib import ExitStack
import json, os, socket, subprocess, tempfile, threading, time
from pathlib import Path
ROOT=Path(__import__('sys').argv[1])
with TemporaryDirectory(prefix='s-') as tmp, ExitStack() as processes:
    os.environ["TMPDIR"] = tmp
    b=Path(tmp); root=b/'repo'; root.mkdir(); (root/'tasks').mkdir()
    def run(*args,env=None):
        return subprocess.run(list(args),env=env,capture_output=True,text=True,timeout=10)
    assert run('git','init','-q',str(root)).returncode==0
    for k,v in [('user.name','Test'),('user.email','test@example.invalid')]:
        assert run('git','-C',str(root),'config',k,v).returncode==0
    assert run('git','-C',str(root),'commit','-qm','base','--allow-empty').returncode==0
    wt=root/'.worktrees/case'
    assert run('git','-C',str(root),'worktree','add','-qb','case',str(wt)).returncode==0
    task=root/'tasks/case.md'; task.write_text(f'state: verified\nworktree-space: id=wTask root-tab=wTask:t1 path={wt}\n')
    state=b/'state.json'; sockpath=socket_path()
    def w(i):
        return dict(workspace_id=i,focused=i=='wOther',active_tab_id=i+':t1',worktree=dict(repo_root=str(root),checkout_path=str(wt) if i=='wTask' else str(root),is_linked_worktree=i=='wTask'))
    def pane(i):
        return dict(pane_id=i+':p1',workspace_id=i,tab_id=i+':t1',agent=None,agent_status='idle',foreground_cwd=str(wt) if i=='wTask' else str(root))
    initial=dict(workspaces=[w('wTask'),w('wOther')],tabs=[dict(tab_id=i+':t1',workspace_id=i) for i in ['wTask','wOther']],panes=[pane('wTask'),pane('wOther')],focused_workspace_id='wOther',focused_tab_id='wOther:t1',focused_pane_id='wOther:p1')
    state.write_text(json.dumps(initial)); stub=b/'stub'; stub.mkdir(); calls=b/'calls'
    (stub/'herdr').write_text(r'''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
a=sys.argv[1:]; state=Path(os.environ['STATE']); s=json.loads(state.read_text())
with open(os.environ['CALLS'],'a') as f: f.write(json.dumps(a)+'\n')
def out(r): print(json.dumps({'result':r}))
if a[:2]==['status','--json']: print(json.dumps({'server':dict(socket=os.environ['SOCKET'],session=os.environ.get('HERDR_SESSION'))}))
elif a[:2]==['api','snapshot']: out({'snapshot':s})
elif a[:2]==['workspace','list']: out({'workspaces':s['workspaces']})
elif a[:2]==['pane','get']:
    r=next(x for x in s['panes'] if x['pane_id']==a[2]); out({'pane':r})
elif a[:2]==['pane','process-info']:
    pid=int(os.environ['NATIVE_PID']); busy=os.environ.get('BUSY')=='1'
    out({'process_info':dict(pane_id=a[3],shell_pid=42,foreground_process_group_id=pid if busy else 42,
         foreground_processes=[dict(pid=pid if busy else 42,argv0='pi' if busy else 'zsh',cwd=os.environ['WT'])])})
elif a[:2]==['workspace','close']:
    if os.environ.get('CLOSE_UNCONFIRMED')!='1':
        for key in ['workspaces','tabs','panes']: s[key]=[x for x in s[key] if x.get('workspace_id')!=a[2]]
        state.write_text(json.dumps(s))
    out({'type':'workspace_closed'})
else: sys.exit(9)
'''); (stub/'herdr').chmod(0o755)
    api=socket.socket(socket.AF_UNIX); api.bind(sockpath); api.listen(); api.settimeout(.2); stop=threading.Event()
    def serve():
        while not stop.is_set():
            try: c,_=api.accept()
            except socket.timeout: continue
            with c:
                req=json.loads(c.makefile('rb').readline()); s=json.loads(state.read_text()); method=req['method']; params=req['params']
                with calls.open('a') as f: f.write(json.dumps(req)+'\n')
                if method=='workspace.move':
                    ws=params['workspace_id']; item=next(x for x in s['workspaces'] if x['workspace_id']==ws)
                    old=s['workspaces'].index(item); slot=params['insert_index']
                    s['workspaces']=[x for x in s['workspaces'] if x['workspace_id']!=ws]; s['workspaces'].insert(slot-1 if slot>old else slot,item)
                    # Herdr-like layout side effect: require explicit same-pane restore/readback.
                    s.update(focused_workspace_id=ws,focused_tab_id=ws+':t1',focused_pane_id=ws+':p1')
                    if s.get('concurrent_focus'): s.update(focused_workspace_id='wOther',focused_tab_id='wOther:t1',focused_pane_id='wOther:p2')
                    result={'type':'workspace_list','workspaces':s['workspaces']}
                elif method=='pane.focus':
                    pane=params['pane_id']; ws=next(x['workspace_id'] for x in s['panes'] if x['pane_id']==pane)
                    s.update(focused_workspace_id=ws,focused_tab_id=ws+':t1',focused_pane_id=pane); result={'type':'ok'}
                else: result={'type':'ok'}
                state.write_text(json.dumps(s)); c.sendall((json.dumps({'id':req['id'],'result':result})+'\n').encode())
    thread=threading.Thread(target=serve,daemon=True); thread.start()
    native=subprocess.Popen([__import__('sys').executable,'-c','import sys; sys.stdin.read()'],stdin=subprocess.PIPE)
    processes.callback(lambda: (native.terminate() if native.poll() is None else None, native.wait(timeout=10), native.stdin.close()))
    env={**os.environ,'PATH':str(stub)+':'+os.environ['PATH'],'STATE':str(state),'SOCKET':sockpath,'CALLS':str(calls),'NATIVE_PID':str(native.pid),'WT':str(wt)}
    helper=['bash',str(ROOT/'bin/qwb-herdr.sh')]
    base=helper+['move','--project',str(root),'--task',str(task),'--space','wTask','--index','1']
    moved=run(*base,env=env); assert moved.returncode==0,moved.stderr
    s=json.loads(state.read_text()); assert [w['workspace_id'] for w in s['workspaces']]==['wOther','wTask'] and s['focused_pane_id']=='wOther:p1',s
    assert task.read_text().endswith(f'path={wt}\n'),'ordering mutated ticket ownership'
    foreign=run(*[x if x!='wTask' else 'wOther' for x in base],env=env); assert foreign.returncode!=0
    concurrent=dict(initial,concurrent_focus=True); concurrent['panes']=initial['panes']+[dict(pane('wOther'),pane_id='wOther:p2')]
    state.write_text(json.dumps(concurrent))
    conflict=run(*base,env=env); assert conflict.returncode!=0 and json.loads(state.read_text())['focused_pane_id']=='wOther:p2',conflict.stderr
    state.write_text(json.dumps(s))
    # A native idle edge with an outstanding tool call is busy and never closed.
    session=b/'pi.jsonl'; session.write_text('\n'.join(json.dumps(x) for x in [
        dict(type='session',id='session',cwd=str(wt)),
        dict(type='message',id='call',parentId=None,message=dict(role='assistant',stopReason='toolUse',content=[dict(type='toolCall',id='long',name='bash')]))])+'\n')
    s['panes'][0 if s['panes'][0]['workspace_id']=='wTask' else 1].update(agent='pi',agent_session=dict(kind='path',source='herdr:pi',value=str(session)))
    state.write_text(json.dumps(s)); busyenv={**env,'BUSY':'1'}
    observed=run(*helper,'activity','--project',str(root),'--pane','wTask:p1','--dir',str(wt),env=busyenv)
    assert observed.returncode==0 and json.loads(observed.stdout)['activity']=='busy',observed.stderr
    close=helper+['close','--project',str(root),'--task',str(task),'--space','wTask']
    blocked=run(*close,env=busyenv); assert blocked.returncode!=0 and len(json.loads(state.read_text())['workspaces'])==2,blocked.stderr
    # Even a settled native Pi must exit to shell before destructive Space close.
    with session.open('a') as f:
        f.write(json.dumps(dict(type='message',id='result',parentId='call',message=dict(role='toolResult',toolCallId='long')))+'\n')
        f.write(json.dumps(dict(type='message',id='finish',parentId='result',message=dict(role='assistant',stopReason='stop',content=[])))+'\n')
    idle=run(*helper,'activity','--project',str(root),'--pane','wTask:p1','--dir',str(wt),env=busyenv)
    assert idle.returncode==0 and json.loads(idle.stdout)['activity']=='idle',idle.stderr
    # Reuse requires this launch's PID/start/session, not only an idle edge or old dispatch.
    original_ticket=task.read_text(); proof=json.loads(idle.stdout)
    unbound=run(*helper,'activity','--project',str(root),'--pane','wTask:p1','--dir',str(wt),'--task',str(task),env=busyenv)
    assert json.loads(unbound.stdout)['activity']=='unknown'
    task.write_text(original_ticket+'working: worker-activity op=fixture pane=wTask:p1 evidence='+json.dumps(proof)+'\n')
    bound=run(*helper,'activity','--project',str(root),'--pane','wTask:p1','--dir',str(wt),'--task',str(task),env=busyenv)
    assert json.loads(bound.stdout)['activity']=='idle',bound.stdout
    proof['pid_start']='stale incarnation'
    task.write_text(original_ticket+'working: worker-activity op=fixture pane=wTask:p1 evidence='+json.dumps(proof)+'\n')
    stale=run(*helper,'activity','--project',str(root),'--pane','wTask:p1','--dir',str(wt),'--task',str(task),env=busyenv)
    assert json.loads(stale.stdout)['activity']=='unknown'
    task.write_text(original_ticket)
    # Pi recovery omits a transport-error attempt; raw history must stay intact.
    settled_bytes=session.read_bytes()
    header=dict(type='session',id='session',cwd=str(wt))
    failed=dict(type='message',id='failed',parentId=None,message=dict(role='assistant',stopReason='error',errorMessage='WebSocket closed 1012',content=[dict(type='toolCall',id='ghost',name='bash')]))
    finish=dict(type='message',id='finish',parentId='failed',message=dict(role='assistant',stopReason='stop',content=[]))
    omission=dict(type='context_edit',id='omit',parentId='finish',targetId='failed',replacement=None)
    def observe(entries,wanted,pending):
        session.write_text('\n'.join(json.dumps(x) for x in [header,*entries])+'\n'); before=session.read_bytes()
        got=run(*helper,'activity','--project',str(root),'--pane','wTask:p1','--dir',str(wt),env=busyenv)
        assert got.returncode==0,(got.stdout,got.stderr)
        data=json.loads(got.stdout)
        assert (data['activity'],data.get('pending_tools'))==(wanted,pending),(wanted,pending,data)
        assert session.read_bytes()==before,'activity rewrote append-only native history'
    observe([failed,finish],'busy',['ghost'])  # An error or Herdr idle alone never clears a call.
    observe([failed,finish,omission],'idle',[])  # Only the explicit edit condition differs.
    observe([failed,finish,dict(omission,targetId='other-entry')],'busy',['ghost'])
    observe([failed,finish,dict(omission,replacement={'content':'recovered text'})],'idle',[])
    observe([failed,finish,dict(omission,replacement={'content':[]})],'idle',[])
    live=dict(type='toolCall',id='live',name='bash')
    observe([failed,finish,dict(omission,replacement={'content':[live]})],'busy',['live'])
    restored=dict(omission,id='restore',parentId='omit',replacement={'content':failed['message']['content']})
    observe([failed,finish,omission,restored],'busy',['ghost'])
    observe([failed,finish,omission,restored,dict(omission,id='delete-again',parentId='restore')],'idle',[])
    # An edit on an abandoned branch must not alter the selected branch's pending call.
    observe([failed,finish,omission,dict(type='label',id='before-edit',parentId='finish')],'busy',['ghost'])
    observe([failed,finish,dict(omission,replacement={'content':[live]}),dict(type='message',id='other-root',parentId=None,message=dict(role='assistant',stopReason='stop',content=[]))],'idle',[])
    result=dict(type='message',id='result',parentId='failed',message=dict(role='toolResult',toolCallId='ghost',content=[]))
    result_finish=dict(finish,parentId='result')
    result_edit=dict(omission,parentId='finish',targetId='result',replacement={'content':'edited result'})
    observe([failed,result,result_finish,result_edit],'idle',[])  # Content changes preserve role/call ID.
    observe([failed,result,result_finish,dict(result_edit,replacement=None)],'busy',['ghost'])
    pending=dict(type='message',id='live-call',parentId='omit',message=dict(role='assistant',stopReason='toolUse',content=[live]))
    observe([failed,finish,omission,pending,dict(finish,id='idle-edge',parentId='live-call')],'busy',['live'])
    # Compaction is not an execution acknowledgement; preserve unmatched native obligations.
    observe([failed,finish,dict(type='compaction',id='summary',parentId='finish',firstKeptEntryId='summary',summary='history summarized')],'busy',['ghost'])
    working=json.loads(state.read_text());next(x for x in working['panes'] if x['pane_id']=='wTask:p1')['agent_status']='working';state.write_text(json.dumps(working))
    observe([failed,finish,omission],'busy',[])
    state.write_text(json.dumps(s))
    observe([failed,finish,{k:v for k,v in omission.items() if k!='replacement'}],'unknown',None)
    observe([failed,finish,dict(omission,replacement={'content':False})],'unknown',None)
    session.write_bytes(settled_bytes)
    print('PASS context edits omit/replace content on selected branch; latest wins; true pending/error/working/compaction remain busy; raw untouched')
    blocked=run(*close,env=busyenv); assert blocked.returncode!=0,blocked.stderr
    state.write_text(json.dumps(initial))
    # A foreground shell is not death proof for the original bound/background PID.
    proof=json.loads(idle.stdout)
    task.write_text(original_ticket+f'dispatch: now pane=wTask:p1 dir={wt}\n'+'working: worker-activity op=fixture pane=wTask:p1 evidence='+json.dumps(proof)+'\n')
    alive=run(*close,env=env); assert alive.returncode!=0 and len(json.loads(state.read_text())['workspaces'])==2,alive.stderr
    task.write_text(original_ticket)
    uncertain=run(*close,env={**env,'CLOSE_UNCONFIRMED':'1'})
    assert uncertain.returncode!=0 and len(json.loads(state.read_text())['workspaces'])==2,uncertain.stderr
    state.write_text(json.dumps(initial))
    closed=run(*close,env=env); assert closed.returncode==0,closed.stderr
    s=json.loads(state.read_text()); assert [w['workspace_id'] for w in s['workspaces']]==['wOther'] and s['focused_pane_id']=='wOther:p1',s
    assert wt.is_dir() and task.read_text().endswith(f'path={wt}\n')
    actions=[json.loads(x) for x in calls.read_text().splitlines()]
    assert not any(isinstance(x,dict) and x.get('method')=='workspace.move' and x['params']['workspace_id']!='wTask' for x in actions)
    stop.set(); thread.join(timeout=1); api.close()
    print('PASS owned ordering/confirmed close preserve unrelated focus; unknown ownership/long idle tool/live Pi refuse')
PY
python3 -B - "$ROOT" <<'PY'
from process_fixture import TemporaryDirectory, socket_path
import hashlib, json, os, shutil, socket, subprocess, tempfile, threading, time
from pathlib import Path
ROOT=Path(__import__('sys').argv[1])
with TemporaryDirectory(prefix='s-') as tmp:
    os.environ["TMPDIR"] = tmp
    b=Path(tmp); p=b/'project'; p.mkdir(); (p/'tasks').mkdir(); (p/'qwbuddy').mkdir()
    subprocess.run(['git','init','-q',str(p)],check=True)
    lock=p/'qwbuddy/.controller.lock'; lock.mkdir(); (lock/'owner').write_text('now ctl\n')
    (p/'qwbuddy/config.sh').write_text('QWB_REWAKE_MS=60000\n')
    shutil.copytree(ROOT/'bin',p/'qwbuddy/bin')
    shutil.copytree(ROOT/'templates/roles',p/'qwbuddy/roles')
    for name in ['TASK.md','QWBUDDY.md']: shutil.copy(ROOT/'templates'/name,p/'qwbuddy'/name)
    t=p/'tasks/case.md'; t.write_text('state: running\n')
    (p/'tasks/observer.md').write_text(f'state: verified\ndispatch: now pane=w:p0 dir={p}\n')
    stub=b/'stub'; stub.mkdir(); log=b/'calls'; socketpath=socket_path()
    (stub/'lsof').write_text('#!/usr/bin/env bash\nexit 1\n'); (stub/'lsof').chmod(0o755)
    (stub/'herdr').write_text(r'''#!/usr/bin/env python3
import json,os,sys
a=sys.argv[1:]
with open(os.environ['LOG'],'a') as f: f.write(json.dumps(a)+'\n')
if a[:2]==['status','--json']: print(json.dumps({'server':{'socket':os.environ['SOCKET'],'session':os.environ.get('HERDR_SESSION')}}))
else: print(json.dumps({'result':{'type':'ok'}}))
'''); (stub/'herdr').chmod(0o755)
    env={**os.environ,'PATH':str(stub)+':'+os.environ['PATH'],'HERDR_PANE_ID':'ctl','LOG':str(log),'SOCKET':socketpath}
    def call(script,cmd,*args,rc=0):
        r=subprocess.run(['bash',str(ROOT/'bin'/script),cmd,'--project',str(p),'--task',str(t),*args],env=env,capture_output=True,text=True,timeout=15)
        assert r.returncode==rc,(script,cmd,r.returncode,r.stdout,r.stderr); return r.stdout
    proof=b/'migration.json'; proof.write_text(json.dumps(dict(task_sha256=hashlib.sha256(t.read_bytes()).hexdigest(),confirm={k:'temporary fixture; old writers stopped' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']})))
    call('qwb-ledger.sh','migrate','--',str(proof))
    wake=['bash',str(ROOT/'bin/qwb-wake.sh'),'--project',str(p),'--pane','ctl','--interval','10000']
    prime=subprocess.run(wake+['--once'],env=env,capture_output=True,text=True,timeout=15); assert prime.returncode==0,prime.stderr
    api=socket.socket(socket.AF_UNIX); api.bind(socketpath); api.listen(); api.settimeout(.2)
    stop=threading.Event(); disconnected=threading.Event(); reconnect=threading.Event(); connected=threading.Event(); requests=[]
    def server():
        count=0
        while not stop.is_set():
            try: c,_=api.accept()
            except socket.timeout: continue
            try:
                with c:
                    c.settimeout(2); req=json.loads(c.makefile('rb').readline()); requests.append(req); count+=1
                    if count>1 and not reconnect.wait(1): continue
                    c.sendall((json.dumps({'id':req['id'],'result':{'type':'subscription_started'}})+'\n').encode())
                    if count==1: disconnected.set(); continue
                    connected.set()
                    for _ in range(3):
                        c.sendall((json.dumps(dict(event='pane.agent_status_changed',data=dict(pane_id='w:p0',workspace_id='w',agent_status='done')))+'\n').encode()); time.sleep(.1)
                    stop.wait(5)
            except (BrokenPipeError,ConnectionResetError,socket.timeout): pass
    thread=threading.Thread(target=server,daemon=True); thread.start()
    owner=subprocess.Popen(wake,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    try:
        assert disconnected.wait(8),'subscription was not established'
        duplicate=subprocess.run(wake+['--once'],env=env,capture_output=True,text=True,timeout=10)
        assert duplicate.returncode==75,('second supervisor not rejected',duplicate.returncode,duplicate.stderr)
        start=time.monotonic()
        call('qwb-ledger.sh','question','--event-id','during-gap-key','--','budget','预算未答')
        call('qwb-ledger.sh','append','--event-id','during-gap-result','--','done: 断流期间结果')
        deadline=time.monotonic()+15
        while time.monotonic()<deadline:
            lines=[json.loads(x) for x in log.read_text().splitlines()]
            if all(any(x[:2]==['pane','run'] and source in x[-1] for x in lines) for source in ['during-gap-key','during-gap-result']): break
            time.sleep(.1)
        else: raise AssertionError('fallback did not deliver all gap facts: '+log.read_text())
        latency=time.monotonic()-start; reconnect.set(); assert connected.wait(8),'not reconnected'
        time.sleep(2)
        data=json.loads(call('qwb-ledger.sh','read')); pending=json.loads(call('qwb-send.sh','pending'))
        assert data['questions']['budget']['answer']=='' and data['questions']['budget']['resumed']==''
        for source in ['during-gap-key','during-gap-result']:
            h=next(x for x in pending if x['source_event']==source); assert not h['handled'],h
            assert h['transport_count']==1,('duplicate event replay repeated transport',h)
        assert len(requests)>=2 and all(r['params']['subscriptions']==[dict(type='pane.agent_status_changed',pane_id='w:p0')] for r in requests)
        print(f'PASS gap facts delivered latency={latency:.3f}s; reconnected level reconcile, one owner, duplicate events keep one transport/unanswered key')
    finally:
        owner.terminate(); out,err=owner.communicate(timeout=15)
        print('reconnect owner output:',out,err)
        stop.set(); thread.join(timeout=3); api.close()
        assert owner.returncode in (0,143),('owner cleanup',owner.returncode,out,err)
    timed=subprocess.run(wake+['--block','--max-ms','150'],env=env,capture_output=True,text=True,timeout=10)
    assert timed.returncode==124 and '--block 到期' in timed.stderr,(timed.returncode,timed.stdout,timed.stderr)
    unchanged=json.loads(call('qwb-ledger.sh','read'))
    assert unchanged['questions']['budget']['answer']=='' and unchanged['questions']['budget']['resumed']==''
    print('PASS normal deadline remains 124 wait, no cancellation/death or unanswered-key consumption')
PY
fi
python3 -B - "$ROOT" <<'PY'
from process_fixture import TemporaryDirectory
from contextlib import ExitStack
import json, os, subprocess, sys, tempfile
from pathlib import Path
ROOT=Path(sys.argv[1]).resolve()
# Reuse the external Herdr contract double/project builder; exercise real writer and finish.
source=(ROOT/'tests/worktree-space.py').read_text()
prefix=source.split("with tempfile.TemporaryDirectory(prefix='s-')")[0]
prefix=prefix.replace('ROOT = Path(__file__).resolve().parents[1]','ROOT = Path(sys.argv[1]).resolve()')
exec(prefix)
for mode in ['live','missing','dead','extra-pane','no-attempt']:
    with TemporaryDirectory(prefix='s-') as d, ExitStack() as processes:
        os.environ["TMPDIR"] = d
        repo,ticket,state,log,env=project(Path(d)); wt=repo/'.worktrees/case'
        assert call('git','-C',str(repo),'worktree','add','-qb','case',str(wt),env=env).returncode==0
        state.write_text(str(wt)); log.write_text('')
        live_child=subprocess.Popen([sys.executable,'-c','import sys; sys.stdin.read()'],stdin=subprocess.PIPE)
        processes.callback(lambda: (live_child.terminate() if live_child.poll() is None else None, live_child.wait(timeout=10), live_child.stdin.close()))
        pid=live_child.pid
        start=call('/bin/ps','-p',str(pid),'-o','lstart=',env=env).stdout.strip()
        evidence=dict(pid=pid,pid_start=start)
        if mode in ('dead','extra-pane'):
            child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)'])
            evidence=dict(pid=child.pid,pid_start=call('/bin/ps','-p',str(child.pid),'-o','lstart=',env=env).stdout.strip())
            child.terminate(); child.wait()
        if mode=='missing': evidence=dict(activity='unknown')
        pane='wTask:p2' if mode=='extra-pane' else 'wTask:p1'
        text=f'state: verified\nworktree-space: id=wTask root-tab=wTask:t1 path={wt}\n'
        if mode!='no-attempt':
            dispatch=f'dispatch: now op_id=launch worker=pi agent=case pane={pane} dir={wt}'
            text+=dispatch+'\n'+f'working: worker-activity op=launch pane={pane} evidence='+json.dumps(evidence)+'\n'
            if mode=='extra-pane':
                text+='working: worker-activity op=old-root pane=wTask:p1 evidence='+json.dumps(dict(pid=pid,pid_start=start))+'\n'
                env={**env,'QWB_TEST_MODE':'worker-success'}
        ticket.write_text(text)
        if mode!='no-attempt':
            compensation=call('bash',str(ROOT/'bin/qwb-ledger.sh'),'not-sent','--project',str(repo),'--task',str(ticket),'--legacy','--','launch','blocked: prompt failed',dispatch,env=env)
            assert compensation.returncode==0,compensation.stderr
            assert 'not-sent: now op_id=launch' in ticket.read_text() and '\ndispatch:' not in ticket.read_text()
        result=call('bash',str(ROOT/'bin/qwb-worktree.sh'),'finish','case','--merged','--project',str(repo),env=env)
        closes=[x for x in log.read_text().splitlines() if json.loads(x)==['workspace','close','wTask']]
        if mode in ('live','missing','extra-pane'):
            assert result.returncode!=0 and wt.exists() and state.exists() and not closes,(mode,result.returncode,result.stdout,result.stderr)
            reason='旧启动代PID/start未知' if mode=='missing' else '旧启动代仍活或死亡未知'
            assert reason in result.stderr,(mode,'must hit lifetime refusal, not an unrelated fixture error',result.stderr)
            os.kill(pid,0)
            assert call('git','-C',str(repo),'show-ref','--verify','--quiet','refs/heads/case',env=env).returncode==0
            print('PASS not-sent '+mode+': original launch obligation retained, no Space/Git close')
        else:
            assert result.returncode==0 and not wt.exists() and not state.exists() and len(closes)==1,(mode,result.returncode,result.stdout,result.stderr)
            print('PASS '+mode+': proven-ended/no-start safe finish remains usable')

# F2 public seam: real qwb-run fresh/reuse (including prompt failure), actual process death, then finish.
# Native Pi metadata is an external Herdr double; PID/start belong to a real owned child, not a model CLI.
native_stub=STUB.replace('if args[:2] == ["status", "--json"]:', r'''native = Path(os.environ["QWB_TEST_NATIVE"])
session = os.environ["QWB_TEST_NATIVE_SESSION"]
if args[:2] == ["agent", "start"]:
    native.write_text("started")
    out({"type": "agent_started"})
elif args[:2] == ["agent", "get"] and native.exists():
    out({"agent": {"name": "qwb-case", "agent": "pi", "agent_status": "idle", "pane_id": "wTask:p1", "workspace_id": "wTask", "cwd": wt}})
elif args[:2] == ["pane", "get"] and args[2] == "wTask:p1" and native.exists():
    out({"pane": {"pane_id": "wTask:p1", "tab_id": "wTask:t1", "workspace_id": "wTask", "agent": "pi", "agent_status": "idle", "foreground_cwd": wt,
         "agent_session": {"source": "herdr:pi", "kind": "path", "value": session}}})
elif args[:2] == ["pane", "process-info"] and args[3] == "wTask:p1" and native.exists():
    pid = int(os.environ["QWB_TEST_NATIVE_PID"])
    out({"process_info": {"pane_id": "wTask:p1", "shell_pid": 42, "foreground_process_group_id": pid,
         "foreground_processes": [{"pid": pid, "argv0": "pi", "cwd": wt}]}})
elif args[:2] == ["agent", "prompt"]:
    # Observe the durable receipt at the external transport boundary, before failure compensation.
    text = Path(os.environ["QWB_TEST_NATIVE_TICKET"]).read_text()
    with log.open("a") as f: f.write(json.dumps(["prompt-ticket", text]) + "\n")
    if os.environ.get("QWB_TEST_PROMPT_FAILED") == "1": err("prompt_failed")
    out({"type": "ok"})
elif args[:2] == ["status", "--json"]:''')
for mode in ['reuse','failed-reuse','unknown-start']:
    with TemporaryDirectory(prefix='s-') as d:
        os.environ["TMPDIR"] = d
        b=Path(d); repo,ticket,state,log,env=project(b); wt=repo/'.worktrees/case'
        assert call('git','-C',str(repo),'worktree','add','-qb','case',str(wt),env=env).returncode==0
        child=subprocess.Popen(['sleep','60'],cwd=wt)
        native=b/'native-active'; session=b/'pi.jsonl'
        session.write_text(json.dumps(dict(type='session',cwd=str(wt)))+'\n'+json.dumps(dict(type='message',id='end',message=dict(role='assistant',content=[],stopReason='stop')))+'\n')
        (b/'stub/herdr').write_text(native_stub)
        env={**env,'QWB_TEST_NATIVE':str(native),'QWB_TEST_NATIVE_SESSION':str(session),'QWB_TEST_NATIVE_PID':str(child.pid),'QWB_TEST_NATIVE_TICKET':str(ticket)}
        dispatch=['bash',str(repo/'qwbuddy/bin/qwb-run.sh'),'--project',str(repo),'--task','case','--worker','pi']
        finish=['bash',str(ROOT/'bin/qwb-worktree.sh'),'finish','case','--merged','--project',str(repo)]
        try:
            first=call(*dispatch,env=env); assert first.returncode==0,(first.stdout,first.stderr)
            if mode=='unknown-start':
                ticket.write_text('\n'.join(x for x in ticket.read_text().splitlines() if not x.startswith('working: worker-activity'))+'\n')
            second=call(*dispatch,env={**env,**({'QWB_TEST_PROMPT_FAILED':'1'} if mode=='failed-reuse' else {})})
            assert second.returncode==(0 if mode=='reuse' else 1),(mode,second.stdout,second.stderr)
            if mode!='unknown-start': assert '复用既有工人' in second.stdout,(mode,second.stdout,second.stderr)
            else: assert '本代真实活动为 unknown' in second.stderr,(mode,second.stderr)
            calls=[json.loads(x) for x in log.read_text().splitlines()]
            assert sum(x[:2]==['agent','start'] for x in calls)==1 and not any(x[:2]==['tab','create'] for x in calls),calls
            # Native label can return to shell while its process still lives: must preserve original obligations.
            native.unlink(); alive=call(*finish,env=env)
            reason='启动代死亡证据缺失' if mode=='unknown-start' else '旧启动代仍活或死亡未知'
            assert alive.returncode!=0 and '候选写入者仍持cwd/FD' in alive.stderr and wt.exists() and state.exists(),(mode,alive.stderr)
            child.terminate(); child.wait()
            ended=call(*finish,env=env)
            print('PUBLIC REUSE',mode,'native_pid=',child.pid,'ended_rc=',ended.returncode,'wt=',wt.exists(),'space=',state.exists(),'stderr=',ended.stderr,flush=True)
            if mode=='unknown-start':
                assert ended.returncode!=0 and reason in ended.stderr and wt.exists() and state.exists(),ended.stderr
                assert sum(x[:2]==['agent','prompt'] for x in calls)==1,'unknown reuse must not deliver'
            else:
                assert ended.returncode==0 and not wt.exists() and not state.exists(),(mode,ended.stdout,ended.stderr)
                receipts=[x for x in ticket.read_text().splitlines() if x.startswith(('dispatch:','not-sent:'))]
                assert len(receipts)==2 and ('not-sent:' in receipts[-1])==(mode=='failed-reuse'),receipts
                # Both delivery ops retain the same validated native incarnation before their prompts.
                proofs=[]
                for _,text in [x for x in calls if x[0]=='prompt-ticket']:
                    receipt=next(x for x in reversed(text.splitlines()) if x.startswith('dispatch:'))
                    op=next(x.split('=',1)[1] for x in receipt.split() if x.startswith('op_id='))
                    bound=next(x for x in text.splitlines() if x.startswith('working: worker-activity op='+op+' pane=wTask:p1 evidence='))
                    proofs.append(json.loads(bound.split(' evidence=',1)[1]))
                assert len(proofs)==2 and all((p['pid'],p['pid_start'],p['session'])==(proofs[0]['pid'],proofs[0]['pid_start'],proofs[0]['session']) for p in proofs),proofs
                assert call('git','-C',str(repo),'show-ref','--verify','--quiet','refs/heads/case',env=env).returncode!=0
            print('PASS public run '+mode+': '+('unknown start never redelivers or closes' if mode=='unknown-start' else 'verified incarnation persists before prompt; alive preserves, proven-ended reuse finishes'))
        finally:
            if child.poll() is None: child.terminate(); child.wait()
PY
