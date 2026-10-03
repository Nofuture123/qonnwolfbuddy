#!/usr/bin/env bash
# Public role/control entrances; Herdr alone is a fixture, never a live pane.
set -euo pipefail
# Fail closed even if the PATH stub disappears.
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
export QWB_ROLES_TEST_ROOT="$ROOT"
python3 -B - <<'PY'
import hashlib, json, os, shutil, subprocess, tempfile
from pathlib import Path

root = Path(os.environ['QWB_ROLES_TEST_ROOT'])
with tempfile.TemporaryDirectory(prefix='qwb-roles-') as tmp:
    tmp = str(Path(tmp).resolve())
    p = Path(tmp) / 'project'; p.mkdir()
    (p / 'qwbuddy/.controller.lock').mkdir(parents=True)
    (p / 'qwbuddy/.controller.lock/owner').write_text('2099-01-01T00:00:00Z w1:pCtl\n')
    integration = Path(tmp) / 'herdr-agent-state.ts'; integration.write_text('// HERDR_INTEGRATION_ID=pi\n')
    (p / 'qwbuddy/config.sh').write_text("QWB_WORKERS='sol'\nQWB_WORKSPACE='w1'\nQWB_ROLE_PI_CONTROL='verified'\nQWB_ROLE_PI_INTEGRATION='"+str(integration)+"'\n")
    (p / 'qwbuddy/workers.sh').write_text('qwb_worker sol herdr pi -- --provider openai-codex --model gpt-6.1-sol --thinking high\n')
    (p / 'qwbuddy/roles').mkdir()
    (p / 'tasks').mkdir()
    for role in ('门禁', '规划', '测试体系'):
        src = root / 'templates/roles' / (role + '.md')
        (p / 'qwbuddy/roles' / (role + '.md')).write_text(src.read_text() if src.exists() else '# 门禁\n仅按主控安排工作；空闲不造票。\n')
    subprocess.run(['git', 'init', '-q', str(p)], check=True)
    subprocess.run(['git', '-C', str(p), 'add', '.'], check=True)
    subprocess.run(['git', '-C', str(p), '-c', 'user.name=Test', '-c', 'user.email=test@invalid', 'commit', '-qm', 'seed'], check=True)
    stub = Path(tmp) / 'stub'; stub.mkdir()
    state = Path(tmp) / 'herdr-state.json'; log = Path(tmp) / 'calls.jsonl'
    (stub / 'herdr').write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
a=sys.argv[1:]; path=Path(os.environ['ROLE_FAKE_STATE']); log=Path(os.environ['ROLE_FAKE_LOG'])
s=json.loads(path.read_text()) if path.exists() else {'live':False,'starts':0}
with log.open('a') as f:f.write(json.dumps(a)+'\\n')
def out(r): print(json.dumps({'result':r}))
def err(): print('io_error',file=sys.stderr); sys.exit(9)
mode=os.environ.get('ROLE_FAKE_MODE','')
if a[:2]==['workspace','list']:out({'workspaces':[{'workspace_id':'w1','worktree':{'repo_root':os.environ['ROLE_PROJECT'],'is_linked_worktree':False}}]})
elif a[:2]==['tab','create']:
 s['cwd']=a[a.index('--cwd')+1];out({'root_pane':{'pane_id':'w1:pRole','tab_id':'w1:tRole','terminal_id':'term-role','workspace_id':'w1'}})
elif a[:2]==['agent','start']:
 s.update(live=True,starts=s['starts']+1,name=a[2],argv=a[a.index('--')+1:])
 if '--session' in s['argv']:
  s['session']=s['argv'][s['argv'].index('--session')+1];s['sid']=json.loads(Path(s['session']).read_text().splitlines()[0])['id']
 else:
  sid=s['argv'][s['argv'].index('--session-id')+1]; sd=s['argv'][s['argv'].index('--session-dir')+1]
  s.update(sid=sid,session=str(Path(sd)/('2099_'+sid+'.jsonl')))
 if mode=='launch-failed':
  path.write_text(json.dumps(s));err()
 out({'type':'agent_started'})
