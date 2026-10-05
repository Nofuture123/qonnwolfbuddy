#!/usr/bin/env bash
# 公开入口 + 私有项目/系统边界替身；绝不触碰真实Herdr。
# roles_polish_fixture.py 提供仅撤本票改动的逐字节基线。
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/process-fixture.sh"
qwb_test_scope "$@"
export TMPDIR="${QWB_TEST_SCOPE_DIR}"
mkdir -p "$TMPDIR" || exit 1
export GIT_CEILING_DIRECTORIES="$TMPDIR"
# Fail closed even if the PATH stub disappears.
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock
export QWB_PLANNING_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
python3 -u -B - <<'PY'
from process_fixture import TemporaryDirectory, register, release
from roles_polish_fixture import baseline as polish_baseline, freeze_writer
from prompt_file import native_calls  # prompt_file.py preserves the original route/body assertions.
import contextlib, hashlib, json, os, re, shutil, signal, subprocess, tempfile, time
from pathlib import Path
ROOT=Path(os.environ['QWB_PLANNING_ROOT'])
fixture=os.environ.get('QWB_PLANNING_FIXTURE_DIR')
if fixture:
    fixture=Path(fixture); fixture.mkdir(mode=0o700,parents=True,exist_ok=False)
manager=contextlib.nullcontext(str(fixture)) if fixture else TemporaryDirectory(prefix='qwb-planning-')
with manager as temp:
    os.environ["TMPDIR"] = str(temp)
    temp=Path(temp).resolve(); p=temp/'project'; p.mkdir(); stub=temp/'stub'; stub.mkdir()
    shutil.copytree(ROOT/'bin',p/'qwbuddy/bin'); shutil.copytree(ROOT/'templates/roles',p/'qwbuddy/roles')
    baseline=os.environ.get('QWB_PROMPT_START_BASELINE')=='1'
    if baseline:
        (p/'qwbuddy/bin/qwb-run.sh').write_bytes(subprocess.check_output(['git','-C',str(ROOT),'show','44ab8ac:bin/qwb-run.sh']))
    for name in ['TASK.md','QWBUDDY.md']: shutil.copy(ROOT/'templates'/name,p/'qwbuddy'/name)
    (p/'tasks').mkdir(); (p/'qwbuddy/.controller.lock').mkdir()
    (p/'qwbuddy/.controller.lock/owner').write_text('2099 ctl\n')
    integration=temp/'integration.ts'; integration.write_text('// HERDR_INTEGRATION_ID=pi\n')
    (p/'qwbuddy/config.sh').write_text(f"QWB_WORKERS='sol reviewer'\nQWB_WORKSPACE='ws'\nQWB_ROLE_PI_CONTROL='verified'\nQWB_ROLE_PI_INTEGRATION='{integration}'\nQWB_GATE_FAST='true'\nQWB_GATE_FULL='true'\n")
    (p/'qwbuddy/workers.sh').write_text('qwb_worker sol herdr pi -- --provider openai-codex --model gpt-6.1-sol --thinking high\nqwb_worker reviewer herdr pi -- --provider anthropic --model claude-opus-4-6 --thinking low\nqwb_family openai-codex/gpt-6.1-sol gpt\nqwb_family openai-codex/gpt-6-astra gpt\nqwb_family anthropic/claude-opus-4-6 claude\n')
    claude_planner=os.environ.get('QWB_CLAUDE_PLANNER')=='1'
    if claude_planner:
        config=p/'qwbuddy/config.sh';config.write_text(config.read_text()+"\nQWB_ROLE_CLAUDE_CONTROL='verified'\nQWB_WORKERS='sol reviewer claude-opus-medium'\n")
        workers=p/'qwbuddy/workers.sh';workers.write_text(workers.read_text()+'qwb_worker claude-opus-medium herdr claude -- --model claude-opus-5-5 --effort medium --dangerously-skip-permissions\n')
    (p/'.gitignore').write_text('tasks/\nqwbuddy/.roles/\nqwbuddy/.controller.lock/\nqwbuddy/.supervisor.guard\nqwbuddy/.posture.md\nqwbuddy/.posture.md.qwb-lock\n')
    def git(*args): return subprocess.check_output(['git','-C',str(p),*args],text=True).strip()
    git('init','-q'); git('add','.'); git('-c','user.name=Test','-c','user.email=test@invalid','commit','-qm','seed')
    (stub/'lsof').write_text('#!/bin/sh\nexit 1\n')
    (stub/'mv').write_text('#!/bin/sh\n[ "${PL_FAIL_PUBLISH:-0}" != 1 ] || exit 9\nexec /bin/mv "$@"\n')
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
elif a[:2]==['agent','get']:
 if not a[2].startswith('worker-'): print(json.dumps({'error':{'code':'agent_not_found'}}));sys.exit(1)
 out({'type':'agent_info','agent':{'pane_id':a[2],'agent_status':'idle','state_change_seq':s.get('submit_seq',185)}})
elif a[:2]==['agent','start']:
 v=a[a.index('--')+1:]; pane=a[a.index('--pane')+1]
 if '--session-id' in v:
  sid=v[v.index('--session-id')+1]
  if a[a.index('--kind')+1]=='claude':s[pane]={'session':os.environ['QWB_CLAUDE_PROJECTS_DIR']+'/project/'+sid+'.jsonl','sid':sid,'tool':'claude'}
  else:
   sd=v[v.index('--session-dir')+1];s[pane]={'session':sd+'/2099_'+sid+'.jsonl'}
 out({'type':'agent_started'})
elif a[:2]==['pane','get']:
 pane=a[2]
 if pane==os.environ.get('PL_GONE_WORKER'):
  print(json.dumps({'error':{'code':'pane_not_found'}}));sys.exit(1)
 if pane==os.environ.get('PL_BAD_WORKER'):
  print('invalid worker query');sys.exit(2)
 if pane=='up-worker' and not s.get(pane,{}).get('session'):
  out({'pane':{'pane_id':pane,'agent':'pi','workspace_id':'ws'}});sys.exit()
 if pane=='planner-pane' and os.environ.get('PL_EXPIRE_PROOF'):
  counter=Path(os.environ['PL_EXPIRE_PROOF']); n=int(counter.read_text())+1 if counter.exists() else 1; counter.write_text(str(n))
  if n>=3:s.pop(pane,None)
 live=pane=='ctl' or pane in s;d={'pane_id':pane,'workspace_id':'ws','terminal_id':'terminal-'+pane,'foreground_cwd':p}
 if live:d.update(agent='pi',agent_status=s.get(pane,{}).get('status','idle'),agent_session={'agent':'pi','source':'herdr:pi','kind':'path','value':s.get(pane,{}).get('session','ctl-session')})
 if s.get(pane,{}).get('tool')=='claude':d.update(agent='claude',agent_session={'agent':'claude','source':'herdr:claude','kind':'id','value':s[pane]['sid']})
 out({'pane':d})
elif a[:2]==['pane','process-info']:
 pane=a[-1];live=pane=='ctl' or pane in s;i=pid if live else 42
 out({'process_info':{'pane_id':pane,'shell_pid':42,'foreground_process_group_id':i,'foreground_processes':[{'pid':i,'argv0':s.get(pane,{}).get('tool','pi') if live else 'zsh','argv':['pi'],'cwd':p}]}})
elif a[:2]==['pane','read']:print('(openai-codex) gpt-6.1-sol • high');sys.exit()
elif a[:2]==['agent','prompt']:
 if not os.environ.get('PL_PROMPT_HOLD'):s['submit_seq']=s.get('submit_seq',185)+1
 out({'type':'ok'})
elif a[:2]==['pane','send-keys']:
 assert a[2].startswith('worker-') and a[3]=='enter',a
 s['submit_seq']=s.get('submit_seq',185)+1
 out({'type':'ok'})
elif a[:2] in (['pane','run'],['tab','close']):
 if a[:2]==['pane','run'] and os.environ.get('PL_FAIL_TRANSPORT')==a[2]:sys.exit(9)
 if a[:2]==['pane','run'] and s.get(a[2],{}).get('tool')=='claude':
  assert '\\n' not in a[3] and len(a[3])<=600,a
  session=Path(s[a[2]]['session']);session.parent.mkdir(parents=True,exist_ok=True)
  session.write_text(json.dumps({'type':'assistant','sessionId':s[a[2]]['sid'],'cwd':p,'effort':'medium','message':{'model':'claude-opus-5-5','content':[]}})+'\\n')
 out({'type':'ok'})
