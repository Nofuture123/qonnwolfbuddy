#!/usr/bin/env bash
# 公开入口 + 私有项目/系统边界替身；绝不触碰真实Herdr。
set -euo pipefail
# Fail closed even if the PATH stub disappears.
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock
export QWB_PLANNING_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
python3 -u -B - <<'PY'
import contextlib, hashlib, json, os, shutil, signal, subprocess, tempfile, time
from pathlib import Path
ROOT=Path(os.environ['QWB_PLANNING_ROOT'])
fixture=os.environ.get('QWB_PLANNING_FIXTURE_DIR')
if fixture:
    fixture=Path(fixture); fixture.mkdir(mode=0o700,parents=True,exist_ok=False)
manager=contextlib.nullcontext(str(fixture)) if fixture else tempfile.TemporaryDirectory(prefix='qwb-planning-')
with manager as temp:
    temp=Path(temp).resolve(); p=temp/'project'; p.mkdir(); stub=temp/'stub'; stub.mkdir()
    shutil.copytree(ROOT/'bin',p/'qwbuddy/bin'); shutil.copytree(ROOT/'templates/roles',p/'qwbuddy/roles')
    for name in ['TASK.md','QWBUDDY.md']: shutil.copy(ROOT/'templates'/name,p/'qwbuddy'/name)
    (p/'tasks').mkdir(); (p/'qwbuddy/.controller.lock').mkdir()
    (p/'qwbuddy/.controller.lock/owner').write_text('2099 ctl\n')
    integration=temp/'integration.ts'; integration.write_text('// HERDR_INTEGRATION_ID=pi\n')
    (p/'qwbuddy/config.sh').write_text(f"QWB_WORKERS='sol reviewer'\nQWB_WORKSPACE='ws'\nQWB_ROLE_PI_CONTROL='verified'\nQWB_ROLE_PI_INTEGRATION='{integration}'\nQWB_GATE_FAST='true'\nQWB_GATE_FULL='true'\n")
    (p/'qwbuddy/workers.sh').write_text('qwb_worker sol herdr pi -- --provider openai-codex --model gpt-6.1-sol --thinking high\nqwb_worker reviewer herdr pi -- --provider anthropic --model claude-opus-4-6 --thinking low\n')
    (p/'.gitignore').write_text('tasks/\nqwbuddy/.roles/\nqwbuddy/.controller.lock/\nqwbuddy/.supervisor.guard\n')
    def git(*args): return subprocess.check_output(['git','-C',str(p),*args],text=True).strip()
    git('init','-q'); git('add','.'); git('-c','user.name=Test','-c','user.email=test@invalid','commit','-qm','seed')
    (stub/'lsof').write_text('#!/bin/sh\nexit 1\n')
    (stub/'ps').write_text("#!/usr/bin/env python3\nimport subprocess,sys\nif sys.argv[-1]=='ppid=': sys.exit(subprocess.run(['/bin/ps',*sys.argv[1:]]).returncode)\nprint('Thu Oct 1 00:00:00 2099')\n")
    (stub/'herdr').write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
a=sys.argv[1:]; file=Path(os.environ['PL_NATIVE']); s=json.loads(file.read_text()) if file.exists() else {}
with open(os.environ['PL_LOG'],'a') as log: print(json.dumps(a,ensure_ascii=False),file=log)
p=os.environ['PL_PROJECT']; pid=int(os.environ['PL_PID'])
def out(d): print(json.dumps({'result':d}))
if a[:2]==['workspace','list']: out({'workspaces':[{'workspace_id':'ws','worktree':{'repo_root':p,'is_linked_worktree':False}}]})
elif a[:2]==['tab','create']:
 label=a[a.index('--label')+1];pane='planner-pane' if label=='规划' else ('gate-pane' if label=='门禁' else 'worker-'+label)
 out({'root_pane':{'pane_id':pane,'tab_id':'tab-'+pane,'terminal_id':'terminal-'+pane}})