elif a[:2]==['pane','get']:
 if mode=='query-fail':err()
 if mode=='empty-query':sys.exit(0)
 if mode=='invalid-query':print('not-json');sys.exit(0)
 if mode=='wrong-result':print(json.dumps({'result':[]}));sys.exit(0)
 ctl=a[2]=='w1:pCtl'
 pane={'pane_id':a[2],'workspace_id':'w1','tab_id':'w1:tCtl' if ctl else 'w1:tRole','terminal_id':'term-ctl' if ctl else 'term-role','foreground_cwd':os.environ['ROLE_PROJECT']}
 if ctl or s['live']:
  pane.update(agent='pi',agent_status='working' if mode=='busy' and not ctl else 'idle',agent_session={'agent':'pi','source':'herdr:pi','kind':'path','value':'ctl-session' if ctl else s['session']})
 if mode=='old-session' and not ctl:pane['agent_session']['value']=str(Path(s['session']).parent/'2099_late-old-session.jsonl')
 if mode=='foreign-terminal' and not ctl:pane['terminal_id']='term-foreign'
 out({'pane':pane})
elif a[:2]==['pane','process-info']:
 ctl=a[-1]=='w1:pCtl'
 live=ctl or (s['live'] and mode!='background')
 argv=['node','/opt/pi/dist/cli.js'] + ([] if ctl else s['argv']) if live else ['-zsh']
 pid=(999 if mode=='spoof-controller' else os.getppid()) if ctl else 100000000+s['starts'] if live else 42
 out({'process_info':{'pane_id':a[-1],'shell_pid':42,'foreground_process_group_id':pid if live else 42,'foreground_processes':[{'pid':pid,'argv0':'pi' if live else 'zsh','argv':argv,'cwd':os.environ['ROLE_PROJECT']}]}})
elif a[:2]==['pane','read']:
 print('────────────────────\\n'+('draft obligation' if mode=='draft' else '')+'\\n────────────────────\\n$0.000 (sub) 0.0%/272k (auto)  (openai-codex) '+('wrong-model' if mode=='wrong-model' else 'gpt-6.1-sol')+' • high');sys.exit(0)
elif a[:2]==['pane','send-keys']:
 if mode=='action-failed':err()
 # Actual Herdr actions succeed with no JSON payload.
elif a[:2]==['pane','run']:
 if mode=='action-failed':err()
 if a[-1]=='/quit' and mode!='exit-pending':s['live']=False
else:err()
path.write_text(json.dumps(s))
''')
    (stub / 'herdr').chmod(0o755)
    # ps is a system-boundary fixture; stable process start time binds the PID.
    (stub / 'ps').write_text('''#!/usr/bin/env python3
import json,os,subprocess,sys
from pathlib import Path
a=sys.argv[1:]
if a[-1]=='ppid=':sys.exit(subprocess.run(['/bin/ps',*a]).returncode)
pid=int(a[a.index('-p')+1]);path=Path(os.environ['ROLE_FAKE_STATE']);s=json.loads(path.read_text()) if path.exists() else {'live':False,'starts':0}
if pid>=100000000:
 if not s['live'] or pid!=100000000+s['starts']:sys.exit(1)
