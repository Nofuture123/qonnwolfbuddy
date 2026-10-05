#!/usr/bin/env bash
# 私有临时Git + 系统边界fakeHerdr；不碰现场main/端点。
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/process-fixture.sh"
qwb_test_scope "$@"
export TMPDIR="${QWB_TEST_SCOPE_DIR}"
mkdir -p "$TMPDIR" || exit 1
export GIT_CEILING_DIRECTORIES="$TMPDIR"
# Fail closed even if the PATH stub disappears.
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock
export QWB_LAND_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
export QWB_LAND_CASE="${1:-all}"
python3 -B - <<'PY'
from process_fixture import TemporaryDirectory, socket_path
import atexit, fcntl, hashlib, json, os, shutil, socket, subprocess, sys, tempfile, threading, time
from pathlib import Path
ROOT=Path(os.environ['QWB_LAND_ROOT'])
with TemporaryDirectory(prefix='qwb-land-') as tmp:
    os.environ["TMPDIR"] = tmp
    tmp=Path(tmp).resolve(); p=tmp/'project'; p.mkdir(); stub=tmp/'stub'; stub.mkdir()
    shutil.copytree(ROOT/'bin',p/'qwbuddy/bin'); shutil.copytree(ROOT/'templates/roles',p/'qwbuddy/roles')
    for n in ['TASK.md','QWBUDDY.md']: shutil.copy(ROOT/'templates'/n,p/'qwbuddy'/n)
    (p/'qwbuddy/.controller.lock').mkdir(); (p/'qwbuddy/.controller.lock/owner').write_text('2099 ctl\n')
    integration=tmp/'integration.ts'; integration.write_text('// HERDR_INTEGRATION_ID=pi\n')
    (p/'qwbuddy/config.sh').write_text(f"QWB_WORKERS='sol reviewer'\nQWB_WORKSPACE='ws'\nQWB_ROLE_PI_CONTROL='verified'\nQWB_ROLE_PI_INTEGRATION='{integration}'\nQWB_GATE_FAST='test -f product.txt'\nQWB_GATE_FULL='test -s product.txt'\n")
    (p/'qwbuddy/workers.sh').write_text('qwb_worker sol herdr pi -- --provider openai-codex --model gpt-6.1-sol --thinking high\nqwb_worker reviewer herdr pi -- --provider anthropic --model claude-opus-4-6 --thinking low\nqwb_family openai-codex/gpt-6.1-sol gpt\nqwb_family openai-codex/gpt-6-astra gpt\nqwb_family anthropic/claude-opus-4-6 claude\n')
    (p/'tasks').mkdir(); (p/'.gitignore').write_text('qwbuddy/.roles/\nqwbuddy/.controller.lock/\nqwbuddy/.supervisor.guard\n.worktrees/\ntasks/*.qwb-*\n')
    (p/'product.txt').write_text('seed\n'); (p/'tasks/live.md').write_text('live seed\n')
    def git(*args,at=p): return subprocess.check_output(['git','-C',str(at),*args],text=True).strip()
    git('init','-qb','main'); git('add','.'); git('-c','user.name=Test','-c','user.email=test@invalid','commit','-qm','seed')
    # Migration examines only the stopped MD; deletion probes must hit the real OS.
    real_lsof=shutil.which('lsof'); assert real_lsof, 'lsof required for writer death regression'
    (stub/'lsof').write_text('#!/bin/sh\nif [ "$1" = "-Ffa" ]; then exit 1; fi\nif [ "${LAND_RESOURCE_PROBE:-}" = unknown ]; then echo "probe unknown" >&2; exit 3; fi\nexec "$LAND_REAL_LSOF" "$@"\n')
    (stub/'ps').write_text("#!/usr/bin/env python3\nimport subprocess,sys\nif sys.argv[-1]=='ppid=':sys.exit(subprocess.run(['/bin/ps',*sys.argv[1:]]).returncode)\nprint('Thu Oct 1 00:00:00 2099')\n")
    (stub/'herdr').write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
a=sys.argv[1:]; f=Path(os.environ['LAND_NATIVE_STATE']); s=json.loads(f.read_text()) if f.exists() else {}
with open(os.environ['LAND_NATIVE_LOG'],'a') as log: print(json.dumps(a),file=log)
p=os.environ['LAND_PROJECT']; pid=int(os.environ['LAND_PID'])
def out(x):
 if 'pane' in x and x['pane']['pane_id']==os.environ.get('LAND_SHAPE_TARGET'):
  shape=os.environ.get('LAND_AGENT_SHAPE','null')
  if shape=='omitted':x['pane'].pop('agent',None)
  else:x['pane']['agent']=json.loads(shape)
  fault=os.environ.get('LAND_PANE_FAULT','')
  if fault=='id':x['pane']['pane_id']='foreign-pane'
  if fault=='object':x['pane']=[]
  if fault=='json':print('{');return
  if fault=='error':print(json.dumps({'error':{'code':'io_error'},'result':x}));return
  if fault=='stderr':print('query warning',file=sys.stderr)
 print(json.dumps({'result':x}))
if a[:2]==['status','--json']:print(json.dumps({'server':{'socket':os.environ['LAND_SOCKET'],'session':os.environ.get('HERDR_SESSION')}}))
elif a[:2]==['api','snapshot']:
 if 'snapshot' not in s:
  ids=['ws','task-space'] if os.environ.get('LAND_SPACE_PATH') and not s.get('space_closed') else ['ws']
  s['snapshot']={'workspaces':[{'workspace_id':w} for w in ids],
   'tabs':[{'workspace_id':w,'tab_id':'task-tab' if w=='task-space' else 'ctl-tab'} for w in ids],
   'panes':[{'workspace_id':w,'tab_id':'task-tab' if w=='task-space' else 'ctl-tab','pane_id':'task-pane' if w=='task-space' else 'ctl'} for w in ids],
   'focused_workspace_id':'ws','focused_tab_id':'ctl-tab','focused_pane_id':'ctl'}
 out({'snapshot':s['snapshot']})
elif a[:2]==['workspace','list']:
 w=[{'workspace_id':'ws','worktree':{'repo_root':p,'is_linked_worktree':False}}]
 if os.environ.get('LAND_SPACE_PATH') and not s.get('space_closed'):w.append({'workspace_id':'task-space','worktree':{'repo_root':p,'is_linked_worktree':True,'checkout_path':os.environ['LAND_SPACE_PATH']}})
 out({'workspaces':w})
elif a[:2]==['tab','list']:out({'tabs':[{'tab_id':'task-tab'}]})
elif a[:2]==['pane','list']:out({'panes':[{'pane_id':'task-pane','agent_status':'idle'}]})
elif a[:2]==['workspace','close']:
 s['space_closed']=True
 for key in ['workspaces','tabs','panes']:s['snapshot'][key]=[x for x in s['snapshot'][key] if x['workspace_id']!=a[2]]
 out({'type':'workspace_closed'})
