#!/usr/bin/env bash
# Public ledger/test/send/wake entries; private Git + fake Herdr only.
set -euo pipefail
QWB_POLICY_TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
export QWB_POLICY_TEST_ROOT
python3 -B - <<'PY'
import hashlib, json, os, shutil, subprocess, tempfile
from pathlib import Path
ROOT=Path(os.environ['QWB_POLICY_TEST_ROOT'])
with tempfile.TemporaryDirectory(prefix='qwb-policy-') as temp:
    tmp=Path(temp).resolve(); p=tmp/'project'; p.mkdir(); stub=tmp/'stub'; stub.mkdir()
    shutil.copytree(ROOT/'bin',p/'qwbuddy/bin'); shutil.copytree(ROOT/'templates/roles',p/'qwbuddy/roles')
    for name in ['TASK.md','QWBUDDY.md']: shutil.copy(ROOT/'templates'/name,p/'qwbuddy'/name)
    (p/'qwbuddy/.controller.lock').mkdir(); (p/'qwbuddy/.controller.lock/owner').write_text('2099 ctl\n')
    integration=tmp/'integration.ts'; integration.write_text('// HERDR_INTEGRATION_ID=pi\n')
    counter=tmp/'runs'; environment=tmp/'environment'; environment.write_text('dependency v1\n')
    (p/'qwbuddy/config.sh').write_text(f"QWB_WORKERS='sol reviewer'\nQWB_WORKSPACE='ws'\nQWB_ROLE_PI_CONTROL='verified'\nQWB_ROLE_PI_INTEGRATION='{integration}'\nQWB_GATE_FAST='true'\nQWB_GATE_FULL='echo run >> {counter}'\n")
    (p/'qwbuddy/workers.sh').write_text('qwb_worker sol herdr pi -- --provider openai-codex --model gpt-6.1-sol --thinking high\nqwb_worker reviewer herdr pi -- --provider anthropic --model claude-opus-4-6 --thinking low\n')
    (p/'tasks').mkdir(); (p/'.gitignore').write_text('qwbuddy/.roles/\nqwbuddy/.controller.lock/\nqwbuddy/.supervisor.guard\nqwbuddy/.watch*\ntasks/\nresult.json\n')
    def git(*args): return subprocess.check_output(['git','-C',str(p),*args],text=True).strip()
    def commit():
        git('add','.'); git('-c','user.name=Test','-c','user.email=test@invalid','commit','-qm','fixture')
    git('init','-q'); commit()
    native=tmp/'native.json'; log=tmp/'calls.jsonl'
    (stub/'lsof').write_text('#!/bin/sh\nexit 1\n')
    (stub/'ps').write_text("#!/usr/bin/env python3\nimport subprocess,sys\nif sys.argv[-1]=='ppid=':sys.exit(subprocess.run(['/bin/ps',*sys.argv[1:]]).returncode)\nprint('Thu Oct 1 00:00:00 2099')\n")
    (stub/'herdr').write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
a=sys.argv[1:];f=Path(os.environ['POLICY_NATIVE']);s=json.loads(f.read_text()) if f.exists() else {};p=os.environ['POLICY_PROJECT'];pid=int(os.environ['POLICY_PID'])
with open(os.environ['POLICY_LOG'],'a') as out:print(json.dumps(a),file=out)
def out(x):print(json.dumps({'result':x}))
if a[:2]==['workspace','list']:out({'workspaces':[{'workspace_id':'ws','worktree':{'repo_root':p,'is_linked_worktree':False}}]})
elif a[:2]==['tab','create']:
 role=a[a.index('--label')+1];pane='test-pane' if role=='测试体系' else 'gate-pane';s['creating']=pane;out({'root_pane':{'pane_id':pane,'tab_id':pane+'-tab','terminal_id':pane+'-term'}})
elif a[:2]==['agent','get']:print(json.dumps({'error':{'code':'agent_not_found'}}));sys.exit(1)
elif a[:2]==['agent','start']:
 v=a[a.index('--')+1:];sid=v[v.index('--session-id')+1];sd=v[v.index('--session-dir')+1];s[s['creating']]=sd+'/2099_'+sid+'.jsonl';out({'type':'agent_started'})
elif a[:2]==['pane','get']:
 pane=a[2];d={'pane_id':pane,'workspace_id':'ws','terminal_id':pane+'-term','foreground_cwd':p}
 if pane=='ctl' or pane in s:d.update(agent='pi',agent_status='idle',agent_session={'agent':'pi','source':'herdr:pi','kind':'path','value':s.get(pane,'ctl-session')})
 out({'pane':d})
