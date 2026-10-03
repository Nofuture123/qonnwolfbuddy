#!/usr/bin/env bash
# Public CLI behavior; private Git, only external Herdr boundary is fake.
set -euo pipefail
# Fail closed even if the PATH stub disappears.
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
export QWB_POSTURE_ROOT="$ROOT"
python3 -B - <<'PY'
import fcntl, hashlib, json, os, subprocess, tempfile, time
from pathlib import Path
ROOT=Path(os.environ['QWB_POSTURE_ROOT'])
with tempfile.TemporaryDirectory(prefix='qwb-posture-') as tmp:
    tmp=Path(tmp).resolve()
    p=tmp/'project'; p.mkdir()
    env=os.environ|{'HERDR_PANE_ID':'ctl'}
    def run(argv, ok=True, extra=None):
        r=subprocess.run(list(map(str,argv)),env=env|(extra or {}),capture_output=True,text=True)
        print('RC='+str(r.returncode)+' '+ ' '.join(map(str,argv[:3])),flush=True)
        if not ok: print('REFUSAL '+r.stderr.strip(),flush=True)
        assert (r.returncode==0)==ok,(r.returncode,r.stdout,r.stderr)
        return r
    run(['git','-C',p,'init','-qb','main'])
    run(['bash',ROOT/'bin/qwb-init.sh',p])
    (p/'qwbuddy/.controller.lock').mkdir()
    (p/'qwbuddy/.controller.lock/owner').write_text('fixture ctl\n')
    def mode(action,*args,ok=True):
        return run(['bash',p/'qwbuddy/bin/qwb-role.sh','mode',action,'--project',p,'--',*args],ok).stdout
    assert json.loads(mode('status'))['mode']=='online'
    r=run(['bash',p/'qwbuddy/bin/qwb-role.sh','mode','enter','--project',p,'--','away','auth-original','伪造工人模式','无授权'],False,{'HERDR_PANE_ID':'unbound-worker'})
    assert '仅现有主控' in r.stderr and not (p/'qwbuddy/.posture.md').exists()
    words='我去睡觉，不发钉钉。\n原授权继续。\n\n'
    mode('enter','away','auth-original',words,'不新增合并/采购/人类推送')
    d=json.loads(mode('status'))
    assert d['mode']=='away' and d['events'][-1]['words']==words
    assert d['events'][-1]['auth_ref']=='auth-original' and d['events'][-1]['at']
    before=(p/'qwbuddy/.posture.md').read_bytes()
    run(['bash',ROOT/'bin/qwb-init.sh',p])
    assert (p/'qwbuddy/.posture.md').read_bytes()==before
    assert json.loads(mode('status'))==d
    print('PASS install → enter → persistent exact words/auth/time → reinstall preserves')
    mode('exit','system','门铃不是返回',ok=False)
    assert (p/'qwbuddy/.posture.md').read_bytes()==before
    mode('exit','user','我回来了\n')
    d=json.loads(mode('status')); assert d['mode']=='online' and d['events'][-1]['words']=='我回来了\n'
    mode('enter','quiet','auth-original','静音但我仍在','零推送')
    mode('exit','user','新的需求，不取消静音')
    assert json.loads(mode('status'))['mode']=='quiet'
    mode('exit','system','后台事件',ok=False)
    mode('exit','explicit','取消静音')
    assert json.loads(mode('status'))['mode']=='online'
    print('PASS system cannot return; away user return; quiet only explicit exit; history retained')

    # Real public 02/04/05 authorization fixture; fake only the external Herdr boundary.
    stub=Path(tmp)/'stub'; stub.mkdir()
    native=Path(tmp)/'native.json'; log=Path(tmp)/'native.log'
    (stub/'herdr').write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
