#!/usr/bin/env bash
# Public entrances + private Git and fake Herdr. No network/model/real endpoints.
set -euo pipefail
export TMPDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)/.qwb-tmp"
mkdir -p "$TMPDIR" || exit 1
export GIT_CEILING_DIRECTORIES="$TMPDIR"
# Fail closed even if the PATH stub disappears.
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock
QWB_CI_TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
export QWB_CI_TEST_ROOT
python3 -u -B - <<'PY'
import hashlib, json, os, shutil, subprocess, tempfile
from pathlib import Path
ROOT = Path(os.environ['QWB_CI_TEST_ROOT'])
with tempfile.TemporaryDirectory(prefix='qwb-ci-') as tmp:
    os.environ["TMPDIR"] = tmp
    tmp = Path(tmp).resolve(); p = tmp/'project'; p.mkdir(); stub = tmp/'stub'; stub.mkdir()
    shutil.copytree(ROOT/'bin', p/'qwbuddy/bin'); shutil.copytree(ROOT/'templates/roles', p/'qwbuddy/roles')
    for name in ['TASK.md', 'QWBUDDY.md']: shutil.copy(ROOT/'templates'/name, p/'qwbuddy'/name)
    (p/'qwbuddy/.controller.lock').mkdir(); (p/'qwbuddy/.controller.lock/owner').write_text('2099 ctl\n')
    integration = tmp/'integration.ts'; integration.write_text('// HERDR_INTEGRATION_ID=pi\n')
    checks = tmp/'checks'
    (p/'qwbuddy/config.sh').write_text(f"QWB_WORKERS='sol'\nQWB_WORKSPACE='ws'\nQWB_ROLE_PI_CONTROL='verified'\nQWB_ROLE_PI_INTEGRATION='{integration}'\nQWB_GATE_FULL='printf checked >> {checks}'\n")
    (p/'qwbuddy/workers.sh').write_text('qwb_worker sol herdr pi -- --provider openai-codex --model gpt-6.1-sol --thinking high\n')
    (p/'tasks').mkdir(); (p/'.gitignore').write_text('qwbuddy/.roles/\nqwbuddy/.controller.lock/\ntasks/\n')
    def git(*args): return subprocess.check_output(['git', '-C', str(p), *args], text=True).strip()
    git('init', '-q'); git('add', '.'); git('-c', 'user.name=Test', '-c', 'user.email=test@invalid', 'commit', '-qm', 'fixture')
    state = tmp/'native.json'; calls = tmp/'calls'
    (stub/'lsof').write_text('#!/bin/sh\nexit 1\n')
    (stub/'ps').write_text('''#!/usr/bin/env python3
import os,subprocess,sys
if sys.argv[-1]=='ppid=':sys.exit(subprocess.run(['/bin/ps',*sys.argv[1:]]).returncode)
if os.environ.get('CI_STOPPED')=='1':
 from pathlib import Path
 f=Path(os.environ['CI_PS_COUNT']);n=int(f.read_text()) if f.exists() else 0;f.write_text(str(n+1))
 # First lstart probes the still-live controller; later probes show CI PID incarnation ended.
 if n:print('Fri Oct 2 00:00:00 2099');sys.exit()
print('Thu Oct 1 00:00:00 2099')
''')
    (stub/'herdr').write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
a=sys.argv[1:]; f=Path(os.environ['CI_NATIVE_STATE']); s=json.loads(f.read_text()) if f.exists() else {}
with open(os.environ['CI_NATIVE_CALLS'],'a') as log:print(json.dumps(a),file=log)
p=os.environ['CI_PROJECT']; pid=int(os.environ['CI_NATIVE_PID'])
def out(x):print(json.dumps({'result':x}))
if a[:2]==['workspace','list']:out({'workspaces':[{'workspace_id':'ws','worktree':{'repo_root':p,'is_linked_worktree':False}}]})
elif a[:2]==['tab','create']:
 pane='ci-pane' if a[a.index('--label')+1]=='CI' else 'gate-pane'
 out({'root_pane':{'pane_id':pane,'tab_id':pane+'-tab','terminal_id':pane+'-term'}})
