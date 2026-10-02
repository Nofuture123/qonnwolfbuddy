#!/usr/bin/env bash
# 私有临时Git + 系统边界fakeHerdr；不碰现场main/端点。
set -euo pipefail
export QWB_LAND_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
export QWB_LAND_CASE="${1:-all}"
python3 -B - <<'PY'
import fcntl, hashlib, json, os, shutil, subprocess, sys, tempfile, time
from pathlib import Path
ROOT=Path(os.environ['QWB_LAND_ROOT'])
with tempfile.TemporaryDirectory(prefix='qwb-land-') as tmp:
    tmp=Path(tmp).resolve(); p=tmp/'project'; p.mkdir(); stub=tmp/'stub'; stub.mkdir()
    shutil.copytree(ROOT/'bin',p/'qwbuddy/bin'); shutil.copytree(ROOT/'templates/roles',p/'qwbuddy/roles')
    for n in ['TASK.md','QWBUDDY.md']: shutil.copy(ROOT/'templates'/n,p/'qwbuddy'/n)
    (p/'qwbuddy/.controller.lock').mkdir(); (p/'qwbuddy/.controller.lock/owner').write_text('2099 ctl\n')
    integration=tmp/'integration.ts'; integration.write_text('// HERDR_INTEGRATION_ID=pi\n')
    (p/'qwbuddy/config.sh').write_text(f"QWB_WORKERS='sol reviewer'\nQWB_WORKSPACE='ws'\nQWB_ROLE_PI_CONTROL='verified'\nQWB_ROLE_PI_INTEGRATION='{integration}'\nQWB_GATE_FAST='test -f product.txt'\nQWB_GATE_FULL='test -s product.txt'\n")
    (p/'qwbuddy/workers.sh').write_text('qwb_worker sol herdr pi -- --provider openai-codex --model gpt-6.1-sol --thinking high\nqwb_worker reviewer herdr pi -- --provider anthropic --model claude-opus-4-6 --thinking low\n')
    (p/'tasks').mkdir(); (p/'.gitignore').write_text('qwbuddy/.roles/\nqwbuddy/.controller.lock/\n.worktrees/\ntasks/*.qwb-*\n')
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
def out(x):print(json.dumps({'result':x}))
if a[:2]==['workspace','list']:
 w=[{'workspace_id':'ws','worktree':{'repo_root':p,'is_linked_worktree':False}}]
 if os.environ.get('LAND_SPACE_PATH') and not s.get('space_closed'):w.append({'workspace_id':'task-space','worktree':{'repo_root':p,'is_linked_worktree':True,'checkout_path':os.environ['LAND_SPACE_PATH']}})
 out({'workspaces':w})
elif a[:2]==['tab','list']:out({'tabs':[{'tab_id':'task-tab'}]})
elif a[:2]==['pane','list']:out({'panes':[{'pane_id':'task-pane','agent_status':'idle'}]})
elif a[:2]==['workspace','close']:s['space_closed']=True;out({'type':'workspace_closed'})
elif a[:2]==['tab','create']:out({'root_pane':{'pane_id':'gate-pane','tab_id':'gate-tab','terminal_id':'gate-terminal'}})
elif a[:2]==['agent','get']:print(json.dumps({'error':{'code':'agent_not_found'}}));sys.exit(1)
elif a[:2]==['agent','start']:
 v=a[a.index('--')+1:]; sid=v[v.index('--session-id')+1]; sd=v[v.index('--session-dir')+1];s={'session':sd+'/2099_'+sid+'.jsonl'};out({'type':'agent_started'})
elif a[:2]==['pane','get'] and a[2]=='task-pane':
 if os.environ.get('LAND_ENDPOINT')=='unknown':print(json.dumps({'error':{'code':'other_error'}}));sys.exit(1)
 out({'pane':{'pane_id':'task-pane','workspace_id':'task-space','tab_id':'task-tab','agent':None if os.environ.get('LAND_ENDPOINT')=='stopped' else 'pi','agent_status':'idle'}})
