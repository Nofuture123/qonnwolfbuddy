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

revision_timing = os.environ.get('QWB_WALK_REVISION', 'before')
probe = os.environ.get('QWB_R4_PROBE', '')
if revision_timing == 'dispatched':
    dispatched = re.findall(r'<!-- qwb-dispatched:([\w-]+) actor=([\w-]+) -->\n```bash\n(.*?)\n```', doc.read_text(), re.S)
    assert len(dispatched) == 1, 'walkthrough: missing dispatched revision branch'

# Exercise a genuinely empty installation before upgrading the configured fixture.
fresh = tmp/'fresh-install'
fresh.mkdir()
installed = subprocess.run(['bash', str(ROOT/'bin/qwb-init.sh'), str(fresh)], env=env, capture_output=True, text=True)
assert installed.returncode == 0, installed.stderr
assert (fresh/'qwbuddy/roles/顾问.md').is_file() and not (fresh/'qwbuddy/roles/咨询师.md').exists()
assert (fresh/'qwbuddy/roles/常驻流程.md').read_bytes()==doc.read_bytes()
if probe == 'lint' or not probe:
    fresh_config = fresh/'qwbuddy/config.sh'
    with fresh_config.open('a') as output:
        output.write('\nQWB_ROLE_PI_CONTROL="verified"\nQWB_ROLE_CLAUDE_CONTROL="verified"\nQWB_GATE_FAST="true"\nQWB_GATE_FULL="true"\n')
    def lint_fresh():
        return subprocess.run(['/bin/bash', str(fresh/'qwbuddy/bin/qwb-lint.sh'), '--project', str(fresh)], env=env, capture_output=True, text=True)
    checked = lint_fresh()
    assert checked.returncode == 0 and 'LINT PASS' in checked.stdout, ('verified role config rejected', checked.stdout, checked.stderr)
    print('PASS user_正常路径_启用常驻职责后自检通过', flush=True)
    with fresh_config.open('a') as output:
        output.write('QWB_DEAD_ROLE="unused"\nQWB_ASSIGNED_ONLY="unused"\nQWB_COMMENT_ONLY="unused"\nQWB_EXPORT_ONLY="unused"\n')
    (fresh/'qwbuddy/bin/dead-config.sh').write_text('QWB_ASSIGNED_ONLY="value"\n# export QWB_COMMENT_ONLY\n# os.environ.get("QWB_COMMENT_ONLY")\nexport QWB_EXPORT_ONLY # os.environ.get("QWB_EXPORT_ONLY")\necho QWB_DEAD_ROLE\n')
    checked = lint_fresh()
    assert checked.returncode != 0 and all(key in checked.stdout for key in ['QWB_DEAD_ROLE', 'QWB_ASSIGNED_ONLY', 'QWB_COMMENT_ONLY', 'QWB_EXPORT_ONLY']), checked.stdout
    print('PASS user_失败路径_真正的死配置仍被报出：赋值、注释、字面量及无解释器读取的export', flush=True)
    if probe == 'lint': raise SystemExit(0)
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
 out({'type':'agent_info','agent':{'name':a[2],'agent':'pi','foreground_cwd':candidate,'workspace_id':'task-space','pane_id':pane,'agent_status':'idle','state_change_seq':s['seq']}})
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

def read_task():
    result = subprocess.run(['/bin/bash', str(p/'qwbuddy/bin/qwb-ledger.sh'), 'read', '--project', str(p), '--task', 'tasks/2026-10-05-hello.md'], env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout)

