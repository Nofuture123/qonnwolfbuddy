#!/usr/bin/env bash
# 真入口+临时Git；仅Herdr/ps/lsof系统边界替身，不调用现场端点。
set -euo pipefail
export QWB_GATE_TEST_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
python3 -u -B - <<'PY'
import hashlib, json, os, shutil, subprocess, tempfile, time
from pathlib import Path
ROOT=Path(os.environ['QWB_GATE_TEST_ROOT'])
with tempfile.TemporaryDirectory(prefix='qwb-gate-') as tmp:
    tmp=Path(tmp).resolve(); p=tmp/'project'; p.mkdir(); stub=tmp/'stub'; stub.mkdir()
    shutil.copytree(ROOT/'bin',p/'qwbuddy/bin'); shutil.copytree(ROOT/'templates/roles',p/'qwbuddy/roles')
    for n in ['TASK.md','QWBUDDY.md']: shutil.copy(ROOT/'templates'/n,p/'qwbuddy'/n)
    (p/'qwbuddy/.controller.lock').mkdir(); (p/'qwbuddy/.controller.lock/owner').write_text('2099 ctl\n')
    integration=tmp/'integration.ts'; integration.write_text('// HERDR_INTEGRATION_ID=pi\n')
    (p/'qwbuddy/config.sh').write_text(f"QWB_WORKERS='sol reviewer astra unknown-reviewer'\nQWB_WORKSPACE='ws'\nQWB_ROLE_PI_CONTROL='verified'\nQWB_ROLE_PI_INTEGRATION='{integration}'\nQWB_GATE_FAST='true'\nQWB_GATE_FULL='true'\n")
    (p/'qwbuddy/workers.sh').write_text('qwb_worker sol herdr pi -- --provider openai-codex --model gpt-6.1-sol --thinking high\nqwb_worker reviewer herdr pi -- --provider anthropic --model claude-opus-4-6 --thinking low\nqwb_worker astra herdr pi -- --provider openai-codex --model gpt-6-astra --thinking low\nqwb_worker unknown-reviewer herdr pi -- --provider anthropic --model claude-unconfirmed --thinking low\n')
    (p/'safety.sh').write_text('#!/bin/sh\n# fixture defect: unresolved request wrongly accepted\nexit 0\n')
    (p/'tasks').mkdir(); (p/'.gitignore').write_text('qwbuddy/.roles/\nqwbuddy/.controller.lock/\nqwbuddy/.supervisor.guard\ntasks/\n')
    def git(*args): return subprocess.check_output(['git','-C',str(p),*args],text=True).strip()
    git('init','-q'); git('add','.'); git('-c','user.name=Test','-c','user.email=test@invalid','commit','-qm','seed')
    # 仅本测试私有Git的候选，不是共享lane/池；TemporaryDirectory随测试回收。
    ca=tmp/'candidate-A'; cb=tmp/'candidate-B'; cc=tmp/'candidate-C'; cl=tmp/'candidate-long-A'; cd=tmp/'candidate-changing'; cr=tmp/'candidate-replay'
    for candidate in [ca,cb,cc,cl,cd,cr]: git('worktree','add','-q','--detach',str(candidate))
    state=tmp/'native.json'
    (stub/'lsof').write_text('#!/bin/sh\nexit 1\n')
    (stub/'ps').write_text('''#!/usr/bin/env python3
import subprocess,sys
if sys.argv[-1]=='ppid=': sys.exit(subprocess.run(['/bin/ps',*sys.argv[1:]]).returncode)
print('Thu Oct 1 00:00:00 2099')
''')
    (stub/'herdr').write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
a=sys.argv[1:]; f=Path(os.environ['GATE_NATIVE_STATE']); s=json.loads(f.read_text()) if f.exists() else {}
with open(os.environ['GATE_NATIVE_LOG'],'a') as logfile:print(json.dumps(a),file=logfile)
p=os.environ['GATE_PROJECT']; pid=int(os.environ['GATE_NATIVE_PID'])
def out(x):print(json.dumps({'result':x}))
if a[:2]==['workspace','list']:out({'workspaces':[{'workspace_id':'ws','worktree':{'repo_root':p,'is_linked_worktree':False}}]+[{'workspace_id':'ws'+str(i),'worktree':{'repo_root':p,'is_linked_worktree':True,'checkout_path':d}} for i,d in enumerate(json.loads(os.environ['GATE_CANDIDATES']))]})
elif a[:2]==['tab','create']:
 label=a[a.index('--label')+1];role=label=='门禁';s['tabs']=s.get('tabs',0)+1;slug=label+'-'+str(s['tabs']);out({'root_pane':{'pane_id':'gate-pane' if role else 'worker-'+slug,'tab_id':'gate-tab' if role else 'tab-'+slug,'terminal_id':'gate-terminal'}})
elif a[:2]==['agent','get']:print(json.dumps({'error':{'code':'agent_not_found'}}));sys.exit(1)
elif a[:2]==['agent','prompt']:out({'type':'prompt_sent'})
elif a[:2]==['agent','start']:
 v=a[a.index('--')+1:]
 if '--session-id' in v:
  sid=v[v.index('--session-id')+1];sd=v[v.index('--session-dir')+1];s={'session':sd+'/2099_'+sid+'.jsonl','sid':sid}
 out({'type':'agent_started'})