elif a[:2]==['tab','create']:out({'root_pane':{'pane_id':'gate-pane','tab_id':'gate-tab','terminal_id':'gate-terminal'}})
elif a[:2]==['agent','get']:print(json.dumps({'error':{'code':'agent_not_found'}}));sys.exit(1)
elif a[:2]==['agent','start']:
 v=a[a.index('--')+1:]; sid=v[v.index('--session-id')+1]; sd=v[v.index('--session-dir')+1];s={'session':sd+'/2099_'+sid+'.jsonl'};out({'type':'agent_started'})
elif a[:2]==['pane','get'] and a[2] in ('task-pane','worker-pane'):
 if os.environ.get('LAND_ENDPOINT')=='unknown':print(json.dumps({'error':{'code':'other_error'}}));sys.exit(1)
 out({'pane':{'pane_id':a[2],'workspace_id':'task-space','tab_id':'task-tab','agent':None if os.environ.get('LAND_ENDPOINT')=='stopped' else 'pi','agent_status':'idle'}})
elif a[:2]==['pane','process-info'] and a[-1] in ('task-pane','worker-pane'):
 fault=os.environ.get('LAND_PROCESS_FAULT','') if a[-1]==os.environ.get('LAND_SHAPE_TARGET') else ''
 if fault=='query':print(json.dumps({'error':{'code':'io_error'}}));sys.exit(1)
 out({'process_info':{'pane_id':a[-1],'shell_pid':42,'foreground_process_group_id':43 if fault=='foreground' else 42,'foreground_processes':[{'pid':42,'argv0':'zsh','cwd':os.environ.get('LAND_SPACE_PATH',p)}]}})
elif a[:2]==['pane','get']:
 d={'pane_id':a[2],'workspace_id':'ws','terminal_id':'gate-terminal','foreground_cwd':p}
 if a[2]!='gate-pane' or 'session' in s:d.update(agent='pi',agent_status='idle',agent_session={'agent':'pi','source':'herdr:pi','kind':'path','value':s.get('session','ctl-session')})
 out({'pane':d})
elif a[:2]==['pane','process-info']:
 live=a[-1]!='gate-pane' or 'session' in s;i=pid if live else 42
 out({'process_info':{'pane_id':a[-1],'shell_pid':42,'foreground_process_group_id':i,'foreground_processes':[{'pid':i,'argv0':'pi' if live else 'zsh','argv':['pi'],'cwd':p}]}})
elif a[:2]==['pane','read']:print('(openai-codex) gpt-6.1-sol • high');sys.exit()
elif a[:2] in (['pane','run'],['tab','close']):out({'type':'input_sent'})
else:sys.exit(9)
f.write_text(json.dumps(s))
''')
    real_git=shutil.which('git'); real_mv=shutil.which('mv')
    (stub/'git').write_text('''#!/usr/bin/env bash
if [[ -n "${LAND_BYTES_GIT_LOG:-}" ]]; then printf '%s\\0' "$@" >> "$LAND_BYTES_GIT_LOG"; printf '\\n' >> "$LAND_BYTES_GIT_LOG"; fi
if [[ "$*" == *"merge --ff-only"* ]]; then printf '%s\\n' "${@: -1}" >> "$LAND_GIT_LOG"; fi
if [[ ! -e "$LAND_FAIL_FLAG" ]] && { [[ "${LAND_FAIL:-}" == remove && "$*" == *"worktree remove"* ]] || [[ "${LAND_FAIL:-}" == delete && "$*" == *"update-ref -d"* ]]; }; then touch "$LAND_FAIL_FLAG"; exit 9; fi
exec "$LAND_REAL_GIT" "$@"
''')
    (stub/'mv').write_text('''#!/usr/bin/env bash