a=sys.argv[1:]; f=Path(os.environ['POSTURE_NATIVE']); s=json.loads(f.read_text()) if f.exists() else {}
with open(os.environ['POSTURE_LOG'],'a') as out:print(json.dumps(a),file=out)
p=os.environ['POSTURE_PROJECT']; pid=int(os.environ['POSTURE_PID'])
def out(x):print(json.dumps({'result':x}))
if a[:2]==['workspace','list']:out({'workspaces':[{'workspace_id':'ws','worktree':{'repo_root':p,'is_linked_worktree':False}}]})
elif a[:2]==['tab','create']:out({'root_pane':{'pane_id':'gate-pane','tab_id':'gate-tab','terminal_id':'gate-terminal'}})
elif a[:2]==['agent','get']:print(json.dumps({'error':{'code':'agent_not_found'}}));sys.exit(1)
elif a[:2]==['agent','start']:
 v=a[a.index('--')+1:];s={'session':v[v.index('--session-dir')+1]+'/2099_'+v[v.index('--session-id')+1]+'.jsonl'};out({'type':'agent_started'})
elif a[:2]==['pane','get']:
 d={'pane_id':a[2],'workspace_id':'ws','terminal_id':'gate-terminal','foreground_cwd':p}
 if a[2]!='gate-pane' or 'session' in s:d.update(agent='pi',agent_status='idle',agent_session={'agent':'pi','source':'herdr:pi','kind':'path','value':s.get('session','ctl-session')})
 out({'pane':d})
elif a[:2]==['pane','process-info']:
 live=a[-1]!='gate-pane' or 'session' in s;i=pid if live else 42
 out({'process_info':{'pane_id':a[-1],'shell_pid':42,'foreground_process_group_id':i,'foreground_processes':[{'pid':i,'argv0':'pi' if live else 'zsh','argv':['pi'],'cwd':p}]}})
