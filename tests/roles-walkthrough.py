# Executed by collab-land.sh inside its private Git/process/socket fixture.
# Only native terminal/process responses are synthetic; all task and Git operations are real.
import re
import signal
import os
from pathlib import Path

if 'p' not in globals():
    os.execv('/bin/bash', ['bash', str(Path(__file__).with_name('collab-land.sh')), 'walkthrough'])

from process_fixture import register, release

doc = p/'qwbuddy/roles/常驻流程.md'
assert doc.is_file(), 'walkthrough step 00: installed 常驻流程.md missing'
blocks = re.findall(r'<!-- qwb-walk:([\w-]+) actor=([\w-]+) -->\n```bash\n(.*?)\n```', doc.read_text(), re.S)
assert len(blocks) == 17, ('walkthrough step 00: missing executable blocks', len(blocks))
assert len({b[0] for b in blocks}) == len(blocks)

# Exercise a genuinely empty installation before upgrading the configured fixture.
fresh = tmp/'fresh-install'
fresh.mkdir()
installed = subprocess.run(['bash', str(ROOT/'bin/qwb-init.sh'), str(fresh)], env=env, capture_output=True, text=True)
assert installed.returncode == 0, installed.stderr
assert (fresh/'qwbuddy/roles/顾问.md').is_file() and not (fresh/'qwbuddy/roles/咨询师.md').exists()
assert (fresh/'qwbuddy/roles/常驻流程.md').read_bytes()==doc.read_bytes()
print('PASS user_正常路径_顾问文件改名后安装与清单一致（空目录实装）', flush=True)
doc.unlink()  # Only this fixture-owned copy; prove the installer actually supplies the walkthrough.
installed = subprocess.run(['bash', str(ROOT/'bin/qwb-init.sh'), str(p)], env=env, capture_output=True, text=True)
assert installed.returncode == 0 and doc.is_file(), installed.stderr
legacy = p/'qwbuddy/roles/咨询师.md'
legacy.write_bytes('用户定制的旧角色\n保留精确字节\n'.encode())
legacy_bytes = legacy.read_bytes()
for _ in range(2):
    upgraded = subprocess.run(['bash', str(ROOT/'bin/qwb-init.sh'), str(p)], env=env, capture_output=True, text=True)
    assert upgraded.returncode == 0 and legacy.read_bytes() == legacy_bytes
    assert '咨询师.md 未改动' in upgraded.stdout and '顾问.md' in upgraded.stdout
print('PASS user_正常路径_已装旧版的项目升级不丢改动（重复升级逐字节保持且有提示）', flush=True)
for file in (ROOT/'templates').rglob('*'):
    if file.is_file():
        assert not any(w in file.read_text() for w in ['同family', '换家族', '咨询师']), file
print('PASS user_正常路径_说明书里不再有过时说法', flush=True)
# Read again after actual installation, so stale copied documentation cannot pass.
blocks = re.findall(r'<!-- qwb-walk:([\w-]+) actor=([\w-]+) -->\n```bash\n(.*?)\n```', doc.read_text(), re.S)
revisions = re.findall(r'<!-- qwb-revise:([\w-]+) actor=([\w-]+) -->\n```bash\n(.*?)\n```', doc.read_text(), re.S)
assert len(revisions)==4, 'walkthrough: missing revision branch blocks'
(p/'qwbuddy/workers.sh').write_bytes((ROOT/'templates/workers.sh').read_bytes())
config = (p/'qwbuddy/config.sh').read_text().replace("QWB_WORKERS='sol reviewer'", "QWB_WORKERS='pi claude pi-sol-high pi-astra-high pi-astra-low claude-opus-medium claude-fable-low'")
config = config.replace("QWB_GATE_FAST='test -f product.txt'", "QWB_GATE_FAST='test -f hello.txt'")
config = config.replace("QWB_GATE_FULL='test -s product.txt'", '''QWB_GATE_FULL="python3 -c 'from pathlib import Path; expected=bytes([104,101,108,108,111,10]); assert Path(\\\"hello.txt\\\").read_bytes()==expected; assert bytes([119,114,111,110,103,10])!=expected'"''')
(p/'qwbuddy/config.sh').write_text(config)
(p/'qwbuddy/dispatch-rules.json').write_bytes((ROOT/'templates/dispatch-rules.json').read_bytes())
git('add', '.')
git('-c', 'user.name=Test', '-c', 'user.email=test@invalid', 'commit', '-qm', 'Prepare walkthrough fixture')
base = git('rev-parse', 'main')
# Existing runtime clock hooks eliminate real retry sleeps even on a failed binding.
clock = tmp/'walk-clock'
clock.write_text('4102444800000')
now = tmp/'walk-now'
now.write_text('#!/usr/bin/env python3\nimport os\nfrom pathlib import Path\nprint(Path(os.environ["WALK_CLOCK"]).read_text())\n')
sleeper = tmp/'walk-sleep'
sleeper.write_text('#!/usr/bin/env python3\nimport os,sys\nfrom pathlib import Path\np=Path(os.environ["WALK_CLOCK"]);p.write_text(str(int(p.read_text())+int(sys.argv[1])))\n')
now.chmod(0o755);sleeper.chmod(0o755)
env.update(WALK_CLOCK=str(clock), QWB_NOW_MS_CMD=str(now), QWB_SLEEP_CMD=str(sleeper))
env.update(GIT_AUTHOR_NAME='Test', GIT_AUTHOR_EMAIL='test@invalid', GIT_COMMITTER_NAME='Test', GIT_COMMITTER_EMAIL='test@invalid')