if [[ "${LAND_FAIL:-}" == publish && ! -e "$LAND_FAIL_FLAG" ]] && grep -q '\\"stage\\":\\"landed\\"' "${@: -2:1}"; then touch "$LAND_FAIL_FLAG"; exit 9; fi
exec "$LAND_REAL_MV" "$@"
''')
    for f in stub.iterdir():f.chmod(0o755)
    env=os.environ|{'LC_ALL':'C','PATH':str(stub)+':'+os.environ['PATH'],'HERDR_PANE_ID':'ctl','LAND_PROJECT':str(p),'LAND_PID':str(os.getpid()),'LAND_NATIVE_STATE':str(tmp/'native.json'),'LAND_NATIVE_LOG':str(tmp/'native.log'),'LAND_REAL_GIT':real_git,'LAND_REAL_MV':real_mv,'LAND_REAL_LSOF':real_lsof,'LAND_GIT_LOG':str(tmp/'git.log'),'LAND_FAIL_FLAG':str(tmp/'fail.flag')}
    # Same newline-delimited RPC fixture as collab-herdr.sh; never use the live socket.
    # Allocate and register the socket through the shared 103-byte path guard.
    sockpath=socket_path()
    api=socket.socket(socket.AF_UNIX); api.bind(sockpath); api.listen(); api.settimeout(.2)
    def serve():
        while True:
            try: connection,_=api.accept()
            except socket.timeout: continue
            except OSError: return
            with connection:
                request=json.loads(connection.makefile('rb').readline())
                state=Path(env['LAND_NATIVE_STATE']); native=json.loads(state.read_text()); snapshot=native['snapshot']
                with Path(env['LAND_NATIVE_LOG']).open('a') as log: print(json.dumps(request),file=log)
                method=request['method']; params=request['params']
                if method=='workspace.move':
                    rows=snapshot['workspaces']; item=next(x for x in rows if x['workspace_id']==params['workspace_id'])
                    old=rows.index(item); slot=params['insert_index']; rows.remove(item)
                    rows.insert(slot-1 if slot>old else slot,item)
                    result={'type':'workspace_list','workspaces':rows}
                elif method=='pane.focus':
                    pane=next(x for x in snapshot['panes'] if x['pane_id']==params['pane_id'])
                    snapshot.update(focused_workspace_id=pane['workspace_id'],focused_tab_id=pane['tab_id'],focused_pane_id=pane['pane_id'])
                    result={'type':'ok'}
                else: raise ValueError('unexpected fixture RPC: '+method)
                state.write_text(json.dumps(native))
                connection.sendall((json.dumps({'id':request['id'],'result':result})+'\n').encode())
    thread=threading.Thread(target=serve,daemon=True); thread.start()
    def close_api():
        api.close(); thread.join(timeout=20)
    atexit.register(close_api)
    env['LAND_SOCKET']=sockpath
    runtime=ROOT/'bin'
    notify_runtime=False
    notify_bin=p/'qwbuddy/bin'
    def call(script,verb=None,*args,actor='ctl',ok=True,extra=None):
        r=subprocess.run(['bash',str(notify_bin/script if notify_runtime else runtime/script),*([] if verb is None else [verb]),'--project',str(p),*map(str,args)],env=env|{'HERDR_PANE_ID':actor}|(extra or {}),capture_output=True,text=True)
        print(f'RC={r.returncode} {script} {verb} '+ ' '.join(map(str,args)))
        assert (r.returncode==0)==ok,(r.returncode,r.stdout,r.stderr)
        return r
    call('qwb-role.sh','start','--actor','gate','--role','门禁','--worker','sol','--dir',p)
    def ledger(verb,t,*args,**kw):return call('qwb-ledger.sh',verb,'--task',t,'--',*args,**kw)
    def read(t):
        d=json.loads(ledger('read',t).stdout)
        if d.get('land'):
            l=d['land'];fact={k:v for k,v in l.items() if k!='context'}
            fact['candidate_binding']={k:l['context'][k] for k in ['candidate','head','tree','base','spec_rev','scenarios_fp','policy']}
            print('EVIDENCE '+json.dumps({'phase':d['phase'],'claim':d['claim'],'land':fact,'actual_main':git('rev-parse','main')},ensure_ascii=False))
        return d
    def accepted(name,base=None,change='product.txt',actor='ctl',check_environment=False,gate_actor=None):
        global notify_runtime
        # gate_actor additionally exercises the release notification; actor alone only changes the gate identity.
        notify=gate_actor=='gate-pane'; actor=gate_actor or actor
        base=base or git('rev-parse','main'); c=p/'.worktrees'/name
        git('worktree','add','-qb',name,str(c),base)
        (c/change).write_text(name+'\n'); git('add',change,at=c);git('-c','user.name=Test','-c','user.email=test@invalid','commit','-qm',name,at=c)
        t=p/'tasks'/f'{name}.md';t.write_text('# '+name+'\nstate: running\n## 验收场景\n### user_success\nGiven candidate\nWhen land\nThen success\n### user_reject\nGiven dirty\nWhen land\nThen reject\n')
        m=tmp/'migration.json';m.write_text(json.dumps({'task_sha256':hashlib.sha256(t.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no external actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
        ledger('migrate',t,m)
        # Migration review is a real controller obligation, independent of acceptance/land.
        for h in json.loads(call('qwb-send.sh','pending','--task',t).stdout):
            hid=h['event_id'];hop='migrate-'+name
            ref=p/'qwbuddy/.roles'/(hop+'.json')
            ref.write_text(json.dumps(dict(event_id=hid,op_id=hop,outcome='applied',evidence='fixture stopped; old obligations checked')))
            for verb in ['received','accept','prepared','handled']:
                args=['--task',t,'--event',hid]
                if verb!='received':args+=['--op',hop]
                if verb=='handled':args+=['--result-ref',ref]
                call('qwb-send.sh',verb,*args)
        environment=tmp/'environment';environment.write_text('fixture v1\n')
        req=tmp/'assignment.json';req.write_text(json.dumps({'candidate':str(c),'base':base,'attempt':'1','policy':'v1','environment':str(environment),'required':{'full':['user_success','user_reject']},'workers':{'review':'reviewer','rework':'sol'}}))
        ledger('gate-assign',t,'gate',req); op='accept-'+name;ledger('claim',t,op,actor=actor)
        report=tmp/(name+'-full.json')
        call('qwb-test.sh','full','--project',c,'--task',t,'--ledger-project',p,'--op',op,'--report',report,actor=actor)
        def session(sid,model,provider,family,effort):
            f=tmp/(sid+'.jsonl');f.write_text('\n'.join(json.dumps(x) for x in [{'type':'session','id':sid,'cwd':str(p)},{'type':'model_change','modelId':model,'provider':provider},{'type':'thinking_level_change','thinkingLevel':effort}])+'\n')
            return {'model':model,'family':family,'session':sid,'evidence':str(f)}
        review=tmp/(name+'-review.json');review.write_text(json.dumps({'context':json.loads(report.read_text())['after'],'implementer':session('impl-'+name,'gpt-6.1-sol','openai-codex','gpt','high'),'reviewer':session('rev-'+name,'claude-opus-4-6','anthropic','claude','low'),'standards':'pass','spec':'pass','covered':['user_success','user_reject'],'findings':[]}))
        changed={'PATH':env['PATH']+':'+str(tmp)}
        if check_environment:
            before=t.read_bytes()
            for verb,evidence,message in [('gate-receipt',report,'收据对象/规格/策略/命令/配置/环境不匹配'),('gate-review',review,'审核不是当前精确对象')]:
                result=ledger(verb,t,op,evidence,actor=actor,extra=changed,ok=False)
                assert result.stderr=='账本拒绝：'+message+'\n' and t.read_bytes()==before,(result.stdout,result.stderr)
                print('PASS changed gate PATH refuses '+verb+' with unchanged ticket')
        ledger('gate-review',t,op,review,actor=actor)
        if check_environment:
            before=t.read_bytes()
            result=ledger('gate-verdict',t,op,'accepted',actor=actor,extra=changed,ok=False)
            assert result.stderr=='账本拒绝：缺当前两轴通过审核\n' and t.read_bytes()==before,(result.stdout,result.stderr)
            print('PASS changed gate PATH refuses gate-verdict with unchanged ticket')
        ledger('gate-verdict',t,op,'accepted',actor=actor)
        if notify:
            # Main has already consumed the verdict: release must independently wake it.
            for h in json.loads(call('qwb-send.sh','pending','--task',t).stdout):
                hid=h['event_id'];hop='notify-'+hashlib.sha256(hid.encode()).hexdigest()
                ref=p/'qwbuddy/.roles'/('result-'+hop+'.json')
                ref.write_text(json.dumps(dict(event_id=hid,op_id=hop,outcome='applied',evidence='public readback before release')))
                for verb in ['received','accept','prepared','handled']:
                    args=['--task',t,'--event',hid]
                    if verb!='received':args+=['--op',hop]
                    if verb=='handled':args+=['--result-ref',ref]
                    call('qwb-send.sh',verb,*args)
            before_pending=t.read_bytes()
            ledger('gate-review',t,op,review,actor=gate_actor)
            ledger('release',t,op,actor=gate_actor)
            pending_state=read(t)
            pending_release=next(e for e in reversed(pending_state['events']) if e['kind']=='release')
            assert 'source:'+pending_release['event_id'] not in pending_state['handoffs'], 'old accepted verdict leaked through newer pending review'
            t.write_bytes(before_pending)
            scripts={s:(p/'qwbuddy/bin'/s).read_bytes() for s in ['qwb-ledger.sh','qwb-lib.sh','qwb-send.sh','qwb-wake.sh']}
            notify_runtime=True
            try:
                if os.environ.get('QWB_NOTIFY_BASELINE')=='1':
                    for s in scripts:(p/'qwbuddy/bin'/s).write_bytes(subprocess.check_output(['git','-C',str(ROOT),'show','4b1f2e2:bin/'+s]))
                ledger('release',t,op,actor=actor)
                native=Path(env['LAND_NATIVE_LOG']);native.write_text('')
                call('qwb-wake.sh','--once','--pane','ctl')
                routes=[a for a in map(json.loads,native.read_text().splitlines()) if isinstance(a,list) and a[:2]==['pane','run']]
                print('EVIDENCE notify D release',routes,flush=True)
                assert len(routes)==1 and routes[0][2]=='ctl' and 'claim' in routes[0][3] and 'land-authorize' in routes[0][3], 'released acceptance has no controller doorbell'
                d=read(t);release=d['events'][next(i for i,e in enumerate(d['events']) if e['kind']=='release' and e['op_id']==op)]
                hid='source:'+release['event_id']
                assert hid in d['handoffs'] and d['handoffs'][hid]['transport_count']==1 and d['claim'] is None
                call('qwb-wake.sh','--once','--pane','ctl')
                assert read(t)['handoffs'][hid]['transport_count']==1
                print('PASS notify D：accepted通知已办理后release仍独立门铃一次，摘要给claim/land-authorize，重启去重且claim已释放',flush=True)
            finally:
                for s,raw in scripts.items():(p/'qwbuddy/bin'/s).write_bytes(raw)
                notify_runtime=False
        else:ledger('release',t,op,actor=actor)
        op='land-'+name;ledger('claim',t,op)
        return t,c,op,base,git('rev-parse','HEAD',at=c)
    if (os.environ['QWB_LAND_CASE']=='all' and not os.environ.get('QWB_NOTIFY_ONLY')) or os.environ.get('QWB_NOTIFY_ONLY')=='E':
        original_bin=notify_bin
        if os.environ.get('QWB_NOTIFY_BASELINE')=='1':
            notify_bin=tmp/'notify-baseline-bin';shutil.copytree(ROOT/'bin',notify_bin)
            for s in ['qwb-ledger.sh','qwb-lib.sh','qwb-send.sh','qwb-wake.sh']:
                (notify_bin/s).write_bytes(subprocess.check_output(['git','-C',str(ROOT),'show','4b1f2e2:bin/'+s]))
            notify_runtime=True
        try:
            t,c,op,m,head=accepted('notify-close')
            ledger('land-authorize',t,op,'notify-close-auth','main','fixture explicit close','tasks/notify-close.md')
            ledger('land-prepare',t,op,'notify-close-auth');ledger('land-apply',t,op,'notify-close-auth')
            ledger('append',t,'working: ordinary controller progress')
            call('qwb-send.sh','pending','--task',t)
            if os.environ.get('QWB_NOTIFY_BASELINE')!='1':
                current=read(t)
                self_kinds=['land-authorize','land-prepare','land-apply','land-close','recover-claim']
                assert not any(current['events'][h['source_seq']-1]['kind'] in self_kinds for h in current['handoffs'].values())
                # Old installed writers already materialized these actions; retain their audit bytes.
                sample=next(h for h in current['handoffs'].values() if not h['handled'])
                for e in current['events']:
                    if e['kind'] not in self_kinds:continue
                    hid='source:'+e['event_id']
                    current['handoffs'][hid]=dict(sample,event_id=hid,corr=hid,source_event=e['event_id'],source_seq=e['seq'],source_actor=e['actor'],payload=e['line'])
                body=t.read_bytes().split(b'\n<!-- qwb-collab-v1\n')[0]
                t.write_bytes(body+b'\n<!-- qwb-collab-v1\n'+json.dumps(current,ensure_ascii=False,separators=(',',':')).encode()+b'\n-->\n')
            git('worktree','remove',str(c));git('branch','-d','notify-close')
            before_close=t.read_bytes()
            result=ledger('land-close',t,op,'notify-close-auth')
            d=read(t);assert d['phase']=='verified' and d['land']['stage']=='closed'
            status=call('qwb-status.sh')
            assert '[已结]' in next(line for line in status.stdout.splitlines() if 'notify-close.md' in line),status.stdout
            assert all(not h['handled'] for h in d['handoffs'].values() if d['events'][h['source_seq']-1]['kind'] in ['land-authorize','land-prepare','land-apply'])
            closed=t.read_bytes()
            t.write_bytes(before_close)
            mismatch=read(t);mismatch['land']['context']['attempt']='unrelated-attempt'
            body=t.read_bytes().split(b'\n<!-- qwb-collab-v1\n')[0]
            t.write_bytes(body+b'\n<!-- qwb-collab-v1\n'+json.dumps(mismatch,ensure_ascii=False,separators=(',',':')).encode()+b'\n-->\n')
            denied=ledger('land-close',t,op,'notify-close-auth',ok=False)
            assert '收尾义务/用户问题仍未结' in denied.stderr
            t.write_bytes(before_close)
            call('qwb-send.sh','send','--task',t,'--corr','notify-fake-self','--attempt','1','--text','working: land-close this is a real explicit request')
            denied=ledger('land-close',t,op,'notify-close-auth',ok=False)
            assert '收尾义务/用户问题仍未结' in denied.stderr
            for problem in ['blocked','question','unread-question','answered']:
                t.write_bytes(before_close)
                if problem=='blocked':
                    ledger('dispatch',t,op,'notify-worker',f'dispatch: op_id={op} worker=sol pane=notify-worker dir={c}')
                    ledger('append',t,'blocked: real worker action remains',actor='notify-worker')
                    call('qwb-send.sh','pending','--task',t)
                else:
                    ledger('question',t,'notify-user','real user decision required')
                    # Handle notification, but never answer/resume merely by handling it.
                    questions=[] if problem=='unread-question' else json.loads(call('qwb-send.sh','pending','--task',t).stdout)
                    for h in questions:
                        if not h['payload'].startswith('needs-decision:'):continue
                        hid=h['event_id'];hop='notify-question'
                        ref=p/'qwbuddy/.roles/notify-question.json';ref.write_text(json.dumps(dict(event_id=hid,op_id=hop,outcome='applied',evidence='question read; still unresolved')))
                        for verb in ['received','accept','prepared','handled']:
                            args=['--task',t,'--event',hid]
                            if verb!='received':args+=['--op',hop]
                            if verb=='handled':args+=['--result-ref',ref]
                            call('qwb-send.sh',verb,*args)
                    if problem=='answered':ledger('answer',t,'notify-user','real answer; not resumed')
                snapshot=t.read_bytes();denied=ledger('land-close',t,op,'notify-close-auth',ok=False)
                expected='收尾义务/用户问题仍未结' if problem=='blocked' else '收尾问题未恢复'
                assert expected in denied.stderr and t.read_bytes()==snapshot,(problem,denied.stderr)
            t.write_bytes(closed)
            print('PASS notify E：四步落地无自办交接，纯进度不挡close，verified已结；真实工人blocked/未答/未恢复仍原文拒绝',flush=True)
        finally:
            notify_runtime=False;notify_bin=original_bin
        if os.environ.get('QWB_NOTIFY_ONLY')=='E':raise SystemExit(0)
        t.unlink()
    if (os.environ['QWB_LAND_CASE']=='all' and not os.environ.get('QWB_NOTIFY_ONLY')) or os.environ.get('QWB_NOTIFY_ONLY')=='D':
        t,c,op,m,head=accepted('notify-release',gate_actor='gate-pane')
        ledger('land-authorize',t,op,'notify-release-auth','main','fixture explicit land after release','tasks/notify-release.md')
        assert read(t)['land']['after']==head
        assert not any('已交还' in h['payload'] for h in json.loads(call('qwb-send.sh','pending','--task',t,'--due').stdout)), 'land-authorize did not satisfy matching release notice'
        if os.environ.get('QWB_NOTIFY_ONLY')=='D':raise SystemExit(0)
        # Restore only this private scenario before unrelated legacy land fixtures.
        git('worktree','remove',str(c));git('branch','-D','notify-release');t.unlink()
    def dead_generation():
        child=subprocess.Popen(['python3','-u','-c',"import os,sys; print(os.getpid(),flush=True); sys.stdin.readline()"],
                               stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
        try:
            pid=int(child.stdout.readline())
            start=subprocess.check_output(['/bin/ps','-p',str(pid),'-o','lstart='],text=True).strip()
            child.communicate('exit\n',timeout=20); assert child.returncode==0
            return {'pid':pid,'pid_start':start}
        finally:
            if child.poll() is None: child.terminate(); child.wait(timeout=20)
    if os.environ['QWB_LAND_CASE']=='env-digest':
        env['LC_ALL']='';env['LANG']='en_US.UTF-8'
        t,c,op,m,head=accepted('env-digest',actor='gate-pane',check_environment=True)
        approved=read(t)['gate']['reviews'][-1]['review']['context']
        other={'PATH':env['PATH']+':'+str(tmp),'LANG':'C'}
        ref='auth-env'
        ledger('land-authorize',t,op,ref,'main','different controller environment','tasks/env-digest.md','tasks/live.md',extra=other)
        assert read(t)['land']['context']==approved
        call('qwb-worktree.sh','land','env-digest','--op',op,'--auth-ref',ref,extra=other)
        d=read(t)
        assert git('rev-parse','main')==head and d['phase']=='verified' and not c.exists()
        assert d['land']['stage']=='closed' and d['land']['context']==approved
        print('PASS different controller PATH/LANG and wrapper LC_ALL land exact accepted candidate')
        sys.exit(0)
    if os.environ['QWB_LAND_CASE']=='env-compat':
        t,c,op,m,head=accepted('env-compat',check_environment=True)
        snapshot=tmp/'env-snapshot';shutil.copytree(p,snapshot)
        runtime=tmp/'env-bin';shutil.copytree(ROOT/'bin',runtime)
        native=Path(env['LAND_NATIVE_STATE']);saved_native=native.read_bytes()
        old=subprocess.check_output([real_git,'-C',str(ROOT),'show','4b1f2e2:bin/qwb-ledger.sh']).decode()
        new=(ROOT/'bin/qwb-ledger.sh').read_text()
        evidence=[]
        for version,source in [('base',old),('current',new)]:
            shutil.rmtree(p);shutil.copytree(snapshot,p);native.write_bytes(saved_native)
            source=source.replace("$event=unpack('H*',$bytes);",'$event=sprintf("%032x",$data->{seq});')
            source=source.replace('int(time()*1000)','1791158400000')
            source=source.replace("at=>strftime('%Y-%m-%dT%H:%M:%SZ',gmtime)","at=>'2026-10-05T00:00:00Z'")
            (runtime/'qwb-ledger.sh').write_text(source)
            results=[]
            def record(script,verb,*args,**kw):
                result=call(script,verb,*args,**kw)
                results.append((result.returncode,result.stdout,result.stderr,t.read_bytes()))
                return result
            ref='auth-compat'
            # Freeze only clock/event entropy; compare real public CLI output and ticket bytes.
            record('qwb-ledger.sh','gate-receipt','--task',t,'--',op,tmp/'env-compat-full.json')
            record('qwb-ledger.sh','gate-review','--task',t,'--',op,tmp/'env-compat-review.json')
            record('qwb-ledger.sh','gate-verdict','--task',t,'--',op,'accepted')
            record('qwb-ledger.sh','land-authorize','--task',t,'--',op,ref,'main','same environment','tasks/env-compat.md','tasks/live.md')
            authorized=t.read_bytes()
            for stage in ['land-authorize','land-prepare','land-apply']:
                t.write_bytes((snapshot/'tasks/env-compat.md').read_bytes() if stage=='land-authorize' else authorized)
                if stage=='land-apply':ledger('land-prepare',t,op,ref)
                clean=t.read_bytes()
                for mutation,message in [('dirty','未验收或验收条件已变'),('spec','规格正文已变'),('scenarios','规格/场景已变；原收据失效，交主控重授权'),('commit','候选已变但未登记新attempt')]:
                    before_head=git('rev-parse','HEAD',at=c)
                    if mutation=='dirty':(c/'dirty.txt').write_text('dirty\n')
                    elif mutation=='spec':t.write_text(t.read_text().replace('# env-compat','# revised spec',1))
                    elif mutation=='scenarios':t.write_text(t.read_text().replace('Given candidate','Given changed candidate',1))
                    else:
                        # A real descendant; restore only this private fixture ref afterwards.
                        tree=git('rev-parse','HEAD^{tree}',at=c)
                        changed=git('-c','user.name=Test','-c','user.email=test@invalid','commit-tree',tree,'-p',before_head,'-m','changed candidate',at=c)
                        git('update-ref','refs/heads/env-compat',changed,before_head)
                    before=t.read_bytes()
                    args=[op,ref,'main','same environment','tasks/env-compat.md','tasks/live.md'] if stage=='land-authorize' else [op,ref]
                    result=record('qwb-ledger.sh',stage,'--task',t,'--',*args,ok=False)
                    assert result.stderr=='账本拒绝：'+message+'\n' and t.read_bytes()==before and git('rev-parse','main')==m,(mutation,result.stderr)
                    if mutation=='dirty':(c/'dirty.txt').unlink()
                    elif mutation=='commit':git('update-ref','refs/heads/env-compat',before_head,changed)
                    t.write_bytes(clean)
            t.write_bytes(authorized)
            record('qwb-worktree.sh','land','env-compat','--op',op,'--auth-ref',ref)
            assert read(t)['phase']=='verified' and git('rev-parse','main')==head and not c.exists()
            evidence.append(results)
            print('EVIDENCE '+version+' byte transcript sha256='+hashlib.sha256(repr(results).encode()).hexdigest())
        assert evidence[0]==evidence[1],[(i,a[:3],b[:3]) for i,(a,b) in enumerate(zip(*evidence)) if a!=b]
        print('PASS base/current gate and official land stdout/stderr/rc/ticket bytes identical')
        print('PASS base/current dirty/spec/scenarios/new commit refused at authorize/prepare/apply; main unchanged')
        sys.exit(0)
    if os.environ['QWB_LAND_CASE']=='agent-shapes':
        t,c,op,m,head=accepted('agent-shapes')
        ledger('dispatch',t,op,'worker-pane',f'dispatch: op_id={op} worker=sol pane=worker-pane dir={c}')
        ledger('append',t,f'worktree-space: id=task-space root-tab=task-tab path={c}')
        ledger('append',t,f'working: worker-activity op={op} pane=worker-pane evidence='+json.dumps(dead_generation()))
        ref='auth-agent-shapes'
        ledger('land-authorize',t,op,ref,'main','fixture explicit local land','tasks/agent-shapes.md','tasks/live.md')
        ledger('land-prepare',t,op,ref); ledger('land-apply',t,op,ref)
        snapshot=tmp/'shape-snapshot'; shutil.copytree(p,snapshot)
        runtime=tmp/'shape-bin';shutil.copytree(ROOT/'bin',runtime)
        # Same deterministic writer clock/event IDs for both scripts; compare actual bytes, not normalized receipts.
        writer=runtime/'qwb-ledger.sh';text=writer.read_text()
        assert text.count("$event=unpack('H*',$bytes);")==1
        text=text.replace("$event=unpack('H*',$bytes);",'$event=sprintf("%032x",$data->{seq});')
        text=text.replace("at=>strftime('%Y-%m-%dT%H:%M:%SZ',gmtime)","at=>'2026-10-04T00:00:00Z'")
        writer.write_text(text)
        names=['qwb-worktree.sh','qwb-herdr.sh']
        old={name:subprocess.check_output([real_git,'-C',str(ROOT),'show','d3e4b49:bin/'+name]) for name in names}
        new={name:(ROOT/'bin'/name).read_bytes() for name in names}
        native=Path(env['LAND_NATIVE_STATE']); saved_native=native.read_bytes()
        gitlog=tmp/'shape-git.log'; nativelog=Path(env['LAND_NATIVE_LOG'])
        def shape_run(version,target,shape='null',process='',fault='',ok=False):
            shutil.rmtree(p);shutil.copytree(snapshot,p)
            native.write_bytes(saved_native);gitlog.write_bytes(b'');nativelog.write_bytes(b'')
            for name,data in version.items():(runtime/name).write_bytes(data)
            extra=dict(LAND_ENDPOINT='stopped',LAND_SPACE_PATH=str(c),LAND_SHAPE_TARGET=target,
                       LAND_AGENT_SHAPE=shape,LAND_PROCESS_FAULT=process,LAND_PANE_FAULT=fault,LAND_BYTES_GIT_LOG=str(gitlog))
            result=subprocess.run(['/bin/bash',str(runtime/'qwb-worktree.sh'),'finish','agent-shapes','--merged',
                                   '--project',str(p),'--op',op,'--auth-ref',ref],env=env|extra,capture_output=True,text=True)
            assert (result.returncode==0)==ok,(target,shape,process,fault,result.stdout,result.stderr)
            if not ok:
                assert t.read_bytes()==(snapshot/'tasks/agent-shapes.md').read_bytes() and c.is_dir()
                assert git('rev-parse','main')==head and git('rev-parse','refs/heads/agent-shapes')==head
                assert native.read_bytes()==saved_native
            records=[json.loads(line) for line in nativelog.read_text().splitlines()]
            for row in records:
                if isinstance(row,dict):row.pop('id',None) # RPC IDs are transport randomness only.
            evidence=dict(rc=result.returncode,stdout=result.stdout,stderr=result.stderr,ticket=t.read_bytes().hex(),
                          git_calls=gitlog.read_bytes().hex(),herdr_calls=records,refs=git('show-ref'),
                          exists=c.exists(),status=git('status','--short'),native=json.loads(native.read_text()))
            print('SHAPE EVIDENCE '+json.dumps(dict(target=target,shape=shape,process=process,fault=fault,
                                                   rc=result.returncode,stdout=result.stdout,stderr=result.stderr),ensure_ascii=False),flush=True)
            return evidence
        # Distinct worker/root panes force both land guards to execute independently.
        baseline=shape_run(old,'worker-pane',ok=True)
        def equivalent(actual):
            assert actual==baseline,{key:(baseline[key],actual[key]) for key in baseline if actual[key]!=baseline[key]}
        for target in ('worker-pane','task-pane'):
            equivalent(shape_run(new,target,ok=True))
            equivalent(shape_run(new,target,'omitted',ok=True))
            print('PASS land '+target+': d3e4b49 null/current null/omitted bytes identical',flush=True)
            for shape in ('"pi"','"1pi"','""','42','0','[]','{}','true','false'):
                got=shape_run(new,target,shape)
                assert ('尚未退出' if shape in ('"pi"','"1pi"') else '未知') in got['stderr'],got
                print('PASS land '+target+' rejects agent='+shape+' without side effects',flush=True)
            for process in ('foreground','query'):
                prior=shape_run(old,target,process=process)
                assert shape_run(new,target,'omitted',process)==prior
                print('PASS land '+target+' omitted agent still rejects '+process+' with unchanged bytes',flush=True)
            for fault in ('json','error','stderr','id','object'):
                got=shape_run(new,target,'omitted',fault=fault)
                assert '未知' in got['stderr'],got
                print('PASS land '+target+' rejects malformed pane '+fault+' without side effects',flush=True)
        # Leave this private project in its accepted closed state for subsequent cases.
        shape_run(new,'worker-pane','omitted',ok=True)
        if os.environ['QWB_LAND_CASE']=='agent-shapes':sys.exit(0)
    if os.environ['QWB_LAND_CASE']=='writers':
        t,c,op,m,head=accepted('background-writer')
        ledger('dispatch',t,op,'task-pane',f'dispatch: op_id={op} worker=sol pane=task-pane dir={c}')
        ref='auth-background'
        ledger('land-authorize',t,op,ref,'main','fixture explicit local land',
               'tasks/background-writer.md','tasks/live.md')
        def land(ok=False,extra=None):
            return call('qwb-worktree.sh','land','background-writer','--op',op,'--auth-ref',ref,
                        extra={'LAND_ENDPOINT':'stopped'}|(extra or {}),ok=ok)
        def retained():
            d=read(t)
            assert c.is_dir() and git('rev-parse','refs/heads/background-writer')==head
            assert git('rev-parse','main')==head and d['land']['stage']=='landed'
            assert d['phase']!='verified' and d['claim']['op_id']==op
            assert (tmp/'git.log').read_text().splitlines().count(head)==1
        for mode in ['cwd+fd','fd-only','cwd-only']:
            code="import os,sys; f=open('product.txt','r+') if sys.argv[1]!='cwd-only' else None; "
            code+="os.chdir(sys.argv[2]) if sys.argv[1]=='fd-only' else None; print(os.getpid(),flush=True); "
            code+="sys.stdin.readline(); print('NLINK='+str(os.fstat(f.fileno()).st_nlink) if f else 'PATH_READ='+str(os.path.isfile('product.txt')),flush=True)"
            writer=subprocess.Popen(['python3','-u','-c',code,mode,str(tmp)],cwd=c,
                                    stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
            try:
                pid=int(writer.stdout.readline()); assert writer.poll() is None
                probe=subprocess.run([real_lsof,'-nP','-Fpfan','+D',str(c)],capture_output=True,text=True)
                assert probe.returncode in (0,1) and f'p{pid}\n' in probe.stdout,(probe.returncode,probe.stdout,probe.stderr)
                print('OS_PROBE '+mode+' '+probe.stdout.replace('\n',' | '),flush=True)
                result=land(); assert '候选写入者' in result.stderr,result.stderr
                retained(); assert writer.poll() is None
                writer.stdin.write('continue\n'); writer.stdin.flush()
                actual=writer.stdout.readline().strip()
                assert actual==('PATH_READ=True' if mode=='cwd-only' else 'NLINK=1'),actual
                assert writer.wait(timeout=20)==0
                print('PASS real writer '+mode+' alive refuses; barrier '+actual,flush=True)
            finally:
                if writer.poll() is None: writer.terminate(); writer.wait(timeout=20)
        # No resources remaining is NOT a proof that an unbound/older launch died.
        result=land(); assert '启动代死亡证据缺失' in result.stderr,result.stderr; retained()
        old=subprocess.Popen(['python3','-u','-c',"import os,sys; print(os.getpid(),flush=True); sys.stdin.readline()"],
                             cwd=tmp,stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
        try:
            pid=int(old.stdout.readline())
            start=subprocess.check_output(['/bin/ps','-p',str(pid),'-o','lstart='],text=True).strip()
            def bind(raw): ledger('append',t,f'working: worker-activity op={op} pane=task-pane evidence='+json.dumps(raw))
            bind({'pid':pid,'pid_start':start})
            # A newer dead launch must not hide an older live launch on the same pane.
            ledger('append',t,'working: worker-activity op=newer-dead pane=task-pane evidence='+json.dumps(dead_generation()))
            result=land(); assert '旧启动代仍活或死亡未知' in result.stderr,result.stderr; retained()
            old.stdin.write('continue\n'); old.stdin.flush(); assert old.wait(timeout=20)==0
            result=land(extra={'LAND_RESOURCE_PROBE':'unknown'})
            assert '候选写入者资源探针未知' in result.stderr,result.stderr; retained()
            land(ok=True)
            d=read(t); assert not c.exists() and d['phase']=='verified' and d['land']['stage']=='closed'
            assert (tmp/'git.log').read_text().splitlines().count(head)==1
            assert len([e for e in d['events'] if e['kind']=='land-apply'])==1
            print('PASS old alive/missing proof refuse; actual exit same op closes without remerge',flush=True)
        finally:
            if old.poll() is None: old.terminate(); old.wait(timeout=20)
        # 共用finish的merged/archive都守资源与未知启动代，不只修land表象。
        for action in ['--merged','--archive']:
            name='legacy-'+action[2:]; wc=p/'.worktrees'/name
            git('worktree','add','-qb',name,str(wc),'main')
            ticket=p/'tasks'/f'{name}.md'; ticket.write_text('state: blocked\n')
            child=subprocess.Popen(['python3','-u','-c',"import os,sys; print(os.getpid(),flush=True); sys.stdin.readline()"],
                                   cwd=wc,stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
            try:
                pid=int(child.stdout.readline())
                start=subprocess.check_output(['/bin/ps','-p',str(pid),'-o','lstart='],text=True).strip()
                result=call('qwb-worktree.sh','finish',name,action,ok=False)
                assert '候选写入者' in result.stderr and wc.is_dir(),result.stderr
                child.communicate('exit\n',timeout=20); assert child.returncode==0
                ticket.write_text(f'state: blocked\ndispatch: op_id=legacy worker=sol pane=task-pane dir={wc}\n')
                result=call('qwb-worktree.sh','finish',name,action,ok=False)
                assert '启动代死亡证据缺失' in result.stderr and wc.is_dir(),result.stderr
                ticket.write_text(ticket.read_text().replace('dispatch:','not-sent:')+'working: worker-activity op=legacy pane=task-pane evidence='+json.dumps({'pid':pid})+'\n')
                result=call('qwb-worktree.sh','finish',name,action,ok=False)
                assert 'PID/start未知' in result.stderr and wc.is_dir(),result.stderr
                # 私有legacy夹具准确补齐启动时已实际读取的start，不改协作票历史。
                ticket.write_text(f'state: blocked\ndispatch: op_id=legacy worker=sol pane=task-pane dir={wc}\nworking: worker-activity op=legacy pane=task-pane evidence='+json.dumps({'pid':pid,'pid_start':start})+'\n')
                call('qwb-worktree.sh','finish',name,action)
                assert not wc.exists()
                print('PASS shared finish '+action+' live/missing PID/start refuses; actual dead succeeds')
            finally:
                if child.poll() is None: child.terminate(); child.wait(timeout=20)
        sys.exit(0)
    t,c,op,m,head=accepted('A')
    status=subprocess.run(['bash',str(ROOT/'bin/qwb-status.sh'),'--project',str(p)],env=env,capture_output=True,text=True)
    assert status.returncode==0 and '本地land:' not in status.stdout and 'Use of uninitialized' not in status.stderr,(status.stdout,status.stderr)
    print('PASS 尚无land的04票状态不伪造空land事实')
    ledger('land-authorize',t,op,'auth-A','main','fixture explicit local land','tasks/A.md','tasks/live.md')
    call('qwb-worktree.sh','land','A','--op',op,'--auth-ref','auth-A')
    d=read(t); assert git('rev-parse','main')==head and not c.exists()
    assert d['land']['before']==m and d['land']['after']==head and d['land']['auth_ref']=='auth-A' and d['land']['stage']=='closed'
    assert d['claim'] is None and d['phase']=='verified'
    metrics=json.loads(ledger('metrics',t).stdout);assert metrics['ready_to_land_seconds']>=0 and metrics['tokens']=='unknown'
    print('METRICS '+json.dumps({k:metrics[k] for k in ['ready_at','ready_to_land_seconds','tokens']}))
    assert len([e for e in d['events'] if e['kind']=='land-apply'])==1
    assert (p/'qwbuddy/.roles/gate.json').exists()
    call('qwb-worktree.sh','land','A','--op',op,'--auth-ref','wrong',ok=False)
    call('qwb-worktree.sh','land','A','--op',op,'--auth-ref','auth-A')
    print('PASS user_合法候选落地并收尾')
    def authorize(t,op,ref,ok=True):
        # 明确登记本夹具实际创建的每个MD，不用tasks目录忽略规则。
        return ledger('land-authorize',t,op,ref,'main','fixture explicit local land',*[str(f.relative_to(p)) for f in sorted((p/'tasks').glob('*.md'))],ok=ok)
    tb,cb,ob,mb,hb=accepted('B',change='b.txt');tc,cc,oc,mc,hc=accepted('C',base=mb)
    authorize(tb,ob,'auth-B'); authorize(tc,oc,'auth-C')
    ledger('land-prepare',tb,ob,'auth-B')
    call('qwb-worktree.sh','land','C','--op',oc,'--auth-ref','auth-C')
    before=tb.read_bytes();call('qwb-worktree.sh','land','B','--op',ob,'--auth-ref','auth-B',ok=False)
    assert git('rev-parse','main')==hc and cb.exists() and tb.read_bytes()==before and read(tb)['land']['stage']=='prepared'
    # 锁外、原候选一次有界集成；旧绿不当组合绿，新的M/C需新检查/授权。
    git('-c','user.name=Test','-c','user.email=test@invalid','merge','--no-edit',hc,at=cb)
    ledger('gate-candidate',tb,ob,'2',cb,hc,'integration')
    ledger('gate-verdict',tb,ob,'accepted',ok=False)
    report=tmp/'B-new-full.json';call('qwb-test.sh','full','--project',cb,'--task',tb,'--ledger-project',p,'--op',ob,'--report',report)
    rev=json.loads((tmp/'B-review.json').read_text());rev['context']=json.loads(report.read_text())['after']
    review=tmp/'B-new-review.json';review.write_text(json.dumps(rev));ledger('gate-review',tb,ob,review);ledger('gate-verdict',tb,ob,'accepted')
    authorize(tb,ob,'auth-B',ok=False);authorize(tb,ob,'auth-B-2')
    call('qwb-worktree.sh','land','B','--op',ob,'--auth-ref','auth-B-2')
    assert read(tb)['land_history'][0]['after']==hb
    print('PASS user_并发候选与旧基线拒绝；锁外有界隔离集成、新证据、新授权')
    td,cd,od,md,hd=accepted('D')
    before=td.read_bytes()
    call('qwb-worktree.sh','land','D','--op',od,'--auth-ref','absent',ok=False)
    ledger('land-authorize',td,od,'gate-authority','main','not controller','tasks/D.md',actor='gate-pane',ok=False)
    assert td.read_bytes()==before and git('rev-parse','main')==md
    authorize(td,od,'auth-D')
    ledger('land-prepare',td,od,'auth-D')
    # 真实flock碰撞，不伪造返回码；busy只拒绝本次land且无测试/merge进入短锁。
    with (p/'.git/qwb-land-main.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        start=time.monotonic();call('qwb-worktree.sh','land','D','--op',od,'--auth-ref','auth-D',ok=False)
        assert time.monotonic()-start<60 and git('rev-parse','main')==md
    (p/'tasks/unregistered.md').write_text('unregistered WIP\n')
    call('qwb-worktree.sh','land','D','--op',od,'--auth-ref','auth-D',ok=False)
    (p/'tasks/unregistered.md').unlink()
    live_bytes=(p/'tasks/live.md').read_bytes();(p/'tasks/live.md').unlink();(p/'tasks/live.md').symlink_to(tmp/'environment')
    call('qwb-worktree.sh','land','D','--op',od,'--auth-ref','auth-D',ok=False)
    (p/'tasks/live.md').unlink();(p/'tasks/live.md').write_bytes(live_bytes)
    (p/'product.txt').write_text('WIP\n');before=td.read_bytes()
    call('qwb-worktree.sh','land','D','--op',od,'--auth-ref','auth-D',ok=False)
    assert (p/'product.txt').read_text()=='WIP\n' and td.read_bytes()==before and cd.exists()
    (p/'product.txt').write_bytes(subprocess.check_output(['git','-C',str(p),'show','HEAD:product.txt']))
    (p/'tasks/live.md').write_text('dynamic MD preserved\n');git('add','tasks/live.md')
    call('qwb-worktree.sh','land','D','--op',od,'--auth-ref','auth-D',ok=False)
    # 只还原本临时夹具自己的索引，不作用共享仓/现场；无reset/stash。
    live_blob=git('rev-parse','HEAD:tasks/live.md');git('update-index','--cacheinfo','100644',live_blob,'tasks/live.md')
    before_live=(p/'tasks/live.md').read_bytes()
    call('qwb-worktree.sh','land','D','--op',od,'--auth-ref','auth-D')
    assert (p/'tasks/live.md').read_bytes()==before_live and git('rev-parse','main')==hd
    te,ce,oe,me,he=accepted('E',change='tasks/live.md')
    before=te.read_bytes();authorize(te,oe,'auth-E',ok=False)
    assert te.read_bytes()==before and ce.exists() and (p/'tasks/live.md').read_bytes()==before_live
    print('PASS user_无权与脏现场拒绝；索引/产品拒绝，受控MD字节保留，相关目录冲突拒绝')
    for failure in ['publish','remove','delete','endpoint','publish-reauthorize']:
        name='recover-'+failure;t,c,op,m,head=accepted(name);ref='auth-'+failure
        if failure=='endpoint':
            ledger('dispatch',t,op,'task-pane',f'dispatch: op_id={op} worker=sol pane=task-pane dir={c}')
            ledger('append',t,f'worktree-space: id=task-space root-tab=task-tab path={c}')
            ledger('append',t,f'working: worker-activity op={op} pane=task-pane evidence='+json.dumps(dead_generation()))
        authorize(t,op,ref)
        flag=Path(env['LAND_FAIL_FLAG']);flag.unlink(missing_ok=True)
        extra={'LAND_FAIL':'publish' if failure=='publish-reauthorize' else failure}
        if failure=='endpoint':extra|={'LAND_SPACE_PATH':str(c),'LAND_ENDPOINT':'active'}
        call('qwb-worktree.sh','land',name,'--op',op,'--auth-ref',ref,extra=extra,ok=False)
        d=read(t);assert git('rev-parse','main')==head and d['phase']!='verified' and d['claim']['op_id']==op
        assert d['land']['stage']==('prepared' if failure.startswith('publish') else 'landed')
        calls=(tmp/'git.log').read_text().splitlines()
        merges=calls.count(head)
        assert merges==1
        if failure=='delete':
            call('qwb-worktree.sh','land',name,'--op',op,'--auth-ref',ref,extra=extra|{'LAND_SPACE_PATH':str(c)},ok=False)
            assert not c.exists() and read(t)['land']['stage']=='landed' and read(t)['phase']!='verified'
        if failure=='publish-reauthorize':
            ledger('land-authorize',t,op,ref+'-resumed','main','fixture exact local C authorizes only remaining cleanup')
            assert read(t)['land_history'][-1]['stage']=='prepared'
            ref+='-resumed'
        if failure=='endpoint':
            call('qwb-worktree.sh','land',name,'--op',op,'--auth-ref',ref,extra=extra|{'LAND_ENDPOINT':'unknown'},ok=False)
            assert c.exists() and read(t)['phase']!='verified'
            # 同pane主控换代：旧auth拒绝，显式新授权保留同op/旧收据，只续收尾。
            (p/'qwbuddy/.controller.lock/owner').write_text('2100 ctl\n')
            call('qwb-worktree.sh','land',name,'--op',op,'--auth-ref',ref,extra=extra,ok=False)
            ledger('land-authorize',t,op,ref,'main','old ref forbidden',ok=False)
            ledger('land-authorize',t,op,ref+'-resumed','main','fixture new generation explicitly authorizes remaining cleanup')
            assert read(t)['land_history'][-1]['auth_ref']==ref
            ref+='-resumed';extra['LAND_ENDPOINT']='stopped'
        call('qwb-worktree.sh','land',name,'--op',op,'--auth-ref',ref,extra=extra)
        d=read(t);assert d['land']['stage']=='closed' and d['phase']=='verified' and not c.exists()
        calls=(tmp/'git.log').read_text().splitlines()
        assert calls.count(head)==1
        assert len([e for e in d['events'] if e['kind']=='land-apply'])==1
        print('PASS user_合并成功记账或清理失败 '+failure+' 同op补事实/partial，无重复merge')
        if failure=='endpoint':(p/'qwbuddy/.controller.lock/owner').write_text('2099 ctl\n')
PY
# Run the new matrix in its own supervised project, preserving the original status/land fixtures.
if [[ "${1:-all}" == all ]]; then
  bash "$0" agent-shapes
  bash "$0" env-digest
  bash "$0" env-compat
fi