elif a[:2]==['pane','read']:print('(openai-codex) gpt-6.1-sol • high');sys.exit()
elif a[:2]==['pane','run']:out({'type':'input_sent'})
else:sys.exit(9)
f.write_text(json.dumps(s))
''')
    (stub/'lsof').write_text('#!/bin/sh\nif [ "$1" = "-Ffa" ]; then exit 1; fi\nexit 9\n')
    for f in stub.iterdir(): f.chmod(0o755)
    env.update(PATH=str(stub)+':'+os.environ['PATH'],POSTURE_NATIVE=str(native),POSTURE_LOG=str(log),POSTURE_PROJECT=str(p),POSTURE_PID=str(os.getpid()),LC_ALL='C')
    integration=Path(tmp)/'integration.ts'; integration.write_text('// HERDR_INTEGRATION_ID=pi\n')
    (p/'qwbuddy/config.sh').write_text(f"QWB_WORKERS='sol reviewer'\nQWB_WORKSPACE='ws'\nQWB_ROLE_PI_CONTROL='verified'\nQWB_ROLE_PI_INTEGRATION='{integration}'\nQWB_GATE_FAST='test -f product.txt'\nQWB_GATE_FULL='test -s product.txt'\n")
    (p/'qwbuddy/workers.sh').write_text('qwb_worker sol herdr pi -- --provider openai-codex --model gpt-6.1-sol --thinking high\nqwb_worker reviewer herdr pi -- --provider anthropic --model claude-opus-4-6 --thinking low\n')
    with (p/'.gitignore').open('a') as f: f.write('qwbuddy/.roles/\ntasks/*.qwb-*\n')
    (p/'product.txt').write_text('seed\n')
    def git(*args,at=p): return run(['git','-C',at,*args]).stdout.strip()
    git('add','.'); git('-c','user.name=Test','-c','user.email=test@invalid','commit','-qm','seed')
    run(['bash',p/'qwbuddy/bin/qwb-role.sh','start','--project',p,'--actor','gate','--role','门禁','--worker','sol','--dir',p])
    def ledger(action,t,*args,ok=True,actor='ctl'):
        return run(['bash',p/'qwbuddy/bin/qwb-ledger.sh',action,'--project',p,'--task',t,'--',*args],ok,{'HERDR_PANE_ID':actor}).stdout
    def ticket(name):
        t=p/'tasks'/(name+'.md'); t.write_text('# '+name+'\nstate: running\n## 验收场景\n### user_success\nGiven candidate\nWhen land\nThen success\n### user_reject\nGiven dirty\nWhen land\nThen reject\n')
        m=Path(tmp)/(name+'-migration.json');m.write_text(json.dumps({'task_sha256':hashlib.sha256(t.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no external actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
        ledger('migrate',t,m); return t
    def read(t): return json.loads(ledger('read',t))
    a=ticket('A'); b=ticket('B'); c=ticket('C'); d=ticket('D')
    ledger('append',b,'blocked: 实际工具失败，保留原码9与证据')
    ledger('question',c,'night-land','原夜间自主land未答，只阻塞此票')
    ledger('claim',d,'independent-work'); ledger('append',d,'working: 独立授权技术工作继续')
    candidate=p/'.worktrees/A'; base=git('rev-parse','main')
    git('worktree','add','-qb','A',candidate,base)
    (candidate/'product.txt').write_text('A completed\n'); git('add','product.txt',at=candidate)
    git('-c','user.name=Test','-c','user.email=test@invalid','commit','-qm','A',at=candidate)
    head=git('rev-parse','HEAD',at=candidate)
    environment=Path(tmp)/'environment';environment.write_text('fixture v1\n')
    assignment=Path(tmp)/'assignment.json';assignment.write_text(json.dumps({'candidate':str(candidate),'base':base,'attempt':'1','policy':'v1','environment':str(environment),'required':{'full':['user_success','user_reject']},'workers':{'review':'reviewer','rework':'sol'}}))
    ledger('gate-assign',a,'gate',assignment); ledger('claim',a,'land-A')
    receipt=Path(tmp)/'full.json'
    run(['bash',p/'qwbuddy/bin/qwb-test.sh','full','--project',candidate,'--task',a,'--ledger-project',p,'--op','land-A','--report',receipt])
    def identity(sid,model,provider,family,effort):
        f=Path(tmp)/(sid+'.jsonl'); f.write_text('\n'.join(json.dumps(x) for x in [{'type':'session','id':sid,'cwd':str(p)},{'type':'model_change','modelId':model,'provider':provider},{'type':'thinking_level_change','thinkingLevel':effort}])+'\n')
        return {'model':model,'family':family,'session':sid,'evidence':str(f)}
    review=Path(tmp)/'review.json';review.write_text(json.dumps({'context':json.loads(receipt.read_text())['after'],'implementer':identity('impl','gpt-6.1-sol','openai-codex','gpt','high'),'reviewer':identity('review','claude-opus-4-6','anthropic','claude','low'),'standards':'pass','spec':'pass','covered':['user_success','user_reject'],'findings':[]}))
    ledger('gate-review',a,'land-A',review);ledger('gate-verdict',a,'land-A','accepted')
    ledger('append',a,'done: 仅实现完成不冒称交付')
    snapshots={t:t.read_bytes() for t in [a,b,c,d]}
    for posture in ['online','quiet','away']:
        if posture!='online': mode('enter',posture,'auth-original','同授权模式对照','不授予新land权')
        assert git('status','--porcelain',at=candidate)=='', 'mode polluted candidate'
        # No land-authorize: mode/auth reference alone never grants 05 authority.
        ledger('land-prepare',a,'land-A','auth-original',ok=False)
        ledger('land-authorize',a,'land-A','auth-original','main','gate has no new authority',ok=False,actor='gate-pane')
        assert all(t.read_bytes()==snapshots[t] for t in snapshots)
        if posture!='online': mode('exit','explicit','结束此模式对照')
    ledger('land-authorize',a,'land-A','auth-A','main','fixture original explicit local land',*[str(t.relative_to(p)) for t in [a,b,c,d]])
    for posture in ['online','quiet','away']:
        if posture!='online': mode('enter',posture,'auth-A','同一C/证据/原授权','不新增权限')
        # Same fixed C and same existing permission, no merge side effect in this condition check.
        ledger('land-prepare',a,'land-A','auth-A')
        assert read(a)['land']['after']==head and read(a)['land']['stage']=='prepared'
        if posture!='online': mode('exit','explicit','完成对照')
    print('PASS user_同授权三模式一致: same C accepts; absent ref/gate rejects; candidate stays clean')

    # Mode damage must stop only its affected land/reconciliation, not independent D.
    mode('enter','away','auth-A','离开原话\n\n','仅沿原授权')
    saved=(p/'qwbuddy/.posture.md').read_bytes()
    (p/'qwbuddy/.posture.md').write_bytes(saved.replace(b'"auth_ref":"auth-A"',b'"auth_ref":null',1))
    damaged=(p/'qwbuddy/.posture.md').read_bytes()
    mode('status',ok=False); mode('summary',ok=False); mode('exit','user','返回',ok=False)
    run(['bash',ROOT/'bin/qwb-init.sh',p])
    assert (p/'qwbuddy/.posture.md').read_bytes()==damaged, 'reinstall washed corrupt state'
    status=run(['bash',p/'qwbuddy/bin/qwb-status.sh','--project',p])
    assert '模式记录损坏' in status.stdout and 'D.md' in status.stdout
    ledger('land-apply',a,'land-A','auth-A',ok=False)
    ledger('append',d,'working: 模式损坏仅拦受影响落地，D仍推进')
    assert git('rev-parse','main')==base and (p/'qwbuddy/.posture.md').read_bytes()==damaged
    (p/'qwbuddy/.posture.md').write_bytes(saved) # Only restore this private test corruption.
    print('PASS user_损坏记录与无权拒绝: corrupt auth retained, no main move, D continues')

    ledger('land-apply',a,'land-A','auth-A')
    assert git('rev-parse','main')==head and candidate.exists() and read(a)['land']['stage']=='landed'
    mode('exit','system','工人系统成果',ok=False)
    mode('exit','user','我回来了，读持久事实\n')
    summary=json.loads(mode('summary')); rows={Path(r['task']).stem:r for r in summary['tasks']}
    assert rows['A']['delivery']=='landed' and rows['A']['cleanup']=='pending' and rows['A']['implementation_done']
    assert rows['B']['failures'][-1]['line']=='blocked: 实际工具失败，保留原码9与证据'
    assert rows['C']['decisions']['night-land']['answer']==''
    assert rows['D']['claim']['op_id']=='independent-work'
    status=run(['bash',p/'qwbuddy/bin/qwb-status.sh','--project',p])
    assert '模式: online' in status.stdout and 'stage=landed' in status.stdout and '问题未结: key=night-land' in status.stdout
    bad=p/'tasks/damaged.md';bad.write_text('state: running\n<!-- qwb-collab-v1\nbroken\n-->\n')
    partial=json.loads(mode('summary'));partial_rows={Path(r['task']).stem:r for r in partial['tasks']}
    assert partial_rows['damaged']['error'] and partial_rows['D']['claim']['op_id']=='independent-work'
    bad.unlink() # This fixture only; retain production corrupt records.
    assert summary['posture']['events'][-2]['words']=='离开原话\n\n'
    print('EVIDENCE_RETURN '+json.dumps(summary,ensure_ascii=False),flush=True)
    print('PASS user_返回事实汇总: actual main C + landed pending cleanup / B failed / C key / independent D')
    mode('enter','quiet','auth-A','静音，不减少技术授权','禁止人类推送')
    def send(action,t,*args):
        return run(['bash',p/'qwbuddy/bin/qwb-send.sh',action,'--project',p,'--task',t,*args]).stdout
    def drain(t):
        for i,h in enumerate(json.loads(send('pending',t))):
            event=h['event_id'];op='handle-'+Path(t).stem+'-'+str(h['source_seq'])
            send('received',t,'--event',event);send('accept',t,'--event',event,'--op',op)
            send('prepared',t,'--event',event,'--op',op)
            proof=p/'qwbuddy/.controller.lock'/(op+'.json')
            proof.write_text(json.dumps({'event_id':event,'op_id':op,'outcome':'applied','evidence':'fixture recipient handled actual source, no external action'}))
            send('handled',t,'--event',event,'--op',op,'--result-ref',proof)
    for t in [a,b,c,d]: drain(t)
    legacy=p/'tasks/legacy.md'; legacy.write_text('state: running\nworking: legacy idle\n')
    def wake():
        return run(['bash',p/'qwbuddy/bin/qwb-wake.sh','--project',p,'--once','--pane','ctl'],extra={'QWB_REWAKE_MS':'1'})
    wake() # One real new legacy fact.
    baseline=log.read_bytes(); mode_before=(p/'qwbuddy/.posture.md').read_bytes()
    revisions={t:read(t)['rev'] for t in [a,b,c,d]}
    for _ in range(3):
        result=wake(); assert result.stdout=='', 'quiet idle emitted routine presentation'
        assert log.read_bytes()==baseline, 'quiet idle repeated Herdr wake'
    assert revisions=={t:read(t)['rev'] for t in revisions}
    assert (p/'qwbuddy/.posture.md').read_bytes()==mode_before and json.loads(mode('status'))['mode']=='quiet'
    ledger('append',b,'blocked: quiet期间真实失败 code=23，需要原负责人处理')
    wake()
    facts=json.loads(send('pending',b))
    actual=next(h for h in facts if h['payload']=='blocked: quiet期间真实失败 code=23，需要原负责人处理')
    assert actual['transport_count']==1 and actual['received']=='' and not actual['handled']
    assert log.read_bytes()!=baseline and json.loads(mode('status'))['mode']=='quiet'
    print('EVIDENCE_FAILURE '+json.dumps(actual,ensure_ascii=False),flush=True)
    drain(b); delivered=log.read_bytes()
    for _ in range(3): wake(); assert log.read_bytes()==delivered
    calls=[json.loads(line) for line in log.read_text().splitlines()]
    assert not any(call[:1] in [['server'],['session']] for call in calls)
    assert sum(call[:2]==['agent','start'] for call in calls)==1, 'a fourth model was started by mode'
    print('PASS user_静音与空闲成本: no idle/repeated wake; failure durable to original recipient; system keeps quiet')

    # Mutation waits on controller BEFORE taking posture: a task's posture reader
    # must remain able to finish while that controller lock is held.
    fd=os.open(p/'qwbuddy',os.O_RDONLY); fcntl.flock(fd,fcntl.LOCK_EX)
    change=subprocess.Popen(['bash',str(p/'qwbuddy/bin/qwb-role.sh'),'mode','exit','--project',str(p),'--','explicit','锁序验收退出'],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    try:
        time.sleep(.15) # Scheduling grace under an actual held kernel lock, not a work poll.
        assert change.poll() is None
        reader=subprocess.run(['bash',str(p/'qwbuddy/bin/qwb-role.sh'),'mode','status','--project',str(p)],env=env,capture_output=True,text=True,timeout=5)
        assert reader.returncode==0 and json.loads(reader.stdout)['mode']=='quiet',(reader.stdout,reader.stderr)
    finally:
        fcntl.flock(fd,fcntl.LOCK_UN);os.close(fd)
        out,err=change.communicate(timeout=5)
        assert change.returncode==0,(out,err)
    assert json.loads(mode('status'))['mode']=='online'
    print('PASS controller/posture lock order: concurrent reader completes while mutation waits')
PY
