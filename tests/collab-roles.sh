#!/usr/bin/env bash
# Public role/control entrances; Herdr alone is a fixture, never a live pane.
set -euo pipefail
# shellcheck source=/dev/null
. "$(dirname "${BASH_SOURCE[0]}")/process-fixture.sh"
qwb_test_scope "$@"
export TMPDIR="${QWB_TEST_SCOPE_DIR}"
mkdir -p "$TMPDIR" || exit 1
export GIT_CEILING_DIRECTORIES="$TMPDIR"
# Fail closed even if the PATH stub disappears.
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
export QWB_ROLES_TEST_ROOT="$ROOT"
python3 -B - <<'PY'
import hashlib, json, os, shlex, shutil, subprocess, tempfile
from pathlib import Path

root = Path(os.environ['QWB_ROLES_TEST_ROOT'])
with tempfile.TemporaryDirectory(prefix='qwb-roles-') as tmp:
    os.environ["TMPDIR"] = tmp
    tmp = str(Path(tmp).resolve())
    p = Path(tmp) / 'project'; p.mkdir()
    subprocess.run(['bash', str(root/'bin/qwb-init.sh'), str(p)], check=True, stdout=subprocess.DEVNULL)
    installed_workers=(p/'qwbuddy/workers.sh').read_bytes()
    installed_config=(p/'qwbuddy/config.sh').read_text()
    (p / 'qwbuddy/.controller.lock').mkdir(parents=True)
    (p / 'qwbuddy/.controller.lock/owner').write_text('2099-01-01T00:00:00Z w1:pCtl\n')
    integration = Path(tmp) / 'herdr-agent-state.ts'; integration.write_text('// HERDR_INTEGRATION_ID=pi\n')
    (p / 'qwbuddy/config.sh').write_text("QWB_WORKERS='sol'\nQWB_WORKSPACE='w1'\nQWB_ROLE_PI_CONTROL='verified'\nQWB_ROLE_PI_INTEGRATION='"+str(integration)+"'\n")
    (p / 'qwbuddy/workers.sh').write_text('qwb_worker sol herdr pi -- --provider openai-codex --model gpt-6.1-sol --thinking high\n')
    (p / 'qwbuddy/roles').mkdir(exist_ok=True)
    (p / 'tasks').mkdir(exist_ok=True)
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
def reply():
 session=Path(s['session']);session.parent.mkdir(parents=True,exist_ok=True)
 with session.open('a') as f:
  f.write(json.dumps({'type':'assistant','sessionId':s['sid'],'cwd':os.environ['ROLE_PROJECT'],'uuid':'reply-'+str(s['starts']),'effort':'low' if mode=='bad-effort' else s['effort'],'message':{'model':'wrong' if mode=='bad-model' else s['model'],'stop_reason':'end_turn','content':[{'type':'text','text':'ready'}]}})+'\\n')
if a[:2]==['workspace','list']:
 out({'workspaces':[{'active_tab_id':'w1:t1','agent_status':'idle','focused':True,'label':'drill-main','number':1,'pane_count':1,'tab_count':1,'workspace_id':'w1'}]} if mode=='workspace-no-worktree' else {'workspaces':[{'workspace_id':'w1','worktree':{'repo_root':os.environ['ROLE_PROJECT'],'is_linked_worktree':False}}]})
elif a[:2]==['tab','create']:
 s['cwd']=a[a.index('--cwd')+1];out({'root_pane':{'pane_id':'w1:pRole','tab_id':'w1:tRole','terminal_id':'term-role','workspace_id':'w1'}})
elif a[:2]==['agent','start']:
 s.update(live=True,starts=s['starts']+1,name=a[2],argv=a[a.index('--')+1:])
 s['tool']=a[a.index('--kind')+1]
 s['model']=s['argv'][s['argv'].index('--model')+1];s['effort']=s['argv'][s['argv'].index('--effort' if s['tool']=='claude' else '--thinking')+1]
 if s['tool']=='claude':
  s['sid']=s['argv'][s['argv'].index('--resume' if '--resume' in s['argv'] else '--session-id')+1]
  s['session']=str(Path(os.environ['QWB_CLAUDE_PROJECTS_DIR'])/'project'/(s['sid']+'.jsonl'))
 elif '--provider' in s['argv']:s['provider']=s['argv'][s['argv'].index('--provider')+1]
 else:s['provider'],s['model']=s['model'].split('/',1)
 if s['tool']=='claude':pass
 elif '--session' in s['argv']:
  s['session']=s['argv'][s['argv'].index('--session')+1];s['sid']=json.loads(Path(s['session']).read_text().splitlines()[0])['id']
 else:
  sid=s['argv'][s['argv'].index('--session-id')+1]; sd=s['argv'][s['argv'].index('--session-dir')+1]
  s.update(sid=sid,session=str(Path(sd)/('2099_'+sid+'.jsonl')))
 if mode=='untrusted':
  s['untrusted']=True;path.write_text(json.dumps(s));print(json.dumps({'error':{'code':'agent_not_ready'}}));sys.exit(1)
 if mode=='launch-failed':
  path.write_text(json.dumps(s));err()
 out({'type':'agent_started'})