def obligations(data):
    result = subprocess.run(['/bin/bash', '-c', '. "$1"; qwb_task_obligations_json', 'obligations', str(p/'qwbuddy/bin/qwb-lib.sh')], input=json.dumps(data), env=env, capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    return result.stdout

def compare_unrevised():
    # Baseline = today's scripts minus this ticket's classifier branch, never a pinned Git object.
    library = p/'qwbuddy/bin/qwb-lib.sh'
    writer = p/'qwbuddy/bin/qwb-ledger.sh'
    current = library.read_bytes(); original_writer = writer.read_bytes()
    old, removed = re.subn(r'    if \(\$e->\{kind\} eq "plan-ready".*?(?=    if \(\$e->\{kind\} eq "gate-assign")', '', current.decode(), count=1, flags=re.S)
    assert removed == 1, 'r4 classifier baseline removal must be exact'
    saved_tasks = {f:f.read_bytes() for f in (p/'tasks').iterdir() if f.is_file()}
    state = Path(env['LAND_NATIVE_STATE']); log = Path(env['LAND_NATIVE_LOG'])
    native = state.read_bytes(); native_log = log.read_bytes(); now_bytes = clock.read_bytes()
    def restore():
        for file,content in saved_tasks.items(): file.write_bytes(content)
        state.write_bytes(native); log.write_bytes(native_log); clock.write_bytes(now_bytes)
    results = []
    try:
        writer.write_text(freeze_writer(original_writer.decode()).replace("strftime('%Y-%m-%dT%H:%M:%SZ',gmtime)", "'2026-10-05T00:00:00Z'"))
        for version in [old.encode(), current]:
            restore(); library.write_bytes(version)
            observed = []
            for script,args in [('qwb-status.sh', []), ('qwb-wake.sh', ['--once', '--pane', 'ctl'])]:
                result = subprocess.run(['/bin/bash', str(p/'qwbuddy/bin'/script), '--project', str(p), *args], env=env, capture_output=True, timeout=60)
                assert result.returncode == 0, (script, result.stdout, result.stderr)
                observed.append((result.returncode, result.stdout, result.stderr))
            results.append((observed, {f.name:f.read_bytes() for f in saved_tasks}, log.read_bytes(), state.read_bytes()))
        if results[0] != results[1]:
            import difflib
            for index,(left,right) in enumerate(zip(results[0], results[1])):
                if left != right:
                    print('R4 byte mismatch component', index, flush=True)
                    print('\n'.join(difflib.unified_diff(repr(left).split('\\n'), repr(right).split('\\n')))[:16000], flush=True)
            raise AssertionError('unrevised status/wake stdout/stderr/rc/ticket/native bytes changed')
    finally:
        restore(); library.write_bytes(current); writer.write_bytes(original_writer)
    print('PASS user_正常路径_未涉及修订的状态和值守逐字节相同：当前脚本只撤本票分类，含rc与票/native字节', flush=True)

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
        if step == '06-worker':
            execute('06-progress', 'worker', "cd '@ROOT@'\nbash qwbuddy/bin/qwb-ledger.sh append --project '@ROOT@' --task tasks/2026-10-05-hello.md -- 'working: 本轮进度已记录，交付以done为准'")
        if step == '04-new' and revision_timing == 'before' and not probe:
            compare_unrevised()
        if (step=='04-new' and revision_timing == 'before') or (step=='06-worker' and revision_timing == 'dispatched'):
            original_worker = json.loads(Path(env['LAND_NATIVE_STATE']).read_text()).get('panes', {}).get('task-pane')
            revision_writer = p/'qwbuddy/bin/qwb-ledger.sh'
            revision_writer_bytes = revision_writer.read_bytes()
            assert revision_writer_bytes.count(b'use Time::HiRes qw(time);') == 1
            revision_writer.write_bytes(revision_writer_bytes.replace(b'use Time::HiRes qw(time);', b'use subs qw(time); sub time { open my $c,"<",$ENV{WALK_CLOCK} or die $!; return scalar(<$c>)/1000 }').replace(b',gmtime)', b',gmtime(time()))'))
            for revision_step,revision_actor,revision_code in revisions:
                execute(revision_step,revision_actor,revision_code)
                if revision_step == 'r03-apply':
                    result = subprocess.run(['/bin/bash', str(p/'qwbuddy/bin/qwb-ledger.sh'), 'plan-ready', '--project', str(p), '--task', 'tasks/2026-10-05-hello.md'], env=env, capture_output=True, text=True)
                    assert result.returncode != 0 and '首次启动无明确实施授权/预算' in result.stdout, (result.stdout, result.stderr)
                    data = read_task()
                    blocker = next(e for e in reversed(data['events']) if e['kind'] == 'plan-ready')
                    blocked_id = 'source:' + blocker['event_id']
                    assert 'source='+blocker['event_id'] in obligations(data)
                    execute('r03-blocked-wake', 'controller', "cd '@ROOT@'\nbash qwbuddy/bin/qwb-wake.sh --project '@ROOT@' --once --pane ctl")
                    data = read_task()
                    assert 'handoff='+blocked_id in obligations(data) and not data['handoffs'][blocked_id]['handled']
                    from prompt_file import native_calls
                    calls = native_calls(Path(env['LAND_NATIVE_LOG']).read_text().splitlines(), p)
                    assert any(a[:3] == ['pane', 'run', 'planner-pane'] and blocked_id in a[3] for a in calls), calls
                    print('PASS user_失败路径_未重新授权时阻塞仍是规划的待办且值守叫醒规划', flush=True)
                if revision_step == 'r04-authorize':
                    assert 'handoff='+blocked_id in obligations(read_task()), 'authorization alone must not settle blocked'
                    # A direct dispatch also publishes readiness through start-claim, without a watcher scan.
                    task_path = p/'tasks/2026-10-05-hello.md'
                    before_claim = task_path.read_bytes()
                    try:
                        execute('r04-direct-ready', 'planner', "cd '@ROOT@'\nbash qwbuddy/bin/qwb-ledger.sh start-claim --project '@ROOT@' --task tasks/2026-10-05-hello.md -- direct-ready pi-sol-high")
                        direct = read_task()
                        assert direct['events'][-1]['kind'] == 'start-claim'
                        assert 'handoff='+blocked_id not in obligations(direct), 'authorized direct start-claim readiness leaves the blocker unresolved'
                    finally:
                        task_path.write_bytes(before_claim)
                    mark = len(Path(env['LAND_NATIVE_LOG']).read_text().splitlines())
                    clock.write_text(str(int(clock.read_text()) + 1800001))
                    execute('r04-ready-wake', 'controller', "cd '@ROOT@'\nbash qwbuddy/bin/qwb-wake.sh --project '@ROOT@' --once --pane ctl")
                    data = read_task()
                    assert data['planning']['ready']['status'] == 'ready'
                    assert 'handoff='+blocked_id not in obligations(data), 'authorized and ready blocker remains an obligation'
                    assert not data['handoffs'][blocked_id]['handled'], 'satisfaction must preserve raw handled audit'
                    calls = native_calls(Path(env['LAND_NATIVE_LOG']).read_text().splitlines()[mark:], p)
                    assert not any(a[:2] == ['pane', 'run'] and blocked_id in a[3] for a in calls), calls
                    # Historical evidence is monotonic; unrelated spec and forged append do not satisfy it.
                    variant = json.loads(json.dumps(data)); variant['planning']['ready'] = {}
                    assert 'handoff='+blocked_id not in obligations(variant)
                    for kind in ['plan-authorize', 'plan-ready']:
                        variant = json.loads(json.dumps(data))
                        for event in variant['events']:
                            if event['seq'] > blocker['seq'] and event['kind'] == kind: event['spec_rev'] += 1
                        assert 'handoff='+blocked_id in obligations(variant), kind
                    variant = json.loads(json.dumps(data))
                    for event in variant['events']:
                        if event['seq'] > blocker['seq'] and event['kind'] == 'plan-authorize': event['seq'] = variant['seq'] + 1
                    variant['events'].sort(key=lambda e:e['seq'])
                    assert 'handoff='+blocked_id in obligations(variant), 'ready before authorization must not settle'
                    variant = json.loads(json.dumps(data))
                    variant['events'][blocker['seq']-1]['kind'] = 'blocked'
                    assert 'handoff='+blocked_id in obligations(variant), 'ordinary blocked text must not be auto-settled'
                    print('PASS user_正常路径_重新授权后各角色没有残留待办：同spec后续ready、值守无旧阻塞门铃、历史不伪造handled', flush=True)
            revision_writer.write_bytes(revision_writer_bytes)
            if revision_timing == 'dispatched':
                for revision_step,revision_actor,revision_code in dispatched:
                    execute(revision_step,revision_actor,revision_code)
                data = read_task()
                assert 'gate' not in data, 'old done must not be submitted to gate'
                old_done = [e for e in data['events'] if e['kind']=='done']
                assert old_done
                for event in old_done:
                    h = data['handoffs']['source:'+event['event_id']]
                    assert h['handled'] and json.loads(Path(h['result_ref']).read_text())['outcome'] == 'not-applied'
                for replay in ['05-dispatch', '06-worker']:
                    replay_actor,replay_code = next((a,c) for s,a,c in blocks if s == replay)
                    execute('redispatched-'+replay,replay_actor,replay_code)
                assert json.loads(Path(env['LAND_NATIVE_STATE']).read_text())['panes']['task-pane'] == original_worker
                native_rows = [json.loads(line) for line in Path(env['LAND_NATIVE_LOG']).read_text().splitlines()]
                assert len([a for a in native_rows if isinstance(a, list) and a[:3] == ['agent', 'start', 'qwb-hello']]) == 1, 'redispatch must not restart the implementer'
                assert len([e for e in read_task()['events'] if e['kind']=='dispatch']) == 2
                print('PASS user_正常路径_已派出后修订按说明书走通：旧done不送门控、not-applied、同副本同会话重派', flush=True)
            print('PASS 文档修订分支：真实source、CAS plan-revision/revise、清空授权、主控plan-authorize后继续派工',flush=True)
        if step=='07-readback':
            data = read_task()
            assert not data['handoffs'][blocked_id]['handled'], 'readback loop must skip the satisfied blocker'
            progress = [e for e in data['events'] if e['kind']=='working']
            assert progress and any(not data['handoffs']['source:'+e['event_id']]['handled'] for e in progress), 'readback loop must leave raw progress alone'
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
            assert data['handoffs'] and all(h['handled'] or h['payload'].startswith('working:') for h in data['handoffs'].values())
        else:
            assert data['spec_rev']==1 and len(data['planning']['revisions'])==1
            assert data['gate']['verdict']=='accepted' and data['land']['stage']=='closed'
            assert data['land']['after']==values['HEAD']
    # Both tickets are truly settled despite raw progress/accepted/release remaining pending.
    for name in ['intake','hello']:
        settled = json.loads(subprocess.check_output(['/bin/bash', str(p/'qwbuddy/bin/qwb-ledger.sh'), 'read', '--project', str(p), '--task', f'tasks/2026-10-05-{name}.md'], env=env, text=True))
        assert obligations(settled) == '', (name, obligations(settled))
    assert (p/'hello.txt').read_bytes()==b'hello\n'
    print('PASS user_正常路径_按说明书示例走到票结案：两票 verified、main 快进候选后窄提交账本、候选副本和分支清理',flush=True)
finally:
    for child in children:
        if child.poll() is None: child.terminate();child.wait(timeout=10)
        release(child.pid)