# Extend the existing land fixture's native boundary for two roles and two workers.
# Children are registered and really terminate on pane close; the lsof deletion probe stays real.
# Real PID birth times keep the worker-death assertion meaningful.
(stub/'ps').write_text('#!/bin/sh\nexec /bin/ps "$@"\n')
children = []
for kind in ['IMPL', 'REVIEW']:
    child = subprocess.Popen(['python3', '-u', '-c', 'import sys; sys.stdin.readline()'], stdin=subprocess.PIPE, start_new_session=True)
    register(child.pid)
    children.append(child)
    env['WALK_'+kind+'_PID'] = str(child.pid)
atexit.register(lambda: [child.poll() is None and child.terminate() for child in children])
(stub/'herdr').write_text('''#!/usr/bin/env python3
import json,os,signal,sys
from pathlib import Path
a=sys.argv[1:];f=Path(os.environ['LAND_NATIVE_STATE']);s=json.loads(f.read_text()) if f.exists() else {}
with open(os.environ['LAND_NATIVE_LOG'],'a') as log:print(json.dumps(a),file=log)
p=os.environ['LAND_PROJECT'];candidate=p+'/.worktrees/hello'
s.setdefault('panes',{});s.setdefault('seq',0)
s['panes'].setdefault('ctl',{'session':'ctl-session','sid':'ctl-session','pid':int(os.environ['LAND_PID']),'model':'codex/gpt-6.1-sol','effort':'high'})
def out(d):print(json.dumps({'result':d}))
def rows():
 w=[{'workspace_id':'ws','worktree':{'repo_root':p,'is_linked_worktree':False}}]
 if s.get('space') and not s.get('space_closed'):w.append({'workspace_id':'task-space','worktree':{'repo_root':p,'is_linked_worktree':True,'checkout_path':candidate}})
 return w
if a[:2]==['status','--json']:print(json.dumps({'server':{'socket':os.environ['LAND_SOCKET'],'session':os.environ.get('HERDR_SESSION')}}))
elif a[:2]==['workspace','list']:out({'workspaces':rows()})
elif a[:2]==['api','snapshot']:
 if 'snapshot' not in s:
  ids=[w['workspace_id'] for w in rows()]
  s['snapshot']={'workspaces':[{'workspace_id':w} for w in ids], 'tabs':[{'workspace_id':w,'tab_id':'task-tab' if w=='task-space' else 'ctl-tab'} for w in ids], 'panes':[{'workspace_id':w,'tab_id':'task-tab' if w=='task-space' else 'ctl-tab','pane_id':'task-pane' if w=='task-space' else 'ctl'} for w in ids], 'focused_workspace_id':'ws','focused_tab_id':'ctl-tab','focused_pane_id':'ctl'}
 out({'snapshot':s['snapshot']})
elif a[:2]==['worktree','open']:
 s['space']=True
 out({'workspace':{'workspace_id':'task-space'},'already_open':False,'root_pane':{'pane_id':'task-pane','tab_id':'task-tab','terminal_id':'task-terminal'}})
elif a[:2]==['tab','create']:
 label=a[a.index('--label')+1];pane='planner-pane' if label=='规划' else ('gate-pane' if label=='门禁' else 'review-pane')
 out({'root_pane':{'pane_id':pane,'tab_id':'tab-'+pane,'terminal_id':'terminal-'+pane}})
elif a[:2]==['agent','start']:
 v=a[a.index('--')+1:];pane=a[a.index('--pane')+1]
 role=pane in ['planner-pane','gate-pane'];sid=v[v.index('--session-id')+1] if '--session-id' in v else 'session-'+pane
 path=v[v.index('--session-dir')+1]+'/2099_'+sid+'.jsonl' if '--session-dir' in v else p+'/qwbuddy/.roles/'+sid+'.jsonl'
 model=v[v.index('--model')+1];effort=v[v.index('--thinking')+1]
 pid=int(os.environ['LAND_PID'] if role else os.environ['WALK_IMPL_PID' if pane=='task-pane' else 'WALK_REVIEW_PID'])
 s['panes'][pane]={'session':path,'sid':sid,'pid':pid,'model':model,'effort':effort}
 file=Path(path);file.parent.mkdir(parents=True,exist_ok=True)
 file.write_text('\\n'.join(json.dumps(x) for x in [{'type':'session','id':sid,'cwd':p if role else candidate},{'type':'model_change','modelId':model,'provider':'magpie'},{'type':'thinking_level_change','thinkingLevel':effort}])+'\\n')
 out({'type':'agent_started'})
elif a[:2]==['agent','get']:
 pane='review-pane' if any('review' in x for x in a[2:]) else 'task-pane'
 if pane not in s['panes']:print(json.dumps({'error':{'code':'agent_not_found'}}));sys.exit(1)
 out({'type':'agent_info','agent':{'pane_id':pane,'agent_status':'idle','state_change_seq':s['seq']}})
elif a[:2]==['pane','get']:
 pane=a[2];v=s['panes'].get(pane,{});d={'pane_id':pane,'workspace_id':'task-space' if pane in ['task-pane','review-pane'] else 'ws','tab_id':'task-tab' if pane=='task-pane' else 'tab-'+pane,'terminal_id':'terminal-'+pane,'foreground_cwd':candidate if pane in ['task-pane','review-pane'] else p}
 if v and not v.get('closed'):d.update(agent='pi',agent_status='idle',agent_session={'agent':'pi','source':'herdr:pi','kind':'path','value':v['session']})
 else:d['agent']=None
 out({'pane':d})
elif a[:2]==['pane','process-info']:
 pane=a[-1];v=s['panes'].get(pane,{});live=bool(v) and not v.get('closed');pid=v['pid'] if live else 42
 out({'process_info':{'pane_id':pane,'shell_pid':42,'foreground_process_group_id':pid,'foreground_processes':[{'pid':pid,'argv0':'pi' if live else 'zsh','argv':['pi'] if live else ['zsh'],'cwd':candidate if live and pane in ['task-pane','review-pane'] else p}]}})
elif a[:2]==['pane','read']:
 v=s['panes'].get(a[2],{});print('(magpie) '+v.get('model','codex/gpt-6.1-sol')+' • '+v.get('effort','high'));sys.exit()
elif a[:2]==['pane','close']:
 v=s['panes'][a[2]];assert a[2] in ['task-pane','review-pane'];os.kill(v['pid'],signal.SIGTERM);v['closed']=True;out({'type':'pane_closed'})
elif a[:2]==['workspace','close']:
 s['space_closed']=True
 for key in ['workspaces','tabs','panes']:s['snapshot'][key]=[x for x in s['snapshot'][key] if x['workspace_id']!=a[2]]
 out({'type':'workspace_closed'})
elif a[:2]==['tab','list']:out({'tabs':[{'tab_id':'task-tab'},{'tab_id':'tab-review-pane'}]})
elif a[:2]==['pane','list']:out({'panes':[{'pane_id':'task-pane','agent_status':'idle'},{'pane_id':'review-pane','agent_status':'idle'}]})
elif a[:2] in (['agent','prompt'],['pane','send-keys']):s['seq']+=1;out({'type':'ok'})
elif a[:2] in (['pane','run'],['tab','rename'],['tab','close']):out({'type':'ok'})
else:print('unexpected fake Herdr command: '+repr(a),file=sys.stderr);sys.exit(77)
f.write_text(json.dumps(s))
''')