elif a[:2]==['pane','get']:
 if mode=='query-fail':err()
 if mode=='empty-query':sys.exit(0)
 if mode=='invalid-query':print('not-json');sys.exit(0)
 if mode=='wrong-result':print(json.dumps({'result':[]}));sys.exit(0)
 ctl=a[2]=='w1:pCtl'
 if not ctl and s.get('reply_pending'):
  s['reply_polls']+=1
  if s['reply_polls']==7:reply();s['reply_pending']=False
 pane={'pane_id':a[2],'workspace_id':'w1','tab_id':'w1:tCtl' if ctl else 'w1:tRole','terminal_id':'term-ctl' if ctl else 'term-role','foreground_cwd':os.environ['ROLE_PROJECT']}
 if ctl or s['live']:
  pane.update(agent='pi',agent_status='working' if mode=='busy' and not ctl else 'idle',agent_session={'agent':'pi','source':'herdr:pi','kind':'path','value':'ctl-session' if ctl else s['session']})
 if s.get('tool')=='claude' and not ctl and s['live']:
  pane.update(agent='claude',agent_session={'agent':'claude','kind':'id','source':'herdr:claude','value':s['sid']})
 if mode=='done' and not ctl and s['live']:pane.update(agent_status='done',focused=False)
 if mode=='untrusted' and not ctl:pane.update(agent_status='blocked',agent_session=None)
 if mode=='old-session' and not ctl:pane['agent_session']['value']='different-session'
 if mode=='scrolled' and not ctl:pane['scroll']={'offset_from_bottom':10}
 if mode=='foreign-terminal' and not ctl:pane['terminal_id']='term-foreign'
 out({'pane':pane})
elif a[:2]==['pane','process-info']:
 ctl=a[-1]=='w1:pCtl'
 live=ctl or (s['live'] and mode!='background')
 argv=['node','/opt/pi/dist/cli.js'] + ([] if ctl else s['argv']) if live else ['-zsh']
 pid=(999 if mode=='spoof-controller' else os.getppid()) if ctl else 100000000+s['starts'] if live else 42
 if mode=='wrong-pid' and not ctl and live:pid+=100
 rows=[{'pid':pid,'argv0':('pi' if ctl else s.get('tool','pi')) if live else 'zsh','argv':argv,'cwd':os.environ['ROLE_PROJECT']}]
 if not ctl and live and s.get('tool')=='claude':rows.append({'pid':pid+1000,'argv0':'caffeinate','cwd':os.environ['ROLE_PROJECT']})
 out({'process_info':{'pane_id':a[-1],'shell_pid':42,'foreground_process_group_id':pid if live else 42,'foreground_processes':rows}})
elif a[:2]==['pane','read']:
 if s.get('tool')=='claude':
  print('────────────────────\\n'+('❯ draft' if mode=='draft' else '❯ Try "hello"' if mode=='placeholder' else '❯')+'\\n────────────────────');sys.exit(0)
 print('────────────────────\\n'+('draft obligation' if mode=='draft' else '')+'\\n────────────────────\\n$0.000 (sub) 0.0%/272k (auto)  ('+s.get('provider','openai-codex')+') '+('wrong-model' if mode=='wrong-model' else s.get('model','gpt-6.1-sol'))+' • '+s.get('effort','high'));sys.exit(0)
elif a[:2]==['pane','send-keys']:
 if mode=='action-failed':err()
 # Actual Herdr actions succeed with no JSON payload.