elif a[:2]==['pane','process-info'] and a[-1]=='task-pane':out({'process_info':{'shell_pid':42,'foreground_process_group_id':42,'foreground_processes':[]}})
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
    def call(script,verb,*args,actor='ctl',ok=True,extra=None):
        r=subprocess.run(['bash',str(ROOT/'bin'/script),verb,'--project',str(p),*map(str,args)],env=env|{'HERDR_PANE_ID':actor}|(extra or {}),capture_output=True,text=True)
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
    def accepted(name,base=None,change='product.txt'):
        base=base or git('rev-parse','main'); c=p/'.worktrees'/name
        git('worktree','add','-qb',name,str(c),base)
        (c/change).write_text(name+'\n'); git('add',change,at=c);git('-c','user.name=Test','-c','user.email=test@invalid','commit','-qm',name,at=c)
        t=p/'tasks'/f'{name}.md';t.write_text('# '+name+'\nstate: running\n## 验收场景\n### user_success\nGiven candidate\nWhen land\nThen success\n### user_reject\nGiven dirty\nWhen land\nThen reject\n')
        m=tmp/'migration.json';m.write_text(json.dumps({'task_sha256':hashlib.sha256(t.read_bytes()).hexdigest(),'confirm':{k:'fixture stopped; no external actions' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']}}))
        ledger('migrate',t,m)
        environment=tmp/'environment';environment.write_text('fixture v1\n')
        req=tmp/'assignment.json';req.write_text(json.dumps({'candidate':str(c),'base':base,'attempt':'1','policy':'v1','environment':str(environment),'required':{'full':['user_success','user_reject']},'workers':{'review':'reviewer','rework':'sol'}}))
        ledger('gate-assign',t,'gate',req); op='accept-'+name;ledger('claim',t,op)
        report=tmp/(name+'-full.json')
        call('qwb-test.sh','full','--project',c,'--task',t,'--ledger-project',p,'--op',op,'--report',report)
        def session(sid,model,provider,family,effort):
            f=tmp/(sid+'.jsonl');f.write_text('\n'.join(json.dumps(x) for x in [{'type':'session','id':sid,'cwd':str(p)},{'type':'model_change','modelId':model,'provider':provider},{'type':'thinking_level_change','thinkingLevel':effort}])+'\n')
            return {'model':model,'family':family,'session':sid,'evidence':str(f)}
        review=tmp/(name+'-review.json');review.write_text(json.dumps({'context':json.loads(report.read_text())['after'],'implementer':session('impl-'+name,'gpt-6.1-sol','openai-codex','gpt','high'),'reviewer':session('rev-'+name,'claude-opus-4-6','anthropic','claude','low'),'standards':'pass','spec':'pass','covered':['user_success','user_reject'],'findings':[]}))
        ledger('gate-review',t,op,review);ledger('gate-verdict',t,op,'accepted')
        ledger('release',t,op); op='land-'+name;ledger('claim',t,op)
        return t,c,op,base,git('rev-parse','HEAD',at=c)
    def dead_generation():
        child=subprocess.Popen(['python3','-u','-c',"import os,sys; print(os.getpid(),flush=True); sys.stdin.readline()"],
                               stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
        try:
            pid=int(child.stdout.readline())
            start=subprocess.check_output(['/bin/ps','-p',str(pid),'-o','lstart='],text=True).strip()
            child.communicate('exit\n',timeout=10); assert child.returncode==0
            return {'pid':pid,'pid_start':start}
        finally:
            if child.poll() is None: child.terminate(); child.wait(timeout=10)
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
                assert writer.wait(timeout=10)==0
                print('PASS real writer '+mode+' alive refuses; barrier '+actual,flush=True)
            finally:
                if writer.poll() is None: writer.terminate(); writer.wait(timeout=10)
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
            old.stdin.write('continue\n'); old.stdin.flush(); assert old.wait(timeout=10)==0
            result=land(extra={'LAND_RESOURCE_PROBE':'unknown'})
            assert '候选写入者资源探针未知' in result.stderr,result.stderr; retained()
            land(ok=True)
            d=read(t); assert not c.exists() and d['phase']=='verified' and d['land']['stage']=='closed'
            assert (tmp/'git.log').read_text().splitlines().count(head)==1
            assert len([e for e in d['events'] if e['kind']=='land-apply'])==1
            print('PASS old alive/missing proof refuse; actual exit same op closes without remerge',flush=True)
        finally:
            if old.poll() is None: old.terminate(); old.wait(timeout=10)
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
                child.communicate('exit\n',timeout=10); assert child.returncode==0
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
                if child.poll() is None: child.terminate(); child.wait(timeout=10)
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