elif a[:2]==['agent','get']: print(json.dumps({'error':{'code':'agent_not_found'}}));sys.exit(1)
elif a[:2]==['agent','start']:
 v=a[a.index('--')+1:]; pane=a[a.index('--pane')+1]
 if '--session-id' in v:
  sid=v[v.index('--session-id')+1];sd=v[v.index('--session-dir')+1];s[pane]={'session':sd+'/2099_'+sid+'.jsonl'}
 out({'type':'agent_started'})
elif a[:2]==['pane','get']:
 pane=a[2]; live=pane=='ctl' or pane in s;d={'pane_id':pane,'workspace_id':'ws','terminal_id':'terminal-'+pane,'foreground_cwd':p}
 if live:d.update(agent='pi',agent_status='idle',agent_session={'agent':'pi','source':'herdr:pi','kind':'path','value':s.get(pane,{}).get('session','ctl-session')})
 out({'pane':d})
elif a[:2]==['pane','process-info']:
 pane=a[-1];live=pane=='ctl' or pane in s;i=pid if live else 42
 out({'process_info':{'pane_id':pane,'shell_pid':42,'foreground_process_group_id':i,'foreground_processes':[{'pid':i,'argv0':'pi' if live else 'zsh','argv':['pi'],'cwd':p}]}})