elif a[:2]==['pane','run']:
 if mode=='action-failed':err()
 if a[-1] in ('/quit','/exit') and mode!='exit-pending':s['live']=False
 elif s.get('tool')=='claude' and mode!='no-reply':
  assert '\\n' not in a[-1] and len(a[-1])<=600,a
  if mode=='delayed-reply':s.update(reply_pending=True,reply_polls=0)
  else:reply()
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
    pi_byte=False
    def byte_snapshot():
        roles=p/'qwbuddy/.roles'
        return (roles.exists(), {str(f.relative_to(roles)):f.read_bytes() for f in roles.rglob('*') if f.is_file()} if roles.exists() else {},
                [str(f.relative_to(roles)) for f in roles.rglob('*') if f.is_dir()] if roles.exists() else [],
                {f:f.read_bytes() if f.exists() else None for f in (state,log)})
    def byte_restore(snapshot):
        exists,files,dirs,native=snapshot;roles=p/'qwbuddy/.roles'
        if roles.exists():shutil.rmtree(roles)
        if exists:
            roles.mkdir(mode=0o700)
            for name in dirs:(roles/name).mkdir(parents=True,exist_ok=True)
            for name,raw in files.items():(roles/name).write_bytes(raw)
        for file,raw in native.items():
            if raw is None:
                if file.exists():file.unlink()
            else:file.write_bytes(raw)
    def call(script, verb, *args, ok=True, extra=None):
        compare=pi_byte and os.environ.get('QWB_ROLE_PI_BYTE_BASELINE')
        before=byte_snapshot() if compare else None
        r = subprocess.run(['bash', str(root/'bin'/script), verb, '--project', str(p), *args], env=env | (extra or {}), capture_output=True, text=True)
        if compare:
            after=byte_snapshot();byte_restore(before)
            old=subprocess.run(['bash',str(Path(compare)/script),verb,'--project',str(p),*args],env=env|(extra or {}),capture_output=True,text=True)
            observed=byte_snapshot();byte_restore(after)
            assert (old.returncode,old.stdout,old.stderr)==(r.returncode,r.stdout,r.stderr),(verb,'Pi stdout/stderr/rc',old,r)
            assert observed==after,(verb,'Pi role/native bytes changed')
            print('BYTE PASS '+script+' '+verb,flush=True)
        assert (r.returncode == 0) == ok, (verb, r.returncode, r.stdout, r.stderr)
        return json.loads(r.stdout) if ok else r
    # Private fake clock only for bounded handshake failure cases; no production timeout knob.
    # Import subprocess first so native query timeouts retain their real clock.
    (stub/'sitecustomize.py').write_text("import os,time,subprocess\nif os.environ.get('ROLE_FAKE_CLOCK')=='1':\n tick=[0]\n def clock():\n  tick[0]+=6\n  return tick[0]\n time.monotonic=clock\n time.sleep=lambda _:None\nif os.environ.get('ROLE_PI_BYTES')=='1':\n import uuid\n time.time=lambda:2099000000\n uuid.uuid4=lambda:uuid.UUID('62391d30-b37e-48e8-8db0-1621cda1707e')\n")
    env['PYTHONPATH']=str(stub)+os.pathsep+env.get('PYTHONPATH','')
    # Claude role adapter starts through the same public entrance; native shape follows the probe.
    config=p/'qwbuddy/config.sh'; saved_config=config.read_bytes()
    workers=p/'qwbuddy/workers.sh'; saved_workers=workers.read_bytes()
    env['QWB_CLAUDE_PROJECTS_DIR']=str(Path(tmp)/'claude-projects')
    config.write_text(installed_config+"\nQWB_WORKSPACE='w1'\nQWB_ROLE_CLAUDE_CONTROL='verified'\n")
    workers.write_bytes(installed_workers)
    installed_roles=p/'qwbuddy/.roles'
    installed=call('qwb-role.sh','start','--actor','installed','--role','规划','--worker','claude-opus-medium','--dir',str(p))
    assert installed['phase']=='active' and installed['actual_model']=='claude-opus-5-5' and installed['actual_effort']=='medium',installed
    installed_argv=installed['argv']
    assert installed_argv[installed_argv.index('--add-dir')+1]==str(p)
    native_argv=json.loads(state.read_text())['argv']
    assert native_argv[native_argv.index('--add-dir')+1]==str(p)
    assert workers.read_bytes()==installed_workers, 'installed declaration must not be hand-rewritten'
    observed_done=call('qwb-role.sh','status','--actor','installed',extra={'ROLE_FAKE_MODE':'done'})
    done_matches=observed_done['activity']=='idle' and observed_done.get('actual_model')=='claude-opus-5-5'
    print(('PASS' if done_matches else 'FAIL')+' Claude未聚焦done且end_turn：活动可认闲并保留模型证明',flush=True)
    call('qwb-control.sh','exit','--actor','installed','--expect-gen','1')
    call('qwb-role.sh','retire','--actor','installed','--expect-gen','1')
    installed_done=call('qwb-role.sh','start','--actor','installed-done','--role','规划','--worker','claude-opus-medium','--dir',str(p),extra={'ROLE_FAKE_MODE':'done'})
    assert installed_done['phase']=='active' and done_matches,(installed_done,observed_done)
    call('qwb-control.sh','exit','--actor','installed-done','--expect-gen','1',extra={'ROLE_FAKE_MODE':'done'})
    call('qwb-role.sh','retire','--actor','installed-done','--expect-gen','1')
    print('PASS Claude done握手发布active，done空输入框可exit，旧PID结束后退休')
    shutil.rmtree(installed_roles);state.unlink();log.unlink()
    print('PASS 真实qwb-init安装工人表：Claude规划start取得active，项目根add-dir原样保留',flush=True)
    def claude_profile(*extra):
        return subprocess.run(['/bin/bash','-c','. "$1"; shift; qwb_claude_profile role herdr claude "$@"','profile',str(root/'bin/qwb-lib.sh'),*installed_argv,*extra],env=env,capture_output=True,text=True)
    repeated=claude_profile('--add-dir','目录 with spaces','--add-dir',"another ' directory")
    assert repeated.returncode==0 and json.loads(repeated.stdout)==dict(provider='anthropic',model='claude-opus-5-5',effort='medium'),repeated
    for extra in [('--add-dir',),('--add-dir',''),('--add-dir','-option'),('--unknown','x'),('--resume','session'),('--fast',),('--add-dir=path',)]:
        rejected=claude_profile(*extra)
        assert rejected.returncode!=0 and extra[0] in rejected.stderr,(extra,rejected)
        if extra[0]!='--add-dir':assert '不允许参数' in rejected.stderr,rejected.stderr
    print('PASS Bash3.2 Claude档位：重复add-dir及含空格/引号路径保真，缺值/空值/选项值和具名未知参数拒绝')
    args=('start','--actor','planner','--role','规划','--worker','claude-opus-medium','--dir',str(p))
    disabled=config.read_text().replace("QWB_ROLE_CLAUDE_CONTROL='verified'", "QWB_ROLE_CLAUDE_CONTROL=''")
    config.write_text(disabled)
    denied=call('qwb-role.sh',*args,ok=False)
    assert 'QWB_ROLE_CLAUDE_CONTROL=verified' in denied.stderr
    config.write_text(disabled.replace("QWB_ROLE_CLAUDE_CONTROL=''", "QWB_ROLE_CLAUDE_CONTROL='verified'"))
    for role in ('门禁','测试体系','CI'):
        denied=call('qwb-role.sh','start','--actor','invalid','--role',role,'--worker','claude-opus-medium','--dir',str(p),ok=False)
        assert 'Claude仅可担任规划' in denied.stderr
    valid_workers=workers.read_text()
    claude_line=next(line for line in valid_workers.splitlines() if line.startswith('qwb_worker claude-opus-medium '))
    for suffix in (' --model duplicate',' --effort high',' --resume arbitrary',' --fast',' --append-system-prompt text'):
        workers.write_text(valid_workers.replace(claude_line,claude_line+suffix))
        call('qwb-role.sh',*args,ok=False)
    for model in ('--dangerously-skip-permissions','""'):
        workers.write_text(valid_workers.replace('--model claude-opus-5-5','--model '+model))
        call('qwb-role.sh',*args,ok=False)
    workers.write_text(valid_workers)
    assert not state.exists() and not (p/'qwbuddy/.roles').exists() and not log.exists()
    print('PASS Claude开关关闭/非规划职责：零Herdr调用零角色记录')
    claude=call('qwb-role.sh',*args)
    assert claude['phase']=='active' and claude['actual_model']=='claude-opus-5-5' and claude['actual_effort']=='medium',claude
    import uuid
    assert str(uuid.UUID(claude['session_id']))==claude['session_id']
    native=json.loads(state.read_text()); argv=native['argv']
    guide=argv[argv.index('--append-system-prompt')+1]
    assert '\n' not in guide and len(guide)<=600 and claude['charter'] in guide
    def identity(ok=True):
        check=subprocess.run(['bash','-c','. "$1"; qwb_planner_identity "$2" planner','identity',str(root/'bin/qwb-lib.sh'),str(p)],env=env,capture_output=True,text=True)
        assert (check.returncode==0)==ok,(check.stdout,check.stderr)
        return json.loads(check.stdout) if ok else check
    assert identity()['session_id']==claude['session_id']
    for generation_args in ((),('--expect-gen','0')):
        rejected=call('qwb-role.sh','reconcile','--actor','planner',*generation_args,ok=False)
        assert '当前代次为 1' in rejected.stderr and '请加 --expect-gen 1' in rejected.stderr,rejected.stderr
        assert json.loads((p/'qwbuddy/.roles/planner.json').read_text())['incarnation']==1
    print('PASS reconcile缺代次/旧代次提示当前1与正确参数，代次校验保留')
    print('PASS Claude规划启动握手：UUID/单行指路/实际模型档位/active/规划身份')
    original=Path(claude['session_path']).read_bytes()
    for field,value in [('effort','low'),('model','wrong'),('sessionId','wrong'),('cwd',str(Path(tmp)) )]:
        record=json.loads(original)
        if field=='model':record['message']['model']=value
        else:record[field]=value
        Path(claude['session_path']).write_text(json.dumps(record)+'\n')
        assert call('qwb-role.sh','status','--actor','planner')['activity']=='unknown'
        assert call('qwb-role.sh','status','--actor','planner',extra={'ROLE_FAKE_MODE':'done'})['activity']=='unknown'
        identity(False)
        Path(claude['session_path']).write_bytes(original)
    for mode in ('old-session','wrong-pid'):
        assert call('qwb-role.sh','status','--actor','planner',extra={'ROLE_FAKE_MODE':mode})['activity']=='unknown'
        call('qwb-control.sh','exit','--actor','planner','--expect-gen','1',ok=False,extra={'ROLE_FAKE_MODE':mode})
    session=Path(claude['session_path']); moved=session.with_suffix('.backup')
    session.rename(moved);session.symlink_to(moved)
    assert call('qwb-role.sh','status','--actor','planner')['activity']=='unknown'
    session.unlink();moved.rename(session)
    duplicate=session.parent.parent/'duplicate';duplicate.mkdir();copy=duplicate/session.name;copy.write_bytes(original)
    assert call('qwb-role.sh','status','--actor','planner')['activity']=='unknown'
    copy.unlink();duplicate.rmdir()
    print('PASS Claude模型/档位/session/cwd/PID漂移及符号链接/重复文件：身份及控制拒绝')
    for mode in ('draft','placeholder','busy','scrolled'):
        call('qwb-control.sh','exit','--actor','planner','--expect-gen','1',ok=False,extra={'ROLE_FAKE_MODE':mode})
        assert json.loads(state.read_text())['live']
    assert call('qwb-role.sh','status','--actor','planner',extra={'ROLE_FAKE_MODE':'busy'})['activity']=='working'
    record=json.loads(original);record['message']['content']=[{'type':'tool_use','id':'call-1','name':'Read','input':{}}]
    Path(claude['session_path']).write_text(json.dumps(record)+'\n')
    assert call('qwb-role.sh','status','--actor','planner')['activity']=='working'
    assert call('qwb-role.sh','status','--actor','planner',extra={'ROLE_FAKE_MODE':'done'})['activity']=='working'
    call('qwb-control.sh','exit','--actor','planner','--expect-gen','1',ok=False,extra={'ROLE_FAKE_MODE':'done'})
    call('qwb-control.sh','exit','--actor','planner','--expect-gen','1',ok=False)
    result=dict(type='user',sessionId=claude['session_id'],cwd=str(p),message={'content':[{'type':'tool_result','tool_use_id':'call-1','content':'read'}]})
    with Path(claude['session_path']).open('a') as f:f.write(json.dumps(result)+'\n'+original.decode())
    assert call('qwb-role.sh','status','--actor','planner')['activity']=='idle'
    call('qwb-control.sh','interrupt','--actor','planner','--expect-gen','1')
    print('PASS Claude活动/输入框：working及未配对工具不认闲；草稿/占位提示不退出；配对完成可认闲')
    for name,activity in [('tool-running','working'),('interrupted','idle'),('after-new-turn','idle')]:
        rows=[json.loads(line) for line in (root/'tests/fixtures/herdr'/('claude-session-'+name+'.jsonl')).read_text().splitlines() if line.strip()]
        for row in rows:
            if 'sessionId' in row:row['sessionId']=claude['session_id']
            if 'cwd' in row:row['cwd']=str(p)
        session.write_text('\n'.join(map(json.dumps,rows))+'\n')
        got=call('qwb-role.sh','status','--actor','planner');assert got['activity']==activity,(name,got)
        if name=='after-new-turn':
            # A newer completed round cannot erase an unmatched tool call in the older round.
            rows=[row for row in rows if not (row.get('type')=='user' and isinstance(row.get('message',{}).get('content'),list) and
                  any(c.get('type')=='tool_result' for c in row['message']['content']))]
            session.write_text('\n'.join(map(json.dumps,rows))+'\n')
            assert call('qwb-role.sh','status','--actor','planner')['activity']=='working'
    session.write_bytes(original)
    print('PASS Claude真机JSONL样本：执行中/打断配对/新一轮及旧悬空调用保守拒闲')
    subdir=p/'subdir';subdir.mkdir()
    later=json.loads(original);later.update(cwd=str(subdir),uuid='after-cd')
    rows=[dict(type='system',sessionId=claude['session_id'],cwd=str(subdir)),json.loads(original),
          dict(type='user',sessionId=claude['session_id'],cwd=str(subdir),message={'content':'继续'}),later]
    after_cd='\n'.join(map(json.dumps,rows))+'\n'
    session.write_text(after_cd)
    cwd_activity=call('qwb-role.sh','status','--actor','planner')
    cwd_identity=subprocess.run(['bash','-c','. "$1"; qwb_planner_identity "$2" planner','identity',str(root/'bin/qwb-lib.sh'),str(p)],env=env,capture_output=True,text=True)
    cwd_matches=cwd_activity['activity']=='idle' and cwd_identity.returncode==0
    print(('PASS' if cwd_matches else 'FAIL')+' Claude后续user/assistant cwd切到子目录：活动与身份仍成立',flush=True)
    for index,key,value in [(1,'cwd',str(subdir)),(3,'sessionId','foreign-session')]:
        damaged=json.loads(json.dumps(rows));damaged[index][key]=value
        session.write_text('\n'.join(map(json.dumps,damaged))+'\n')
        assert call('qwb-role.sh','status','--actor','planner')['activity']=='unknown'
        identity(False)
    session.write_bytes(original)
    call('qwb-control.sh','exit','--actor','planner','--expect-gen','1')
    starts=json.loads(state.read_text())['starts']
    for index,key,value in [(1,'cwd',str(subdir)),(3,'sessionId','foreign-session')]:
        damaged=json.loads(json.dumps(rows));damaged[index][key]=value
        session.write_text('\n'.join(map(json.dumps,damaged))+'\n')
        call('qwb-control.sh','relaunch','--actor','planner','--expect-gen','1',ok=False)
        assert json.loads(state.read_text())['starts']==starts
    session.write_text(after_cd)
    resumed=call('qwb-control.sh','relaunch','--actor','planner','--expect-gen','1')
    assert cwd_matches,(cwd_activity,cwd_identity.stderr)
    print('PASS Claude后续cwd变化可恢复；首条消息cwd错误/后续sessionId冲突仍拒绝身份与恢复')
    assert resumed['incarnation']==2 and resumed['session_id']==claude['session_id'] and resumed['session_path']==claude['session_path']
    argv=json.loads(state.read_text())['argv']; assert '--resume' in argv and '--session-id' not in argv
    call('qwb-control.sh','exit','--actor','planner','--expect-gen','2')
    call('qwb-role.sh','retire','--actor','planner','--expect-gen','2')
    print('PASS Claude退出/原会话resume/代次递增/显式退休')
    for mode in ('untrusted','bad-model','bad-effort','no-reply'):
        actor='planner-'+mode
        failed=call('qwb-role.sh','start','--actor',actor,'--role','规划','--worker','claude-opus-medium','--dir',str(p),ok=False,extra={'ROLE_FAKE_MODE':mode,'ROLE_FAKE_CLOCK':'1'})
        if mode=='untrusted': assert '确认目录信任' in failed.stderr
        else: assert 'Claude握手未确认：' in failed.stderr,failed.stderr
        command=failed.stderr.split('执行：',1)[1].split('；',1)[0]
        assert shlex.split(command)==['bash',str(root/'bin/qwb-role.sh'),'reconcile','--project',str(p),'--actor',actor,'--expect-gen','0'],failed.stderr
        record_path=p/'qwbuddy/.roles'/(actor+'.json')
        pending=json.loads(record_path.read_text()); assert pending['incarnation']==0 and pending.get('pending') and pending['phase']!='active'
        snapshot=json.loads(state.read_text()); starts=snapshot['starts']
        if mode=='untrusted':
            for generation_args in ((),('--expect-gen','1')):
                rejected=call('qwb-role.sh','reconcile','--actor',actor,*generation_args,ok=False)
                assert '当前代次为 0' in rejected.stderr and '请加 --expect-gen 0' in rejected.stderr,rejected.stderr
                assert json.loads(record_path.read_text())['incarnation']==0 and json.loads(state.read_text())['starts']==starts
        if mode!='untrusted':
            # Simulate the pending native answer arriving/correcting after timeout; no prompt re-send.
            session=Path(snapshot['session']);session.parent.mkdir(exist_ok=True,parents=True)
            session.write_text(json.dumps(dict(type='assistant',uuid='late',sessionId=snapshot['sid'],cwd=str(p),effort='medium',message={'model':'claude-opus-5-5','content':[]}))+'\n')
        recovered=call('qwb-role.sh','reconcile','--actor',actor,'--expect-gen','0')
        assert recovered['phase']=='active' and json.loads(state.read_text())['starts']==starts
        call('qwb-control.sh','exit','--actor',actor,'--expect-gen','1')
        call('qwb-role.sh','retire','--actor',actor,'--expect-gen','1')
    print('PASS Claude未信任/握手超时附完整reconcile命令与当前代次，恢复不重发启动')
    # Two pane queries per loop; the 7th query releases the reply on loop 4.
    # The private clock advances 6s per deadline check: old 10s stops at loop 2.
    delayed=call('qwb-role.sh','start','--actor','planner-delayed','--role','规划','--worker','claude-opus-medium','--dir',str(p),extra={'ROLE_FAKE_MODE':'delayed-reply','ROLE_FAKE_CLOCK':'1'})
    assert delayed['phase']=='active' and json.loads(state.read_text())['reply_polls']==7
    call('qwb-control.sh','exit','--actor','planner-delayed','--expect-gen','1')
    call('qwb-role.sh','retire','--actor','planner-delayed','--expect-gen','1')
    print('PASS Claude握手假钟越过10秒后取得新回复并active，仍保留无回复超时反例')
    config.write_bytes(saved_config); workers.write_bytes(saved_workers)
    shutil.rmtree(p/'qwbuddy/.roles'); state.unlink(); log.unlink()
    pi_byte=True
    if os.environ.get('QWB_ROLE_PI_BYTE_BASELINE'):env['ROLE_PI_BYTES']='1'
    # Config errors must stick even when a later valid declaration succeeds (Bash || disables errexit).
    workers=p/'qwbuddy/workers.sh'; original_workers=workers.read_text()
    workers.write_text('qwb_worker not-registered herdr pi -- --provider openai-codex --model gpt-6.1-sol --thinking high\n'+original_workers)
    call('qwb-role.sh','start','--actor','gate','--role','门禁','--worker','sol','--dir',str(p),ok=False)
    workers.write_text(original_workers)
    assert not state.exists(), 'invalid registry must refuse before any Herdr side effect'
    # 有意收紧：当前start与gate都须在任何Herdr/角色/账本动作前拒绝缺渠道。
    implicit=original_workers.replace('--provider openai-codex ', '').replace('--model gpt-6.1-sol', '--model openai-codex/gpt-6.1-sol')
    workers.write_text(implicit)
    before=(log.read_bytes() if log.exists() else b'', list((p/'tasks').iterdir()))
    rejected=call('qwb-role.sh','start','--actor','gate','--role','门禁','--worker','sol','--dir',str(p),ok=False)
    assert '--provider' in rejected.stderr and '--provider 渠道 --model 模型ID' in rejected.stderr, rejected.stderr
    gate=subprocess.run(['/bin/bash','-c','. "$1"; qwb_gate_profile "$2" sol','test',str(root/'bin/qwb-lib.sh'),str(p)],env=env,capture_output=True,text=True)
    assert gate.returncode!=0 and '--provider' in gate.stderr and '--provider 渠道 --model 模型ID' in gate.stderr,gate.stderr
    assert not state.exists() and not (p/'qwbuddy/.roles').exists()
    assert before==(log.read_bytes() if log.exists() else b'', list((p/'tasks').iterdir()))
    print('PASS 缺provider的角色与门禁明确提示改法，零Herdr调用、零角色或账本写入')
    # 固定起点的真实角色入口对相同隐式argv仍接受，证明收紧源于本票。
    legacy=Path(tmp)/'legacy-project';shutil.copytree(p,legacy)
    baseline=Path(tmp)/'baseline-bin';shutil.copytree(root/'bin',baseline)
    for name in ('qwb-role.sh','qwb-lib.sh','qwb-herdr.sh'):
        (baseline/name).write_bytes(subprocess.check_output(['git','-C',str(root),'show','bea487d:bin/'+name]))
    old=subprocess.run(['bash',str(baseline/'qwb-role.sh'),'start','--project',str(legacy),'--actor','legacy','--role','门禁','--worker','sol','--dir',str(legacy)],
                       env=env|{'ROLE_PROJECT':str(legacy),'ROLE_FAKE_STATE':str(Path(tmp)/'legacy-state.json'),'ROLE_FAKE_LOG':str(Path(tmp)/'legacy-log.jsonl')},capture_output=True,text=True)
    assert old.returncode==0 and json.loads(old.stdout)['actual_model']=='openai-codex/gpt-6.1-sol', (old.stdout,old.stderr)
    print('PASS 起点bea487d的真实角色start接受相同无provider声明（有意收紧对照）')
    workers.write_text(original_workers)
    config=p/'qwbuddy/config.sh'; config_bytes=config.read_bytes()
    config.write_text(config.read_text().replace("QWB_WORKSPACE='w1'", "QWB_WORKSPACE=''"))
    try:
        before=[x.name for x in (p/'qwbuddy/.roles').iterdir()] if (p/'qwbuddy/.roles').exists() else []
        offset=len(log.read_text().splitlines()) if log.exists() else 0
        rejected=call('qwb-role.sh','start','--actor','no-workspace','--role','门禁','--worker','sol','--dir',str(p),ok=False,extra={'ROLE_FAKE_MODE':'workspace-no-worktree'})
        assert rejected.returncode==1 and rejected.stdout=='', (rejected.returncode,rejected.stdout,rejected.stderr)
        assert rejected.stderr.startswith('拒绝: 须有唯一已登记workspace，不回退focused默认窗口\n'), rejected.stderr
        assert all(word in rejected.stderr for word in ['qwbuddy/config.sh','QWB_WORKSPACE','主工作区','w1']), rejected.stderr
        assert before==[x.name for x in (p/'qwbuddy/.roles').iterdir()]
        calls=[json.loads(line) for line in log.read_text().splitlines()[offset:]]
        assert not any(a[:2] in (['tab','create'],['agent','start'],['pane','run']) for a in calls), calls
        print('PASS user_无workspace角色启动：真机无worktree形态，rc1/原前缀/config改法/w1，无角色记录或新tab')
    finally: config.write_bytes(config_bytes)
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
    byte_bin=Path(tmp)/'byte-bin'; shutil.copytree(root/'bin',byte_bin)
    (byte_bin/'qwb-role.sh').write_bytes(subprocess.check_output(['git','-C',str(root),'show','d66d77c:bin/qwb-role.sh']))
    snapshots={f:f.read_bytes() for f in (p/'qwbuddy/.roles').iterdir() if f.is_file()}
    results=[]
    for script in (byte_bin/'qwb-role.sh',root/'bin/qwb-role.sh'):
        result=subprocess.run(['bash',str(script),'start','--project',str(p),'--actor','gate','--role','门禁','--worker','sol','--dir',str(p)],env=env,capture_output=True,timeout=30)
        results.append((result.returncode,result.stdout,result.stderr))
        assert snapshots=={f:f.read_bytes() for f in (p/'qwbuddy/.roles').iterdir() if f.is_file()}
    assert results[0]==results[1] and results[0][0]==0, results
    print('PASS user_其余行为字节对照：固定d66d77c与当前role start成功重放stdout/stderr/rc/角色记录字节相同')
    assert list((p/'tasks').iterdir()) == [p/'tasks/lessons'], 'idle role must not manufacture tasks'
    assert not any(json.loads(x)[:2] == ['agent','prompt'] for x in log.read_text().splitlines())
    role_status = subprocess.run(['git','-C',str(p),'status','--short','--untracked-files=all'],capture_output=True,text=True)
    assert role_status.returncode == 0 and role_status.stdout == '', role_status.stdout
    assert (p/'qwbuddy/.roles/gate.json').exists()
    print('PASS public role start: local registry/charter/session directory ignored, installed project remains clean')
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
    shutil.copytree(root/'bin',p/'qwbuddy/bin',dirs_exist_ok=True)
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

    # 模板真实角色入口与门禁入口核对同一档位；固定模型ID的斜杠保留。
    workers.write_text((root/'templates/workers.sh').read_text())
    config=p/'qwbuddy/config.sh'
    config.write_text(config.read_text()+"\nQWB_WORKERS='pi-sol-high pi-astra-high pi-astra-low'\n")
    # 只取需要的三名Pi工人，家族声明全部保留；其他工人不在此夹具QWB_WORKERS内。
    workers.write_text('\n'.join(line for line in workers.read_text().splitlines() if not line.startswith('qwb_worker ') or line.split()[1] in ('pi-sol-high','pi-astra-high','pi-astra-low'))+'\n')
    for worker,provider,model,effort in [('pi-sol-high','magpie','codex/gpt-6.1-sol','high'),('pi-astra-high','magpie','codex/gpt-6-astra','high'),('pi-astra-low','magpie','codex/gpt-6-astra','low')]:
        got=call('qwb-role.sh','start','--actor',worker,'--role','门禁','--worker',worker,'--dir',str(p))
        assert (got['provider'],got['model'],got['effort'],got['actual_model'])==(provider,model,effort,provider+'/'+model),got
        gate=subprocess.run(['/bin/bash','-c','. "$1"; qwb_gate_profile "$2" "$3"','test',str(root/'bin/qwb-lib.sh'),str(p),worker],env=env,capture_output=True,text=True)
        assert gate.returncode==0 and json.loads(gate.stdout)==dict(provider=provider,model=model,effort=effort),gate.stderr
        call('qwb-control.sh','exit','--actor',worker,'--expect-gen','1')
        call('qwb-role.sh','retire','--actor',worker,'--expect-gen','1')
        print('PASS 模板'+worker+'真实角色start与gate_profile均匹配provider/model/effort')
PY

bash "$ROOT/tests/pi-profile.sh"