actors = {'controller':'ctl','planner':'planner-pane','gate':'gate-pane','worker':'task-pane','reviewer':'review-pane'}
values = {'ROOT':str(p), 'BASE':base, 'IMPL_PANE':'task-pane', 'REVIEW_PANE':'review-pane'}
def refresh():
    intake = p/'tasks/2026-10-05-intake.md'
    if intake.exists(): values['INTAKE_SHA'] = hashlib.sha256(intake.read_bytes()).hexdigest()
    source = p/'qwbuddy/.roles/controller.work/source-event.txt'
    if source.exists(): values['SOURCE_EVENT'] = source.read_text().strip()
    revision = p/'qwbuddy/.roles/controller.work/revision-event.txt'
    if revision.exists(): values['REVISION_EVENT'] = revision.read_text().strip()
    candidate = p/'.worktrees/hello'
    if candidate.exists(): values['HEAD'] = git('rev-parse','HEAD',at=candidate)
    context = p/'qwbuddy/.roles/gate.work/context.json'
    if context.exists(): values['CONTEXT'] = context.read_text().strip()
    native = Path(env['LAND_NATIVE_STATE'])
    if native.exists():
        for prefix,pane in [('IMPL','task-pane'),('REVIEW','review-pane')]:
            row = json.loads(native.read_text()).get('panes',{}).get(pane)
            if row: values[prefix+'_SESSION'] = row['sid']; values[prefix+'_NATIVE'] = row['session']