elif a[:2]==['pane','read']:print('(openai-codex) gpt-6.1-sol • high');sys.exit()
elif a[:2] in (['agent','prompt'],['pane','run'],['tab','close']):out({'type':'ok'})
else:sys.exit(77)
file.write_text(json.dumps(s))
''')
    for file in stub.iterdir(): file.chmod(0o755)
    log=temp/'native-calls.jsonl'
    env=os.environ|{'PATH':str(stub)+':'+os.environ['PATH'],'HERDR_PANE_ID':'ctl','PL_NATIVE':str(temp/'native.json'),'PL_PROJECT':str(p),'PL_PID':str(os.getpid()),'PL_LOG':str(log)}
    diagnostic=os.environ.get('QWB_PLANNING_DIAGNOSTIC_DIR')
    diagnostic=Path(diagnostic) if diagnostic else None
    if diagnostic: diagnostic.mkdir(parents=True,exist_ok=False)
    if fixture:
        (temp/'fixture-env.json').write_text(json.dumps({k:env[k] for k in ['PATH','PL_NATIVE','PL_PROJECT','PL_PID','PL_LOG']}|{'source_root':str(ROOT),'note':'仅fakeHerdr fixture。PL_PID与角色PID为本轮测试父进程，测试结束后不能声称仍活；独立复现须显式重建原生边界替身。'},ensure_ascii=False))
    def process_chain(pid):
        table=subprocess.check_output(['/bin/ps','-axo','pid=,ppid=,state=,etime=,wchan=,command='],text=True)
        rows=[line for line in table.splitlines() if len(line.split(None,4))==5]
        children={pid}
        for _ in range(64):
            grown=children|{int(line.split(None,4)[0]) for line in rows if int(line.split(None,4)[1]) in children}
            if grown==children: break
            children=grown
        return '\n'.join(line for line in rows if int(line.split(None,4)[0]) in children)+'\n'
    step=0
    def cli(script,*args,ok=True,actor='ctl'):
        global step
        step+=1; verb=str(args[0]) if args else 'status'; label=f'{step:03}-{verb}'
        argv=['bash',str(ROOT/'bin'/script),*map(str,args)]
        if script!='qwb-ledger.sh': argv+=['--project',str(p)]
        if diagnostic: print(f'DIAG start {label} actor={actor}',flush=True)
        target=verb in ('gate-assign','plan-revision','revision-handoff')
        bound=20 if target else 90
        started=time.monotonic(); started_at=time.time()
        child_env=env|{'HERDR_PANE_ID':actor}
        if diagnostic and script in ('qwb-run.sh','qwb-wake.sh'):
            argv.insert(1,'-x'); child_env['PS4']='+qwb-cli seconds=${SECONDS} pid=$$ line=${LINENO}: '
        process=subprocess.Popen(argv,env=child_env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
        if diagnostic:
            (diagnostic/(label+'-command.json')).write_text(json.dumps({'argv':argv,'actor':actor,'pid':process.pid,'timeout_seconds':bound,'started_at':started_at},ensure_ascii=False))
            if target:(diagnostic/(label+'-start-processes.txt')).write_text(process_chain(process.pid))
        try:
            while True:
                remaining=bound-(time.monotonic()-started)
                if remaining<=0:raise subprocess.TimeoutExpired(argv,bound)
                try:
                    out,err=process.communicate(timeout=min(5,remaining)); break
                except subprocess.TimeoutExpired:
                    if diagnostic and target:
                        age=time.monotonic()-started
                        (diagnostic/(label+f'-age-{age:.1f}-processes.txt')).write_text(process_chain(process.pid))
                    if time.monotonic()-started>=bound:raise
        except subprocess.TimeoutExpired:
            # 只读本次目标后代链；各子调用年龄单列，不能把父累计成本冒充持锁等待。
            chain=process_chain(process.pid)
            if diagnostic:
                (diagnostic/(label+'-processes.txt')).write_text(chain)
                (diagnostic/(label+'-command.json')).write_text(json.dumps({'argv':argv,'actor':actor,'pid':process.pid,'timeout_seconds':bound,'started_at':started_at,'ended_at':time.time(),'elapsed_seconds':time.monotonic()-started},ensure_ascii=False))
                shutil.copytree(p/'tasks',diagnostic/(label+'-tasks'))
                if log.exists():shutil.copy(log,diagnostic/(label+'-native-calls.jsonl'))
            print(f'DIAG timeout {label}\n{chain}',flush=True)
            os.killpg(process.pid,signal.SIGTERM)
            try: out,err=process.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid,signal.SIGKILL); out,err=process.communicate()
            if diagnostic:
                (diagnostic/(label+'.stdout')).write_text(out);(diagnostic/(label+'.stderr')).write_text(err)
            raise AssertionError(f'有界单步超时：{label}；原始子进程码={process.returncode}（测试主动终止，不是公开入口自然退出）')
        r=subprocess.CompletedProcess(argv,process.returncode,out,err)
        if diagnostic:
            (diagnostic/(label+'.json')).write_text(json.dumps({'actor':actor,'rc':r.returncode,'started_at':started_at,'ended_at':time.time(),'elapsed_seconds':time.monotonic()-started},ensure_ascii=False))
            if target:(diagnostic/(label+'-end-processes.txt')).write_text(process_chain(process.pid))
            (diagnostic/(label+'.stdout')).write_text(out);(diagnostic/(label+'.stderr')).write_text(err)
            print(f'DIAG end {label} rc={r.returncode}',flush=True)
        assert (r.returncode==0)==ok,(script,args,r.returncode,r.stdout,r.stderr)
        return r
    def call(verb,task='intake.md',*args,ok=True,actor='ctl'):
        return cli('qwb-ledger.sh',verb,'--project',p,'--task',p/'tasks'/task,*args,ok=ok,actor=actor)
    def read(task): return json.loads(call('read',task).stdout)
    def payload(name,data):
        f=temp/name; f.write_text(json.dumps(data,ensure_ascii=False)); return f
    def source(corr,text): return call('handoff-send','intake.md','--','controller',corr,'1',text).stdout.strip()
    def run(task,ok=True,actor='ctl',worker='sol'):
        return cli('qwb-run.sh','--task',p/'tasks'/task,'--worker',worker,'--here',ok=ok,actor=actor)
    def no_dispatch_since(offset):
        calls=[json.loads(s) for s in log.read_text().splitlines()[offset:]] if log.exists() else []
        assert not any(a[:2] in (['tab','create'],['agent','start'],['agent','prompt'],['pane','run'],['worktree','open']) for a in calls),calls
    def count(): return len(log.read_text().splitlines()) if log.exists() else 0
    scenarios='## 验收场景\n### user_good\nGiven project\nWhen request\nThen result persists\n### user_failure\nGiven invalid request\nWhen dispatch\nThen 拒绝'
    intake=p/'tasks/intake.md'; intake.write_text('# 需求入口\nstate: running\n'+scenarios+'\n')
    proof=payload('migration.json',{'task_sha256':hashlib.sha256(intake.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}})
    call('migrate','intake.md','--',proof)
    event=source('request-one','原话：A接口v1；B用此接口；C独立')
    request={'request_id':'request-one','package_id':'A','packages':{'A':'A.md','B':'B.md','C':'C.md'},'source_task':'intake.md','source_event':event,'intent':'用户需要接口','spec':'实现接口v1','constraints':'单机，不联网','scenarios':scenarios,'paths':['api.sh'],'needs':{'start':[],'accept':[],'land':[]}}
    req=payload('new.json',request); call('new','A.md','--',req)
    before=(p/'tasks/A.md').read_bytes(); call('new','A.md','--',req)
    assert (p/'tasks/A.md').read_bytes()==before
    a=read('A.md'); assert a['planning']['source']['text']=='原话：A接口v1；B用此接口；C独立'
    assert a['planning']['packages']=={'A':'A.md','B':'B.md','C':'C.md'}
    conflicting=dict(request,package_id='A',packages={'A':'other.md'})
    call('new','other.md','--',payload('conflict.json',conflicting),ok=False)
    assert not (p/'tasks/other.md').exists()
    mark=count(); run('A.md',ok=False); no_dispatch_since(mark)
    old=p/'tasks/old.md'; old.write_text('# 旧票无实施授权\nstate: running\n'+scenarios+'\n')
    mark=count(); run('old.md',ok=False); no_dispatch_since(mark)
    print('PASS user_可重放需求与真实就绪：持久source/一次request包映射；重放逐字节不变；旧running未授权拒绝')
    # 启用既有02身份、主控受限授权、03持久request；不靠角色字符串授权。
    for actor,role in [('planner','规划'),('gate','门禁')]:cli('qwb-role.sh','start','--actor',actor,'--role',role,'--worker','sol','--dir',p)
    approval={'workers':['sol'],'permissions':[],'evidence':'fixture explicit implementation approval; no paid operations','budget':1}
    grant=dict(approval,request_id='request-one',source_event=event,packages=request['packages'],paths=['api.sh'])
    call('plan-assign','intake.md','--','planner',payload('grant.json',grant))
    # 规划实际办理03持久请求，而非只看到角色文字或API已投递。
    cli('qwb-send.sh','pending','--task',intake,actor='planner-pane')
    cli('qwb-send.sh','received','--task',intake,'--event',event,actor='planner-pane')
    cli('qwb-send.sh','accept','--task',intake,'--event',event,'--op','plan-request',actor='planner-pane')
    cli('qwb-send.sh','prepared','--task',intake,'--event',event,'--op','plan-request',actor='planner-pane')
    ack=p/'tasks/plan-request.json'; ack.write_text(json.dumps({'event_id':event,'op_id':'plan-request','outcome':'applied','evidence':'公开read核对同request映射与source'}))
    cli('qwb-send.sh','handled','--task',intake,'--event',event,'--op','plan-request','--result-ref',ack,actor='planner-pane')
    assert read('intake.md')['handoffs'][event]['handled']==1
    before=intake.read_bytes()
    call('append','intake.md','--','working: spec-resolved: planner grant cannot answer spec',actor='planner-pane',ok=False)
    assert intake.read_bytes()==before
    def accept_land_checks():
        # 沿用04的Pi JSONL外部证据fixture；不启动真实审核代理，私有true门不是仓库full验收。
        change=source('acceptance-request','原话：StageB验收需StageA accepted，落地需StageA landed')
        packages={'StageA':'StageA.md','StageB':'StageB.md'}
        stage_request=dict(request,request_id='acceptance-request',package_id='StageA',packages=packages,source_event=change)
        call('new','StageA.md','--',payload('stage-A.json',stage_request))
        def status_dependencies(expected):
            before={f.name:f.read_bytes() for f in (p/'tasks').glob('*.md')}
            output=cli('qwb-status.sh').stdout
            for stage,condition in expected.items():
                assert f'依赖[{stage}]: StageA.md/api@v1 spec_rev=0 condition={condition}' in output, output
            if not expected: assert '依赖[' not in output, output
            assert before=={f.name:f.read_bytes() for f in (p/'tasks').glob('*.md')}, 'status must remain read-only'
        status_only=os.environ.get('QWB_PLANNING_STATUS_ONLY')=='1'
        if status_only: status_dependencies({})
        edge={'task':'StageA.md','artifact':'api','version':'v1','spec_rev':0,'condition':'accepted'}
        stage_needs={'start':[dict(edge,condition='available')] if status_only else [],'accept':[edge],'land':[dict(edge,condition='landed')]}
        call('new','StageB.md','--',payload('stage-B.json',dict(stage_request,package_id='StageB',needs=stage_needs)))
        status_dependencies({'start':'available','accept':'accepted','land':'landed'} if status_only else {'accept':'accepted','land':'landed'})
        if status_only:
            print('PASS public status: empty and nonempty start/accept/land, literal @ and frozen fields; ledger bytes unchanged')
            return
        artifact=temp/'stage-api-v1'; artifact.write_text('stage interface v1\n')
        call('plan-artifact','StageA.md','--',payload('stage-artifact.json',{'name':'api','version':'v1','ref':str(artifact)}))
        environment=temp/'stage-environment'; environment.write_text('private fixture dependencies v1\n')
        assignment={'candidate':str(p),'base':git('rev-parse','HEAD'),'attempt':'1','policy':'existing-v1','environment':str(environment),'required':{'full':['user_good','user_failure']},'workers':{'review':'reviewer','rework':'sol'}}
        def session(name,provider,model,effort,family):
            f=temp/(name+'.jsonl')
            records=[{'type':'session','id':name,'cwd':str(p)},{'type':'model_change','provider':provider,'modelId':model},{'type':'thinking_level_change','thinkingLevel':effort}]
            f.write_text(''.join(json.dumps(r)+'\n' for r in records))
            return {'model':model,'family':family,'session':name,'evidence':str(f)}
        implementer=session('stage-implementation','openai-codex','gpt-6.1-sol','high','gpt')
        reviewer=session('stage-review','anthropic','claude-opus-4-6','low','claude')
        for task,op in [('StageA.md','accept-stage-A'),('StageB.md','accept-stage-B')]:
            call('gate-assign',task,'--','gate',payload(task+'.gate.json',assignment))
            call('claim',task,'--',op,actor='gate-pane')
            report=temp/(task+'.receipt.json')
            cli('qwb-test.sh','full','--task',p/'tasks'/task,'--ledger-project',p,'--op',op,'--report',report,actor='gate-pane')
            receipt=json.loads(report.read_text()); assert receipt['rc']==0
            review={'context':receipt['after'],'implementer':implementer,'reviewer':reviewer,'standards':'pass','spec':'pass','covered':['user_good','user_failure'],'findings':[]}
            call('gate-review',task,'--',op,payload(task+'.review.json',review),actor='gate-pane')
        # 同候选成功收据/独立session格式不绕过前置accepted/landed；拒绝不改票。
        before=(p/'tasks/StageB.md').read_bytes()
        call('gate-verdict','StageB.md','--','accept-stage-B','accepted',actor='gate-pane',ok=False)
        assert (p/'tasks/StageB.md').read_bytes()==before
        call('gate-verdict','StageA.md','--','accept-stage-A','accepted',actor='gate-pane')
        call('gate-verdict','StageB.md','--','accept-stage-B','accepted',actor='gate-pane')
        b=read('StageB.md'); resolved=b['planning']['ready']['accept_evidence']
        assert len(resolved)==1 and resolved[0]['condition']=='accepted' and resolved[0]['version']=='v1' and resolved[0]['spec_rev']==0 and resolved[0]['sha256']==hashlib.sha256(artifact.read_bytes()).hexdigest()
        before=(p/'tasks/StageB.md').read_bytes()
        call('plan-land','StageB.md','--','private fixture landing evidence B',ok=False)
        assert (p/'tasks/StageB.md').read_bytes()==before
        call('plan-land','StageA.md','--','private fixture landing evidence A; no merge performed')
        call('plan-land','StageB.md','--','private fixture landing evidence B; no merge performed')
        b=read('StageB.md'); resolved=b['planning']['landed']['dependencies']
        assert b['gate']['verdict']=='accepted' and b['phase']!='verified' and len(resolved)==1 and resolved[0]['condition']=='landed' and resolved[0]['version']=='v1' and resolved[0]['spec_rev']==0 and resolved[0]['sha256']==hashlib.sha256(artifact.read_bytes()).hexdigest()
        evidence=os.environ.get('QWB_PLANNING_STAGE_EVIDENCE_DIR')
        if evidence:
            dest=Path(evidence); dest.mkdir(parents=True,exist_ok=False)
            for task in ['StageA.md','StageB.md']:
                (dest/(task+'.json')).write_text(call('read',task).stdout); shutil.copy(p/'tasks'/task,dest/task)
                for suffix in ['.receipt.json','.review.json']: shutil.copy(temp/(task+suffix),dest/(task+suffix))
            for name in ['stage-implementation.jsonl','stage-review.jsonl']: shutil.copy(temp/name,dest/name)
            shutil.copy(log,dest/'fake-herdr.jsonl')
            (dest/'README.md').write_text('临时Git+fakeHerdr/外部Pi JSONL证据fixture；true门仅供依赖阶段契约，未跑仓库full、真实审核或生产merge。\n')
        print('PASS accept/land正向公开契约：available不等accepted、不等landed；指定版本解除证据同票保存，未merge/自动verified')
    if os.environ.get('QWB_PLANNING_ACCEPT_LAND_ONLY')=='1' or os.environ.get('QWB_PLANNING_STATUS_ONLY')=='1':
        accept_land_checks()
        raise SystemExit(0)
    if os.environ.get('QWB_PLANNING_REQUEST_ONLY')=='1':
        print('PASS 规划03办理/受限source原话接缝；不能写主控spec-resolved，拒绝逐字节不变')
        raise SystemExit(0)
    edge={'task':'A.md','artifact':'api','version':'v1','spec_rev':0,'condition':'available'}
    brequest=dict(request,package_id='B',spec='使用接口v1',needs={'start':[edge],'accept':[],'land':[]})
    call('new','B.md','--',payload('B.json',brequest),actor='planner-pane')
    crequest=dict(request,package_id='C',spec='独立C')
    call('new','C.md','--',payload('C.json',crequest),actor='planner-pane')
    call('new','C.md','--',temp/'C.json',actor='planner-pane')
    call('new','unauthorized.md','--',payload('unauthorized.json',dict(request,package_id='evil',packages={'evil':'unauthorized.md'})),actor='planner-pane',ok=False)
    call('plan-authorize','A.md','--',payload('approval.json',approval))
    mark=count(); run('B.md',ok=False,actor='planner-pane'); no_dispatch_since(mark)
    # 代码监督只登记阻塞/就绪并按02授权通知规划，不直接启动任何新工人。
    mark=count(); cli('qwb-wake.sh','--once','--pane','ctl')
    calls=[json.loads(s) for s in log.read_text().splitlines()[mark:]]
    assert not any(a[:2] in (['tab','create'],['agent','start'],['agent','prompt']) for a in calls)
    assert any(a[:3]==['pane','run','planner-pane'] for a in calls)
    assert read('B.md')['planning']['ready']['status']=='blocked'
    c_before=read('C.md'); call('plan-ready','C.md',actor='planner-pane'); ready=read('C.md')
    call('plan-ready','C.md',actor='planner-pane'); assert read('C.md')['rev']==ready['rev']
    run('C.md',actor='planner-pane'); c_running=read('C.md')
    assert len([e for e in c_running['events'] if e['kind']=='dispatch'])==1 and c_running['claim'] is None
    mark=count(); run('C.md',actor='planner-pane',ok=False); no_dispatch_since(mark)
    artifact=temp/'api-v1'; artifact.write_text('interface v1\n')
    call('plan-artifact','A.md','--',payload('artifact.json',{'name':'api','version':'v1','ref':str(artifact)}))
    mark=count(); cli('qwb-wake.sh','--once','--pane','ctl')
    calls=[json.loads(s) for s in log.read_text().splitlines()[mark:]]
    assert not any(a[:2] in (['tab','create'],['agent','start'],['agent','prompt']) for a in calls)
    b=read('B.md'); assert b['planning']['ready']['status']=='ready'
    c_running=read('C.md'); assert len([e for e in c_running['events'] if e['kind']=='dispatch'])==1 and c_running['claim'] is None
    assert b['planning']['ready']['evidence'][0]['sha256']==hashlib.sha256(artifact.read_bytes()).hexdigest()
    assert not read('A.md').get('gate') and read('A.md')['phase']=='blocked', '接口就绪被错误地等同合并/accepted'
    call('plan-ready','B.md',actor='planner-pane'); assert read('B.md')['rev']==b['rev']
    # 缺票/自依赖/环/歧义/旧版产物均使用公开首次派发入口拒绝，无dispatch副作用。
    for label,bad in [('missing',dict(edge,task='missing.md')),('self',dict(edge,task='B.md')),('ambiguous',dict(edge,task='A')),('old-version',dict(edge,version='v0')),('unaccepted',dict(edge,condition='accepted')),('unlanded',dict(edge,condition='landed'))]:
        current=read('B.md'); raw=(p/'tasks/B.md').read_bytes()
        needs={'start':[bad],'accept':[],'land':[]}
        valid_edge=label in ('old-version','unaccepted','unlanded')
        call('plan-needs','B.md','--expect',current['rev'],'--',payload('needs.json',needs),actor='planner-pane',ok=valid_edge)
        if not valid_edge: assert (p/'tasks/B.md').read_bytes()==raw
        mark=count()
        if valid_edge: run('B.md',ok=False,actor='planner-pane')
        no_dispatch_since(mark)
        if valid_edge:call('plan-needs','B.md','--expect',read('B.md')['rev'],'--',payload('restore.json',brequest['needs']),actor='planner-pane')
    # 第一次入口重读真实前置票：票消失或产物字节改变均拒绝，恢复原字节后继续。
    a_path=p/'tasks/A.md'; saved=temp/'A-held.md'; a_path.rename(saved)
    try:
        mark=count(); run('B.md',actor='planner-pane',ok=False); no_dispatch_since(mark)
    finally:saved.rename(a_path)
    original_artifact=artifact.read_bytes(); artifact.write_text('changed interface\n')
    try:
        mark=count(); run('B.md',actor='planner-pane',ok=False); no_dispatch_since(mark)
    finally:artifact.write_bytes(original_artifact)
    # A->B->A真实环；不能把U/C整体暂停。
    raw=(p/'tasks/A.md').read_bytes()
    call('plan-needs','A.md','--expect',read('A.md')['rev'],'--',payload('cycle.json',{'start':[dict(edge,task='B.md')],'accept':[],'land':[]}),ok=False)
    assert (p/'tasks/A.md').read_bytes()==raw and read('C.md')==c_running
    if os.environ.get('QWB_PLANNING_DEPENDENCY_ONLY')=='1':
        print('PASS 指定available/accepted/landed不混同；缺失验收/落地证据拒绝，B无dispatch，C保持原字节')
        raise SystemExit(0)
    run('B.md',actor='planner-pane'); b_running=read('B.md')
    mark=count(); run('B.md',actor='planner-pane',ok=False); no_dispatch_since(mark)
    print('PASS user_非法依赖或未授权拒绝：真实02/03授权，B指定接口证据才可派；C继续；缺票/自依赖/环/歧义/旧版本拒绝，事件不重复派')
    # gate持claim期间登记修订不改旧正文；gate必须显式handoff，不能仅release绕过。
    environment=temp/'environment'; environment.write_text('fixture dependencies v1\n')
    binding={'candidate':str(p),'base':git('rev-parse','HEAD'),'attempt':'1','policy':'existing-v1','environment':str(environment),'required':{'full':['user_good','user_failure']},'workers':{'review':'reviewer','rework':'sol'}}
    assignment=payload('gate.json',binding); call('gate-assign','B.md','--','gate',assignment)
    call('claim','B.md','--','accept-B',actor='gate-pane')
    context=call('gate-context','B.md','--','accept-B',actor='gate-pane').stdout
    change=source('change-B','原话：B接口升级；C不变')
    revision={'source_task':'intake.md','source_event':change,'spec':'升级B接口','constraints':'单机，不联网','scenarios':scenarios,'needs':brequest['needs']}
    revfile=payload('revision.json',revision); old_spec=read('B.md')['planning']['spec']
    call('plan-revision','B.md','--expect',read('B.md')['rev'],'--',revfile,actor='planner-pane')
    assert read('B.md')['planning']['spec']==old_spec and read('B.md')['spec_rev']==0
    call('revise','B.md','--expect',read('B.md')['rev'],'--',change,actor='planner-pane',ok=False)
    call('revise-scenarios','B.md','--expect',read('B.md')['rev'],'--',scenarios,'bypass',ok=False)
    call('release','B.md','--','accept-B',actor='gate-pane')
    call('revise','B.md','--expect',read('B.md')['rev'],'--',change,actor='planner-pane',ok=False)
    call('claim','B.md','--','handoff-B',actor='gate-pane')
    stale=read('B.md')['rev']; call('revision-handoff','B.md','--','handoff-B','已停止旧规格验收',actor='gate-pane')
    call('revise','B.md','--expect',stale,'--',change,actor='planner-pane',ok=False)
    call('revise','B.md','--expect',read('B.md')['rev'],'--',change,actor='planner-pane')
    revised=read('B.md'); assert revised['spec_rev']==1 and revised['planning']['authorization'] is None and 'gate' not in revised
    assert revised['planning']['revisions'][0]['gate']['binding']['spec_rev']==0
    assert revised['planning']['source']['text']=='原话：A接口v1；B用此接口；C独立' and revised['planning']['revisions'][0]['source']['text']=='原话：B接口升级；C不变'
    assert read('C.md')==c_running
    call('gate-context','B.md','--','handoff-B',actor='gate-pane',ok=False)
    mark=count(); run('B.md',actor='planner-pane',ok=False); no_dispatch_since(mark)
    # 已verified历史不重写；新需求须后续票，拒绝时原MD逐字节保持。
    call('state','C.md','--','verified'); history=(p/'tasks/C.md').read_bytes()
    call('plan-revision','C.md','--expect',read('C.md')['rev'],'--',revfile,actor='planner-pane',ok=False)
    assert (p/'tasks/C.md').read_bytes()==history
    print('PASS user_变更使旧证据失效：CAS/显式gate handoff，旧binding保留且失效；原话不覆盖；C不中止；已验收历史拒绝重写')
    accept_land_checks()
    evidence=os.environ.get('QWB_PLANNING_EVIDENCE_DIR')
    if evidence:
        dest=Path(evidence);dest.mkdir(parents=True,exist_ok=False)
        for task in ['intake.md','A.md','B.md','C.md']:
            (dest/(task+'.json')).write_text(call('read',task).stdout);shutil.copy(p/'tasks'/task,dest/task)
        shutil.copy(log,dest/'fake-herdr.jsonl')
        (dest/'README.md').write_text('私有Git+fakeHerdr边界fixture；并非现场session/PID/生产交互证据。\n')
PY