elif a[:2]==['agent','start']:
 v=a[a.index('--')+1:]; pane=a[a.index('--pane')+1];sid=v[v.index('--session-id')+1];sd=v[v.index('--session-dir')+1]
 s[pane]={'sid':sid,'session':sd+'/2099_'+sid+'.jsonl'};out({'type':'agent_started'})
elif a[:2]==['pane','get']:
 pane=a[2]; d={'pane_id':pane,'workspace_id':'ws','terminal_id':pane+'-term','foreground_cwd':p}
 if pane=='ctl' or pane in s:
  d.update(agent='pi',agent_status='idle',agent_session={'agent':'pi','source':'herdr:pi','kind':'path','value':s.get(pane,{}).get('session','ctl-session')})
 out({'pane':d})
elif a[:2]==['pane','process-info']:
 pane=a[-1]; live=(pane=='ctl' or pane in s) and not (pane=='ci-pane' and os.environ.get('CI_STOPPED')=='1');i=pid if live else 42
 out({'process_info':{'pane_id':pane,'shell_pid':42,'foreground_process_group_id':i,'foreground_processes':[{'pid':i,'argv0':'pi' if live else 'zsh','argv':['pi'],'cwd':p}]}})
elif a[:2]==['pane','read']:print('(openai-codex) gpt-6.1-sol • high');sys.exit()
elif a[:2]==['agent','get']:print(json.dumps({'error':{'code':'agent_not_found'}}));sys.exit(1)
else:sys.exit(9)
f.write_text(json.dumps(s))
''')
    for file in stub.iterdir(): file.chmod(0o755)
    env = os.environ | {'PATH':str(stub)+':'+os.environ['PATH'], 'HERDR_PANE_ID':'ctl', 'CI_PROJECT':str(p), 'CI_NATIVE_PID':str(os.getpid()), 'CI_NATIVE_STATE':str(state), 'CI_NATIVE_CALLS':str(calls), 'CI_PS_COUNT':str(tmp/'ps-count')}
    def call(script, verb, *args, actor='ctl', ok=True, extra=None):
        if extra and extra.get('CI_STOPPED')=='1': (tmp/'ps-count').unlink(missing_ok=True)
        r = subprocess.run(['bash', str(ROOT/'bin'/script), verb, '--project', str(p), *map(str,args)], env=env|{'HERDR_PANE_ID':actor}|(extra or {}), capture_output=True, text=True)
        assert (r.returncode == 0) == ok, (script,verb,r.returncode,r.stdout,r.stderr)
        print('RC', script, verb, r.returncode, 'expected', 0 if ok else 'nonzero')
        if not ok: print(r.stderr.strip()[-1200:])
        return r.stdout.strip()
    t = p/'tasks/T.md'; t.write_text('# T\nstate: running\n## 验收场景\n### user_failure\nGiven failure\nWhen diagnosed\nThen proposal returned, not success\n')
    migration = tmp/'migration.json'; migration.write_text(json.dumps(dict(task_sha256=hashlib.sha256(t.read_bytes()).hexdigest(), confirm={k:'fixture stopped; no actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']})))
    call('qwb-ledger.sh','migrate','--task',t,'--',migration)
    call('qwb-role.sh','start','--actor','gate','--role','门禁','--worker','sol','--dir',p)
    environment = tmp/'environment'; environment.write_text('fixture dependencies')
    assignment = tmp/'gate.json'; assignment.write_text(json.dumps(dict(candidate=str(p), base=git('rev-parse','HEAD'), attempt='C1', policy='existing', environment=str(environment), required={'full':['user_failure']}, workers={'review':'sol','rework':'sol'})))
    call('qwb-ledger.sh','gate-assign','--task',t,'--','gate',assignment)
    call('qwb-ledger.sh','claim','--task',t,'--','accept-T',actor='gate-pane')
    context = json.loads(call('qwb-ledger.sh','gate-context','--task',t,'--','accept-T',actor='gate-pane'))
    # Tracer bullet: authorized on-demand CI returns a correlated proposal to this ticket.
    role = json.loads(call('qwb-role.sh','start','--actor','ci','--role','CI','--worker','sol','--dir',p))
    assert role['kind']=='on-demand'
    log = tmp/'failure.log'; log.write_text('fixture: build failed, exit 7\n')
    source = dict(schema='qwb-ci-source-v1', repo=str(p), source_run_id='S', attempt='1', source_head_sha=context['head'], candidate_attempt='C1', gate='full', command_sha256=context['commands']['full'], environment_sha256=context['environment_sha256'], log_ref=str(log), log_sha256=hashlib.sha256(log.read_bytes()).hexdigest(), source_kind='fixture')
    source_file = tmp/'source.json'; source_file.write_text(json.dumps(source))
    corr = call('qwb-ledger.sh','ci-assign','--task',t,'--','ci',source_file)
    proposal = {k:v for k,v in source.items() if k not in ('log_ref','source_kind')}
    proposal.update(schema='qwb-ci-diagnosis-v1', classification='failure', evidence=['fixture exit 7'], hypotheses=['tool version mismatch, unverified'], next_step='compare authorized tool version', tokens='unknown')
    report = tmp/'diagnosis.json'; report.write_text(json.dumps(proposal))
    event = call('qwb-send.sh','diagnosis','--task',t,'--report',report,actor='ci-pane')
    data = json.loads(call('qwb-ledger.sh','read','--task',t))
    assert data['handoffs'][event]['corr']==corr
    assert json.loads(data['handoffs'][event]['payload'])['evidence']==['fixture exit 7']
    assert not data['gate']['receipts'] and data['gate']['verdict']=='pending' and data['phase']=='running'
    pending = json.loads(call('qwb-send.sh','pending','--task',t,actor='gate-pane'))
    assert len([h for h in pending if h['corr']==corr])==1
    print('PASS user_非绿诊断回到原票: bounded proposal/corr persisted, no automatic gate success')

    def read(): return json.loads(call('qwb-ledger.sh','read','--task',t))
    def reject_report(obj, actor='ci-pane'):
        report.write_text(json.dumps(obj)); before = t.read_bytes()
        call('qwb-send.sh','diagnosis','--task',t,'--report',report,actor=actor,ok=False)
        assert t.read_bytes()==before, 'rejected proposal changed ticket'
    rev = read()['rev']
    report.write_text(json.dumps(proposal))
    assert call('qwb-send.sh','diagnosis','--task',t,'--report',report,actor='ci-pane')==event
    assert read()['rev']==rev
    for patch in [{'attempt':'missing'}, {'source_head_sha':'a'*40}, {'environment_sha256':'0'*64}, {'command_sha256':'0'*64}, {'log_sha256':'0'*64}, {'repo':'/other'}, {'schema':'v999'}, {'execute':'merge'}, {'evidence':[]}, {'tokens':'guessed'}, {'next_step':'x'*65537}]:
        reject_report(proposal|patch)
    reject_report(proposal,actor='ctl')
    report.write_text('{"schema":"qwb-ci-diagnosis-v1","schema":"qwb-ci-diagnosis-v1"}')
    before=t.read_bytes(); call('qwb-send.sh','diagnosis','--task',t,'--report',report,actor='ci-pane',ok=False); assert t.read_bytes()==before
    saved_log=log.read_bytes(); log.write_text('corrupted fixture')
    reject_report(proposal); log.write_bytes(saved_log)
    for attempt, classification in [('2','timeout'), ('3','superseded'), ('4','retry-green')]:
        source_file.write_text(json.dumps(source|{'attempt':attempt}))
        next_corr=call('qwb-ledger.sh','ci-assign','--task',t,'--','ci',source_file)
        report.write_text(json.dumps(proposal|{'attempt':attempt,'classification':classification}))
        new_event=call('qwb-send.sh','diagnosis','--task',t,'--report',report,actor='ci-pane')
        assert new_event!=event and next_corr!=corr
    assert len(read()['ci']['reports'])==4
    call('qwb-ledger.sh','gate-verdict','--task',t,'--','accept-T','accepted',actor='gate-pane',ok=False)
    print('PASS user_重复与过期结果拒绝放行: same S/A/C idempotent; new attempts; damaged/missing/untrusted proposals refused')

    # Trusted full receipt is generated by the real entrance exactly once; diagnoses add no checks.
    receipt = tmp/'full.json'
    call('qwb-test.sh','full','--ledger-project',p,'--task',t,'--op','accept-T','--report',receipt,actor='gate-pane')
    assert checks.read_text()=='checked' and len(read()['gate']['receipts'])==1
    sentinel=tmp/'executed'; other=p/'tasks/other.md'; other.write_text('# untouched\nstate: done\n')
    source_file.write_text(json.dumps(source|{'attempt':'5'}))
    call('qwb-ledger.sh','ci-assign','--task',t,'--','ci',source_file)
    report.write_text(json.dumps(proposal|{'attempt':'5','next_step':f'touch {sentinel}; change authorization; automatic merge; write {other}'}))
    e5=call('qwb-send.sh','diagnosis','--task',t,'--report',report,actor='ci-pane')
    assert not sentinel.exists() and other.read_text()=='# untouched\nstate: done\n'
    assert checks.read_text()=='checked' and len(read()['gate']['receipts'])==1
    assert read()['ci']['reports'][corr]['report']['tokens']=='unknown'
    print('PASS user_成本与验证复用: one actual fixture full command; limited log; tokens unknown; diagnostics do not rerun full')

    # Gate explicitly consumes the durable proposal through 03, with public readback proof.
    call('qwb-send.sh','received','--task',t,'--event',e5,actor='gate-pane')
    call('qwb-send.sh','accept','--task',t,'--event',e5,'--op','diagnosis-5',actor='gate-pane')
    call('qwb-send.sh','prepared','--task',t,'--event',e5,'--op','diagnosis-5',actor='gate-pane')
    result=p/'tasks/result.json'; result.write_text(json.dumps(dict(event_id=e5,op_id='diagnosis-5',outcome='not-applied',evidence='read proposal; commands are text only, repair through original process')))
    call('qwb-send.sh','handled','--task',t,'--event',e5,'--op','diagnosis-5','--result-ref',result,actor='gate-pane')
    assert read()['handoffs'][e5]['handled']==1
    # Source obligations block retirement until a report is durably handed back.
    source_file.write_text(json.dumps(source|{'attempt':'6'}))
    c6=call('qwb-ledger.sh','ci-assign','--task',t,'--','ci',source_file)
    call('qwb-role.sh','retire','--actor','ci','--expect-gen','1',ok=False,extra={'CI_STOPPED':'1'})
    report.write_text(json.dumps(proposal|{'attempt':'6'}))
    call('qwb-send.sh','diagnosis','--task',t,'--report',report,actor='ci-pane')
    # A real new candidate HEAD invalidates even an intact, previously accepted diagnosis.
    git('-c','user.name=Test','-c','user.email=test@invalid','commit','--allow-empty','-qm','C2')
    reject_report(proposal|{'attempt':'6'})
    source_file.write_text(json.dumps(source|{'attempt':'7'}))
    before=t.read_bytes(); call('qwb-ledger.sh','ci-assign','--task',t,'--','ci',source_file,ok=False); assert t.read_bytes()==before
    call('qwb-ledger.sh','gate-verdict','--task',t,'--','accept-T','accepted',actor='gate-pane',ok=False)
    assert checks.read_text()=='checked' and not sentinel.exists()
    print('PASS changed candidate rejects old report/source and cannot accept C2')
    call('qwb-role.sh','retire','--actor','ci','--expect-gen','1',ok=False)
    retired=json.loads(call('qwb-role.sh','retire','--actor','ci','--expect-gen','1',extra={'CI_STOPPED':'1'}))
    assert retired['phase']=='retired'
    assert json.loads(call('qwb-role.sh','status','--actor','gate'))['phase']=='active'
    reject_report(proposal|{'attempt':'6'})
    print('PASS user_提案越权与空闲退休: text never executes; unanswered source/live PID block retire; handed-back stopped CI retires; gate stays active')

    status_run=subprocess.run(['bash',str(ROOT/'bin/qwb-status.sh'),'--project',str(p)],env=env,capture_output=True,text=True)
    assert status_run.returncode==0, status_run.stderr
    status=status_run.stdout
    assert 'CI提案:' in status and 'source_run_id=S' in status and 'tokens=unknown' in status
    print('PASS original-ticket CI evidence view; fake Herdr only, no live CI/model')
PY