elif a[:2]==['pane','get']:
 gate=a[2]=='gate-pane'; d={'pane_id':a[2],'workspace_id':'ws','terminal_id':'gate-terminal' if gate else 'ctl-terminal','foreground_cwd':p}
 if not gate or 'session' in s:d.update(agent='pi',agent_status='idle',agent_session={'agent':'pi','source':'herdr:pi','kind':'path','value':s['session'] if gate else 'ctl-session'})
 out({'pane':d})
elif a[:2]==['pane','process-info']:
 live=a[-1]!='gate-pane' or 'session' in s;i=pid if live else 42
 out({'process_info':{'pane_id':a[-1],'shell_pid':42,'foreground_process_group_id':i,'foreground_processes':[{'pid':i,'argv0':'pi' if live else 'zsh','argv':['pi'],'cwd':p}]}})
elif a[:2]==['pane','read']:print('(openai-codex) gpt-6.1-sol • high');sys.exit()
elif a[:2] in (['pane','run'],['tab','close']):out({'type':'input_sent'})
else:sys.exit(9)
f.write_text(json.dumps(s))
''')
    for f in stub.iterdir(): f.chmod(0o755)
    env=os.environ|{'PATH':str(stub)+':'+os.environ['PATH'],'HERDR_PANE_ID':'ctl','GATE_PROJECT':str(p),'GATE_NATIVE_PID':str(os.getpid()),'GATE_NATIVE_STATE':str(state),'GATE_NATIVE_LOG':str(tmp/'native-calls.jsonl'),'GATE_CANDIDATES':json.dumps(list(map(str,[ca,cb,cc])))}
    def call(script,verb,*args,actor='ctl',ok=True,extra=None):
        argv=['bash',str(ROOT/'bin'/script)]
        argv += ['--project',str(p),verb,*map(str,args)] if script=='qwb-run.sh' else [verb,'--project',str(p),*map(str,args)]
        r=subprocess.run(argv,env=env|{'HERDR_PANE_ID':actor}|(extra or {}),capture_output=True,text=True)
        assert (r.returncode==0)==ok,(script,verb,r.returncode,r.stdout,r.stderr)
        return r
    call('qwb-role.sh','start','--actor','gate','--role','门禁','--worker','sol','--dir',p)
    t=p/'tasks/A.md'; t.write_text('# A\nstate: running\n## 验收场景\n### user_good\nGiven project\nWhen check\nThen success\n### user_failure\nGiven bad\nWhen rejected\nThen failure\n')
    m=tmp/'migration.json';m.write_text(json.dumps({'task_sha256':hashlib.sha256(t.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
    call('qwb-ledger.sh','migrate','--task',t,'--',m)
    frozen='## 验收场景\n### user_good\nGiven project\nWhen check\nThen success\n### user_failure\nGiven bad\nWhen rejected\nThen failure'
    call('qwb-ledger.sh','prepare','--task',t,'--',hashlib.sha1(frozen.encode()).hexdigest())
    call('qwb-ledger.sh','claim','--task',t,'--','impl-A')
    call('qwb-ledger.sh','dispatch','--task',t,'--','impl-A','worker-A',f'dispatch: 2099 op_id=impl-A worker=sol agent=impl-A pane=worker-A dir={ca}')
    call('qwb-ledger.sh','release','--task',t,'--','impl-A')
    call('qwb-ledger.sh','append','--task',t,'--','done: 候选A交回',actor='worker-A')
    call('qwb-send.sh','send','--task',t,'--corr','result-A','--attempt','1','--text','done: 候选A交回',actor='worker-A')
    bt=p/'tasks/B.md';bt.write_text('# B\nstate: running\n## 验收场景\n### user_good\nGiven project\nWhen check\nThen success\n### user_failure\nGiven bad\nWhen rejected\nThen failure\n')
    m.write_text(json.dumps({'task_sha256':hashlib.sha256(bt.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
    call('qwb-ledger.sh','migrate','--task',bt,'--',m)
    call('qwb-ledger.sh','prepare','--task',bt,'--',hashlib.sha1(frozen.encode()).hexdigest())
    call('qwb-ledger.sh','claim','--task',bt,'--','impl-B')
    call('qwb-ledger.sh','dispatch','--task',bt,'--','impl-B','worker-B',f'dispatch: 2099 op_id=impl-B worker=sol agent=impl-B pane=worker-B dir={cb}')
    call('qwb-ledger.sh','release','--task',bt,'--','impl-B')
    call('qwb-ledger.sh','append','--task',bt,'--','done: 候选B交回',actor='worker-B')
    call('qwb-send.sh','send','--task',bt,'--corr','result-B','--attempt','1','--text','done: 候选B交回',actor='worker-B')
    # 第一纵向切片：主控授权已登记门禁，claim真实绑定且跨调用保留。
    request=tmp/'assignment.json'; environment=tmp/'environment'; environment.write_text('fixture dependency v1\n')
    request.write_text(json.dumps({'candidate':str(ca),'base':git('rev-parse','HEAD'),'attempt':'1','policy':'existing-v1','environment':str(environment),'required':{'full':['user_good','user_failure']},'workers':{'review':'reviewer','rework':'sol'}}))
    call('qwb-ledger.sh','gate-assign','--task',t,'--','gate',request)
    call('qwb-ledger.sh','claim','--task',t,'--','accept-A',actor='gate-pane')
    brequest=json.loads(request.read_text());brequest['candidate']=str(cb);request.write_text(json.dumps(brequest))
    call('qwb-ledger.sh','gate-assign','--task',bt,'--','gate',request)
    call('qwb-ledger.sh','claim','--task',bt,'--','accept-B',actor='gate-pane')
    # 现有03唯一监督直接给被claim门禁一条A/B摘要，不先唤主控逐票转发。
    (tmp/'native-calls.jsonl').write_text('')
    call('qwb-wake.sh','--once','--pane','ctl')
    calls=[json.loads(line) for line in (tmp/'native-calls.jsonl').read_text().splitlines()]
    delivery=[a for a in calls if a[:2]==['pane','run']]
    assert len(delivery)==1 and delivery[0][2]=='gate-pane' and 'A(running)' in delivery[0][3] and 'B(running)' in delivery[0][3], delivery
    print('PASS 现有唯一监督一批A/B成果直接门铃门禁，不自动received/handled')
    (tmp/'native-calls.jsonl').write_text('')
    routed=call('qwb-wake.sh','--block','--max-ms','1',ok=False,extra={'QWB_REWAKE_MS':'1'})
    calls=[json.loads(line) for line in (tmp/'native-calls.jsonl').read_text().splitlines()]
    delivery=[a for a in calls if a[:2]==['pane','run']]
    assert routed.returncode==124 and len(delivery)==1 and delivery[0][2]=='gate-pane', (routed.returncode,delivery,routed.stderr)
    print('PASS Pi宿主block同样路由门禁，不以rc2逐轮唤主控；唯一监督与有界重投不变')
    if os.environ.get('QWB_GATE_ROUTES_ONLY')=='1':
        print('PASS 仅04/06直接门铃接缝窄验；未执行后段candidate/full fixture检查')
        raise SystemExit(0)
    batch=[]
    for ticket in [t,bt]:batch+=json.loads(call('qwb-send.sh','pending','--task',ticket,actor='gate-pane').stdout)
    assert any(h['payload']=='done: 候选A交回' for h in batch) and any(h['payload']=='done: 候选B交回' for h in batch)
    print('PASS 03批量持久交接直接读回A/B成果，未逐轮转主控')
    d=json.loads(call('qwb-ledger.sh','read','--task',t).stdout)
    assert d['claim']=={'owner':'gate-pane','op_id':'accept-A'}
    before=t.read_bytes()
    call('qwb-ledger.sh','claim','--task',t,'--','second',ok=False)
    call('qwb-ledger.sh','answer','--task',t,'--','budget','yes',actor='gate-pane',ok=False)
    assert t.read_bytes()==before
    print('PASS 单票角色授权、持久claim和越权拒绝')
    # 第二切片：真实qwb-test成功只产收据，不能自动accepted；旧对象/dirty拒绝复用。
    report=tmp/'A-full.json'
    r=call('qwb-test.sh','full','--project',ca,'--task',t,'--ledger-project',p,'--op','accept-A','--report',report,actor='gate-pane')
    receipt=json.loads(report.read_text()); assert receipt['rc']==0 and receipt['before']['head']==git('rev-parse','HEAD')
    d=json.loads(call('qwb-ledger.sh','read','--task',t).stdout)
    assert d['gate']['verdict']=='pending' and d['phase']=='running' and len(d['gate']['receipts'])==1
    (ca/'dirty.txt').write_text('uncommitted\n')
    call('qwb-ledger.sh','gate-verdict','--task',t,'--','accept-A','accepted',actor='gate-pane',ok=False)
    (ca/'dirty.txt').unlink()
    changed=dict(receipt); changed['before']=dict(receipt['before'],head='0'*40)
    old=tmp/'old.json';old.write_text(json.dumps(changed))
    call('qwb-ledger.sh','gate-receipt','--task',t,'--','accept-A',old,actor='gate-pane',ok=False)
    print('PASS candidate-bound收据，rc0不等于accepted，dirty/旧head拒绝')
    # 第三切片：独立会话证据、原finding保留、偏好不阻断、未决不放行。
    def session(name,model):
        f=tmp/(name+'.jsonl'); f.write_text(json.dumps({'type':'session','id':name,'cwd':str(p)})+'\n'+json.dumps({'type':'model_change','provider':'openai-codex' if model.startswith('gpt-') else 'anthropic','modelId':model})+'\n'+json.dumps({'type':'thinking_level_change','thinkingLevel':'high' if model=='gpt-6.1-sol' else 'low'})+'\n')
        return {'model':model,'family':'gpt' if model.startswith('gpt-') else 'claude','session':name,'evidence':str(f)}
    impl=session('implementation','gpt-6.1-sol'); reviewer=session('review','claude-opus-4-6')
    reviewfile=tmp/'review.json'
    review={'context':receipt['after'],'implementer':impl,'reviewer':reviewer,'standards':'pass','spec':'pass','covered':['user_good','user_failure'],'findings':[{'id':'F1','original':'真实安全缺陷：允许未决放行','classification':'unresolved','root':'safety','evidence':'反例已复现'}]}
    assert subprocess.run(['bash',str(ca/'safety.sh'),'unresolved']).returncode==0, 'A真实fixture缺陷未复现（预期拒绝7，实际接受0）'
    reviewfile.write_text(json.dumps(review))
    call('qwb-ledger.sh','gate-review','--task',t,'--','accept-A',reviewfile,actor='gate-pane')
    call('qwb-ledger.sh','gate-verdict','--task',t,'--','accept-A','accepted',actor='gate-pane',ok=False)
    review['findings'][0]['classification']='must-fix';reviewfile.write_text(json.dumps(review))
    call('qwb-ledger.sh','gate-review','--task',t,'--','accept-A',reviewfile,actor='gate-pane')
    call('qwb-ledger.sh','gate-verdict','--task',t,'--','accept-A','rework','safety','同一反例',actor='gate-pane')
    d=json.loads(call('qwb-ledger.sh','read','--task',t).stdout)
    assert d['gate']['verdict']=='rework' and d['gate']['findings']['F1']['original']=='真实安全缺陷：允许未决放行'
    assert d['claim']['owner']=='gate-pane'
    # A原票公开run返修，验收claim不释放、不换规格；B独立accepted。
    call('qwb-run.sh','--task',t,'--worker','sol','--worktree',ca,'--gate-op','accept-A','--gate-kind','rework','--name','rework-a',actor='gate-pane')
    assert json.loads(call('qwb-ledger.sh','read','--task',t).stdout)['claim']['op_id']=='accept-A'
    br=tmp/'B-full.json';call('qwb-test.sh','full','--project',cb,'--task',bt,'--ledger-project',p,'--op','accept-B','--report',br,actor='gate-pane')
    call('qwb-run.sh','--task',bt,'--worker','reviewer','--worktree',cb,'--gate-op','accept-B','--gate-kind','review','--name','review-b',actor='gate-pane')
    breview=tmp/'B-review.json';breview.write_text(json.dumps(dict(review,context=json.loads(br.read_text())['after'],findings=[])))
    call('qwb-ledger.sh','gate-review','--task',bt,'--','accept-B',breview,actor='gate-pane')
    bstate=json.loads(call('qwb-ledger.sh','read','--task',bt).stdout);bchild=next(iter(bstate['gate']['dispatches']))
    call('qwb-ledger.sh','gate-verdict','--task',bt,'--','accept-B','accepted',actor='gate-pane',ok=False)
    call('qwb-ledger.sh','append','--task',bt,'--','done: Standards+Spec独立审核完成；真实JSONL fixture已交回',actor=bstate['ops'][bchild]['pane'])
    call('qwb-ledger.sh','gate-verdict','--task',bt,'--','accept-B','accepted',actor='gate-pane')
    assert json.loads(call('qwb-ledger.sh','read','--task',t).stdout)['gate']['verdict']=='rework'
    assert json.loads(call('qwb-ledger.sh','read','--task',bt).stdout)['gate']['verdict']=='accepted'
    print('PASS 两票不同结论：A公开run原范围返修，B accepted，未自动verified/合并')
    # F1单条件红测：配置/对象不变，真实0→真实7→原成功重放，不能洗掉失败。
    failure_marker=tmp/'replay-fail'
    with (cr/'qwbuddy/config.sh').open('a') as f:f.write(f"QWB_GATE_FULL='test ! -e {failure_marker} || exit 7'\n")
    subprocess.run(['git','-C',str(cr),'add','qwbuddy/config.sh'],check=True)
    subprocess.run(['git','-C',str(cr),'-c','user.name=Test','-c','user.email=test@invalid','commit','-qm','replay command fixture'],check=True)
    rt=p/'tasks/Replay.md';rt.write_text('# 收据重放\nstate: running\n'+frozen+'\n')
    m.write_text(json.dumps({'task_sha256':hashlib.sha256(rt.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
    call('qwb-ledger.sh','migrate','--task',rt,'--',m)
    request.write_text(json.dumps(dict(brequest,candidate=str(cr))))
    call('qwb-ledger.sh','gate-assign','--task',rt,'--','gate',request);call('qwb-ledger.sh','claim','--task',rt,'--','accept-R',actor='gate-pane')
    def replay_test(name,ok=True):
        f=tmp/name
        result=call('qwb-test.sh','full','--project',cr,'--task',rt,'--ledger-project',p,'--op','accept-R','--report',f,actor='gate-pane',ok=ok)
        return f,result
    def import_replay(f):return call('qwb-ledger.sh','gate-receipt','--task',rt,'--','accept-R',f,actor='gate-pane')
    def replay_verdict(ok=True):return call('qwb-ledger.sh','gate-verdict','--task',rt,'--','accept-R','accepted',actor='gate-pane',ok=ok)
    first,_=replay_test('Replay-original-success.json')
    replay_review=tmp/'Replay-review.json';replay_review.write_text(json.dumps(dict(review,context=json.loads(first.read_text())['after'],findings=[])))
    call('qwb-ledger.sh','gate-review','--task',rt,'--','accept-R',replay_review,actor='gate-pane');replay_verdict()
    failure_marker.touch();failed_report,failed_result=replay_test('Replay-newer-failure.json',ok=False)
    assert failed_result.returncode==7
    replay_verdict(ok=False)
    import_replay(first)
    replay_verdict(ok=False)
    assert [r['receipt']['rc'] for r in json.loads(call('qwb-ledger.sh','read','--task',rt).stdout)['gate']['receipts']]==[0,7]
    # 等待严格跨秒边界，不用导入顺序或同秒并列推断执行先后。
    while int(time.time())<=json.loads(failed_report.read_text())['ended_at']:time.sleep(0.05)
    failure_marker.unlink();fresh,_=replay_test('Replay-fresh-success.json');replay_verdict()
    snapshot=rt.read_bytes();import_replay(first);import_replay(failed_report);import_replay(fresh)
    # 另一报告路径、JSON排版不同仍是同一执行；幂等不能重置verdict/rev/事件。
    duplicate=tmp/'Replay-duplicate-format.json';duplicate.write_text(json.dumps(json.loads(first.read_text()),indent=2))
    import_replay(duplicate);assert rt.read_bytes()==snapshot
    # 协议乱序/模糊时间夹具只改变真实收据时间，不冒充额外真实执行。
    later=json.loads(fresh.read_text());earlier=json.loads(failed_report.read_text())
    older=tmp/'Replay-older-failure.json';earlier.update(started_at=later['started_at']-2,ended_at=later['started_at']-2,elapsed_seconds=0);older.write_text(json.dumps(earlier))
    import_replay(older);replay_verdict() # 较晚成功仍可用，不能按数组尾失败判定。
    tied=tmp/'Replay-ambiguous-failure.json';earlier.update(started_at=later['started_at'],ended_at=later['ended_at'],elapsed_seconds=later['elapsed_seconds']);tied.write_text(json.dumps(earlier))
    import_replay(tied);replay_verdict(ok=False);import_replay(fresh);replay_verdict(ok=False)
    malformed=tmp/'Replay-invalid-time.json';invalid=dict(later,started_at=later['ended_at']+1);malformed.write_text(json.dumps(invalid))
    call('qwb-ledger.sh','gate-receipt','--task',rt,'--','accept-R',malformed,actor='gate-pane',ok=False)
    while int(time.time())<=later['ended_at']:time.sleep(0.05)
    replay_test('Replay-after-ambiguity-success.json');replay_verdict()
    history=json.loads(call('qwb-ledger.sh','read','--task',rt).stdout)['gate']['receipts']
    assert [r['receipt']['rc'] for r in history]==[0,7,0,7,7,0]
    print('PASS F1真实0→7→旧0仍拒绝；重复执行幂等、乱序保历史、同秒不猜先后、明确新成功恢复')
    # 原票工人修复真实缺陷，新attempt重验；旧必须修复意见保留在原版本历史。
    ca.joinpath('safety.sh').write_text('#!/bin/sh\n[ "${1:-}" != unresolved ] || exit 7\nexit 0\n')
    subprocess.run(['git','-C',str(ca),'add','safety.sh'],check=True)
    subprocess.run(['git','-C',str(ca),'-c','user.name=Test','-c','user.email=test@invalid','commit','-qm','fix original-scope defect'],check=True)
    astate=json.loads(call('qwb-ledger.sh','read','--task',t).stdout)
    child=next(iter(astate['gate']['dispatches']))
    call('qwb-ledger.sh','append','--task',t,'--','done: 原范围安全缺陷已修复，unresolved返回7',actor=astate['ops'][child]['pane'])
    call('qwb-ledger.sh','gate-candidate','--task',t,'--','accept-A','2',ca,git('rev-parse','HEAD'),actor='gate-pane')
    assert subprocess.run(['bash',str(ca/'safety.sh'),'unresolved']).returncode==7
    repaired=tmp/'A-repaired.json';call('qwb-test.sh','full','--project',ca,'--task',t,'--ledger-project',p,'--op','accept-A','--report',repaired,actor='gate-pane')
    review['context']=json.loads(repaired.read_text())['after']
    # 对当前已修候选的意见不再成立；原must-fix仍绑定原head，不洗历史。
    review['findings'][0].update(classification='not-founded',evidence='修复复核：当前safety.sh unresolved实际返回7；原缺陷在旧head成立，历史保留')
    review['findings'].append({'id':'P1','original':'命名偏好','classification':'suggestion','root':'style','evidence':'未违反契约'})
    reviewfile.write_text(json.dumps(review));call('qwb-ledger.sh','gate-review','--task',t,'--','accept-A',reviewfile,actor='gate-pane')
    review['covered']=[];reviewfile.write_text(json.dumps(review));call('qwb-ledger.sh','gate-review','--task',t,'--','accept-A',reviewfile,actor='gate-pane')
    call('qwb-ledger.sh','gate-verdict','--task',t,'--','accept-A','accepted',actor='gate-pane',ok=False)
    review['covered']=['user_good','user_failure'];reviewfile.write_text(json.dumps(review));call('qwb-ledger.sh','gate-review','--task',t,'--','accept-A',reviewfile,actor='gate-pane')
    call('qwb-ledger.sh','gate-verdict','--task',t,'--','accept-A','accepted',actor='gate-pane')
    d=json.loads(call('qwb-ledger.sh','read','--task',t).stdout)
    assert d['gate']['verdict']=='accepted' and d['phase']=='running' and len(d['gate']['receipts'])==2
    assert len(d['gate']['findings']['F1']['history'])==5
    print('PASS 独立审核、原意见分类闭环、缺场景拒绝、偏好不阻断且复用同对象收据')
    # 第四切片：独立op里的长门不持writer锁；B复用，C新成果可处理。
    # 并行场景独立fixture：Long-A仍有同一真实缺陷，不修改已accepted的A/B候选。
    t=p/'tasks/Long-A.md';t.write_text('# Long A\nstate: running\n'+frozen+'\n')
    m.write_text(json.dumps({'task_sha256':hashlib.sha256(t.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
    call('qwb-ledger.sh','migrate','--task',t,'--',m)
    request.write_text(json.dumps(dict(brequest,candidate=str(cl))))
    call('qwb-ledger.sh','gate-assign','--task',t,'--','gate',request)
    call('qwb-ledger.sh','claim','--task',t,'--','accept-A',actor='gate-pane')
    call('qwb-send.sh','send','--task',t,'--corr','result-A','--attempt','1','--text','done: Long-A候选有真实安全缺陷')
    longseed=tmp/'Long-A-seed.json';call('qwb-test.sh','full','--project',cl,'--task',t,'--ledger-project',p,'--op','accept-A','--report',longseed,actor='gate-pane')
    review['context']=json.loads(longseed.read_text())['after']
    review['findings'][0].update(classification='must-fix',evidence='公开safety.sh unresolved返回0，预期拒绝7')
    assert subprocess.run(['bash',str(cl/'safety.sh'),'unresolved']).returncode==0
    reviewfile.write_text(json.dumps(review));call('qwb-ledger.sh','gate-review','--task',t,'--','accept-A',reviewfile,actor='gate-pane')
    call('qwb-ledger.sh','gate-verdict','--task',t,'--','accept-A','rework','safety','同一反例',actor='gate-pane')
    ca=cl
    started=tmp/'long-started';finish=tmp/'long-finish'; cfg=ca/'qwbuddy/config.sh'
    with cfg.open('a') as f:f.write(f"QWB_GATE_FULL='touch {started}; while [ ! -e {finish} ]; do sleep 0.1; done'\n")
    subprocess.run(['git','-C',str(ca),'add','qwbuddy/config.sh'],check=True)
    subprocess.run(['git','-C',str(ca),'-c','user.name=Test','-c','user.email=test@invalid','commit','-qm','original-scope rework'],check=True)
    call('qwb-ledger.sh','gate-candidate','--task',t,'--','accept-A','2',ca,git('rev-parse','HEAD'),actor='gate-pane')
    diff=json.loads(call('qwb-ledger.sh','gate-diff','--task',t,'--','accept-A','','qwbuddy/config.sh',actor='gate-pane').stdout)
    assert diff['reviewed_head']==receipt['after']['head'] and 'long-started' in diff['reviewed_diff'] and 'qwbuddy/config.sh' in diff['contexts']
    call('qwb-ledger.sh','gate-receipt','--task',t,'--','accept-A',report,actor='gate-pane',ok=False)
    # 03处理阶段确认+prepared/activity保留，在长门执行前占不同的持久op。
    h=next(h for h in json.loads(call('qwb-send.sh','pending','--task',t,actor='gate-pane').stdout) if h['corr']=='result-A')
    for verb,args in [('received',[]),('accept',['--op','long-A']),('prepared',['--op','long-A']),('activity',['--wait-ms','180000','--reason','等待候选外long-finish'])]:
        call('qwb-send.sh',verb,'--task',t,'--event',h['event_id'],*args,actor='gate-pane')
    longreport=tmp/'A-long.json'
    wait_start=time.monotonic()
    process=subprocess.Popen(['bash',str(ROOT/'bin/qwb-test.sh'),'full','--project',str(ca),'--ledger-project',str(p),'--task',str(t),'--op','accept-A','--report',str(longreport)],env=env|{'HERDR_PANE_ID':'gate-pane'},stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    try:
        deadline=time.monotonic()+30
        while not started.exists():
            assert process.poll() is None,'长门提前失败'
            assert time.monotonic()<deadline,'长门未启动';time.sleep(.05)
        # B同对象/条件可信full直接复用，A仍真正在等。
        call('qwb-ledger.sh','gate-verdict','--task',bt,'--','accept-B','accepted',actor='gate-pane')
        assert process.poll() is None
        ct=p/'tasks/C.md';ct.write_text('# C\nstate: running\n'+frozen+'\n')
        m.write_text(json.dumps({'task_sha256':hashlib.sha256(ct.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
        call('qwb-ledger.sh','migrate','--task',ct,'--',m)
        crequest=dict(brequest,candidate=str(cc));request.write_text(json.dumps(crequest))
        call('qwb-ledger.sh','gate-assign','--task',ct,'--','gate',request)
        call('qwb-ledger.sh','claim','--task',ct,'--','accept-C',actor='gate-pane')
        ce=call('qwb-send.sh','send','--task',ct,'--corr','result-C','--attempt','1','--text','done: C的新结果').stdout.strip()
        call('qwb-send.sh','received','--task',ct,'--event',ce,actor='gate-pane')
        call('qwb-send.sh','accept','--task',ct,'--event',ce,'--op','handle-C',actor='gate-pane')
        call('qwb-send.sh','prepared','--task',ct,'--event',ce,'--op','handle-C',actor='gate-pane')
        proof=p/'tasks/C-result.json';proof.write_text(json.dumps({'event_id':ce,'op_id':'handle-C','outcome':'applied','evidence':'C真实公开读回；A长门仍运行'}))
        call('qwb-send.sh','handled','--task',ct,'--event',ce,'--op','handle-C','--result-ref',proof,actor='gate-pane')
        assert process.poll() is None
        bd=json.loads(call('qwb-ledger.sh','read','--task',bt).stdout)
        assert len(bd['gate']['receipts'])==1 and bd['gate']['verdict']=='accepted'
        print(f'PASS A持久prepared/wait长门中B复用C handled；处理耗时={time.monotonic()-wait_start:.2f}s tokens=unknown')
    finally:
        finish.touch();out,err=process.communicate(timeout=30)
    assert process.returncode==0,(out,err)
    ad=json.loads(call('qwb-ledger.sh','read','--task',t).stdout)
    assert ad['gate']['binding']['attempt']=='2' and ad['gate']['receipts'][0]['receipt']['before']['attempt']=='1' and ad['gate']['verdict']=='pending'
    assert ad['gate']['receipts'][-1]['receipt']['elapsed_seconds']>0
    # 三轮必须实际新attempt+独立复核，不把重复同轮调用计成三轮。
    for attempt in ['2','3']:
        if attempt=='3':call('qwb-ledger.sh','gate-candidate','--task',t,'--','accept-A',attempt,ca,git('rev-parse','HEAD'),actor='gate-pane')
        review['context']=json.loads(call('qwb-ledger.sh','gate-context','--task',t,'--','accept-A',actor='gate-pane').stdout)
        reviewfile.write_text(json.dumps(review));call('qwb-ledger.sh','gate-review','--task',t,'--','accept-A',reviewfile,actor='gate-pane')
        call('qwb-ledger.sh','gate-verdict','--task',t,'--','accept-A','rework','safety','同一反例',actor='gate-pane')
        if attempt=='2':
            snapshot=json.loads(call('qwb-ledger.sh','read','--task',t).stdout)
            call('qwb-ledger.sh','gate-verdict','--task',t,'--','accept-A','rework','safety','同一反例',actor='gate-pane')
            assert json.loads(call('qwb-ledger.sh','read','--task',t).stdout)['rev']==snapshot['rev']
    ad=json.loads(call('qwb-ledger.sh','read','--task',t).stdout)
    assert ad['gate']['verdict']=='rediagnose' and len(ad['gate']['rounds'])==3 and not ad['questions']
    call('qwb-ledger.sh','gate-dispatch','--task',t,'--','accept-A','bad-rework','rework','sol',actor='gate-pane',ok=False)
    print('PASS 三轮同根因无新证据转主控技术重诊，不默认询问用户、不清旧意见')
    # 身份unknown、同family、越权改场景/首次派工都必须代码拒绝。
    unknown=dict(review,context=json.loads(br.read_text())['after'],findings=[],reviewer=dict(reviewer,family='unknown'))
    reviewfile.write_text(json.dumps(unknown));call('qwb-ledger.sh','gate-review','--task',bt,'--','accept-B',reviewfile,actor='gate-pane',ok=False)
    et=p/'tasks/Same-family.md';et.write_text('# 同family规则冲突\nstate: running\n'+frozen+'\n')
    m.write_text(json.dumps({'task_sha256':hashlib.sha256(et.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
    call('qwb-ledger.sh','migrate','--task',et,'--',m)
    erequest=dict(brequest,candidate=str(cc),workers={'review':'astra','rework':'sol'});request.write_text(json.dumps(erequest))
    call('qwb-ledger.sh','gate-assign','--task',et,'--','gate',request);call('qwb-ledger.sh','claim','--task',et,'--','accept-E',actor='gate-pane')
    same=dict(unknown,context=json.loads(call('qwb-ledger.sh','gate-context','--task',et,'--','accept-E',actor='gate-pane').stdout),reviewer=session('same-family','gpt-6-astra'))
    reviewfile.write_text(json.dumps(same));conflict=call('qwb-ledger.sh','gate-review','--task',et,'--','accept-E',reviewfile,actor='gate-pane',ok=False)
    assert '同family审核冲突' in conflict.stderr, conflict.stderr
    print('PASS Sol high/Astra low两个原生fixture session均GPT；如实同family冲突拒绝')
    ut=p/'tasks/Unknown-native-model.md';ut.write_text('# 未知真实型号不猜family\nstate: running\n'+frozen+'\n')
    m.write_text(json.dumps({'task_sha256':hashlib.sha256(ut.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
    call('qwb-ledger.sh','migrate','--task',ut,'--',m)
    request.write_text(json.dumps(dict(brequest,candidate=str(cc),workers={'review':'unknown-reviewer','rework':'sol'})))
    call('qwb-ledger.sh','gate-assign','--task',ut,'--','gate',request);call('qwb-ledger.sh','claim','--task',ut,'--','accept-U',actor='gate-pane')
    unverified=dict(unknown,context=json.loads(call('qwb-ledger.sh','gate-context','--task',ut,'--','accept-U',actor='gate-pane').stdout),reviewer=session('unconfirmed-native','claude-unconfirmed'))
    reviewfile.write_text(json.dumps(unverified));rejected=call('qwb-ledger.sh','gate-review','--task',ut,'--','accept-U',reviewfile,actor='gate-pane',ok=False)
    assert '原生模型family未可靠确认' in rejected.stderr,rejected.stderr
    print('PASS 原生model前缀类似Claude也不猜family；未知固定provider/model拒绝')
    call('qwb-ledger.sh','revise-scenarios','--task',bt,'--expect',str(bd['rev']),'--',frozen,'新产品',actor='gate-pane',ok=False)
    call('qwb-run.sh','--task',bt,'--worker','sol','--worktree',cb,actor='gate-pane',ok=False)
    call('qwb-run.sh','--task',bt,'--worker','sol','--worktree',cb,'--gate-op','accept-B','--gate-kind','review','--revise-scenarios=新产品',actor='gate-pane',ok=False)
    oldenv=environment.read_bytes();environment.write_text('fixture dependency v2\n')
    call('qwb-ledger.sh','gate-verdict','--task',bt,'--','accept-B','accepted',actor='gate-pane',ok=False)
    environment.write_bytes(oldenv)
    print('PASS 越权/unknown/实际同family安排拒绝，依赖环境变化不能复用旧收据')
    # 原始post-run对象必须留证：命令rc0期间产生新commit不能采信运行前HEAD。
    changing=cd/'qwbuddy/config.sh'
    with changing.open('a') as f:f.write("QWB_GATE_FULL='printf fixed >> safety.sh; git add safety.sh; git -c user.name=Test -c user.email=test@invalid commit -qm during-test'\n")
    subprocess.run(['git','-C',str(cd),'add','qwbuddy/config.sh'],check=True)
    subprocess.run(['git','-C',str(cd),'-c','user.name=Test','-c','user.email=test@invalid','commit','-qm','changing command fixture'],check=True)
    dt=p/'tasks/Changing.md';dt.write_text('# 运行后变化\nstate: running\n'+frozen+'\n')
    m.write_text(json.dumps({'task_sha256':hashlib.sha256(dt.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
    call('qwb-ledger.sh','migrate','--task',dt,'--',m)
    request.write_text(json.dumps(dict(brequest,candidate=str(cd))))
    call('qwb-ledger.sh','gate-assign','--task',dt,'--','gate',request);call('qwb-ledger.sh','claim','--task',dt,'--','accept-D',actor='gate-pane')
    call('qwb-test.sh','full','--project',cd,'--task',dt,'--ledger-project',p,'--op','accept-D','--report',cd/'in-candidate.json',actor='gate-pane',ok=False)
    changingreport=tmp/'Changing.json';result=call('qwb-test.sh','full','--project',cd,'--task',dt,'--ledger-project',p,'--op','accept-D','--report',changingreport,actor='gate-pane',ok=False)
    observed=json.loads(changingreport.read_text())
    assert result.returncode==3 and observed['rc']==0 and observed['before']['head']!=observed['after']['head'] and observed['before']['tree']!=observed['after']['tree']
    assert not json.loads(call('qwb-ledger.sh','read','--task',dt).stdout)['gate']['receipts']
    # 当前spec改变，即便HEAD/门成功不变也不能ready；恢复临时票原字节。
    before=bt.read_bytes();bt.write_bytes(before.replace(b'## ',b'changed original spec\n## ',1))
    call('qwb-ledger.sh','gate-verdict','--task',bt,'--','accept-B','accepted',actor='gate-pane',ok=False);bt.write_bytes(before)
    print('PASS 候选外报告、原spec变化、运行前后真实commit/tree差异拒绝；rc0原始证据仍保留')
    # 门失败后元信息失败，仍透传真实7，不能被set -e改成1或写可信收据。
    with changing.open('a') as f:f.write("QWB_GATE_FULL='exit 7'\n")
    subprocess.run(['git','-C',str(cd),'add','qwbuddy/config.sh'],check=True)
    subprocess.run(['git','-C',str(cd),'-c','user.name=Test','-c','user.email=test@invalid','commit','-qm','failed gate metadata fixture'],check=True)
    ft=p/'tasks/Metadata.md';ft.write_text('# 元信息失败\nstate: running\n'+frozen+'\n')
    m.write_text(json.dumps({'task_sha256':hashlib.sha256(ft.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
    call('qwb-ledger.sh','migrate','--task',ft,'--',m)
    request.write_text(json.dumps(dict(brequest,candidate=str(cd))))
    call('qwb-ledger.sh','gate-assign','--task',ft,'--','gate',request);call('qwb-ledger.sh','claim','--task',ft,'--','accept-F',actor='gate-pane')
    (stub/'date').write_text('#!/bin/sh\nn=$(cat "$QWB_DATE_COUNT" 2>/dev/null || echo 0); n=$((n+1)); printf %s "$n" > "$QWB_DATE_COUNT"\n[ "$n" != 2 ] || exit 1\nexec /bin/date "$@"\n');(stub/'date').chmod(0o755)
    badtime=tmp/'metadata-failure.json'
    failed=call('qwb-test.sh','full','--project',cd,'--task',ft,'--ledger-project',p,'--op','accept-F','--report',badtime,actor='gate-pane',ok=False,extra={'QWB_DATE_COUNT':str(tmp/'date-count')})
    assert failed.returncode==7 and not badtime.exists(),(failed.returncode,failed.stderr)
    print('PASS 按票门真实7后元信息失败仍返回7，无可信收据')
    evidence=os.environ.get('QWB_GATE_EVIDENCE_DIR')
    if evidence:
        dest=Path(evidence).resolve();dest.mkdir(parents=True,exist_ok=False)
        for file in tmp.iterdir():
            if file.is_file() and file.suffix in ('.json','.jsonl'):shutil.copy(file,dest/file.name)
        for ticket in (p/'tasks').glob('*.md'):
            (dest/(ticket.stem+'-ledger.json')).write_text(call('qwb-ledger.sh','read','--task',ticket).stdout)
            shutil.copy(ticket,dest/ticket.name)
        (dest/'README.md').write_text('这些是临时Git+fakeHerdr的行为证据，路径/PID/模型会话是fixture，不是现场原生审核身份；临时副本已回收。不能据此声称真实Herdr交互已验。\n')
        print('fixture原始收据/审核/账本/Herdr调用保存：'+str(dest))
PY