else:sys.exit(77)
file.write_text(json.dumps(s))
''')
    for file in stub.iterdir(): file.chmod(0o755)
    log=temp/'native-calls.jsonl'
    env=os.environ|{'PATH':str(stub)+':'+os.environ['PATH'],'HERDR_PANE_ID':'ctl','PL_NATIVE':str(temp/'native.json'),'PL_PROJECT':str(p),'PL_PID':str(os.getpid()),'PL_LOG':str(log)}
    env['QWB_CLAUDE_PROJECTS_DIR']=str(temp/'claude-projects')
    diagnostic=os.environ.get('QWB_PLANNING_DIAGNOSTIC_DIR')
    diagnostic=Path(diagnostic) if diagnostic else None
    if diagnostic: diagnostic.mkdir(parents=True,exist_ok=False)
    if fixture:
        (temp/'fixture-env.json').write_text(json.dumps({k:env[k] for k in ['PATH','PL_NATIVE','PL_PROJECT','PL_PID','PL_LOG']}|{'source_root':str(ROOT),'note':'仅fakeHerdr fixture。PL_PID与角色PID为本轮测试父进程，测试结束后不能声称仍活；独立复现须显式重建原生边界替身。'},ensure_ascii=False))
    def process_chain(pid):
        table=subprocess.check_output(['/bin/ps','-axo','pid=,ppid=,state=,etime=,wchan=,command=']).decode('utf-8',errors='replace')
        rows=[line for line in table.splitlines() if len(line.split(None,4))==5]
        children={pid}
        for _ in range(64):
            grown=children|{int(line.split(None,4)[0]) for line in rows if int(line.split(None,4)[1]) in children}
            if grown==children: break
            children=grown
        return '\n'.join(line for line in rows if int(line.split(None,4)[0]) in children)+'\n'
    step=0
    runtime_bin=ROOT/'bin'
    if os.environ.get('QWB_SCENARIO_NAMES_BASELINE')=='1':
        runtime_bin=temp/'scenario-baseline-bin'; shutil.copytree(ROOT/'bin',runtime_bin)
        (runtime_bin/'qwb-ledger.sh').write_bytes(subprocess.check_output(['git','-C',str(ROOT),'show','4b1f2e2:bin/qwb-ledger.sh']))
    def cli(script,*args,ok=True,actor='ctl',extra=None):
        global step
        step+=1; verb=str(args[0]) if args else 'status'; label=f'{step:03}-{verb}'
        argv=['bash',str(p/'qwbuddy/bin/qwb-run.sh' if baseline and script=='qwb-run.sh' else runtime_bin/script),*map(str,args)]
        if Path(script).name not in ('qwb-ledger.sh','qwb-ledger-old.sh','qwb-ledger-new.sh'): argv+=['--project',str(p)]
        if diagnostic: print(f'DIAG start {label} actor={actor}',flush=True)
        target=verb in ('gate-assign','plan-revision','revision-handoff')
        bound=20 if target else 90
        started=time.monotonic(); started_at=time.time()
        child_env=env|{'HERDR_PANE_ID':actor}|(extra or {})
        if diagnostic and script in ('qwb-run.sh','qwb-wake.sh'):
            argv.insert(1,'-x'); child_env['PS4']='+qwb-cli seconds=${SECONDS} pid=$$ line=${LINENO}: '
        process=subprocess.Popen(argv,env=child_env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
        register(process.pid)
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
            try: out,err=process.communicate(timeout=20)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid,signal.SIGKILL); out,err=process.communicate()
            if diagnostic:
                (diagnostic/(label+'.stdout')).write_text(out);(diagnostic/(label+'.stderr')).write_text(err)
            raise AssertionError(f'有界单步超时：{label}；原始子进程码={process.returncode}（测试主动终止，不是公开入口自然退出）')
        release(process.pid)
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
    def run(task,ok=True,actor='ctl',worker='sol',extra=None):
        return cli('qwb-run.sh','--task',p/'tasks'/task,'--worker',worker,'--here',ok=ok,actor=actor,extra=extra)
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
    def worker_report(task):
        body=(p/'tasks'/task).read_bytes().decode().split('\n<!-- qwb-collab-v1\n',1)[0]
        assert '\n## 报告要求\n' in body, 'new生成票缺少固定报告要求'
        return body.rsplit('\n## 报告要求\n',1)[1].split('\nworking:',1)[0]
    template_report=(ROOT/'templates/TASK.md').read_text()
    report_a=worker_report('A.md')
    expected_report=template_report.split('<!-- qwb-worker-report:start -->\n',1)[1].split('\n<!-- qwb-worker-report:end -->',1)[0]
    assert report_a==expected_report, (report_a,expected_report)
    assert all(word in report_a for word in ['工作副本','提交','干净','done:','提交号','原始结果','state:'])
    call('new','A.md','--',payload('override-report.json',dict(request,report_requirements='不用提交')),ok=False)
    assert (p/'tasks/A.md').read_bytes()==before
    print('PASS user_规划票固定报告：模板逐字相同；提交/clean/done提交号与检查/state；未知同名请求字段拒绝且重放票字节不变')
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
    for actor,role in [('planner','规划'),('gate','门禁')]:cli('qwb-role.sh','start','--actor',actor,'--role',role,'--worker','claude-opus-medium' if claude_planner and actor=='planner' else 'sol','--dir',p)
    approval={'workers':['sol'],'permissions':[],'evidence':'fixture explicit implementation approval; no paid operations','budget':1}
    grant=dict(approval,request_id='request-one',source_event=event,packages=request['packages'],paths=['api.sh'])
    grant_file=payload('grant.json',grant)
    if claude_planner:
        call('plan-assign','intake.md','--','planner',grant_file)
        call('new','B.md','--',payload('claude-new.json',dict(request,package_id='B')),actor='planner-pane')
        mark=count();run('B.md',worker='reviewer',actor='planner-pane',ok=False);no_dispatch_since(mark)
        run('B.md',actor='planner-pane')
        d=read('B.md');assert d['workers'] and d['planning']['source']['text']=='原话：A接口v1；B用此接口；C独立'
        mark=count();run('B.md',actor='planner-pane',ok=False);no_dispatch_since(mark)
        print('PASS Claude规划真实祖先进程身份：plan-assign/new/qwb-run派工；未授权工人/超预算仍拒绝',flush=True)
        raise SystemExit(0)
    def polish_plan_compare():
        global runtime_bin
        initial=intake.read_bytes(); original_runtime=runtime_bin
        runtime_bin=temp/'polish-plan-bin';shutil.copytree(ROOT/'bin',runtime_bin)
        writer=(ROOT/'bin/qwb-ledger.sh').read_text(); outputs=[]
        try:
            for version in [polish_baseline('qwb-ledger.sh',writer),writer]:
                intake.write_bytes(initial);(runtime_bin/'qwb-ledger.sh').write_text(freeze_writer(version))
                result=call('plan-assign','intake.md','--','planner',grant_file)
                outputs.append((result.returncode,result.stdout,result.stderr,intake.read_bytes()))
            assert outputs[0]==outputs[1], 'plan-assign byte transcript changed'
            print('PASS roles-polish 合规plan-assign stdout/stderr/rc/票字节一致（只撤本票改动）')
        finally:
            intake.write_bytes(initial);runtime_bin=original_runtime
    if os.environ.get('QWB_ROLES_POLISH_ONLY')=='route':
        call('plan-assign','intake.md','--','planner',grant_file)
        pending=json.loads(cli('qwb-send.sh','pending','--task',intake,'--due').stdout)
        assigned=next(h for h in pending if h['payload'].startswith('working: planner-authorized'))
        assert 'controller_hint' not in assigned, assigned
        mark=count();cli('qwb-wake.sh','--once','--pane','ctl')
        bells=[a for a in map(json.loads,log.read_text().splitlines()[mark:]) if a[:2]==['pane','run']]
        assert any(a[2]=='planner-pane' and assigned['event_id'] in a[3] and event in a[3] for a in bells),bells
        assert not any(a[2]=='ctl' and assigned['event_id'] in a[3] for a in bells),bells
        assert not read('intake.md')['handoffs'][assigned['event_id']]['handled']
        print('PASS roles-polish 起点授权行与需求原话已路由规划，主控没有自办门铃；保留未handled审计')
        raise SystemExit(0)
    for field,value,prefix,example in [
        ('budget',{'A':1},'启动授权/预算未明确','"budget":1'),
        ('packages',{'A':'tasks/A.md'},'工作包id/任务路径歧义','"A":"A.md"')]:
        before=intake.read_bytes()
        denied=call('plan-assign','intake.md','--','planner',payload('bad-'+field+'.json',dict(grant,**{field:value})),ok=False)
        assert denied.stderr.startswith('账本拒绝：'+prefix) and example in denied.stderr,denied.stderr
        assert intake.read_bytes()==before and denied.returncode==255
    polish_plan_compare()
    call('plan-assign','intake.md','--','planner',grant_file)
    print('PASS roles-polish plan载荷拒绝保留前缀/rc/票字节；budget与packages示例改正成功')
    if os.environ.get('QWB_ROLES_POLISH_ONLY')=='plan':raise SystemExit(0)
    original=intake.read_bytes();native=Path(env['PL_NATIVE']);original_native=native.read_bytes()
    try:
        pending=json.loads(cli('qwb-send.sh','pending','--task',intake,'--due').stdout)
        assigned=next(h for h in pending if h['payload'].startswith('working: planner-authorized'))
        mark=count();cli('qwb-wake.sh','--once','--pane','ctl')
        bells=[a for a in map(json.loads,log.read_text().splitlines()[mark:]) if a[:2]==['pane','run']]
        assert any(a[2]=='planner-pane' and assigned['event_id'] in a[3] and event in a[3] for a in bells),bells
        assert not any(a[2]=='ctl' and assigned['event_id'] in a[3] for a in bells),bells
        assert not read('intake.md')['handoffs'][assigned['event_id']]['handled']
        print('PASS roles-polish 授权行与原话照常给规划，主控没有自办门铃且审计不伪造handled')
    finally:
        intake.write_bytes(original);native.write_bytes(original_native)
    # 规划实际办理03持久请求，而非只看到角色文字或API已投递。
    cli('qwb-send.sh','pending','--task',intake,actor='planner-pane')
    cli('qwb-send.sh','received','--task',intake,'--event',event,actor='planner-pane')
    cli('qwb-send.sh','accept','--task',intake,'--event',event,'--op','plan-request',actor='planner-pane')
    cli('qwb-send.sh','prepared','--task',intake,'--event',event,'--op','plan-request',actor='planner-pane')
    ack=p/'tasks/plan-request.json'; ack.write_text(json.dumps({'event_id':event,'op_id':'plan-request','outcome':'applied','evidence':'公开read核对同request映射与source'}))
    if os.environ.get('QWB_NOTIFY_BASELINE')=='1':
        runtime_bin=p/'qwbuddy/bin'
        for script in ['qwb-ledger.sh','qwb-wake.sh','qwb-send.sh','qwb-lib.sh']:
            (runtime_bin/script).write_bytes(subprocess.check_output(['git','-C',str(ROOT),'show','4b1f2e2:bin/'+script]))
    cli('qwb-send.sh','handled','--task',intake,'--event',event,'--op','plan-request','--result-ref',ack,actor='planner-pane')
    assert read('intake.md')['handoffs'][event]['handled']==1
    original_result='source:planner-result:'+hashlib.sha256(event.encode()).hexdigest()
    assert original_result in read('intake.md')['handoffs'], 'planner handled controller request without upward result'
    def notify_finish(event_id,actor):
        op='notify-'+hashlib.sha256(event_id.encode()).hexdigest()
        result=p/'qwbuddy/.roles'/('notify-'+op+'.json')
        result.write_text(json.dumps(dict(event_id=event_id,op_id=op,outcome='applied',evidence='public readback of request result')))
        for verb in ['received','accept','prepared','handled']:
            args=['--task',intake,'--event',event_id]
            if verb!='received':args+=['--op',op]
            if verb=='handled':args+=['--result-ref',result]
            cli('qwb-send.sh',verb,*args,actor=actor)
        return op,result
    notify_finish(original_result,'ctl')
    # Keep the request/result exercise isolated from old planning and route assertions.
    request_snapshot=intake.read_bytes()
    try:
        for h in json.loads(cli('qwb-send.sh','pending','--task',intake).stdout):notify_finish(h['event_id'],'ctl')
        request_id=cli('qwb-send.sh','send','--task',intake,'--corr','notify-controller-request','--attempt','1','--text','请修订已授权场景').stdout.strip()
        op,ref=notify_finish(request_id,'planner-pane')
        d=read('intake.md'); upward='source:planner-result:'+hashlib.sha256(request_id.encode()).hexdigest()
        h=d['handoffs'][upward]
        assert d['handoffs'][request_id]['handled'] and all(v in h['payload'] for v in [request_id,str(ref),d['handoffs'][request_id]['result_sha256']])
        before=intake.read_bytes()
        cli('qwb-send.sh','handled','--task',intake,'--event',request_id,'--op',op,'--result-ref',ref,actor='planner-pane')
        assert intake.read_bytes()==before
        for verb in ['received','accept','prepared','handled']:
            args=['--task',intake,'--event',upward]
            if verb!='received':args+=['--op','wrong-owner']
            if verb=='handled':args+=['--result-ref',ref]
            rejected=cli('qwb-send.sh',verb,*args,actor='planner-pane',ok=False)
            assert '规划不能办理主控专属交接' in rejected.stderr and intake.read_bytes()==before
        mark=count();cli('qwb-wake.sh','--once','--pane','ctl')
        routes=native_calls(log.read_text().splitlines()[mark:], p)
        routes=[a for a in routes if a[:2]==['pane','run'] and upward in a[3]]
        assert len(routes)==1 and routes[0][2]=='ctl',routes
        notify_finish(upward,'ctl')
        assert len([h for h in read('intake.md')['handoffs'] if h.startswith('source:planner-result:')])==2
        fake=cli('qwb-send.sh','send','--task',intake,'--corr','notify-planner-self','--attempt','1','--text','主控请求：只是规划自己的正文',actor='planner-pane').stdout.strip()
        notify_finish(fake,'planner-pane')
        assert 'source:planner-result:'+hashlib.sha256(fake.encode()).hexdigest() not in read('intake.md')['handoffs']
        # A failed atomic publish leaves neither a handled request nor its upward result.
        failed=source('notify-publish-failure','请读回授权内修订')
        op='notify-failed';ref=p/'qwbuddy/.roles/notify-failed.json'
        ref.write_text(json.dumps(dict(event_id=failed,op_id=op,outcome='applied',evidence='readback')))
        for verb in ['received','accept','prepared']:
            cli('qwb-send.sh',verb,'--task',intake,'--event',failed,*([] if verb=='received' else ['--op',op]),actor='planner-pane')
        before=intake.read_bytes()
        cli('qwb-send.sh','handled','--task',intake,'--event',failed,'--op',op,'--result-ref',ref,actor='planner-pane',ok=False,extra={'PL_FAIL_PUBLISH':'1'})
        assert intake.read_bytes()==before
        print('PASS notify B：主控send及需求原话原子上行、一次主控门铃、重复handled零写、规划自发反例与四入口拒绝、发布失败零半写',flush=True)
    finally:intake.write_bytes(request_snapshot)
    if os.environ.get('QWB_NOTIFY_ONLY')=='B':raise SystemExit(0)
    before=intake.read_bytes()
    call('append','intake.md','--','working: spec-resolved: planner grant cannot answer spec',actor='planner-pane',ok=False)
    assert intake.read_bytes()==before
    def scenario_name_checks():
        # 复用本文件的02/03身份、进程登记和失效关闭fakeHerdr；逐场景恢复原票。
        selected=os.environ.get('QWB_SCENARIO_NAMES_ONLY')
        initial={f:f.read_bytes() for f in (p/'tasks').glob('*.md')}
        target=p/'tasks/B.md'
        b_request=dict(request,package_id='B')
        environment=temp/'scenario-environment'; environment.write_text('private dependencies\n')
        binding={'candidate':str(p),'base':git('rev-parse','HEAD'),'attempt':'1','policy':'existing-v1','environment':str(environment),'required':{'full':['user_good','user_failure']},'workers':{'review':'reviewer','rework':'sol'}}
        assignment=payload('scenario-gate.json',binding)
        def create(block=scenarios):
            return call('new','B.md','--',payload('scenario-new.json',dict(b_request,scenarios=block)),actor='planner-pane')
        def reject_new(block,bad):
            r=call('new','B.md','--',payload('scenario-new.json',dict(b_request,scenarios=block)),actor='planner-pane',ok=False)
            assert r.returncode==255 and r.stdout=='' and not target.exists(),r
            assert '### user_' in r.stderr and '示例：### user_正常路径_保存' in r.stderr and bad in r.stderr,r.stderr
        def invalid_new():
            reject_new(scenarios.replace('### user_good','### 单行内容').replace('### user_failure','### 失败路径'),'### 单行内容')
            reject_new(scenarios.replace('### user_good\n','').replace('### user_failure\n',''),'至少一个')
            for title in ['### user_', '###', '### user_bad extra']:
                reject_new(scenarios.replace('### user_good',title),title)
            # 场景外的user_标题不能充当门控冻结名。
            reject_new(scenarios.replace('### user_good\n','').replace('### user_failure\n','')+'\n## 报告要求\n### user_later','至少一个')
        def mixed_new(): reject_new(scenarios.replace('### user_failure','### 失败路径'),'### 失败路径')
        def valid_gate():
            create(); call('start-claim','B.md','--','scenario-worker','sol',actor='planner-pane')
            call('dispatch','B.md','--','scenario-worker','scenario-pane',f'dispatch: 2099 op_id=scenario-worker worker=sol agent=scenario-worker pane=scenario-pane dir={p}',actor='planner-pane')
            call('append','B.md','--','done: fixture clean candidate delivered',actor='scenario-pane')
            call('release','B.md','--','scenario-worker',actor='planner-pane')
            assert git('status','--porcelain=v1','--untracked-files=all')==''
            call('gate-assign','B.md','--','gate',assignment)
            assert read('B.md')['gate']['binding']['required']==binding['required']
        def revision(block):
            change=cli('qwb-send.sh','send','--task',intake,'--corr','scenario-change','--attempt','1','--text','请求规划修订B的场景标题').stdout.strip()
            r={'source_task':'intake.md','source_event':change,'spec':'修订B','constraints':'单机，不联网','scenarios':block,'needs':b_request['needs']}
            call('plan-revision','B.md','--expect',read('B.md')['rev'],'--',payload('scenario-revision.json',r),actor='planner-pane')
            return change
        def invalid_revision():
            create(); change=revision(scenarios.replace('### user_failure','### 失败路径'))
            before=target.read_bytes()
            r=call('revise','B.md','--expect',read('B.md')['rev'],'--',change,actor='planner-pane',ok=False)
            assert r.returncode!=0 and r.stdout=='' and target.read_bytes()==before,r
            assert '### 失败路径' in r.stderr and '示例：### user_正常路径_保存' in r.stderr,r.stderr
        def refusal_routes():
            create(); before=target.read_bytes()
            old_bin=temp/'scenario-refusal-bin'; shutil.copytree(ROOT/'bin',old_bin)
            old_script=old_bin/'qwb-ledger-old.sh'
            old_script.write_bytes(subprocess.check_output(['git','-C',str(ROOT),'show','4b1f2e2:bin/qwb-ledger.sh']))
            args=['--expect',str(read('B.md')['rev']),'--',scenarios,'修正命名']
            old_result=cli(str(old_script),'revise-scenarios','--project',p,'--task',target,*args,ok=False)
            r=call('revise-scenarios','B.md',*args,ok=False)
            assert r.returncode==old_result.returncode and r.stdout==old_result.stdout=='' and target.read_bytes()==before,(old_result,r)
            assert old_result.stderr=='账本拒绝：规划票修订须使用持久plan-revision/CAS\n',old_result.stderr
            revise_route=r.stderr.startswith('账本拒绝：规划票修订须使用持久plan-revision/CAS') and all(s in r.stderr for s in ['主控','入口票','qwb-send.sh send','规划','plan-revision','revise'])
            old=before.replace(b'### user_good', '### 单行内容'.encode()).replace(b'### user_failure', '### 失败路径'.encode())
            target.write_bytes(old)
            old_result=cli(str(old_script),'gate-assign','--project',p,'--task',target,'--','gate',assignment,ok=False)
            r=call('gate-assign','B.md','--','gate',assignment,ok=False)
            assert r.returncode==old_result.returncode and r.stdout==old_result.stdout=='' and target.read_bytes()==old,(old_result,r)
            assert old_result.stderr=='账本拒绝：需要冻结的命名场景\n',old_result.stderr
            gate_route=r.stderr.startswith('账本拒绝：需要冻结的命名场景') and all(s in r.stderr for s in ['### user_名字','主控','规划','plan-revision','revise','其余已迁票','revise-scenarios'])
            assert revise_route and gate_route,('revise-route',revise_route,'gate-route',gate_route)
        def byte_equivalence():
            # 同bindir/依赖字节；只冻结观察副本的时钟与event_id，完整对比CLI结果与票字节。
            byte_bin=temp/'scenario-byte-bin'; shutil.copytree(ROOT/'bin',byte_bin)
            versions=[]
            # Baseline is today's writer with only the scenario-name checks removed, so later
            # unrelated writer changes cannot invalidate this comparison.
            current=(ROOT/'bin/qwb-ledger.sh').read_bytes(); check=b'  require_scenario_names($r->{scenarios});\n'
            assert current.count(check)==2
            for label,raw in [('old',current.replace(check,b'')),('new',current)]:
                assert raw.count(b'use Time::HiRes qw(time);')==1 and raw.count(b',gmtime)')==2
                script=byte_bin/('qwb-ledger-'+label+'.sh')
                script.write_bytes(raw.replace(b'use Time::HiRes qw(time);',b'use subs qw(time); sub time { 2099000000 }').replace(b',gmtime)',b',gmtime(2099000000))'))
                versions.append(script)
            def compare(verb,*args,actor='ctl',expect=None):
                before={f:f.read_bytes() for f in (p/'tasks').glob('*.md')}; results=[]
                try:
                    for script in versions:
                        extra=['--expect',str(expect)] if expect is not None else []
                        r=cli(str(script),verb,'--project',p,'--task',target,'--event-id','scenario-'+verb,*extra,'--',*args,actor=actor)
                        results.append((r.returncode,r.stdout.encode(),r.stderr.encode(),target.read_bytes()))
                        for f in (p/'tasks').glob('*.md'):
                            if f not in before: f.unlink()
                        for f,raw in before.items(): f.write_bytes(raw)
                    assert results[0]==results[1],(verb,results)
                    target.write_bytes(results[1][3])
                except BaseException:
                    for f,raw in before.items(): f.write_bytes(raw)
                    raise
            compare('new',payload('scenario-new.json',b_request),actor='planner-pane')
            change=revision(scenarios)
            compare('revise',change,actor='planner-pane',expect=read('B.md')['rev'])
            compare('gate-assign','gate',assignment)
            assert read('B.md')['spec_rev']==1 and read('B.md')['gate']['binding']['required']==binding['required']
        checks=[('invalid-new',invalid_new),('mixed-new',mixed_new),('valid-gate',valid_gate),('invalid-revision',invalid_revision),('refusal-routes',refusal_routes),('byte-equivalence',byte_equivalence)]
        failed=0
        for name,check in checks:
            if selected and selected not in ('all',name): continue
            try:
                check(); print('PASS scenario-names '+name,flush=True)
            except AssertionError as error:
                failed+=1; print('FAIL scenario-names '+name+': '+repr(error),flush=True)
            finally:
                for f in (p/'tasks').glob('*.md'):
                    if f not in initial: f.unlink()
                for f,raw in initial.items(): f.write_bytes(raw)
        assert not failed, ('scenario-names failures',failed)
    scenario_name_checks()
    if os.environ.get('QWB_SCENARIO_NAMES_ONLY'):
        raise SystemExit(0)
    def upward_checks():
        # 真实公开开票/授权/派发；不启动工人模型。所有native操作都经过本文件fake Herdr。
        name='Up.md'; ticket=p/'tasks'/name; intake_name='UpIntake.md'
        new_intake=p/'tasks'/intake_name; new_intake.write_text('# Up intake\nstate: running\n'+scenarios+'\n')
        migration=payload('up-migration.json',{'task_sha256':hashlib.sha256(new_intake.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}})
        call('migrate',intake_name,'--',migration)
        req_event=call('handoff-send',intake_name,'--','controller','up-request','1','原话：交付后主控接安排门禁').stdout.strip()
        up_grant=dict(grant,request_id='up-request',source_event=req_event,packages={'Up':name})
        call('plan-assign',intake_name,'--','planner',payload('up-grant.json',up_grant))
        up_request=dict(request,request_id='up-request',package_id='Up',packages={'Up':name},source_task=intake_name,source_event=req_event)
        call('new',name,'--',payload('up-new.json',up_request),actor='planner-pane')
        call('start-claim',name,'--','up-dispatch','sol',actor='planner-pane')
        call('prepare',name,'--',hashlib.sha1(scenarios.encode()).hexdigest(),actor='planner-pane')
        call('dispatch',name,'--','up-dispatch','up-worker',f'dispatch: 2099 op_id=up-dispatch worker=sol agent=up-worker pane=up-worker dir={p}',actor='planner-pane')
        call('release',name,'--','up-dispatch',actor='planner-pane')
        def handoff(verb,event,task=name,actor='ctl',ok=True):
            args=['--event',event]
            if verb in ('accept','prepared','handled'): args+=['--op','handle-'+event]
            if verb=='handled':
                ref=p/'tasks'/('result-'+hashlib.sha256(event.encode()).hexdigest()+'.json')
                ref.write_text(json.dumps({'event_id':event,'op_id':'handle-'+event,'outcome':'applied','evidence':'public readback fixture; no external action'}))
                args+=['--result-ref',ref]
            before=(p/'tasks'/task).read_bytes()
            result=cli('qwb-send.sh',verb,'--task',p/'tasks'/task,*args,actor=actor,ok=ok)
            if not ok: assert (p/'tasks'/task).read_bytes()==before, '拒绝改变原票'
            return result
        def pending(task=name): return json.loads(cli('qwb-send.sh','pending','--task',p/'tasks'/task).stdout)
        def settle(task=name):
            for h in pending(task):
                for verb in ['received','accept','prepared','handled']: handoff(verb,h['event_id'],task)
        settle(); settle(intake_name)
        def deliveries(ok=True):
            mark=count(); result=cli('qwb-wake.sh','--once','--pane','ctl',ok=ok)
            calls=native_calls(log.read_text().splitlines()[mark:], p)
            return [a for a in calls if a[:2]==['pane','run'] and 'Up(running)' in a[3]],result
        # 本票同一用例先在固定起点跑红：仅替换私有运行时，不改主仓脚本。
        silence_baseline=os.environ.get('QWB_SILENCE_BASELINE')=='1'
        runtime=p/'qwbuddy/bin'
        if silence_baseline:
            for script in ['qwb-ledger.sh','qwb-wake.sh']:
                (runtime/script).write_bytes(subprocess.check_output(['git','-C',str(ROOT),'show','44ab8ac:bin/'+script]))
        for index in range(3):
            call('append',name,'--event-id',f'silent-worker-{index}','--',f'working: 工人进度{index}',actor='up-worker')
            if silence_baseline:
                mark=count()
                result=subprocess.run(['bash',str(runtime/'qwb-wake.sh'),'--project',str(p),'--once','--pane','ctl'],env=env,capture_output=True,text=True)
                assert result.returncode==0,(result.stdout,result.stderr)
                routes=native_calls(log.read_text().splitlines()[mark:], p)
                routes=[a for a in routes if a[:2]==['pane','run'] and 'Up(running)' in a[3]]
            else: routes,_=deliveries()
            assert not routes, ('A: 纯工人进度不应门铃任何角色',routes)
        for actor in ['ctl','planner-pane']:
            call('append',name,'--','working: 角色普通进度',actor=actor)
        def obligations():
            probe=subprocess.run(['bash','-c','. "$1"; qwb_task_obligations "$2" "$3"','probe',str(ROOT/'bin/qwb-lib.sh'),str(p),str(ticket)],env=env,capture_output=True,text=True)
            assert probe.returncode==0,(probe.stdout,probe.stderr)
            return probe.stdout
        assert not obligations(), '未生成handoff的纯进度不得形成source义务'
        for _ in range(2):
            routes,_=deliveries(); assert not routes, routes
        progress=[h for h in pending() if h['source_event'].startswith('silent-worker-')]
        assert len(progress)==3 and all(h['transport_count']==0 and not h['handled'] for h in progress)
        assert not obligations(), '已生成handoff的纯进度不得形成未结义务'
        listing_dir=p/'.worktrees/Up'; listing_dir.mkdir(parents=True)
        for phase in ['done','verified']:
            call('state',name,'--',phase)
            assert not obligations()
            listing=cli('qwb-worktree.sh','list').stdout
            assert any(row.startswith('残留') and str(listing_dir) in row for row in listing.splitlines()),listing
        call('append',name,'--event-id','silent-negative-blocked','--','blocked: 仍有动作义务')
        assert 'source=silent-negative-blocked' in obligations()
        pending()
        assert 'handoff=source:silent-negative-blocked' in obligations()
        listing=cli('qwb-worktree.sh','list').stdout
        assert any(row.startswith('未结项') and str(listing_dir) in row for row in listing.splitlines()),listing
        handoff_id='source:silent-negative-blocked'
        for verb in ['received','accept','prepared','handled']: handoff(verb,handoff_id)
        call('state',name,'--','running'); listing_dir.rmdir()
        print('PASS silence A义务：done/verified与worktree列表不被未办理纯进度挡住；blocked的source/handoff仍未结')
        print('PASS silence A：连续三条工人进度与主控/规划普通进度只记账；多轮零门铃、零传输、不伪造handled')
        def watch_checks():
            global runtime_bin
            saved_bin=runtime_bin; runtime_bin=runtime
            script=runtime/'qwb-ledger.sh'; original_script=script.read_bytes()
            original_ticket=ticket.read_bytes(); native_path=Path(env['PL_NATIVE']); native_bytes=native_path.read_bytes()
            config=p/'qwbuddy/config.sh'; config_bytes=config.read_bytes()
            clock=temp/'silence-clock'; now=temp/'silence-now'
            now.write_text('#!/usr/bin/env python3\nimport os\nprint(open(os.environ["PL_CLOCK"]).read().strip())\n'); now.chmod(0o755)
            env['PL_CLOCK']=str(clock); env['QWB_NOW_MS_CMD']=str(now)
            clock.write_text('4102444800000')
            script.write_bytes(original_script.replace(b'use Time::HiRes qw(time);',b'use subs qw(time); sub time { open my $c,"<",$ENV{PL_CLOCK} or die $!; return scalar(<$c>)/1000 }').replace(b',gmtime)',b',gmtime(time()))'))
            config.write_bytes(config_bytes+b'QWB_REWAKE_MS=60000\n')
            def advance(ms): clock.write_text(str(int(clock.read_text())+ms))
            try:
                call('append',name,'--event-id','watch-progress','--','working: 重置静默时钟',actor='up-worker')
                snapshot=ticket.read_bytes()
                env['PL_GONE_WORKER']='up-worker'
                routes,_=deliveries()
                assert len(routes)==1 and routes[0][2]=='planner-pane' and '工人丢失' in routes[0][3],routes
                for _ in range(2):
                    routes,_=deliveries(); assert not routes,routes
                native=json.loads(native_path.read_bytes()); del native['planner-pane']; native_path.write_text(json.dumps(native))
                routes,_=deliveries()
                assert len(routes)==1 and routes[0][2]=='ctl' and '工人丢失' in routes[0][3],routes
                routes,_=deliveries(); assert not routes,routes
                native_path.write_bytes(native_bytes); ticket.write_bytes(snapshot)
                env['PL_EXPIRE_PROOF']=str(temp/'watch-proof-counter')
                routes,_=deliveries()
                assert len(routes)==1 and routes[0][2]=='ctl' and '工人丢失' in routes[0][3],routes
                del env['PL_EXPIRE_PROOF']; native_path.write_bytes(native_bytes)
                del env['PL_GONE_WORKER']; ticket.write_bytes(snapshot)
                env['PL_BAD_WORKER']='up-worker'
                routes,result=deliveries()
                assert not routes and '无法确认工人状态' in result.stderr,(routes,result.stderr)
                del env['PL_BAD_WORKER']
                print('PASS silence B丢失：规划派工一次通知、跨进程重启去重、失效/第二次proof失效转主控、unknown不冒充丢失')
                advance(59000); routes,_=deliveries(); assert not routes,routes
                advance(1000); routes,_=deliveries()
                assert len(routes)==1 and routes[0][2]=='planner-pane' and '工人无进展：60000ms' in routes[0][3],routes
                routes,_=deliveries(); assert not routes,routes
                advance(59000); routes,_=deliveries(); assert not routes,routes
                call('append',name,'--','working: 新进度重新计时',actor='up-worker')
                advance(59000); routes,_=deliveries(); assert not routes,routes
                advance(1000); routes,_=deliveries(); assert len(routes)==1 and '工人无进展' in routes[0][3],routes
                print('PASS silence B停滞：假钟阈值、成功wake低频去重、新业务事件重置，通知收据不重置业务时钟')
                ticket.write_bytes(snapshot)
                h=call('handoff-send',name,'--','controller','watch-wait','1','等待已有工具').stdout.strip()
                for verb in ['received','accept']: handoff(verb,h)
                cli('qwb-send.sh','activity','--task',ticket,'--event',h,'--wait-ms','120000','--reason','fixture bounded tool wait')
                advance(60000); routes,_=deliveries(); assert not routes,routes
                env['PL_GONE_WORKER']='up-worker'; routes,_=deliveries()
                assert len(routes)==1 and '工人丢失' in routes[0][3],routes
                del env['PL_GONE_WORKER']
                ticket.write_bytes(snapshot)
                # 私有持久快照移除规划授权，模拟原派工者为主控；不会启动任何工人。
                d=read(name); d.pop('planning'); d['ops']['up-dispatch']['owner']='ctl'
                body=snapshot.split(b'\n<!-- qwb-collab-v1\n')[0]
                ticket.write_bytes(body+b'\n<!-- qwb-collab-v1\n'+json.dumps(d,ensure_ascii=False).encode()+b'\n-->\n')
                env['PL_GONE_WORKER']='up-worker'; routes,_=deliveries()
                assert len(routes)==1 and routes[0][2]=='ctl' and '工人丢失' in routes[0][3],routes
                call('append',name,'--','done: 工人已经完成',actor='up-worker')
                routes,_=deliveries(); assert all('工人丢失' not in r[3] for r in routes),routes
                print('PASS silence B边界：合理wait抑制停滞但不吞丢失；无规划授权归主控、已done不误报')
            finally:
                for key in ['PL_GONE_WORKER','PL_BAD_WORKER','PL_EXPIRE_PROOF','PL_CLOCK','QWB_NOW_MS_CMD']: env.pop(key,None)
                runtime_bin=saved_bin; script.write_bytes(original_script); ticket.write_bytes(original_ticket); native_path.write_bytes(native_bytes); config.write_bytes(config_bytes)
        def silent_end_checks():
            global runtime_bin
            saved_bin=runtime_bin; runtime_bin=runtime
            def silent_baseline(raw):
                text=raw.decode()
                text=re.sub(r'^  +# SILENT_END_BEGIN[^\n]*\n.*?^  +# SILENT_END_END\n','',text,flags=re.M|re.S)
                text=text.replace('  worker_lost "$f" >/dev/null || true\n  lost="$QWB_WORKER_LOST_PANE"\n','  lost="$(worker_lost "$f")" || lost=""\n')
                text=text.replace('my $s=decode_json(<STDIN>); exit !($s->{timer_due} || $s->{silent_end})','exit !decode_json(<STDIN>)->{timer_due}')
                text=text.replace('if ($s->{lost} || $s->{silent_end}) { exit if @wakes }','if ($s->{lost}) { exit if @wakes }')
                text,count=re.subn(r'        my \$g=\$d->\{gate\};\n        if \(\$s->\{silent_end\}.*?\n        \} elsif \(\$p','        if ($p',text,flags=re.S)
                assert count==1,'silent-end gate routing baseline boundary changed'
                return text.encode()
            wake=runtime/'qwb-wake.sh'; wake_bytes=wake.read_bytes()
            if os.environ.get('QWB_SILENT_END_BASELINE')=='1':wake.write_bytes(silent_baseline(wake_bytes))
            writer=runtime/'qwb-ledger.sh'; writer_bytes=writer.read_bytes()
            original_ticket=ticket.read_bytes(); config=p/'qwbuddy/config.sh'; config_bytes=config.read_bytes()
            native=Path(env['PL_NATIVE']); native_bytes=native.read_bytes()
            session=temp/'silent-end-session.jsonl'; clock=temp/'silent-end-clock'; now=temp/'silent-end-now'
            now.write_text('#!/bin/sh\ncat "$PL_CLOCK"\n'); now.chmod(0o755)
            env.update(PL_CLOCK=str(clock),QWB_NOW_MS_CMD=str(now))
            writer.write_bytes(writer_bytes.replace(b'use Time::HiRes qw(time);',b'use subs qw(time); sub time { open my $c,"<",$ENV{PL_CLOCK} or die $!; return scalar(<$c>)/1000 }').replace(b',gmtime)',b',gmtime(time()))'))
            clock.write_text('4102444800000')
            config.write_bytes(config_bytes+b'QWB_REWAKE_MS=1800000\nQWB_SILENT_END_MS=60000\n')
            def advance(ms): clock.write_text(str(int(clock.read_text())+ms))
            def native_session(status='idle',stamp='2100-01-01T00:00:00.000Z',pending=False,large=False):
                records=[dict(type='session',id='silent-session',cwd=str(p)),dict(type='message',id='end',parentId='silent-session',timestamp=stamp,message=dict(role='assistant',content=[dict(type='toolCall',id='pending')] if pending else [dict(type='text',text='x'*10000)] if large else [],stopReason='stop'))]
                session.write_text(''.join(json.dumps(row)+'\n' for row in records))
                state=json.loads(native_bytes); state['up-worker']=dict(session=str(session),status=status); native.write_text(json.dumps(state))
            def restore(snapshot):
                ticket.write_bytes(snapshot);clock.write_text('4102444800000');native_session()
            try:
                native_session()
                probe=cli('qwb-herdr.sh','activity','--task',ticket,'--pane','up-worker')
                assert json.loads(probe.stdout)['activity']=='unknown',probe.stdout
                evidence=json.loads(cli('qwb-herdr.sh','activity','--pane','up-worker').stdout)
                assert evidence['activity']=='idle',evidence
                call('append',name,'--',f'working: worker-activity op=up-dispatch pane=up-worker evidence={json.dumps(evidence)}')
                base=ticket.read_bytes()
                # 同一私有已派快照改为门控归属；身份/claim/门铃仍走公开入口。
                state=read(name);state.pop('planning');state['ops']['up-dispatch']['owner']='ctl'
                body=base.split(b'\n<!-- qwb-collab-v1\n')[0]
                ticket.write_bytes(body+b'\n<!-- qwb-collab-v1\n'+json.dumps(state,ensure_ascii=False).encode()+b'\n-->\n')
                # 临时Git自身的clean候选；不碰源码仓的任何worktree元数据。
                candidate=temp/'silent-end-candidate';git('worktree','add','-q','--detach',str(candidate))
                assignment={'candidate':str(candidate),'base':git('rev-parse','HEAD'),'attempt':'1','policy':'existing-v1','environment':str(payload('silent-end-environment.json',{})),'required':{'full':['user_good','user_failure']},'workers':{'review':'reviewer','rework':'sol'}}
                call('gate-assign',name,'--','gate',payload('silent-end-gate.json',assignment))
                call('claim',name,'--','silent-end-gate',actor='gate-pane')
                state=read(name);state['ops']['up-dispatch']['owner']='gate-pane'
                body=ticket.read_bytes().split(b'\n<!-- qwb-collab-v1\n')[0]
                ticket.write_bytes(body+b'\n<!-- qwb-collab-v1\n'+json.dumps(state,ensure_ascii=False).encode()+b'\n-->\n')
                routes,_=deliveries();assert not routes,routes
                advance(59999);routes,_=deliveries();assert not routes,routes
                advance(1);routes,_=deliveries();assert len(routes)==1 and routes[0][2]=='gate-pane' and '工人已收工但没有报告' in routes[0][3] and 'pane=up-worker op=up-dispatch' in routes[0][3] and '读审核工人的窗口或让它补写 done 行' in routes[0][3],('silent-end: 门控一分钟没有未报告门铃',routes)
                for _ in range(2):routes,_=deliveries();assert not routes,routes
                print('PASS silent-end 场景2：门控派工一分钟直达门控，窗口/op齐全、多轮只叫一次',flush=True)
                native_session(status='working');advance(1000);routes,_=deliveries();assert not routes,routes
                ended=time.strftime('%Y-%m-%dT%H:%M:%S.000Z',time.gmtime(int(clock.read_text())//1000))
                native_session(stamp=ended,large=True)
                advance(59999);routes,_=deliveries();assert not routes,routes
                advance(1);routes,_=deliveries();assert len(routes)==1 and routes[0][2]=='gate-pane' and '没有报告' in routes[0][3],routes
                routes,_=deliveries();assert not routes,routes
                print('PASS silent-end 再次收工：重新满一分钟才叫一次；超过4096字节末记录可从尾部完整读取',flush=True)
                restore(base)
                routes,_=deliveries();assert not routes,routes
                advance(59999);routes,_=deliveries();assert not routes,routes
                advance(1);routes,_=deliveries()
                assert len(routes)==1 and routes[0][2]=='planner-pane' and '工人已收工但没有报告' in routes[0][3] and 'pane=up-worker op=up-dispatch' in routes[0][3],('silent-end: 一分钟没有通知规划',routes)
                for _ in range(3):advance(60000);routes,_=deliveries();assert not routes,routes
                print('PASS silent-end 场景3：规划派工满一分钟只叫一次，跨进程重启不重叫',flush=True)
                call('append',name,'--event-id','silent-end-late-done','--','done: 补写真实交付',actor='up-worker')
                routes,_=deliveries();assert len(routes)==1 and 'source:silent-end-late-done' in routes[0][3] and all('没有报告' not in r[3] for r in routes),routes
                print('PASS silent-end 场景6：门铃之后补写done恢复正常交付路由',flush=True)
                restore(base)
                call('append',name,'--event-id','silent-end-normal-done','--','done: 正常真实交付',actor='up-worker')
                advance(60000);routes,_=deliveries();assert len(routes)==1 and 'source:silent-end-normal-done' in routes[0][3] and all('没有报告' not in r[3] for r in routes),routes
                print('PASS silent-end 场景5：正常done只有原交付，无未报告门铃',flush=True)
                for report in ['blocked','needs-decision']:
                    restore(base);call('append',name,'--',report+': 工人有交代',actor='up-worker');advance(60000)
                    routes,_=deliveries();assert routes and all('没有报告' not in r[3] for r in routes),routes
                for mode in ['busy','unknown','pending','missing-time','future-time','old-time','stale-binding']:
                    restore(base)
                    if mode in ['busy','unknown']:native_session(status='working' if mode=='busy' else 'unverified')
                    elif mode=='pending':native_session(pending=True)
                    elif mode=='missing-time':native_session(stamp=None)
                    elif mode=='future-time':native_session(stamp='2100-01-01T00:30:00.000Z')
                    elif mode=='old-time':native_session(stamp='2000-01-01T00:00:00.000Z')
                    else:
                        rows=json.loads(native.read_text());rows['up-worker']['session']=str(temp/'unbound.jsonl');shutil.copy(session,temp/'unbound.jsonl');native.write_text(json.dumps(rows))
                    advance(60000);mark=count();routes,_=deliveries();assert not routes,(mode,routes)
                    if mode=='busy':
                        calls=native_calls(log.read_text().splitlines()[mark:],p)
                        probes=[a for a in calls if a[:2]==['pane','get'] and a[2]=='up-worker' or a[:2]==['pane','process-info'] and a[-1]=='up-worker']
                        assert probes==[['pane','get','up-worker']],('working invoked activity instead of reusing pane get',probes)
                        print('PASS silent-end 性能：working窗口仅一次pane get，零activity/process-info调用',flush=True)
                    advance(1740000);routes,_=deliveries();assert len(routes)==1 and '工人无进展' in routes[0][3],(mode,routes)
                print('PASS silent-end 场景4：busy/unknown/未配对工具/缺时间/未来/旧时间/旧绑定不误叫；30分钟原兜底保留',flush=True)
                restore(base)
                state=read(name);state.pop('planning');state['ops']['up-dispatch']['owner']='ctl'
                body=base.split(b'\n<!-- qwb-collab-v1\n')[0]
                ticket.write_bytes(body+b'\n<!-- qwb-collab-v1\n'+json.dumps(state,ensure_ascii=False).encode()+b'\n-->\n')
                advance(60000);routes,_=deliveries();assert len(routes)==1 and routes[0][2]=='ctl' and '没有报告' in routes[0][3],routes
                restore(base);rows=json.loads(native.read_text());rows.pop('planner-pane');native.write_text(json.dumps(rows))
                advance(60000);routes,_=deliveries();assert len(routes)==1 and routes[0][2]=='ctl' and '没有报告' in routes[0][3],routes
                print('PASS silent-end 场景3：无规划授权直接主控，规划身份失效沿原规则回主控',flush=True)
                others_dir=temp/'silent-end-other-tasks';others_dir.mkdir()
                others=[f for f in (p/'tasks').glob('*.md') if f!=ticket]
                for f in others:f.rename(others_dir/f.name)
                try:
                    writer.write_bytes(writer.read_bytes().replace(b"$event=unpack('H*',$bytes);",b'$event=sprintf("%032x",$data->{seq});'))
                    for case in ['disabled-idle','quiet','away','busy-short','unknown-short','lost','stalled']:
                        restore(base)
                        config.write_bytes(config_bytes+b'QWB_REWAKE_MS=1800000\n'+(b'QWB_SILENT_END_MS=0\n' if case=='disabled-idle' else b'QWB_SILENT_END_MS=60000\n'))
                        if case in ['quiet','away']:cli('qwb-ledger.sh','mode-enter','--project',p,'--',case,'silent-end-authorized','fixture posture','no new authority')
                        if case in ['busy-short','stalled']:native_session(status='working')
                        if case=='unknown-short':native_session(status='unverified')
                        if case=='lost':env['PL_GONE_WORKER']='up-worker'
                        advance(1800000 if case=='stalled' else 60000)
                        outputs=[]
                        for version in ['baseline','candidate']:
                            wake.write_bytes(silent_baseline(wake_bytes) if version=='baseline' else wake_bytes)
                            ticket.write_bytes(base);log.write_bytes(b'')
                            result=cli('qwb-wake.sh','--once','--pane','ctl')
                            outputs.append((result.stdout.encode(),result.stderr.encode(),result.returncode,ticket.read_bytes()))
                        assert outputs[0]==outputs[1],('silent-end byte mismatch',case,outputs)
                        print('EVIDENCE silent-end byte-equivalence '+case,flush=True)
                        env.pop('PL_GONE_WORKER',None)
                        if case in ['quiet','away']:cli('qwb-ledger.sh','mode-exit','--project',p,'--','explicit','fixture explicit exit')
                    print('PASS silent-end 场景7：关闭/quiet/away与busy/unknown/丢失/30分钟兜底，当前仅撤本票改动基线stdout/stderr/rc/票内容逐字节一致',flush=True)
                finally:
                    for f in others:(others_dir/f.name).rename(f)
                    others_dir.rmdir();env.pop('PL_GONE_WORKER',None)
            finally:
                runtime_bin=saved_bin;wake.write_bytes(wake_bytes);writer.write_bytes(writer_bytes);ticket.write_bytes(original_ticket);config.write_bytes(config_bytes);native.write_bytes(native_bytes)
                for key in ['PL_CLOCK','QWB_NOW_MS_CMD']:env.pop(key,None)
        if os.environ.get('QWB_SILENT_END_ONLY')=='1':
            silent_end_checks();return
        if os.environ.get('QWB_SILENCE_DELIVERY_ONLY')!='1': watch_checks()
        if os.environ.get('QWB_SILENCE_WATCH_ONLY')=='1': return
        silent_end_checks()
        def exhausted_checks(gate=False):
            global runtime_bin
            saved_bin=runtime_bin; runtime_bin=runtime
            script=runtime/'qwb-ledger.sh'; original_script=script.read_bytes(); original_ticket=ticket.read_bytes()
            other_dir=Path(tempfile.mkdtemp(prefix='delivery-other-',dir=temp))
            others=[f for f in (p/'tasks').glob('*.md') if f!=ticket]
            for f in others: f.rename(other_dir/f.name)
            config=p/'qwbuddy/config.sh'; config_bytes=config.read_bytes()
            clock=temp/'delivery-clock'; now=temp/'delivery-now'
            now.write_text('#!/usr/bin/env python3\nimport os\nprint(open(os.environ["PL_CLOCK"]).read().strip())\n'); now.chmod(0o755)
            env['PL_CLOCK']=str(clock); env['QWB_NOW_MS_CMD']=str(now); clock.write_text('4102444800000')
            script.write_bytes(original_script.replace(b'use Time::HiRes qw(time);',b'use subs qw(time); sub time { open my $c,"<",$ENV{PL_CLOCK} or die $!; return scalar(<$c>)/1000 }').replace(b',gmtime)',b',gmtime(time()))'))
            config.write_bytes(config_bytes+b'QWB_REWAKE_MS=0\nQWB_WAKE_INTERVAL_MS=60000\n')
            def advance(ms): clock.write_text(str(int(clock.read_text())+ms))
            def assert_reminder(routes,event,role):
                control=[r for r in routes if r[2]=='ctl']
                assert len(control)==1 and event in control[0][3] and f'={role}/' in control[0][3] and '已投次数=3' in control[0][3],routes
                return control[0][3]
            def cap(event):
                for _ in range(3): cli('qwb-send.sh','transport','--task',ticket,'--event',event)
            try:
                if gate:
                    # 门禁普通working仅允许真实已派child活动绑定；不启动工人模型。
                    call('gate-dispatch',name,'--','up-gate','silent-child','review','reviewer',actor='gate-pane')
                    call('dispatch',name,'--','silent-child','up-worker',f'dispatch: 2099 op_id=silent-child worker=reviewer agent=up-worker pane=up-worker dir={p}',actor='gate-pane')
                    call('append',name,'--event-id','silent-gate-progress','--','working: worker-activity op=silent-child pane=up-worker evidence=fixture',actor='gate-pane')
                    call('append',name,'--event-id','gate-progress-worker','--','working: 门禁在途工人进度',actor='up-worker')
                    routes,_=deliveries(); assert not routes,routes
                    assert not read(name)['handoffs']['source:silent-gate-progress']['handled']
                    call('append',name,'--event-id','exhaust-gate','--','blocked: 门禁处理的工人问题',actor='up-worker')
                    pending(); cap('source:exhaust-gate'); routes,_=deliveries()
                    assert '交接升级主控' in assert_reminder(routes,'source:exhaust-gate','门禁')
                    before=ticket.read_bytes(); routes,_=deliveries(); assert not routes and ticket.read_bytes()==before,routes
                    cli('qwb-role.sh','start','--actor','up-test','--role','测试体系','--worker','sol','--dir',p)
                    # 请求生成入口另由collab-test-policy全文件验证；这里固定其合法持久读模，专测耗尽分流。
                    identity=subprocess.run(['bash','-c','. "$1"; qwb_gate_identity "$2" up-test 测试体系','probe',str(ROOT/'bin/qwb-lib.sh'),str(p)],env=env,capture_output=True,text=True)
                    assert identity.returncode==0,identity.stderr
                    event='exhaust-test'
                    call('append',name,'--event-id',event,'--','working: 明确绑定的测试请求')
                    d=read(name); d['test_requests']={'silence-test':{'event_id':event,'identity':json.loads(identity.stdout),'reason':'new-behavior','scenario':'user_good','context':{},'reply':{},'reply_sha256':''}}
                    body=ticket.read_bytes().split(b'\n<!-- qwb-collab-v1\n')[0]
                    ticket.write_bytes(body+b'\n<!-- qwb-collab-v1\n'+json.dumps(d,ensure_ascii=False).encode()+b'\n-->\n')
                    pending(); cap('source:'+event)
                    routes,_=deliveries(); assert '交接升级主控' in assert_reminder(routes,'source:'+event,'测试体系')
                    print('PASS silence C门禁/测试：进度静默；两类三投耗尽均绕过原优先路由升级主控一次')
                    return
                call('append',name,'--event-id','exhaust-planner','--','blocked: 三次后仍须有人接收',actor='up-worker')
                event='source:exhaust-planner'
                for _ in range(3):
                    routes,_=deliveries(); assert len(routes)==1 and routes[0][2]=='planner-pane' and event in routes[0][3],routes
                    advance(60000)
                assert read(name)['handoffs'][event]['transport_count']==3
                capped=ticket.read_bytes()
                # 额外参数只描述真实到期路由；不能让调用者伪填目标或提前重提。
                cli('qwb-send.sh','transport','--task',ticket,'--event',event,'--mode','reminder','--route-role','主控','--route-pane','ctl','--retry-ms','60000',ok=False)
                assert ticket.read_bytes()==capped
                # 同批有新动作，升级项仅给主控，新动作照旧给规划。
                call('append',name,'--event-id','fresh-blocked','--','blocked: 新动作不扣旧升级预算',actor='up-worker')
                call('append',name,'--event-id','silent-exhaust','--','working: 不参与升级',actor='up-worker')
                routes,_=deliveries(); assert '交接升级主控' in assert_reminder(routes,event,'规划')
                planner=[r for r in routes if r[2]=='planner-pane']; assert len(planner)==1 and 'source:fresh-blocked' in planner[0][3] and event not in planner[0][3],routes
                d=read(name); assert d['handoffs'][event]['transport_count']==3 and d['handoffs']['source:fresh-blocked']['transport_count']==1 and d['handoffs']['source:silent-exhaust']['transport_count']==0
                before=ticket.read_bytes(); routes,_=deliveries(); assert not routes and ticket.read_bytes()==before,routes
                ticket.write_bytes(capped); env['PL_FAIL_PUBLISH']='1'
                routes,result=deliveries(ok=False); assert not routes and result.returncode==3 and ticket.read_bytes()==capped,(routes,result.stderr)
                del env['PL_FAIL_PUBLISH']
                env['PL_FAIL_TRANSPORT']='ctl'; routes,result=deliveries()
                assert '交接升级主控' in assert_reminder(routes,event,'规划') and '投递失败' in result.stderr
                d=read(name); keys=set(d['handoffs']); assert sum('mode=escalation ' in e['line'] for e in d['events'])==1
                del env['PL_FAIL_TRANSPORT']
                routes,_=deliveries(); assert not routes,routes
                advance(1800000); routes,_=deliveries(); assert '交接低频重提' in assert_reminder(routes,event,'规划')
                assert set(read(name)['handoffs'])==keys and read(name)['handoffs'][event]['transport_count']==3
                handoff('received',event,actor='planner-pane'); advance(1800000); routes,_=deliveries(); assert not routes,routes
                for verb in ['accept','prepared','handled']: handoff(verb,event,actor='planner-pane')
                result_id='source:planner-result:'+hashlib.sha256(event.encode()).hexdigest()
                before=ticket.read_bytes(); handoff('handled',event,actor='planner-pane'); assert ticket.read_bytes()==before
                routes,_=deliveries(); assert len(routes)==1 and routes[0][2]=='ctl' and result_id in routes[0][3],routes
                assert sum(hid==result_id for hid in read(name)['handoffs'])==1
                print('PASS silence C规划：三投后一次升级、混批分流、重启不重复、失败发布无半写/API失败有界重提、后来received停止且handled唯一上行')
                ticket.write_bytes(original_ticket)
                d=read(name); d.pop('planning'); d['ops']['up-dispatch']['owner']='ctl'
                body=original_ticket.split(b'\n<!-- qwb-collab-v1\n')[0]
                ticket.write_bytes(body+b'\n<!-- qwb-collab-v1\n'+json.dumps(d,ensure_ascii=False).encode()+b'\n-->\n')
                call('append',name,'--event-id','exhaust-controller','--','done: 无规划授权也不能永久沉默',actor='up-worker')
                event='source:exhaust-controller'; pending(); cap(event); keys=set(read(name)['handoffs'])
                routes,_=deliveries(); assert not routes,routes
                advance(1799000); routes,_=deliveries(); assert not routes,routes
                advance(1000); routes,_=deliveries(); assert '交接低频重提' in assert_reminder(routes,event,'主控')
                routes,_=deliveries(); assert not routes,routes
                advance(1800000)
                due=json.loads(cli('qwb-send.sh','pending','--task',ticket,'--due','--retry-ms','3600000').stdout)
                assert event not in [h['event_id'] for h in due]
                advance(1800000)
                due=json.loads(cli('qwb-send.sh','pending','--task',ticket,'--due','--retry-ms','3600000').stdout)
                assert event in [h['event_id'] for h in due]
                handoff('received',event); advance(3600000); routes,_=deliveries(); assert not routes,routes
                assert set(read(name)['handoffs'])==keys and read(name)['handoffs'][event]['transport_count']==3
                print('PASS silence C主控：无规划授权三投后30分钟首次重提、更长配置生效、received停止、计数封顶/交接集合不增长')
            finally:
                for key in ['PL_CLOCK','QWB_NOW_MS_CMD','PL_FAIL_PUBLISH','PL_FAIL_TRANSPORT']: env.pop(key,None)
                runtime_bin=saved_bin; script.write_bytes(original_script); ticket.write_bytes(original_ticket); config.write_bytes(config_bytes)
                for f in others: (other_dir/f.name).rename(f)
                other_dir.rmdir()
        exhausted_checks()
        if os.environ.get('QWB_SILENCE_DELIVERY_ONLY')=='1': return
        call('append',name,'--event-id','up-blocked','--','blocked: 等待技术处理',actor='up-worker')
        call('append',name,'--event-id','up-done','--','done: 已交付固定候选',actor='up-worker')
        # 红证使用同一新用例和公开入口，仅替换本私有项目运行时脚本。
        baseline=os.environ.get('QWB_PLANNING_UPWARD_BASELINE')=='1'
        if baseline:
            for script in ['qwb-ledger.sh','qwb-wake.sh']:
                (p/'qwbuddy/bin'/script).write_bytes(subprocess.check_output(['git','-C',str(ROOT),'show','d66d77c:bin/'+script]))
            mark=count()
            result=subprocess.run(['bash',str(p/'qwbuddy/bin/qwb-wake.sh'),'--project',str(p),'--once','--pane','ctl'],env=env,capture_output=True,text=True)
            assert result.returncode==0,(result.stdout,result.stderr)
            routes=native_calls(log.read_text().splitlines()[mark:], p)
            routes=[a for a in routes if a[:2]==['pane','run'] and 'Up(running)' in a[3]]
        else: routes,_=deliveries()
        control=[a for a in routes if a[2]=='ctl']; planning=[a for a in routes if a[2]=='planner-pane']
        assert len(control)==1 and 'source:up-done' in control[0][3] and '下一步：主控安排门禁' in control[0][3], ('P1: 工人交付未直达主控',routes)
        assert len(planning)==1 and 'source:up-blocked' in planning[0][3] and 'source:up-done' not in planning[0][3]
        assert 'source:up-blocked' not in control[0][3]
        state=read(name)
        assert state['handoffs']['source:up-done']['transport_count']==1 and state['handoffs']['source:up-blocked']['transport_count']==1
        print('PASS upward P1：混合done/blocked按真实来源分流；交付提示安排门禁；预算只记各自子集')
        def reject_planner(event,task=name):
            for verb in ['received','accept','prepared','handled']:
                result=handoff(verb,event,task,actor='planner-pane',ok=False)
                assert '规划不能办理主控专属交接' in result.stderr,(verb,result.stderr)
        reject_planner('source:up-done')
        migration_state=read(intake_name)
        migrated=next(h['event_id'] for h in migration_state['handoffs'].values() if migration_state['events'][h['source_seq']-1]['kind']=='migrate')
        reject_planner(migrated,intake_name)
        for verb in ['received','accept','prepared']: handoff(verb,'source:up-blocked',actor='planner-pane')
        bad_ref=p/'tasks/up-unknown.json'
        bad_ref.write_text(json.dumps({'event_id':'source:up-blocked','op_id':'handle-source:up-blocked','outcome':'unknown','evidence':'not proven'}))
        before=ticket.read_bytes()
        failed=cli('qwb-send.sh','handled','--task',ticket,'--event','source:up-blocked','--op','handle-source:up-blocked','--result-ref',bad_ref,actor='planner-pane',ok=False)
        assert ticket.read_bytes()==before and '结果读回不匹配/未知' in failed.stderr
        env['PL_FAIL_PUBLISH']='1'
        try:
            failed=handoff('handled','source:up-blocked',actor='planner-pane',ok=False)
            assert '候选发布失败' in failed.stderr
        finally: del env['PL_FAIL_PUBLISH']
        handoff('handled','source:up-blocked',actor='planner-pane')
        # 直接read，不先调用pending：原handled与派生必须已在同一次发布里可见。
        state=read(name); result_id='source:planner-result:'+hashlib.sha256(b'source:up-blocked').hexdigest()
        original_h=state['handoffs']['source:up-blocked']; result_h=state['handoffs'][result_id]
        assert original_h['handled']==1 and not result_h['handled'] and result_h['source_event']=='up-blocked'
        for text in ['source:up-blocked','actor=planner','op=handle-source:up-blocked',original_h['result_ref'],original_h['result_sha256']]: assert text in result_h['payload']
        before=ticket.read_bytes(); handoff('handled','source:up-blocked',actor='planner-pane')
        assert ticket.read_bytes()==before, '重放handled产生第二条上行或额外事件'
        # 升级恢复夹具：模拟旧writer已handled但尚无结果上行，不能依赖规划再次行动。
        legacy_state=json.loads(json.dumps(state)); del legacy_state['handoffs'][result_id]
        legacy_body=before.split(b'\n<!-- qwb-collab-v1\n')[0]
        ticket.write_bytes(legacy_body+b'\n<!-- qwb-collab-v1\n'+json.dumps(legacy_state,ensure_ascii=False,separators=(',',':')).encode()+b'\n-->\n')
        pending(); recovered=read(name)
        assert recovered['handoffs'][result_id]==result_h and recovered['handoffs']['source:up-blocked']==original_h
        restored=ticket.read_bytes(); pending(); assert ticket.read_bytes()==restored, '恢复扫描重复造上行'
        reject_planner(result_id)
        routes,_=deliveries()
        assert len(routes)==1 and routes[0][2]=='ctl' and result_id in routes[0][3] and original_h['result_sha256'] in routes[0][3],routes
        print('PASS upward P2：blocked先规划；handled原子派生带结果引用的主控上行；重复handled原字节不变')
        print('PASS upward writer：done/迁入核查/结果上行的四入口拒绝规划，票字节不变；未知结果拒绝无半发布')
        settle()
        # needs-decision与question均须是派发工人的真实来源；question本身没有op字段。
        call('append',name,'--event-id','up-decision','--','needs-decision: 原授权内技术选择',actor='up-worker')
        call('question',name,'--event-id','up-question','--','up-budget','真实用户预算问题',actor='up-worker')
        pending()
        for event in ['source:up-decision','source:up-question']:
            for verb in ['received','accept','prepared','handled']: handoff(verb,event,actor='planner-pane')
            result='source:planner-result:'+hashlib.sha256(event.encode()).hexdigest()
            assert result in read(name)['handoffs']
        assert read(name)['questions']['up-budget']['answer']=='' and read(name)['questions']['up-budget']['resumed']==''
        call('answer',name,'--','up-budget','fixture controller approved')
        call('resume',name,'--','up-budget','fixture resumes after explicit answer')
        settle(); before=ticket.read_bytes(); assert pending()==[] and ticket.read_bytes()==before, '上行回执自激'
        print('PASS upward question/needs-decision：均派生结果，handled不关闭用户问题，上行处理不递归')
        # payload冒充done不改变系统来源；普通worker working静默。
        fake=call('handoff-send',name,'--','controller','up-fake-done','1','done: 只是用户正文',actor='up-worker').stdout.strip()
        call('append',name,'--event-id','up-progress','--','working: 正在推进',actor='up-worker')
        routes,_=deliveries()
        assert len(routes)==1 and routes[0][2]=='planner-pane' and fake in routes[0][3] and 'source:up-progress' not in routes[0][3],routes
        print('PASS upward 范围边界：working进度静默；显式send仍交接，用户done正文不当真实交付')
        settle()
        # 规划身份不符只能回主控，不能让原交接被消费。
        call('append',name,'--event-id','up-fallback','--','blocked: 身份失效回主控',actor='up-worker')
        native_path=Path(env['PL_NATIVE']); native_bytes=native_path.read_bytes()
        native=json.loads(native_bytes); del native['planner-pane']; native_path.write_text(json.dumps(native))
        try:
            routes,_=deliveries()
            assert len(routes)==1 and routes[0][2]=='ctl' and 'source:up-fallback' in routes[0][3],routes
            assert not read(name)['handoffs']['source:up-fallback']['handled']
        finally: native_path.write_bytes(native_bytes)
        print('PASS upward 场景6：规划身份失效回主控，原事件仍未handled')
        settle()
        call('append',name,'--event-id','up-second-proof','--','blocked: 第二次身份复核失效',actor='up-worker')
        native_bytes=native_path.read_bytes(); env['PL_EXPIRE_PROOF']=str(temp/'up-proof-counter')
        try:
            routes,_=deliveries()
            # role status与其activity探针各读一次pane；第三次读才进入第二轮gate_proof。
            assert int(Path(env['PL_EXPIRE_PROOF']).read_text())==3
            assert len(routes)==1 and routes[0][2]=='ctl' and 'source:up-second-proof' in routes[0][3],routes
        finally:
            del env['PL_EXPIRE_PROOF']; native_path.write_bytes(native_bytes)
        settle()
        call('append',name,'--event-id','up-block-mode','--','done: 宿主block同样回主控',actor='up-worker')
        result=cli('qwb-wake.sh','--block','--max-ms','1',ok=False)
        assert result.returncode==2 and 'source:up-block-mode' in result.stdout and '下一步：主控安排门禁' in result.stdout,(result.returncode,result.stdout,result.stderr)
        settle()
        print('PASS upward 双身份复核不减，第二次失效回主控；block入口同样报告交付')
        # 用公开04收据/审核/verdict走到accepted；私有true门不等于仓库全门。
        environment=temp/'up-environment'; environment.write_text('private fixture dependencies\n')
        assignment={'candidate':str(p),'base':git('rev-parse','HEAD'),'attempt':'1','policy':'existing-v1','environment':str(environment),'required':{'full':['user_good','user_failure']},'workers':{'review':'reviewer','rework':'sol'}}
        gate_assignment=call('gate-assign',name,'--','gate',payload('up-gate.json',assignment)).stdout.strip()
        reject_planner('source:'+gate_assignment)
        call('claim',name,'--','up-gate',actor='gate-pane')
        exhausted_checks(gate=True)
        call('append',name,'--event-id','up-rework-done','--','done: 门禁接返修成果',actor='up-worker')
        routes,_=deliveries(); assert len(routes)==1 and routes[0][2]=='gate-pane',routes
        report=temp/'up-receipt.json'
        cli('qwb-test.sh','full','--task',ticket,'--ledger-project',p,'--op','up-gate','--report',report,actor='gate-pane')
        context=json.loads(report.read_text())['after']
        identities=[]
        for label,provider,model,effort in [('implementer','openai-codex','gpt-6.1-sol','high'),('reviewer','anthropic','claude-opus-4-6','low')]:
            sid='up-'+label; native=temp/(sid+'.jsonl')
            native.write_text(''.join(json.dumps(r)+'\n' for r in [{'type':'session','id':sid,'cwd':str(p)},{'type':'model_change','provider':provider,'modelId':model},{'type':'thinking_level_change','thinkingLevel':effort}]))
            identities.append({'session':sid,'model':model,'evidence':str(native)})
        review={'context':context,'implementer':identities[0],'reviewer':identities[1],'standards':'pass','spec':'pass','covered':['user_good','user_failure'],'findings':[]}
        call('gate-review',name,'--','up-gate',payload('up-review.json',review),actor='gate-pane')
        call('gate-verdict',name,'--','up-gate','accepted',actor='gate-pane')
        call('append',name,'--event-id','up-after-accepted','--','working: spec-resolved: 等主控落地')
        routes,_=deliveries()
        assert len(routes)==1 and routes[0][2]=='ctl' and 'source:up-after-accepted' in routes[0][3] and '门禁 accepted' in routes[0][3],routes
        assert read(name)['gate']['verdict']=='accepted' and read(name)['claim']['owner']=='gate-pane' and read(name)['phase']=='running'
        print('PASS upward P3：公开accepted之后交接回主控，pending门禁优先、claim/state不变')
        reject_planner('source:up-after-accepted')
        print('PASS upward writer：accepted后续交接的四入口拒绝规划，票字节不变')
        if os.environ.get('QWB_PLANNING_UPWARD_COMPARE')!='1': return
        # 同路径、同初始票/身份，固定两份writer的时钟与随机输入；比较未过滤的完整字节。
        # 复用耗尽测试已登记的测试角色；fake Herdr每个角色标签只有一个pane。
        probe=subprocess.run(['bash','-c','. "$1"; qwb_gate_identity "$2" up-test 测试体系','probe',str(ROOT/'bin/qwb-lib.sh'),str(p)],env=env,capture_output=True,text=True)
        assert probe.returncode==0,(probe.stdout,probe.stderr)
        test_identity=json.loads(probe.stdout)
        original=ticket.read_bytes(); initial=read(name); native_path=Path(env['PL_NATIVE']); native_bytes=native_path.read_bytes()
        other_dir=temp/'compat-other-tasks'; other_dir.mkdir()
        others=[f for f in (p/'tasks').glob('*.md') if f!=ticket]
        for f in others: f.rename(other_dir/f.name)
        runtime=p/'qwbuddy/bin'
        notify_compare=os.environ.get('QWB_NOTIFY_COMPARE')=='1'
        compare_base='4b1f2e2' if notify_compare else '44ab8ac'
        originals={s:(runtime/s).read_bytes() for s in ['qwb-ledger.sh','qwb-wake.sh']+(['qwb-send.sh','qwb-lib.sh'] if notify_compare else [])}
        snapshots={}
        def frozen_ticket(data):
            if notify_compare:
                # Old already-claimed grants never had A notifications; this is outside A.
                data['handoffs']={key:h for key,h in data['handoffs'].items() if data['events'][h['source_seq']-1]['kind']!='gate-assign'}
            body=original.split(b'\n<!-- qwb-collab-v1\n')[0]
            return body+b'\n<!-- qwb-collab-v1\n'+json.dumps(data,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()+b'\n-->\n'
        for case in ['plain','pending','rework','test-request']:
            data=json.loads(json.dumps(initial))
            if case=='plain': data.pop('planning'); data.pop('gate'); data['claim']=None
            elif case in ('pending','rework'): data['gate']['verdict']=case
            else:
                event_id='up-after-accepted'
                data['test_requests']={'compat-test':{'event_id':event_id,'identity':test_identity,'reason':'new-behavior','scenario':'user_good','context':{},'reply':{},'reply_sha256':''}}
            snapshots[case]=frozen_ticket(data)
        live=json.loads(json.dumps(initial)); live.pop('planning'); live.pop('gate'); live['claim']=None
        live['seq']+=1; live['rev']+=1
        live_line=f'dispatch: 2099 op_id=compat-live worker=sol agent=up-worker pane=up-worker dir={p}'
        live['events'].append({'event_id':'compat-live','seq':live['seq'],'at':'2099-01-01T00:00:00Z','kind':'dispatch','actor':'ctl','op_id':'compat-live','spec_rev':live['spec_rev'],'line':live_line})
        live['ops']['compat-live']={'owner':'ctl','pane':'up-worker','status':'sent'}; live['workers']['up-worker']='compat-live'
        snapshots['live']=frozen_ticket(live).replace(b'\n<!-- qwb-collab-v1\n',b'\n'+live_line.encode()+b'\n<!-- qwb-collab-v1\n')
        snapshots['legacy']=b'# legacy\nstate: blocked\nblocked: unchanged legacy input\n'
        evidence=os.environ.get('QWB_PLANNING_UPWARD_EVIDENCE')
        evidence=Path(evidence) if evidence else None
        if evidence: evidence.mkdir(parents=True,exist_ok=False)
        try:
            for case,snapshot in snapshots.items():
                outputs=[]
                for version in ['baseline','candidate']:
                    for script in originals:
                        raw=subprocess.check_output(['git','-C',str(ROOT),'show',compare_base+':bin/'+script]) if version=='baseline' else (ROOT/'bin'/script).read_bytes()
                        if script=='qwb-ledger.sh':
                            raw=raw.replace(b'my $now=int(time()*1000);',b'my $now=4102444800000;')
                            raw=raw.replace(b"strftime('%Y-%m-%dT%H:%M:%SZ',gmtime)",b"'2099-01-01T00:00:00Z'")
                            raw=raw.replace(b"$event=unpack('H*',$bytes);",b'$event=substr(sha256_hex("$cmd:$data->{seq}"),0,32);')
                        (runtime/script).write_bytes(raw)
                    ticket.write_bytes(snapshot); native_path.write_bytes(native_bytes); log.write_bytes(b'')
                    result=subprocess.run(['bash',str(runtime/'qwb-wake.sh'),'--project',str(p),'--once','--pane','ctl'],env=env,capture_output=True)
                    observed={'stdout':result.stdout,'stderr':result.stderr,'rc':str(result.returncode).encode(),'ticket':ticket.read_bytes(),'herdr':log.read_bytes()}
                    assert result.returncode==0,(case,version,observed)
                    calls=[json.loads(s) for s in observed['herdr'].splitlines()]
                    expected='gate-pane' if case in ('pending','rework') else ('worker-测试体系' if case=='test-request' else 'ctl')
                    assert any(a[:3]==['pane','run',expected] for a in calls),(case,version,calls)
                    outputs.append(observed)
                    if evidence:
                        for key,value in observed.items(): (evidence/(case+'-'+version+'.'+key)).write_bytes(value)
                for key in outputs[0]:
                    candidate=outputs[1][key]
                    if case=='live' and key=='herdr' and not notify_compare:
                        lines=candidate.splitlines(keepends=True)
                        probes=[i for i,line in enumerate(lines) if json.loads(line)==['pane','get','up-worker']]
                        assert len(probes)==1, ('只允许一次新增工人只读探针',probes)
                        candidate=b''.join(line for i,line in enumerate(lines) if i!=probes[0])
                    assert outputs[0][key]==candidate, ('P6 byte mismatch',case,key,outputs[0][key],candidate)
                print('PASS upward P6逐字节 '+case+': stdout/stderr/rc/票/Herdr一致'+('（仅允许一次新增工人只读探针）' if case=='live' and not notify_compare else ''))
        finally:
            ticket.write_bytes(original); native_path.write_bytes(native_bytes)
            for script,raw in originals.items(): (runtime/script).write_bytes(raw)
            for f in others: (other_dir/f.name).rename(f)
    if os.environ.get('QWB_PLANNING_UPWARD_ONLY')=='1':
        upward_checks()
        raise SystemExit(0)
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
    assert worker_report('B.md')==worker_report('C.md')==report_a
    private_payload=p/'qwbuddy/.roles/planner.work/request.json'; private_payload.parent.mkdir()
    private_payload.write_bytes((temp/'C.json').read_bytes())
    replay=(p/'tasks/C.md').read_bytes()
    call('new','C.md','--',private_payload,actor='planner-pane')
    assert (p/'tasks/C.md').read_bytes()==replay and git('status','--porcelain=v1','--untracked-files=all')==''
    print('PASS user_规划授权开票报告相同且角色私有载荷可公开重放，候选保持clean')
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
    clock=temp/'prompt-clock'; clock.write_text('0\n')
    now=temp/'prompt-now.sh'; now.write_text('#!/bin/sh\ncat "$PL_PROMPT_CLOCK"\n'); now.chmod(0o755)
    sleeper=temp/'prompt-sleep.sh'; sleeper.write_text('#!/bin/sh\necho $(( $(cat "$PL_PROMPT_CLOCK") + 1000 )) > "$PL_PROMPT_CLOCK"\n'); sleeper.chmod(0o755)
    mark=count()
    prompted=run('C.md',actor='planner-pane',extra={'PL_PROMPT_HOLD':'1','PL_PROMPT_CLOCK':str(clock),'QWB_NOW_MS_CMD':str(now),'QWB_SLEEP_CMD':str(sleeper)})
    c_running=read('C.md')
    calls=[json.loads(row) for row in log.read_text().splitlines()[mark:]]
    enters=[a for a in calls if a[:2]==['pane','send-keys']]
    dispatch=next(e for e in c_running['events'] if e['kind']=='dispatch')
    assert len(enters)==1 and int(clock.read_text())==15000 and '账本拒绝' not in prompted.stderr,(enters,prompted)
    note=f"prompt-submit-enter op={dispatch['op_id']} pane={enters[0][2]}"
    if baseline:
        assert note in (p/'tasks/C.md').read_text() and note not in prompted.stdout,prompted.stdout
        print(f'BASELINE planning rc={prompted.returncode} stdout={prompted.stdout!r} stderr={prompted.stderr!r} enters=1 ticket-note={note!r}',flush=True)
    else:
        assert prompted.stdout.count(note+'\n')==1 and 'prompt-submit-enter' not in (p/'tasks/C.md').read_text(),prompted.stdout
        print('PASS user_规划派工提示词停输入框：补一次Enter成功，stdout含op/pane，票无额外working/拒绝痕迹',flush=True)
    assert len([e for e in c_running['events'] if e['kind']=='dispatch'])==1 and c_running['claim'] is None
    if os.environ.get('QWB_PLANNING_PROMPT_ONLY')=='1':
        raise SystemExit(0)
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
    assignment=payload('gate.json',binding)
    # 固定旧实现的真实拒绝与成功对照；只在私有fixture观察副本冻结时钟/事件ID。
    byte_bin=temp/'byte-bin'; shutil.copytree(ROOT/'bin',byte_bin)
    scripts=[]
    for label,source_bytes in [('old',subprocess.check_output(['git','-C',str(ROOT),'show','d66d77c:bin/qwb-ledger.sh'])),('new',(ROOT/'bin/qwb-ledger.sh').read_bytes())]:
        assert source_bytes.count(b'use Time::HiRes qw(time);')==1 and source_bytes.count(b',gmtime)')==2
        script=byte_bin/('qwb-ledger-'+label+'.sh')
        script.write_bytes(source_bytes.replace(b'use Time::HiRes qw(time);',b'use subs qw(time); sub time { 2099000000 }').replace(b',gmtime)',b',gmtime(2099000000))'))
        scripts.append(script)
    def byte_compare(verb,*args):
        task=p/'tasks/B.md'; raw=task.read_bytes(); results=[]
        try:
            for script in scripts:
                result=cli(str(script),verb,'--project',p,'--task',task,'--event-id','ticket-body-byte-check','--',*args)
                results.append((result.returncode,result.stdout.encode(),result.stderr.encode(),task.read_bytes()))
                task.write_bytes(raw)
            if verb=='gate-assign':
                assert results[0][:3]==results[1][:3], 'gate-assign changed stdout/stderr/rc'
                old_body,old_json=results[0][3].split(b'\n<!-- qwb-collab-v1\n');new_body,new_json=results[1][3].split(b'\n<!-- qwb-collab-v1\n')
                old_data=json.loads(old_json.split(b'\n-->')[0]);new_data=json.loads(new_json.split(b'\n-->')[0])
                added=new_data['handoffs'].pop('source:ticket-body-byte-check')
                expected=dict(event_id='source:ticket-body-byte-check',corr='source:ticket-body-byte-check',attempt='1',recipient='controller',source_event='ticket-body-byte-check',source_seq=new_data['seq'],source_actor='ctl',payload='门禁待接手；授权=ticket-body-byte-check；请先 claim，再按原交接协议读取成果。',transport_count=0,transport_at=0,received='',accepted='',owner_fp='',op_id='',activity_at=0,wait_until=0,wait_reason='',prepared=0,handled=0,result_ref='',result_sha256='')
                assert added==expected, added
                if 'handoffs' not in old_data:
                    assert not new_data['handoffs'];del new_data['handoffs']
                assert new_body==old_body and new_data==old_data, 'gate-assign changed facts beyond its authorized A handoff'
            else:assert results[0]==results[1], (verb,'stdout/stderr/rc/写后票字节不一致')
        finally: task.write_bytes(raw)
    byte_compare('read')
    byte_compare('gate-assign','gate',assignment)
    print('PASS user_其余行为字节对照：固定d66d77c的read逐字节一致；gate-assign仅新增A授权交接，stdout/stderr/rc/正文/其余事实均不变')
    tracked=p/'qwbuddy/config.sh'; tracked_bytes=tracked.read_bytes()
    scratch=p/'未提交 payload.json'; scratch.write_text('{}\n')
    tracked.write_bytes(tracked_bytes+b'\n# uncommitted fixture\n')
    extra_paths=[]
    try:
        raw_b=(p/'tasks/B.md').read_bytes()
        for task,route in [('B.md','由规划在预算内续派原工人'),('A.md','由主控续派原工人')]:
            raw=(p/'tasks'/task).read_bytes()
            rejected=call('gate-assign',task,'--','gate',assignment,ok=False)
            assert rejected.returncode==255 and rejected.stdout==''
            assert rejected.stderr.startswith('账本拒绝：授权候选必须clean\n'), rejected.stderr
            assert all(word in rejected.stderr for word in ['qwbuddy/config.sh','未提交 payload.json','原副本提交后重试',route]), rejected.stderr
            if task=='B.md': assert 'plan-authorize' in rejected.stderr and '预算不足' in rejected.stderr
            assert (p/'tasks'/task).read_bytes()==raw
        old_rejected=cli(str(scripts[0]),'gate-assign','--project',p,'--task',p/'tasks/B.md','--','gate',assignment,ok=False)
        assert old_rejected.returncode==255 and old_rejected.stdout=='' and old_rejected.stderr=='账本拒绝：授权候选必须clean\n', old_rejected
        assert (p/'tasks/B.md').read_bytes()==raw_b
        for index in range(11):
            extra=p/f'probe-{index:02}.json'; extra_paths.append(extra); extra.write_text('{}\n')
        capped=call('gate-assign','B.md','--','gate',assignment,ok=False)
        listed=capped.stderr.split('Git状态）：\n',1)[1].split('\n另有',1)[0].splitlines()
        assert len(listed)==10 and '\n另有3条未列出。\n' in capped.stderr, capped.stderr
        assert (p/'tasks/B.md').read_bytes()==raw_b
        print('PASS user_候选dirty拒绝给出路：rc255/原前缀；tracked与中文空格untracked路径；规划/主控各续派原工人，票字节不变')
    finally:
        tracked.write_bytes(tracked_bytes); scratch.unlink()
        for extra in extra_paths: extra.unlink()
    call('gate-assign','B.md','--','gate',assignment)
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
    assert worker_report('B.md')==report_a
    print('PASS user_修订规格保留报告：plan-revision/revision-handoff/revise成功，固定报告要求逐字节不变')
    call('gate-context','B.md','--','handoff-B',actor='gate-pane',ok=False)
    mark=count(); run('B.md',actor='planner-pane',ok=False); no_dispatch_since(mark)
    # 已verified历史不重写；新需求须后续票，拒绝时原MD逐字节保持。
    call('state','C.md','--','verified'); history=(p/'tasks/C.md').read_bytes()
    call('plan-revision','C.md','--expect',read('C.md')['rev'],'--',revfile,actor='planner-pane',ok=False)
    assert (p/'tasks/C.md').read_bytes()==history
    print('PASS user_变更使旧证据失效：CAS/显式gate handoff，旧binding保留且失效；原话不覆盖；C不中止；已验收历史拒绝重写')
    accept_land_checks()
    upward_checks()
    evidence=os.environ.get('QWB_PLANNING_EVIDENCE_DIR')
    if evidence:
        dest=Path(evidence);dest.mkdir(parents=True,exist_ok=False)
        for task in ['intake.md','A.md','B.md','C.md']:
            (dest/(task+'.json')).write_text(call('read',task).stdout);shutil.copy(p/'tasks'/task,dest/task)
        shutil.copy(log,dest/'fake-herdr.jsonl')
        (dest/'README.md').write_text('私有Git+fakeHerdr边界fixture；并非现场session/PID/生产交互证据。\n')
PY

if [[ "${QWB_CLAUDE_PLANNER:-}" != 1 ]]; then
  QWB_CLAUDE_PLANNER=1 bash "$0"
fi