print('Thu Oct  1 00:00:00 2099')
''')
    (stub / 'ps').chmod(0o755)
    env = os.environ | {'PATH':str(stub)+':'+os.environ['PATH'], 'HERDR_PANE_ID':'w1:pCtl', 'HERDR_WORKSPACE_ID':'w1',
                         'ROLE_PROJECT':str(p), 'ROLE_FAKE_STATE':str(state), 'ROLE_FAKE_LOG':str(log)}
    def call(script, verb, *args, ok=True, extra=None):
        r = subprocess.run(['bash', str(root/'bin'/script), verb, '--project', str(p), *args], env=env | (extra or {}), capture_output=True, text=True)
        assert (r.returncode == 0) == ok, (verb, r.returncode, r.stdout, r.stderr)
        return json.loads(r.stdout) if ok else r
    # Config errors must stick even when a later valid declaration succeeds (Bash || disables errexit).
    workers=p/'qwbuddy/workers.sh'; original_workers=workers.read_text()
    workers.write_text('qwb_worker not-registered herdr pi -- --provider openai-codex --model gpt-6.1-sol --thinking high\n'+original_workers)
    call('qwb-role.sh','start','--actor','gate','--role','门禁','--worker','sol','--dir',str(p),ok=False)
    workers.write_text(original_workers)
    assert not state.exists(), 'invalid registry must refuse before any Herdr side effect'
    # F1: delivered first launch has no registered PID; a foreground shell can hide a live/background Pi.
    rejected=call('qwb-role.sh','start','--actor','gate','--role','门禁','--worker','sol','--dir',str(p),ok=False,extra={'ROLE_FAKE_MODE':'launch-failed'})
    assert rejected.returncode!=0 and json.loads(state.read_text())['live']
    for verb in ('exit','relaunch'):
        call('qwb-control.sh',verb,'--actor','gate','--expect-gen','0',ok=False,extra={'ROLE_FAKE_MODE':'background'})
        got=call('qwb-role.sh','status','--actor','gate',extra={'ROLE_FAKE_MODE':'background'})
        assert got['activity']=='unknown' and got['pending']['incarnation']==1 and got.get('exit')!='confirmed'
        assert got['incarnation']==0 and got['phase']=='launch-uncertain'
        assert json.loads(state.read_text())['live'] and json.loads(state.read_text())['starts']==1
    print('PASS F1 first partial/background launch: unknown+pending, no confirmed exit, no second start')
    recovered=call('qwb-role.sh','reconcile','--actor','gate','--expect-gen','0')
    assert recovered['incarnation']==1 and recovered['pid']==100000001 and json.loads(state.read_text())['starts']==1
    first = call('qwb-role.sh', 'start', '--actor', 'gate', '--role', '门禁', '--worker', 'sol', '--dir', str(p))
    second = call('qwb-role.sh', 'start', '--actor', 'gate', '--role', '门禁', '--worker', 'sol', '--dir', str(p))
    assert first['pane'] == second['pane'] == 'w1:pRole'
    assert first['incarnation'] == second['incarnation'] == 1
    assert json.loads(state.read_text())['starts'] == 1
    assert not list((p/'tasks').iterdir()), 'idle role must not manufacture tasks'
    assert not any(json.loads(x)[:2] == ['agent','prompt'] for x in log.read_text().splitlines())
    print('PASS public start: one bound instance, no work manufactured')

    # Next vertical slice: unknown/late observations never grant a replacement or advance gen.
    for mode in ('query-fail','empty-query','invalid-query','wrong-result','old-session','foreign-terminal','wrong-model'):
        got = call('qwb-role.sh','status','--actor','gate',extra={'ROLE_FAKE_MODE':mode})
        assert got['activity']=='unknown' and 'actual_model' not in got, (mode,got)
        call('qwb-control.sh','relaunch','--actor','gate','--expect-gen','1',ok=False,extra={'ROLE_FAKE_MODE':mode})
        call('qwb-role.sh','retire','--actor','gate','--expect-gen','1',ok=False,extra={'ROLE_FAKE_MODE':mode})
    for verb in ('retire','reconcile'):
        call('qwb-role.sh',verb,'--actor','gate','--expect-gen','0',ok=False)
    call('qwb-control.sh','exit','--actor','gate','--expect-gen','0',ok=False)
    assert json.loads(state.read_text())['starts']==1
    got=call('qwb-role.sh','status','--actor','gate')
    assert got['incarnation']==1 and got['activity']=='idle'
    print('PASS unknown/old generation: no replacement, no retirement, current model not fabricated')

    # Nonzero actions keep partial phases; no delivery/death is fabricated or retried.
    for verb,phase in [('interrupt','interrupt-sent'),('exit','exit-sent')]:
        offset=len(log.read_text().splitlines())
        rejected=call('qwb-control.sh',verb,'--actor','gate','--expect-gen','1',ok=False,extra={'ROLE_FAKE_MODE':'action-failed'})
        assert 'io_error' in rejected.stderr and json.loads(state.read_text())['live']
        persisted=json.loads((p/'qwbuddy/.roles/gate.json').read_text())
        assert persisted['phase']==phase and persisted['cancel']=='unconfirmed' and persisted.get('exit')!='confirmed'
        actions=[json.loads(x)[:2] for x in log.read_text().splitlines()[offset:]]
        assert sum(x in (['pane','send-keys'],['pane','run']) for x in actions)==1
    # Interrupt reports delivery only; idle/done alone is not a cancellation acknowledgment.
    got=call('qwb-control.sh','interrupt','--actor','gate','--expect-gen','1')
    assert got['cancel']=='unconfirmed' and got['phase']=='interrupt-delivered'
    for mode in ('draft','busy','exit-pending'):
        call('qwb-control.sh','exit','--actor','gate','--expect-gen','1',ok=False,extra={'ROLE_FAKE_MODE':mode})
        assert json.loads(state.read_text())['live']
    call('qwb-role.sh','retire','--actor','gate','--expect-gen','1',ok=False)
    print('PASS honest control: delivered != canceled/stopped; pending draft and busy agent preserved')

    # Same registered directory; dirty tracked/untracked files and pending instructions survive.
    tracked=p/'source'; tracked.write_text('committed source\\n')
    subprocess.run(['git','-C',str(p),'add','source'],check=True)
    subprocess.run(['git','-C',str(p),'-c','user.name=Test','-c','user.email=test@invalid','commit','-qm','source'],check=True)
    tracked.write_text('uncommitted source\\n')
    untracked=p/'private-wip'; untracked.write_bytes(b'untracked\\x00data')
    inbox=p/'qwbuddy/.roles/gate.inbox';inbox.mkdir();(inbox/'001.msg').write_text('unprocessed obligation')
    head=subprocess.check_output(['git','-C',str(p),'rev-parse','HEAD'])
    before=(tracked.read_bytes(),untracked.read_bytes(),(inbox/'001.msg').read_bytes())
    got=call('qwb-control.sh','exit','--actor','gate','--expect-gen','1')
    assert got['exit']=='confirmed' and got['activity']=='stopped' and got['cancel']=='unconfirmed'
    call('qwb-role.sh','retire','--actor','gate','--expect-gen','1',ok=False)
    got=call('qwb-control.sh','relaunch','--actor','gate','--expect-gen','1')
    assert got['incarnation']==2 and got['pane']=='w1:pRole' and got['dir']==str(p)
    assert got['actual_model']=='openai-codex/gpt-6.1-sol' and got['actual_effort']=='high'
    assert subprocess.check_output(['git','-C',str(p),'rev-parse','HEAD'])==head
    assert before==(tracked.read_bytes(),untracked.read_bytes(),(inbox/'001.msg').read_bytes())
    assert any(x['kind']=='unhandled-instruction' for x in got['obligations'])
    call('qwb-role.sh','reconcile','--actor','gate','--expect-gen','1',ok=False)
    print('PASS preservation: original pane/checkout/HEAD/WIP/inbox; old gen cannot reconcile')

    # Exact native resume when a conversation was persisted; no most-recent-session shortcut.
    session=Path(got['session_path'])
    session.write_text(json.dumps({'type':'session','version':3,'id':got['session_id'],'cwd':str(p)})+'\n')
    got=call('qwb-control.sh','exit','--actor','gate','--expect-gen','2')
    got=call('qwb-control.sh','relaunch','--actor','gate','--expect-gen','2')
    assert got['incarnation']==3 and got['session_path']==str(session)
    native=json.loads(state.read_text())
    assert native['argv'][native['argv'].index('--session')+1]==str(session)
    assert '--continue' not in native['argv'] and native['starts']==3
    print('PASS exact resume: existing session id/path survives, same native model/effort')

    # Durable01 claim/question guards via the actual ledger entry, no hand-built protocol data.
    shutil.copytree(root/'bin',p/'qwbuddy/bin')
    for name in ('QWBUDDY.md','TASK.md'):
        shutil.copyfile(root/'templates'/name,p/'qwbuddy'/name)
    shutil.copyfile(root/'templates/roles/执行者.md',p/'qwbuddy/roles/执行者.md')
    ticket=p/'tasks/2099-01-01-role-task.md'
    ticket.write_text('state: running\n## 验收场景\n### user_正常\nGiven 角色\nWhen 控制\nThen 保留现场\n### user_拒绝\nGiven 未知\nWhen 恢复\nThen 拒绝\n')
    manifest=Path(tmp)/'migration.json'
    manifest.write_text(json.dumps({'task_sha256':hashlib.sha256(ticket.read_bytes()).hexdigest(),
                                  'confirm':{k:'fixture only, stopped and reconciled' for k in ('run','wake','worktree','worker','controller','old-fds','external-actions')}}))
    def ledger(verb,*args):
        out=subprocess.run(['bash',str(root/'bin/qwb-ledger.sh'),verb,'--project',str(p),'--task',str(ticket),'--',*args],env=env,capture_output=True,text=True)
        assert out.returncode==0,(verb,out.stderr)
        return json.loads(out.stdout) if verb=='read' else out.stdout
    ledger('migrate',str(manifest));ledger('claim','roleop')
    ledger('dispatch','roleop','w1:pRole',f'dispatch: op_id=roleop worker=sol agent=qwb-role-gate pane=w1:pRole dir={p}')
    ledger('question','rolequestion','pending instruction')
    call('qwb-control.sh','exit','--actor','gate','--expect-gen','3')
    prior=ticket.read_bytes()
    for verb,script in (('retire','qwb-role.sh'),('relaunch','qwb-control.sh')):
        call(script,verb,'--actor','gate','--expect-gen','3',ok=False)
        assert ticket.read_bytes()==prior, 'control must not release or rewrite active claim'
    assert ledger('read')['claim']['op_id']=='roleop'
    ledger('release','roleop')
    call('qwb-role.sh','retire','--actor','gate','--expect-gen','3',ok=False)
    got=call('qwb-control.sh','relaunch','--actor','gate','--expect-gen','3')
    assert got['incarnation']==4 and any(x['kind']=='unresolved-question' for x in got['obligations'])
    assert ticket.read_bytes()!=prior and ledger('read')['questions']['rolequestion']['resumed']==''
    print('PASS claim/retirement: release never implicit; unhandled requests block retirement, survive recovery')

    # Partially delivered launch: retry binds actual new instance, not a second spawn.
    call('qwb-control.sh','exit','--actor','gate','--expect-gen','4')
    call('qwb-control.sh','relaunch','--actor','gate','--expect-gen','4',ok=False,extra={'ROLE_FAKE_MODE':'launch-failed'})
    got=call('qwb-role.sh','status','--actor','gate')
    assert got['incarnation']==4 and got['phase']=='launch-uncertain' and got['activity']=='unknown'
    starts=json.loads(state.read_text())['starts']
    # Old-generation PID is dead, but that does not prove the unbound replacement died.
    for verb in ('exit','relaunch'):
        call('qwb-control.sh',verb,'--actor','gate','--expect-gen','4',ok=False,extra={'ROLE_FAKE_MODE':'background'})
        partial=call('qwb-role.sh','status','--actor','gate',extra={'ROLE_FAKE_MODE':'background'})
        assert partial['incarnation']==4 and partial['pending']['incarnation']==5 and partial.get('exit')!='confirmed'
        assert partial['activity']=='unknown' and json.loads(state.read_text())['starts']==starts and json.loads(state.read_text())['live']
    print('PASS F1 replacement partial/background: dead parent PID is not candidate death proof')
    observed=call('qwb-control.sh','interrupt','--actor','gate','--expect-gen','4')
    assert observed['incarnation']==4 and observed['pending']['pid']==100000000+starts and observed['pending']['pid_start']
    call('qwb-control.sh','exit','--actor','gate','--expect-gen','4',ok=False,extra={'ROLE_FAKE_MODE':'background'})
    still=call('qwb-role.sh','status','--actor','gate',extra={'ROLE_FAKE_MODE':'background'})
    assert still['pending']['pid']==observed['pending']['pid'] and still['activity']=='unknown'
    assert json.loads(state.read_text())['live'] and json.loads(state.read_text())['starts']==starts
    print('PASS F1 observed candidate: persistent PID/start ownership, live background process still refuses exit')
    got=call('qwb-role.sh','reconcile','--actor','gate','--expect-gen','4')
    assert got['incarnation']==5 and json.loads(state.read_text())['starts']==starts
    call('qwb-control.sh','interrupt','--actor','gate','--expect-gen','5',ok=False,extra={'ROLE_FAKE_MODE':'spoof-controller'})
    assert json.loads(state.read_text())['live']
    print('PASS partial launch: reality reconciliation, single spawn; forged controller env is not authority')

    call('qwb-control.sh','exit','--actor','gate','--expect-gen','5')
    ledger('answer','rolequestion','real fixture answer');ledger('resume','rolequestion','fixture acknowledged')
    (inbox/'001.msg').unlink()
    got=call('qwb-role.sh','retire','--actor','gate','--expect-gen','5')
    assert got['phase']=='retired' and got['activity']=='stopped'
    call('qwb-role.sh','start','--actor','gate','--role','门禁','--worker','sol','--dir',str(p),ok=False)
    assert session.exists() and tracked.read_bytes()==before[0] and untracked.read_bytes()==before[1]
    print('PASS retirement: explicit only, endpoint/WIP/session retained; old actor id cannot reactivate')
PY