elif a[:2]==['pane','process-info']:
 pane=a[-1];live=pane=='ctl' or pane in s;i=pid if live else 42;out({'process_info':{'pane_id':pane,'shell_pid':42,'foreground_process_group_id':i,'foreground_processes':[{'pid':i,'argv0':'pi' if live else 'zsh','argv':['pi'],'cwd':p}]}})
elif a[:2]==['pane','read']:print('(openai-codex) gpt-6.1-sol • high');sys.exit()
elif a[:2] in (['pane','run'],['tab','close']):out({'type':'input_sent'})
else:sys.exit(9)
f.write_text(json.dumps(s))
''')
    for f in stub.iterdir(): f.chmod(0o755)
    env=os.environ|{'PATH':str(stub)+':'+os.environ['PATH'],'HERDR_PANE_ID':'ctl','POLICY_NATIVE':str(native),'POLICY_LOG':str(log),'POLICY_PROJECT':str(p),'POLICY_PID':str(os.getpid())}
    def call(script,verb,*args,actor='ctl',ok=True,extra=None):
        argv=['bash',str(ROOT/'bin'/script),verb,*map(str,args)] if script=='qwb-init.sh' else ['bash',str(ROOT/'bin'/script),verb,'--project',str(p),*map(str,args)]
        r=subprocess.run(argv,env=env|{'HERDR_PANE_ID':actor}|(extra or {}),capture_output=True,text=True,timeout=120)
        assert (r.returncode==0)==ok,(script,verb,r.returncode,r.stdout,r.stderr)
        return r
    call('qwb-role.sh','start','--actor','gate','--role','门禁','--worker','sol','--dir',p)
    call('qwb-role.sh','start','--actor','steward','--role','测试体系','--worker','sol','--dir',p)
    frozen='## 验收场景\n### user_good\nGiven project\nWhen check\nThen success\n### user_failure\nGiven bad\nWhen rejected\nThen failure'
    ticket=p/'tasks/case.md'; ticket.write_text('# Test policy\nstate: running\ntest-policy: qwb-v1\nrisk: high\n'+frozen+'\n')
    manifest=tmp/'migration.json'; manifest.write_text(json.dumps({'task_sha256':hashlib.sha256(ticket.read_bytes()).hexdigest(),'confirm':{key:'fixture stopped' for key in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
    call('qwb-ledger.sh','migrate','--task',ticket,'--',manifest)
    policy=p/'qwbuddy/test-policy/qwb-v1.md'; policy.parent.mkdir(); shutil.copy(ROOT/'templates/test-policy/qwb-v1.md',policy); commit()
    assignment=tmp/'assignment.json'; assignment.write_text(json.dumps({'candidate':str(p),'base':git('rev-parse','HEAD'),'attempt':'1','policy':'qwb-v1','environment':str(environment),'required':{'full':['user_good','user_failure']},'workers':{'review':'reviewer','rework':'sol'}}))
    call('qwb-ledger.sh','gate-assign','--task',ticket,'--','gate',assignment)
    call('qwb-ledger.sh','claim','--task',ticket,'--','accept',actor='gate-pane')
    def ledger(verb,*args,actor='gate-pane',ok=True):return call('qwb-ledger.sh',verb,'--task',ticket,'--',*args,actor=actor,ok=ok)
    def read():return json.loads(ledger('read').stdout)
    def check(name,**options):return call('qwb-test.sh','full','--task',ticket,'--ledger-project',p,'--op','accept','--report',tmp/name,actor='gate-pane',**options)
    # RED: a covered high-risk ticket must reuse a valid receipt without another command or test signature.
    check('first.json'); check('reuse.json')
    assert counter.read_text().splitlines()==['run'], 'matching receipt caused duplicate full'
    assert len(read()['gate']['receipts'])==1 and read()['gate']['verdict']=='pending'
    assert not read().get('test_requests'), 'covered high risk ticket requested extra test approval'
    reused=json.loads((tmp/'reuse.json').read_text())
    assert reused['schema']=='qwb-reused-receipt-v1' and reused['sha256']==read()['gate']['receipts'][0]['sha256']
    print('PASS user_策略覆盖不加关卡: exact receipt reused, gate remains sole assessor')
    # A genuine gap requests the registered steward once, through original-ticket handoff receipts.
    ledger('test-request','accept','new-path','steward','new-behavior','user_failure')
    first=read(); ledger('test-request','accept','new-path','steward','new-behavior','user_failure')
    assert read()==first, 'request replay created another event'
    request=first['test_requests']['new-path']
    waiting=ledger('gate-verdict','accept','accepted',ok=False)
    assert '测试补充尚未回复' in waiting.stderr
    role=json.loads(call('qwb-role.sh','status','--actor','steward').stdout)
    assert any(item['kind']=='test-request' for item in role['obligations']), 'pending consultation not protected on retirement/recovery'
    pending=json.loads(call('qwb-send.sh','pending','--task',ticket).stdout)
    source=next(h for h in pending if h['source_event']==request['event_id'])['event_id']
    log.write_text(''); call('qwb-wake.sh','--once','--pane','ctl')
    deliveries=[json.loads(line) for line in log.read_text().splitlines() if json.loads(line)[:2]==['pane','run']]
    assert any(a[2]=='test-pane' for a in deliveries), deliveries
    test_delivery=next(a for a in deliveries if a[2]=='test-pane')
    assert source in test_delivery[3] and '接班核查迁入前正文' not in test_delivery[3], test_delivery
    def send(verb,*args,actor='test-pane',ok=True):return call('qwb-send.sh',verb,'--task',ticket,'--event',source,*args,actor=actor,ok=ok)
    send('received'); send('accept','--op','consult'); send('prepared','--op','consult')
    current=json.loads(ledger('gate-context','accept').stdout)
    assert current==request['context'], {key:(request['context'].get(key),value) for key,value in current.items() if request['context'].get(key)!=value}
    reply=tmp/'reply.json'; reply.write_text(json.dumps({'task':str(ticket),'request_id':'new-path','context':request['context'],'validation':['拒绝无授权调用，持久读回原票不变'],'tests':['授权作者补一条公开入口失败检查']}))
    ledger('test-reply','new-path',reply,actor='test-pane')
    after=read();ledger('test-reply','new-path',reply,actor='test-pane');assert read()==after
    assert after['gate']['verdict']=='pending' and after['test_requests']['new-path']['reply']['validation']
    result=p/'result.json'; result.write_text(json.dumps({'event_id':source,'op_id':'consult','outcome':'applied','evidence':'reply read back from original ticket'}))
    send('handled','--op','consult','--result-ref',result)
    ledger('test-request','accept','second','steward','policy-gap','user_failure',ok=False)
    print('PASS user_新行为请求一次有效补充: linked request/reply and original 03 receipts, no author self-proof')
    # Old receipt changes are exercised through public writer/runner, not source-text grep.
    old=tmp/'first.json'; original=ticket.read_bytes()
    for content in [original.replace(b'risk: high',b'risk: normal'), original.replace(b'test-policy: qwb-v1',b'test-policy: qwb-v2'), original.replace(b'Then failure',b'Then different failure')]:
        ticket.write_bytes(content); snapshot=ticket.read_bytes()
        ledger('gate-receipt','accept',old,ok=False); ledger('gate-verdict','accept','accepted',ok=False)
        assert ticket.read_bytes()==snapshot
        ticket.write_bytes(original)
    policy_bytes=policy.read_bytes(); policy.write_bytes(policy_bytes+b'\nChanged policy\n')
    ledger('gate-reuse','accept','full',ok=False); ledger('gate-receipt','accept',old,ok=False)
    policy.write_bytes(policy_bytes)
    environment.write_text('dependency v2\n'); ledger('gate-reuse','accept','full',ok=False)
    check('env-v2.json'); assert counter.read_text().splitlines()==['run','run']
    ledger('gate-receipt','accept',old,ok=False)
    # Selected runtime variable changes invalidate just this candidate-bound receipt.
    call('qwb-ledger.sh','gate-reuse','--task',ticket,'--','accept','full',actor='gate-pane',ok=False,extra={'NODE_ENV':'changed'})
    config=p/'qwbuddy/config.sh'; config_bytes=config.read_bytes()
    config.write_bytes(config_bytes+b"QWB_GATE_FULL='exit 7'\n")
    ledger('gate-reuse','accept','full',ok=False); check('dirty-command.json',ok=False)
    config.write_bytes(config_bytes)
    # An in-memory receipt mutation is never mistaken for a matching executed receipt.
    for key,value in [('tree','0'*40),('head','0'*40),('config_sha256','0'*64),('environment_sha256','0'*64),('test_policy_sha256','0'*64)]:
        forged=json.loads(old.read_text());forged['before'][key]=value;forged['after'][key]=value
        file=tmp/'forged.json';file.write_text(json.dumps(forged));ledger('gate-receipt','accept',file,ok=False)
    ledger('test-reply','new-path',reply,actor='gate-pane',ok=False)
    print('PASS user_旧证据与删风险绕门拒绝: risk/spec/scene/policy/object/config/environment changes rejected; full retained')
    # Empty roles do not invent a task, command or model call.
    idle=tmp/'saved-ticket'; ticket.rename(idle); log.write_text('')
    idle_role=json.loads(call('qwb-role.sh','status','--actor','steward').stdout); assert idle_role['obligations']==[]
    call('qwb-wake.sh','--once','--pane','ctl')
    calls=[json.loads(line) for line in log.read_text().splitlines()]
    assert not any(a[:2] in (['pane','run'],['agent','start'],['agent','prompt']) for a in calls)
    idle.rename(ticket)
    assert counter.read_text().splitlines()==['run','run']
    print('PASS user_空闲与技术重诊: idle silent; three-round diagnosis is also exercised by collab-gate.sh')
    # An ordinary covered ticket actually reaches accepted with one full and no steward consultation.
    high_ticket=ticket; ticket=p/'tasks/normal.md'
    ticket.write_text('# Normal covered ticket\nstate: running\ntest-policy: qwb-v1\nrisk: normal\n'+frozen+'\n')
    manifest.write_text(json.dumps({'task_sha256':hashlib.sha256(ticket.read_bytes()).hexdigest(),'confirm':{key:'fixture stopped' for key in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
    call('qwb-ledger.sh','migrate','--task',ticket,'--',manifest)
    call('qwb-ledger.sh','gate-assign','--task',ticket,'--','gate',assignment)
    ledger('claim','accept');check('normal-full.json');check('normal-reuse.json')
    context=json.loads(ledger('gate-context','accept').stdout)
    def session(name,provider,model,effort,family):
        path=tmp/(name+'.jsonl')
        path.write_text('\n'.join(json.dumps(row) for row in [{'type':'session','id':name,'cwd':str(p)},{'type':'model_change','provider':provider,'modelId':model},{'type':'thinking_level_change','thinkingLevel':effort}])+'\n')
        return {'model':model,'family':family,'session':name,'evidence':str(path)}
    review=tmp/'normal-review.json'; review.write_text(json.dumps({'context':context,'implementer':session('impl','openai-codex','gpt-6.1-sol','high','gpt'),'reviewer':session('review','anthropic','claude-opus-4-6','low','claude'),'standards':'pass','spec':'pass','covered':['user_good','user_failure'],'findings':[]}))
    ledger('gate-review','accept',review);ledger('gate-verdict','accept','accepted')
    assert read()['gate']['verdict']=='accepted' and not read().get('test_requests')
    assert counter.read_text().splitlines()==['run','run','run']
    ticket=high_ticket
    print('PASS covered normal ticket: gate accepted, one full reused, zero test signature')
    # Install immutable policy versions once; upgrades preserve project-owned versions/config.
    installed=tmp/'installed'; installed.mkdir()
    call('qwb-init.sh',str(installed))
    version=installed/'qwbuddy/test-policy/qwb-v1.md'
    assert version.read_bytes()==(ROOT/'templates/test-policy/qwb-v1.md').read_bytes()
    version.write_text(version.read_text()+'\nProject-owned revision history\n'); saved=version.read_bytes()
    installed_config=installed/'qwbuddy/config.sh'; config_saved=installed_config.read_bytes()
    call('qwb-init.sh',str(installed)); assert version.read_bytes()==saved and installed_config.read_bytes()==config_saved
    version.unlink(); version.symlink_to(policy)
    call('qwb-init.sh',str(installed),ok=False); assert version.is_symlink()
    print('PASS minimal policy installation: preserve prior version/config and fail closed on symlink')
    evidence=os.environ.get('QWB_POLICY_EVIDENCE_DIR')
    if evidence:
        dest=Path(evidence).resolve();dest.mkdir(parents=True,exist_ok=False)
        for file in tmp.iterdir():
            if file.is_file() and file.suffix in ('.json','.jsonl'):shutil.copy(file,dest/file.name)
        (dest/'ledger.json').write_text(ledger('read').stdout)
        (dest/'README.md').write_text('Private Git + fakeHerdr fixture evidence; not live native model/session validation. No real Herdr lifecycle driven.\n')
        print('fixture evidence: '+str(dest))
PY