def execute(step,actor,code):
    # Fixture paths are generated internally without quote/newline characters. Never eval user substitutions.
    refresh()
    for key,value in values.items():
        if key!='CONTEXT': assert not any(c in value for c in "'\\\n\r\"")
        code=code.replace('@'+key+'@',value)
    assert not re.search(r'@[A-Z_]+@',code), ('unresolved documentation placeholder',step)
    script=tmp/('walk-'+step+'.sh');script.write_text('set -euo pipefail\n'+code+'\n')
    process=subprocess.Popen(['/bin/bash',str(script)],cwd=p,env=env|{'HERDR_PANE_ID':actors[actor]},stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
    register(process.pid)
    try: out,err=process.communicate(timeout=60)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid,signal.SIGTERM)
        try:out,err=process.communicate(timeout=10)
        except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);out,err=process.communicate()
        raise AssertionError('walkthrough step '+step+' timed out')
    finally:release(process.pid)
    print(f'STEP {step} actor={actor} rc={process.returncode}\n{out}{err}',flush=True)
    samples = re.findall(r'cat > [^\n]*?/([\w-]+\.json) <<', code)
    assert process.returncode==0, ('walkthrough step '+step+' samples='+','.join(samples),process.returncode,out,err)
    return err

try:
    for step,actor,code in blocks:
        if step=='03-assign':
            # Mutate only the installed document text, then use the same extraction/execution path.
            original=doc.read_bytes()
            try:
                document = doc.read_text()
                match = re.search(r"plan-assign.json <<'JSON'\n(.*?)\nJSON", document, re.S)
                assert match, 'walkthrough step 03-assign: plan-assign.json sample missing'
                try: grant = json.loads(match[1])
                except ValueError as error: raise AssertionError('walkthrough step 03-assign: plan-assign.json invalid JSON') from error
                grant['budget'] = {}
                doc.write_text(document[:match.start(1)] + json.dumps(grant,ensure_ascii=False,indent=2) + document[match.end(1):])
                mutated=re.findall(r'<!-- qwb-walk:([\w-]+) actor=([\w-]+) -->\n```bash\n(.*?)\n```',doc.read_text(),re.S)
                bad=next(b for b in mutated if b[0]==step)
                before=(p/'tasks/2026-10-05-intake.md').read_bytes()
                try: execute(step+'-bad-budget',actor,bad[2])
                except AssertionError as error:
                    assert all(s in str(error) for s in ['03-assign','plan-assign.json','启动授权/预算未明确']), str(error)
                else: raise AssertionError('walkthrough step 03-assign: corrupted plan-assign.json passed the normal runner')
                assert (p/'tasks/2026-10-05-intake.md').read_bytes()==before
                print('PASS user_失败路径_说明书样例被改坏时测试变红：03-assign plan-assign.json budget',flush=True)
            finally:doc.write_bytes(original)
        execute(step,actor,code)
        if step=='04-new':
            for revision_step,revision_actor,revision_code in revisions:
                execute(revision_step,revision_actor,revision_code)
            print('PASS 文档修订分支：真实source、CAS plan-revision/revise、清空授权、主控plan-authorize后继续派工',flush=True)
        if step=='11-close-workers':
            for child in children:
                child.wait(timeout=10)
                assert child.returncode==-signal.SIGTERM
        if step=='12-land':
            assert git('rev-parse','main')==values['HEAD']
            assert not (p/'.worktrees/hello').exists()
            assert not git('branch','--list','hello')
    assert git('status','--porcelain')==''
    git('merge-base','--is-ancestor',values['HEAD'],'main')
    for name in ['intake','hello']:
        data=json.loads(subprocess.check_output(['bash',str(p/'qwbuddy/bin/qwb-ledger.sh'),'read','--project',str(p),'--task',str(p/f'tasks/2026-10-05-{name}.md')],env=env,text=True))
        assert data['phase']=='verified' and data['claim'] is None
        if name=='intake':
            assert data['handoffs'] and all(h['handled'] for h in data['handoffs'].values())
        else:
            assert data['spec_rev']==1 and len(data['planning']['revisions'])==1
            assert data['gate']['verdict']=='accepted' and data['land']['stage']=='closed'
            assert data['land']['after']==values['HEAD']
    assert (p/'hello.txt').read_bytes()==b'hello\n'
    print('PASS user_正常路径_按说明书示例走到票结案：两票 verified、main 快进候选后窄提交账本、候选副本和分支清理',flush=True)
finally:
    for child in children:
        if child.poll() is None: child.terminate();child.wait(timeout=10)
        release(child.pid)
