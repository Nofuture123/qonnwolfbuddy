#!/usr/bin/env bash
# Offline public-entry contract: real temporary Git/MD, fake Herdr CLI + Unix stream.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/process-fixture.sh"
qwb_test_scope "$@"
export TMPDIR="${QWB_TEST_SCOPE_DIR}"
mkdir -p "$TMPDIR" || exit 1
export GIT_CEILING_DIRECTORIES="$TMPDIR"
# Fail closed even if the PATH stub disappears.
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock
ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
# Explicit missing-writer proof: exercise both independent public guards and partial receipts.
if [[ "${1:-}" != finish-equivalence ]]; then
python3 -B - "$ROOT" <<'PY'
from process_fixture import TemporaryDirectory
from contextlib import ExitStack
import json, os, shutil, subprocess, sys
from pathlib import Path
ROOT=Path(sys.argv[1]).resolve()
prefix=(ROOT/'tests/worktree-space.py').read_text().split("with tempfile.TemporaryDirectory(prefix='s-')")[0]
exec(prefix.replace('ROOT = Path(__file__).resolve().parents[1]','ROOT = Path(sys.argv[1]).resolve()'))
UNKNOWN={'activity':'unknown','proof':'unverified','conflict':'native tool identity unknown'}
FLAG='--writer-proof-missing=人工核对旧启动代已退出'
proof_stub=STUB.replace('def out(result): print(json.dumps({"result": result}))', r'''def out(result):
    if 'pane' in result and behavior!='source' and 'QWB_AGENT_SHAPE' in os.environ:
        shape=os.environ['QWB_AGENT_SHAPE']
        if shape=='omitted': result['pane'].pop('agent',None)
        else: result['pane']['agent']=json.loads(shape)
    if 'pane' in result and behavior!='source':
        fault=os.environ.get('QWB_PANE_FAULT','')
        if fault=='id': result['pane']['pane_id']='foreign-pane'
        if fault=='object': result['pane']=[]
        if fault=='json': print('{'); return
        if fault=='error': print(json.dumps({'error':{'code':'io_error'},'result':result})); return
        if fault=='stderr': print('query warning',file=sys.stderr)
    print(json.dumps({'result':result}))''').replace('if args[:2] == ["status", "--json"]:', r'''target=os.environ.get('QWB_PROOF_PANE','wTask:p1')
behavior=os.environ.get('QWB_PROOF_BEHAVIOR','')
if args[:2]==['pane','get'] and args[2]==target and behavior=='source':
    out({'pane':dict(pane_id=target,workspace_id='wTask',tab_id='wTask:t2' if target=='wTask:p2' else 'wTask:t1',agent='new-tool',agent_status='idle',foreground_cwd=wt)})
elif args[:2]==['pane','process-info'] and args[3]==target and behavior in ('source','foreground'):
    pid=int(os.environ['QWB_PROOF_PID']); out({'process_info':dict(pane_id=target,shell_pid=42,foreground_process_group_id=pid,
         foreground_processes=[dict(pid=pid,argv0='python3',cwd=wt)])})
elif args[:2]==['pane','get'] and args[2]==target and behavior in ('query','absent'):
    err('pane_not_found' if behavior=='absent' else 'io_error')
elif args[:2]==['pane','get'] and args[2]==target and behavior=='agent':
    out({'pane':dict(pane_id=target,workspace_id='wTask',tab_id='wTask:t1',agent='pi',agent_status='idle',foreground_cwd=wt)})
elif args[:2]==['api','snapshot'] and mode=='proof-root-missing' and wt:
    out({'snapshot':dict(workspaces=[dict(workspace_id='wRoot'),dict(workspace_id='wTask')],tabs=[dict(tab_id='wTask:t2',workspace_id='wTask')],
        panes=[dict(pane_id='wRoot:p1',workspace_id='wRoot',tab_id='wRoot:t1'),dict(pane_id='wTask:p2',workspace_id='wTask',tab_id='wTask:t2')],
        focused_workspace_id='wRoot',focused_tab_id='wRoot:t1',focused_pane_id='wRoot:p1')})
elif args[:2]==['tab','list'] and mode=='proof-root-missing': out({'tabs':[dict(tab_id='wTask:t2')]})
elif args[:2]==['pane','list'] and mode=='proof-root-missing': out({'panes':[dict(pane_id='wTask:p2',agent_status='idle')]})
elif args[:2] == ["status", "--json"]:''')
for mode in ['merged','archive','absent','both-markers','agent','foreground','query','resource','known-live','later-live',
             'json','duplicate-json','string-pid','conflict','pid-null','not-probe','orphan','remove-partial','branch-partial','both-partial','missing-close-mark','misuse',
             'omitted','empty-agent','number-agent','array-agent','object-agent','bool-agent','digit-string-agent','process-query',
             'pane-id','pane-object','pane-json','pane-error','pane-stderr']:
    with TemporaryDirectory(prefix='proof-') as d, ExitStack() as processes:
        os.environ['TMPDIR']=d; b=Path(d)
        repo,ticket,state,log,env=project(b); wt=repo/'.worktrees/case'
        assert call('git','-C',str(repo),'worktree','add','-qb','case',str(wt),env=env).returncode==0
        state.write_text(str(wt)); log.write_text('')
        def child_at(directory):
            child=subprocess.Popen([sys.executable,'-u','-c','import sys; print("ready",flush=True); sys.stdin.readline()'],
                                   cwd=directory,stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
            processes.callback(lambda owned=child: (owned.terminate() if owned.poll() is None else None, owned.wait(timeout=10), owned.stdin.close(), owned.stdout.close()))
            assert child.stdout.readline().strip()=='ready'; return child
        original=child_at(wt)
        pid_start=call('/bin/ps','-p',str(original.pid),'-o','lstart=',env=env).stdout.strip(); assert pid_start
        pane='wTask:p2' if mode in ('both-markers','both-partial') else 'wGone:p9' if mode=='absent' else 'wTask:p1'
        (b/'stub/herdr').write_text(proof_stub)
        env=env|{'QWB_PROOF_PANE':pane,'QWB_PROOF_PID':str(original.pid)}
        observed=call('bash',str(ROOT/'bin/qwb-herdr.sh'),'activity','--project',str(repo),'--pane',pane,'--dir',str(wt),env=env|{'QWB_PROOF_BEHAVIOR':'source'})
        assert observed.returncode==0 and json.loads(observed.stdout)==UNKNOWN,observed.stdout
        original.communicate('exit\n',timeout=10); assert original.returncode==0
        raw=json.dumps(UNKNOWN); extra=''
        if mode=='json': raw='{'
        if mode=='duplicate-json': raw='{'+'"activity":"unknown",'+json.dumps(UNKNOWN)[1:]
        if mode=='string-pid': raw=json.dumps(dict(pid=str(original.pid),pid_start=pid_start))
        if mode=='pid-null': raw=json.dumps(dict(UNKNOWN,pid=None))
        if mode=='not-probe': raw=json.dumps({'activity':'unknown'})
        if mode=='conflict': extra='working: worker-activity op=unknown pane='+pane+' evidence='+json.dumps(dict(UNKNOWN,conflict='different unknown'))+'\n'
        if mode in ('known-live','later-live'):
            live=child_at(b); start=call('/bin/ps','-p',str(live.pid),'-o','lstart=',env=env).stdout.strip()
            live_pane=pane if mode=='later-live' else 'wGone:p8'
            extra+=f'dispatch: op_id=later worker=pi pane={live_pane} dir={wt}\nworking: worker-activity op=later pane={live_pane} evidence='+json.dumps(dict(pid=live.pid,pid_start=start))+'\n'
        if mode=='resource': child_at(wt)
        shapes={'omitted':'omitted','empty-agent':'""','number-agent':'42','array-agent':'[]',
                'object-agent':'{}','bool-agent':'false','digit-string-agent':'"1pi"'}
        if mode in shapes: env=env|{'QWB_AGENT_SHAPE':shapes[mode]}
        if mode.startswith('pane-'):env=env|{'QWB_AGENT_SHAPE':'omitted','QWB_PANE_FAULT':mode[5:]}
        if mode=='process-query':
            (b/'stub/herdr').write_text(proof_stub.replace('elif args[:2] == ["pane", "process-info"]:',
                                                        'elif args[:2] == ["pane", "process-info"]: err("io_error")\nelif False:'))
            env=env|{'QWB_AGENT_SHAPE':'omitted'}
        if mode in ('agent','foreground'):
            live=child_at(b); env=env|{'QWB_PROOF_PID':str(live.pid)}
        if mode in ('agent','foreground','query','absent'): env=env|{'QWB_PROOF_BEHAVIOR':mode}
        if mode=='foreground': env=env|{'QWB_AGENT_SHAPE':'omitted'}
        if mode in ('both-markers','both-partial'): env=env|{'QWB_TEST_MODE':'proof-root-missing'}
        text=f'state: verified\nworktree-space: id=wTask root-tab=wTask:t1 path={wt}\n'
        if mode!='orphan': text+=f'dispatch: op_id=unknown worker=pi pane={pane} dir={wt}\n'
        text+=f'working: worker-activity op=unknown pane={pane} evidence={raw}\n'+extra
        ticket.write_text(text); before=ticket.read_bytes(); refs=call('git','-C',str(repo),'show-ref',env=env).stdout
        baseline=b/'baseline-bin'; shutil.copytree(ROOT/'bin',baseline)
        for name in ['qwb-worktree.sh','qwb-herdr.sh']:
            (baseline/name).write_bytes(subprocess.check_output(['git','-C',str(ROOT),'show','6f3a8cc:bin/'+name]))
        finish=['finish','case','--merged','--project',str(repo)]
        current=call('bash',str(ROOT/'bin/qwb-worktree.sh'),*finish,env=env)
        old=call('bash',str(baseline/'qwb-worktree.sh'),*finish,env=env)
        if mode=='resource':
            lines=current.stderr.splitlines(); assert len(lines)==2 and lines[1].startswith('提示：'),current.stderr
            assert lines[0]+'\n'==old.stderr and current.stdout==old.stdout and current.returncode==old.returncode
        else:
            assert (current.returncode,current.stdout,current.stderr)==(old.returncode,old.stdout,old.stderr),(mode,current.stdout,current.stderr,old.stdout,old.stderr)
        assert current.returncode!=0 and ticket.read_bytes()==before and wt.is_dir() and state.exists()
        if mode=='misuse':
            for args in [['list',FLAG],finish+['--writer-proof-missing'],finish+['--writer-proof-missing='],['land','case',FLAG]]:
                wrong=call('bash',str(ROOT/'bin/qwb-worktree.sh'),*args,'--project',str(repo),env=env)
                assert wrong.returncode==2 and ticket.read_bytes()==before and wt.is_dir() and state.exists(),(args,wrong.stderr)
            plain=call('bash',str(ROOT/'bin/qwb-worktree.sh'),'finish','case','--keep=待裁决','--project',str(repo),env=env)
            plain_ticket=ticket.read_bytes(); ticket.write_bytes(before)
            keep=call('bash',str(ROOT/'bin/qwb-worktree.sh'),'finish','case','--keep=待裁决',FLAG,'--project',str(repo),env=env)
            assert (keep.returncode,keep.stdout,keep.stderr,ticket.read_bytes())==(plain.returncode,plain.stdout,plain.stderr,plain_ticket)
            assert 'writer-proof-missing' not in ticket.read_text()
            print('PASS writer-proof misuse: missing/empty/list/land reject; keep bytes identical',flush=True); continue
        close=['close','--project',str(repo),'--task',str(ticket),'--space','wTask']
        lower=call('bash',str(ROOT/'bin/qwb-herdr.sh'),*close,env=env)
        if mode=='absent':
            assert lower.returncode==0 and not state.exists() and ticket.read_bytes()==before
            state.write_text(str(wt))
            old_lower=call('bash',str(baseline/'qwb-herdr.sh'),*close,env=env)
            assert (lower.returncode,lower.stdout,lower.stderr)==(old_lower.returncode,old_lower.stdout,old_lower.stderr)
            state.write_text(str(wt))
        else: assert lower.returncode!=0 and state.exists() and ticket.read_bytes()==before
        positive=mode in ('merged','archive','absent','both-markers','remove-partial','branch-partial','both-partial','missing-close-mark','omitted')
        lower=call('bash',str(ROOT/'bin/qwb-herdr.sh'),*close,FLAG,env=env)
        print('WRITER-PROOF close',mode,'rc=',lower.returncode,'stdout=',repr(lower.stdout),'stderr=',repr(lower.stderr),flush=True)
        if positive:
            assert lower.returncode==0 and not state.exists(),(mode,lower.stdout,lower.stderr)
            state.write_text(str(wt))
        else:
            assert lower.returncode!=0 and state.exists() and ticket.read_bytes()==before,(mode,lower.stdout,lower.stderr)
            if mode.startswith('pane-'): assert '身份未知' in lower.stderr,lower.stderr
            if mode in shapes and mode!='omitted':
                assert ('仍有agent' if mode=='digit-string-agent' else '身份未知') in lower.stderr,lower.stderr
        if mode=='missing-close-mark':
            mutant=b/'mutant-bin'; shutil.copytree(ROOT/'bin',mutant)
            source=(mutant/'qwb-worktree.sh').read_text()
            line='  [[ "$WRITER_PROOF_MISSING_APPLIED" -eq 0 ]] || argv+=("--writer-proof-missing=$WRITER_PROOF_MISSING")'
            assert source.count(line)==1; (mutant/'qwb-worktree.sh').write_text(source.replace(line,'  : # fixture mutation: omit the close marker'))
            bad=call('bash',str(mutant/'qwb-worktree.sh'),*finish,FLAG,env=env)
            assert bad.returncode!=0 and 'old launch PID/start unknown' in bad.stderr and wt.is_dir() and state.exists() and ticket.read_bytes()==before,bad.stderr
            print('PASS writer-proof missing close marker mutation: upper guard passes, lower still refuses',flush=True); continue
        if mode in ('remove-partial','branch-partial','both-partial'):
            target='update-ref -d' if mode=='branch-partial' else 'worktree remove'
            (b/'stub/git').write_text('#!/usr/bin/env bash\nif [[ "$*" == *"'+target+'"* && ! -e "$QWB_PROOF_FAIL" ]]; then touch "$QWB_PROOF_FAIL"; exit 9; fi\nexec "$QWB_REAL_GIT" "$@"\n')
            (b/'stub/git').chmod(0o755); env=env|{'QWB_REAL_GIT':shutil.which('git'),'QWB_PROOF_FAIL':str(b/'git-failed')}
        actions=['--archive'] if mode=='archive' else ['--merged','--archive'] if not positive else ['--merged']
        for action in actions:
            cmd=['bash',str(ROOT/'bin/qwb-worktree.sh'),'finish','case',action,FLAG,'--project',str(repo)]
            if mode in ('both-markers','both-partial'): cmd+=['--root-tab-missing']
            got=call(*cmd,env=env)
            print('WRITER-PROOF finish',mode,action,'rc=',got.returncode,'stdout=',repr(got.stdout),'stderr=',repr(got.stderr),flush=True)
            if mode in ('remove-partial','branch-partial','both-partial'):
                assert got.returncode!=0 and 'writer-proof-missing=1' in ticket.read_text() and 'worktree: partial' in ticket.read_text(),got.stderr
                assert 'working: writer-proof-missing op=unknown pane='+pane in ticket.read_text()
                recovery=next(x.split('恢复命令：',1)[1].strip() for x in got.stderr.splitlines() if x.startswith('恢复命令：'))
                assert '--writer-proof-missing=' in recovery,recovery
                got=call('bash','-c',recovery,env=env)
                assert got.returncode==0,(got.stdout,got.stderr)
                print('PASS writer-proof '+mode+': conditional recovery retains marker and reason',flush=True)
            elif positive:
                assert got.returncode==0,(mode,got.stdout,got.stderr)
            else:
                assert got.returncode!=0 and ticket.read_bytes()==before and wt.is_dir() and state.exists(),(mode,got.stdout,got.stderr)
                assert call('git','-C',str(repo),'show-ref',env=env).stdout==refs
                if mode in ('json','duplicate-json','string-pid','conflict','pid-null','not-probe','orphan'): assert got.stderr==current.stderr,(mode,got.stderr,current.stderr)
                if mode.startswith('pane-'): assert '身份未知' in got.stderr,got.stderr
                if mode in shapes and mode!='omitted':
                    assert ('仍有agent' if mode=='digit-string-agent' else '身份未知') in got.stderr,got.stderr
                if mode=='resource': assert '候选写入者仍持cwd/FD' in got.stderr,got.stderr
                if mode in ('known-live','later-live'): assert '旧启动代仍活或死亡未知' in got.stderr,got.stderr
        if positive:
            assert not wt.exists() and not state.exists() and call('git','-C',str(repo),'show-ref','--verify','--quiet','refs/heads/case',env=env).returncode!=0
            final=next(x for x in reversed(ticket.read_text().splitlines()) if x.startswith('worktree:'))
            assert final.endswith('writer-proof-missing=1'),final
            notes=[x for x in ticket.read_text().splitlines() if x.startswith('working: writer-proof-missing ')]
            assert notes and 'op=unknown pane='+pane in notes[0] and '人工核对旧启动代已退出' in notes[0] and 'lsof-clean' in notes[0] and 'none' in notes[0],notes
            if mode in ('both-markers','both-partial'): assert 'root-tab-missing=1 writer-proof-missing=1' in final,final
        print('PASS writer-proof '+mode+': '+('explicit proof closes and records' if positive else 'both guards refuse without side effects'),flush=True)
PY
fi
# Default byte contract: identical private paths, Git snapshot, subprocess identities and external logs.
python3 -B - "$ROOT" <<'PY'
from process_fixture import TemporaryDirectory
from contextlib import ExitStack
import json, os, shutil, subprocess, sys
from pathlib import Path
ROOT=Path(sys.argv[1]).resolve()
prefix=(ROOT/'tests/worktree-space.py').read_text().split("with tempfile.TemporaryDirectory(prefix='s-')")[0]
exec(prefix.replace('ROOT = Path(__file__).resolve().parents[1]','ROOT = Path(sys.argv[1]).resolve()'))
# Reuse the explicit suite's native boundary for the existing root-tab-missing condition.
UNKNOWN={'activity':'unknown','proof':'unverified','conflict':'native tool identity unknown'}
FLAG='--writer-proof-missing=人工核对旧启动代已退出'
text=(ROOT/'tests/collab-herdr.sh').read_text()
probe=text.split('proof_stub=STUB.replace(',1)[1].split("for mode in ['merged'",1)[0]
exec('proof_stub=STUB.replace('+probe)
for mode in ['normal','archive','alive','busy','query','close','root-tab','missing-proof','remove-partial','branch-partial','resource','no-pane-resource','many-resource']:
    with TemporaryDirectory(prefix='bytes-') as d, ExitStack() as processes:
        os.environ['TMPDIR']=d; b=Path(d)
        repo,ticket,state,log,env=project(b); wt=repo/'.worktrees/case'
        assert call('git','-C',str(repo),'worktree','add','-qb','case',str(wt),env=env).returncode==0
        child=subprocess.Popen([sys.executable,'-u','-c','import sys; print("ready",flush=True); sys.stdin.readline()'],
                               cwd=b,stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
        processes.callback(lambda: (child.terminate() if child.poll() is None else None, child.wait(timeout=10), child.stdin.close(), child.stdout.close()))
        assert child.stdout.readline().strip()=='ready'
        start=call('/bin/ps','-p',str(child.pid),'-o','lstart=',env=env).stdout.strip(); assert start
        if mode!='alive': child.communicate('exit\n',timeout=10); assert child.returncode==0
        pane='wTask:p2' if mode=='root-tab' else 'wTask:p1'
        ticket.write_text(f'state: verified\nworktree-space: id=wTask root-tab=wTask:t1 path={wt}\n'+
                          f'dispatch: op_id=bound worker=pi pane={pane} dir={wt}\nworking: worker-activity op=bound pane={pane} evidence='+
                          json.dumps(dict(pid=child.pid,pid_start=start))+'\n')
        resource_children=[]
        if mode in ('resource','no-pane-resource','many-resource'):
            for _ in range(6 if mode=='many-resource' else 1):
                owned=subprocess.Popen([sys.executable,'-u','-c','import sys; print("ready",flush=True); sys.stdin.readline()'],
                                       cwd=wt,stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
                processes.callback(lambda owned=owned: (owned.terminate() if owned.poll() is None else None, owned.wait(timeout=10), owned.stdin.close(), owned.stdout.close()))
                assert owned.stdout.readline().strip()=='ready'; resource_children.append(owned)
        if mode=='no-pane-resource': ticket.write_text('state: verified\n')
        if mode=='many-resource':
            ticket.write_text(ticket.read_text()+f'dispatch: op_id=second worker=pi pane=wTask:p2 dir={wt}\n')
        if mode=='missing-proof':
            ticket.write_text(ticket.read_text().split('working: worker-activity',1)[0]+
                              'working: worker-activity op=bound pane='+pane+' evidence='+json.dumps(UNKNOWN)+'\n')
        state.write_text(str(wt)); log.write_text('')
        if mode in ('root-tab','missing-proof'): (b/'stub/herdr').write_text(proof_stub)
        if mode=='root-tab': env=env|{'QWB_TEST_MODE':'proof-root-missing'}
        if mode in ('busy','query','close'): env=env|{'QWB_TEST_MODE':{'busy':'busy','query':'query-fail','close':'close-fail'}[mode]}
        real_git=shutil.which('git'); gitlog=b/'git-calls'; failed=b/'git-failed'
        target='worktree remove' if mode=='remove-partial' else 'update-ref -d' if mode=='branch-partial' else ''
        (b/'stub/git').write_text('#!/usr/bin/env python3\nimport json,os,subprocess,sys\nfrom pathlib import Path\na=sys.argv[1:]\nwith open(os.environ["QWB_BYTES_GIT_LOG"],"a") as f: f.write(json.dumps(a)+"\\n")\nif os.environ["QWB_BYTES_TARGET"] and os.environ["QWB_BYTES_TARGET"] in " ".join(a) and not Path(os.environ["QWB_BYTES_FAILED"]).exists():\n Path(os.environ["QWB_BYTES_FAILED"]).touch(); sys.exit(9)\nsys.exit(subprocess.run([os.environ["QWB_REAL_GIT"],*a]).returncode)\n')
        (b/'stub/git').chmod(0o755)
        env=env|{'QWB_REAL_GIT':real_git,'QWB_BYTES_GIT_LOG':str(gitlog),'QWB_BYTES_TARGET':target,'QWB_BYTES_FAILED':str(failed)}
        runtime=b/'runtime-bin'; shutil.copytree(ROOT/'bin',runtime)
        old={name:subprocess.check_output(['git','-C',str(ROOT),'show','d3e4b49:bin/'+name]) for name in ['qwb-worktree.sh','qwb-herdr.sh']}
        new={name:(ROOT/'bin'/name).read_bytes() for name in old}
        snapshot=b/'snapshot'; shutil.copytree(repo,snapshot)
        results=[]
        versions=[(old,'null'),(new,'null')]
        if mode in ('normal','missing-proof'): versions.append((new,'omitted'))
        for version,shape in versions:
            env=env|{'QWB_AGENT_SHAPE':shape}
            if mode=='normal': (b/'stub/herdr').write_text(proof_stub)
            if len(results) and not resource_children: shutil.rmtree(repo); shutil.copytree(snapshot,repo)
            for name,data in version.items(): (runtime/name).write_bytes(data)
            state.write_text(str(wt)); log.write_text(''); gitlog.write_text(''); failed.unlink(missing_ok=True)
            command=['bash',str(runtime/'qwb-worktree.sh'),'finish','case','--archive' if mode in ('archive','remove-partial','branch-partial') else '--merged','--project',str(repo)]
            if mode=='root-tab': command+=['--root-tab-missing']
            if mode=='missing-proof': command+=[FLAG]
            first=call(*command,env=env)
            if resource_children and version is new:
                lines=first.stderr.splitlines()
                assert lines[0]=='拒绝：候选写入者仍持cwd/FD，保留成果' and len(lines)==2 and lines[1].startswith('提示：'),lines
                reported=__import__('re').findall(r'(\d+)\(([^)]+)\)',lines[1])
                assert len(reported)==min(5,len(resource_children)),reported
                assert {int(pid) for pid,_ in reported}.issubset({c.pid for c in resource_children}),reported
                assert all(name.startswith('Python') or name.startswith('python') for _,name in reported),reported
                assert all(c.poll() is None for c in resource_children)
                if mode=='no-pane-resource':
                    assert 'herdr pane close' not in lines[1] and '让这些进程退出或离开副本目录后重试' in lines[1]
                else:
                    assert 'herdr pane close wTask:p1' in lines[1] and '确认工人已交付' in lines[1]
                    if mode=='many-resource': assert '等 6 个' in lines[1] and 'herdr pane close wTask:p2' in lines[1]
                print('PASS refusal hint '+mode+': real PID(command), exact first line, registered panes, no side effects',flush=True)
            stderr=first.stderr.split('提示：',1)[0] if resource_children else first.stderr
            runs=[(first.returncode,first.stdout,stderr)]
            if mode in ('remove-partial','branch-partial'):
                assert first.returncode!=0 and 'worktree: partial' in ticket.read_text()
                second=call(*command,env=env); assert second.returncode==0,(mode,second.stdout,second.stderr)
                runs.append((second.returncode,second.stdout,second.stderr))
            else: assert (first.returncode==0)==(mode in ('normal','archive','root-tab','missing-proof')),(mode,first.stdout,first.stderr)
            result=dict(runs=runs,ticket=ticket.read_bytes().hex(),git_log=gitlog.read_text(),herdr_log=log.read_text(),
                        refs=call(real_git,'-C',str(repo),'show-ref',env=env).stdout,worktree_exists=wt.exists(),space_exists=state.exists(),
                        git_status=call(real_git,'-C',str(repo),'status','--short',env=env).stdout)
            results.append(result)
        assert all(result==results[0] for result in results[1:]),(mode,results)
        print('PASS finish d3e4b49 byte equivalence '+mode+': stdout/stderr/rc/ticket/git/herdr/refs/layout identical; only resource hint excluded',flush=True)
PY
if [[ "${1:-}" == writer-proof-missing || "${1:-}" == writer-proof-equivalence || "${1:-}" == finish-equivalence ]]; then exit 0; fi

# Multiple tool processes bind only their matching foreground group leader.
python3 -B - "$ROOT" <<'PY'
from process_fixture import TemporaryDirectory
from contextlib import ExitStack
import json, os, shutil, subprocess, sys
from pathlib import Path
ROOT=Path(sys.argv[1]).resolve()
prefix=(ROOT/'tests/worktree-space.py').read_text().split("with tempfile.TemporaryDirectory(prefix='s-')")[0]
exec(prefix.replace('ROOT = Path(__file__).resolve().parents[1]','ROOT = Path(sys.argv[1]).resolve()'))
with TemporaryDirectory(prefix='s-') as d, ExitStack() as processes:
    os.environ['TMPDIR']=d
    b=Path(d); repo,ticket,state,log,env=project(b); wt=repo/'.worktrees/case'
    assert call('git','-C',str(repo),'worktree','add','-qb','case',str(wt),env=env).returncode==0
    state.write_text(str(wt))
    children=[]
    for _ in range(3):
        child=subprocess.Popen([sys.executable,'-u','-c','import sys; print("ready",flush=True); sys.stdin.readline()'],
                               cwd=wt,stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
        processes.callback(lambda owned=child: (owned.terminate() if owned.poll() is None else None, owned.wait(timeout=10), owned.stdin.close(), owned.stdout.close()))
        assert child.stdout.readline().strip()=='ready'; children.append(child)
    leader,other,foreign=children
    stamp=call('/bin/ps','-p',str(leader.pid),'-o','lstart=',env=env).stdout.strip(); assert stamp
    active=b/'native-active'; shape=b/'native-shape.json'; session=b/'pi.jsonl'
    session.write_text(json.dumps(dict(type='session',cwd=str(wt)))+'\n'+json.dumps(dict(type='message',id='end',message=dict(role='assistant',content=[],stopReason='stop')))+'\n')
    native_stub=STUB.replace('if args[:2] == ["status", "--json"]:', r'''active=Path(os.environ['QWB_TEST_NATIVE_ACTIVE'])
shape=json.loads(Path(os.environ['QWB_TEST_NATIVE_SHAPE']).read_text())
if args[:2]==['agent','start']:
    active.write_text('started'); out({'type':'agent_started'})
elif args[:2]==['agent','get'] and active.exists():
    out({'agent':dict(name='qwb-case',agent=shape['tool'],agent_status='idle',pane_id='wTask:p1',workspace_id='wTask',cwd=wt)})
elif args[:2]==['pane','get'] and args[2]=='wTask:p1' and active.exists():
    out({'pane':dict(pane_id='wTask:p1',tab_id='wTask:t1',workspace_id='wTask',agent=shape['tool'],agent_status='idle',foreground_cwd=wt,
                    agent_session=dict(source='herdr:pi',kind='path',value=os.environ['QWB_TEST_NATIVE_SESSION']))})
elif args[:2]==['pane','process-info'] and args[3]=='wTask:p1' and active.exists():
    out({'process_info':dict(pane_id='wTask:p1',shell_pid=42,foreground_process_group_id=shape['group'],foreground_processes=shape['rows'])})
elif args[:2]==['agent','prompt']:
    with log.open('a') as f: f.write(json.dumps(['prompt-ticket',Path(os.environ['QWB_TEST_NATIVE_TICKET']).read_text()])+'\n')
    out({'type':'ok'})
elif args[:2] == ["status", "--json"]:''')
    (b/'stub/herdr').write_text(native_stub)
    env=env|{'QWB_TEST_NATIVE_ACTIVE':str(active),'QWB_TEST_NATIVE_SHAPE':str(shape),'QWB_TEST_NATIVE_SESSION':str(session),'QWB_TEST_NATIVE_TICKET':str(ticket)}
    baseline=b/'baseline-bin'; baseline.mkdir()
    (baseline/'qwb-herdr.sh').write_bytes(subprocess.check_output(['git','-C',str(ROOT),'show','ded7d88:bin/qwb-herdr.sh']))
    shutil.copy(ROOT/'bin/qwb-lib.sh',baseline/'qwb-lib.sh')
    selected=baseline/'qwb-herdr.sh' if os.environ.get('QWB_NATIVE_HERDR_BASELINE') else ROOT/'bin/qwb-herdr.sh'
    def row(pid,name): return dict(pid=pid,argv0=name,cwd=str(wt))
    devin=dict(tool='devin',group=leader.pid,rows=[row(other.pid,'devin'),row(leader.pid,'devin')])
    shapes=[('devin',devin),('pi',dict(tool='pi',group=leader.pid,rows=[row(leader.pid,'pi')])),
            ('claude',dict(tool='claude',group=leader.pid,rows=[row(leader.pid,'claude'),row(other.pid,'caffeinate')])),
            ('no-matching-leader',dict(devin,group=foreign.pid)),
            ('no-tool-name',dict(tool='devin',group=leader.pid,rows=[row(leader.pid,'caffeinate')]))]
    active.write_text('started')
    for mode,data in shapes:
        shape.write_text(json.dumps(data))
        args=['activity','--project',str(repo),'--pane','wTask:p1','--dir',str(wt)]
        got=call('bash',str(selected),*args,env=env); assert got.returncode==0,got.stderr
        proof=json.loads(got.stdout)
        old=call('bash',str(baseline/'qwb-herdr.sh'),*args,env=env)
        print('NATIVE-SHAPE',mode,'baseline=',old.stdout.strip(),'current=',got.stdout.strip(),flush=True)
        if mode in ('no-matching-leader','no-tool-name'):
            assert proof['activity']=='unknown' and 'pid' not in proof and proof['conflict']=='native tool identity unknown',proof
        else:
            assert proof['pid']==leader.pid and proof['pid_start']==stamp,proof
            if mode=='devin': assert 'pid' not in json.loads(old.stdout) and json.loads(old.stdout)['activity']=='unknown'
            else: assert (got.returncode,got.stdout,got.stderr)==(old.returncode,old.stdout,old.stderr),'single-name behavior changed'
        print('PASS native shape '+mode,flush=True)
    # Fresh real qwb-run binds the leader before prompt; two live children keep finish closed.
    shape.write_text(json.dumps(devin)); active.unlink(); state.unlink(); log.write_text('')
    (repo/'qwbuddy/config.sh').write_text("QWB_WORKERS='devin'\nQWB_WORKSPACE=''\n")
    (repo/'qwbuddy/workers.sh').write_text('qwb_worker devin herdr devin\n')
    dispatch=call('bash',str(repo/'qwbuddy/bin/qwb-run.sh'),'--project',str(repo),'--task','case','--worker','devin',env=env)
    assert dispatch.returncode==0,(dispatch.stdout,dispatch.stderr)
    lines=ticket.read_text().splitlines(); receipt=next(x for x in reversed(lines) if x.startswith('dispatch:'))
    op=next(x.split('=',1)[1] for x in receipt.split() if x.startswith('op_id='))
    bound=next(x for x in lines if x.startswith('working: worker-activity op='+op+' pane=wTask:p1 evidence='))
    proof=json.loads(bound.split(' evidence=',1)[1]); assert (proof['pid'],proof['pid_start'])==(leader.pid,stamp),proof
    prompted=json.loads(log.read_text().splitlines()[-1]); assert prompted[0]=='prompt-ticket' and bound in prompted[1],prompted
    active.unlink()
    finish=['bash',str(ROOT/'bin/qwb-worktree.sh'),'finish','case','--merged','--project',str(repo)]
    alive=call(*finish,env=env); assert alive.returncode!=0 and wt.is_dir() and state.exists() and '候选写入者仍持cwd/FD' in alive.stderr,alive.stderr
    for child in children: child.communicate('exit\n',timeout=10); assert child.returncode==0
    ended=call(*finish,env=env)
    print('NATIVE-E2E dispatch_rc=',dispatch.returncode,'leader_pid=',leader.pid,'pid_start=',stamp,'alive_rc=',alive.returncode,'ended_rc=',ended.returncode,'stdout=',repr(ended.stdout),'stderr=',repr(ended.stderr),flush=True)
    assert ended.returncode==0 and not wt.exists() and not state.exists(),(ended.stdout,ended.stderr)
    assert call('git','-C',str(repo),'show-ref','--verify','--quiet','refs/heads/case',env=env).returncode!=0
    print('PASS devin public dispatch records leader before prompt; actual exit permits merged finish',flush=True)
PY
if [[ "${1:-}" == activity-native ]]; then exit 0; fi
# The focused mode also runs in full: real PID/start evidence through both public close paths.
python3 -B - "$ROOT" <<'PY'
from process_fixture import TemporaryDirectory
import json, os, shutil, subprocess, sys
from pathlib import Path
ROOT=Path(sys.argv[1]).resolve()
source=(ROOT/'tests/worktree-space.py').read_text()
prefix=source.split("with tempfile.TemporaryDirectory(prefix='s-')")[0]
exec(prefix.replace('ROOT = Path(__file__).resolve().parents[1]','ROOT = Path(sys.argv[1]).resolve()'))
BASE='ded7d889ff3fef9c7b9fe142612177c4bedff011'
# Faults wrap only this test interpreter's subprocess.run, never the system ps file.
fault_runner=r'''
import os, subprocess, sys
from pathlib import Path
from unittest.mock import patch
script, fault, marker, *args=sys.argv[1:]
text=Path(script).read_text()
if script.endswith('qwb-herdr.sh'):
    code=text.split("<<'PY'\n",1)[1].rsplit('\nPY',1)[0]
    os.environ['QWB_HERDR_BINDIR']=str(Path(script).parent)
else:
    code=text.split('\nwriters_stopped() {',1)[1].split("<<'PY'\n",1)[1].split('\nPY',1)[0]
sys.argv=[script,*args]; real_run=subprocess.run
calls=[]
def run(argv,**kw):
    if argv[0] not in ('ps','/bin/ps'): return real_run(argv,**kw)
    assert argv[0]=='/bin/ps' and kw['timeout']==2,argv
    calls.append(argv); Path(marker).write_text(repr(calls))
    if fault=='timeout': raise subprocess.TimeoutExpired(argv,2)
    rc,out,err={
        'stderr-dead':(1,'','probe failed'),
        'stderr-reused':(0,'different start','probe failed'),
        'status-3':(3,'',''),
        'empty-live':(0,'',''),
        'output-dead':(1,'unexpected output',''),
    }[fault]
    return subprocess.CompletedProcess(argv,rc,out,err)
with patch('subprocess.run',side_effect=run): exec(compile(code,script,'exec'),{'__name__':'__main__'})
'''
for mode in ['dead','live','reused','invalid','missing','fake-ps','boolean']:
    with TemporaryDirectory(prefix='s-') as d:
        os.environ['TMPDIR']=d
        b=Path(d); repo,ticket,state,log,env=project(b); wt=repo/'.worktrees/case'
        assert call('git','-C',str(repo),'worktree','add','-qb','case',str(wt),env=env).returncode==0
        child=subprocess.Popen([sys.executable,'-u','-c','import sys; print("ready",flush=True); sys.stdin.readline()'],
                               cwd=b,stdin=subprocess.PIPE,stdout=subprocess.PIPE,text=True)
        try:
            assert child.stdout.readline().strip()=='ready'
            stamp=call('/bin/ps','-p',str(child.pid),'-o','lstart=',env=env)
            assert stamp.returncode==0 and stamp.stdout.strip() and not stamp.stderr
            evidence=dict(pid=child.pid,pid_start=stamp.stdout.strip())
            if mode=='dead': child.communicate('exit\n',timeout=10); assert child.returncode==0
            if mode=='reused': evidence['pid_start']='recorded older incarnation'
            if mode=='invalid': evidence['pid']=-1
            if mode=='missing': evidence.pop('pid_start')
            if mode=='boolean': evidence['pid']=True
            if mode=='fake-ps':
                fake=b/'stub/ps'; fake.write_text('#!/bin/sh\nexit 1\n'); fake.chmod(0o755)
            text=f'state: verified\nworktree-space: id=wTask root-tab=wTask:t1 path={wt}\n'
            text+=f'dispatch: now op_id=launch worker=pi pane=wTask:p1 dir={wt}\n'
            text+='working: worker-activity op=launch pane=wTask:p1 evidence='+json.dumps(evidence)+'\n'
            ticket.write_text(text); before=ticket.read_bytes()
            refs=call('git','-C',str(repo),'show-ref',env=env).stdout
            baseline=b/'baseline-bin'; baseline.mkdir()
            (baseline/'qwb-herdr.sh').write_bytes(subprocess.check_output(['git','-C',str(ROOT),'show',BASE+':bin/qwb-herdr.sh']))
            shutil.copy(ROOT/'bin/qwb-lib.sh',baseline/'qwb-lib.sh')
            selected=ROOT/'bin/qwb-herdr.sh'
            if os.environ.get('QWB_DEATH_HERDR_REV'):
                selected=baseline/'qwb-herdr.sh'
            args=['close','--project',str(repo),'--task',str(ticket),'--space','wTask']
            def close(script):
                state.write_text(str(wt)); log.write_text('')
                return call('bash',str(script),*args,env=env)
            old=close(baseline/'qwb-herdr.sh') if mode in ('dead','fake-ps') else None
            got=close(selected); expected=mode in ('dead','reused')
            print('DEATH-PROOF',mode,'herdr_rc=',got.returncode,'stdout=',repr(got.stdout),'stderr=',repr(got.stderr),flush=True)
            if mode=='dead':
                assert (got.returncode,got.stdout,got.stderr)==(old.returncode,old.stdout,old.stderr),'normal close changed bytes'
            if mode=='fake-ps':
                assert old.returncode==0
                print('BASELINE fake-ps herdr_rc=',old.returncode,'stdout=',repr(old.stdout),'stderr=',repr(old.stderr),flush=True)
            assert ticket.read_bytes()==before and wt.is_dir() and call('git','-C',str(repo),'show-ref',env=env).stdout==refs
            preserved=state.exists() and not any(json.loads(x)==['workspace','close','wTask'] or isinstance(json.loads(x),dict) for x in log.read_text().splitlines())
            # Faults reach the same full close body; no system executable is substituted.
            if mode=='live':
                marker=b/'fault-calls'
                for fault in ['stderr-dead','stderr-reused','status-3','timeout','empty-live','output-dead']:
                    state.write_text(str(wt)); log.write_text(''); marker.unlink(missing_ok=True)
                    bad=call(sys.executable,'-B','-c',fault_runner,str(ROOT/'bin/qwb-herdr.sh'),fault,str(marker),*args,env=env)
                    assert marker.exists() and bad.returncode==1 and not bad.stdout,(fault,bad.stdout,bad.stderr)
                    assert bad.stderr=='Herdr refusal/unknown: old native PID still alive or death unknown\n',bad.stderr
                    assert state.exists() and ticket.read_bytes()==before and wt.is_dir()
                    assert not any(json.loads(x)==['workspace','close','wTask'] or isinstance(json.loads(x),dict) for x in log.read_text().splitlines())
                    marker.unlink()
                    other=call(sys.executable,'-B','-c',fault_runner,str(ROOT/'bin/qwb-worktree.sh'),fault,str(marker),str(ticket),str(wt),'',env=env)
                    assert marker.exists() and other.returncode==1,(fault,other.stdout,other.stderr)
                    print('PASS death-proof fault '+fault+': both reject; herdr stderr='+repr(bad.stderr),flush=True)
            state.write_text(str(wt)); log.write_text('')
            finished=call('bash',str(ROOT/'bin/qwb-worktree.sh'),'finish','case','--merged','--project',str(repo),env=env)
            print('DEATH-PROOF',mode,'worktree_rc=',finished.returncode,'stdout=',repr(finished.stdout),'stderr=',repr(finished.stderr),flush=True)
            assert (got.returncode==0)==(finished.returncode==0)==expected,(mode,got.stdout,got.stderr,finished.stdout,finished.stderr)
            if expected:
                assert not wt.exists() and not state.exists()
            else:
                assert preserved and wt.is_dir() and state.exists() and ticket.read_bytes()==before
                if mode in ('live','fake-ps'): assert got.stderr=='Herdr refusal/unknown: old native PID still alive or death unknown\n',got.stderr
                assert call('git','-C',str(repo),'show-ref',env=env).stdout==refs
                assert not any(json.loads(x)==['workspace','close','wTask'] for x in log.read_text().splitlines())
            if child.poll() is None: assert call('/bin/ps','-p',str(child.pid),'-o','lstart=',env=env).stdout.strip()==stamp.stdout.strip()
            print('PASS death-proof '+mode+': herdr/worktree agree '+('allow' if expected else 'refuse'),flush=True)
        finally:
            if child.poll() is None: child.terminate(); child.wait(timeout=10)
            child.stdin.close(); child.stdout.close()
PY
if [[ "${1:-}" == death-proof ]]; then exit 0; fi
if [[ "${1:-}" != not-sent ]]; then
python3 -B - "$ROOT" <<'PY'
from process_fixture import TemporaryDirectory, socket_path
import json, os, socket, subprocess, tempfile, threading, time
from pathlib import Path
ROOT=Path(__import__('sys').argv[1])
with TemporaryDirectory(prefix='s-') as tmp:
    os.environ["TMPDIR"] = tmp
    b=Path(tmp); p=b/'project'; p.mkdir(); (p/'tasks').mkdir(); (p/'qwbuddy').mkdir()
    subprocess.run(['git','init','-q',str(p)],check=True)
    (p/'qwbuddy/config.sh').write_text('QWB_REWAKE_MS=0\n')
    lock=p/'qwbuddy/.controller.lock'; lock.mkdir(); (lock/'owner').write_text('now ctl\n')
    for n in range(3):
        (p/f'tasks/{n}.md').write_text(f'state: running\ndispatch: 2099-01-0{n+1} pane=w:p{n} dir={p}\nworking: initial\n')
    roles=p/'qwbuddy/.roles'; roles.mkdir()
    (roles/'planner.json').write_text(json.dumps(dict(version=1,root=str(p.resolve()),phase='active',pane='w:role')))
    stub=b/'stub'; stub.mkdir(); sockpath=socket_path(); log=b/'calls'; requests=[]
    (stub/'herdr').write_text('''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
a=sys.argv[1:]
with open(os.environ['LOG'],'a') as f: f.write(json.dumps(a)+'\\n')
if a[:2]==['status','--json']: print(json.dumps({'server':{'socket':os.environ['SOCKET']}}))
elif a[:2]==['pane','get']: print(json.dumps({'result':{'pane':{'pane_id':a[2],'agent':'pi'}}}))
else: print(json.dumps({'result':{'type':'ok'}}))
'''); (stub/'herdr').chmod(0o755)
    env={**os.environ,'PATH':str(stub)+':'+os.environ['PATH'],'HERDR_PANE_ID':'ctl','LOG':str(log),'SOCKET':sockpath}
    wake=['bash',str(ROOT/'bin/qwb-wake.sh'),'--project',str(p),'--interval','15000']
    # Consume initial legacy facts through the same public entry, not fabricated fingerprints.
    prime=subprocess.run(wake+['--once','--pane','ctl'],env=env,capture_output=True,text=True)
    assert prime.returncode==0,prime.stderr
    server=socket.socket(socket.AF_UNIX); server.bind(sockpath); server.listen(); server.settimeout(20)
    ready=threading.Event(); errors=[]
    def emit():
        try:
            c,_=server.accept()
            with c:
                f=c.makefile('rb'); req=json.loads(f.readline()); requests.append(req)
                c.sendall((json.dumps({'id':req['id'],'result':{'type':'subscription_started'}})+'\n').encode())
                ready.set(); time.sleep(.15)
                with (p/'tasks/0.md').open('a') as t: t.write('done: older worker completed\n')
                c.sendall((json.dumps({'event':'pane.agent_status_changed','data':{'pane_id':'w:p0','workspace_id':'w','agent_status':'done'}})+'\n').encode())
                time.sleep(.2)
        except Exception as e: errors.append(str(e)); ready.set()
    thread=threading.Thread(target=emit,daemon=True); thread.start()
    start=time.monotonic()
    got=subprocess.run(wake+['--block','--max-ms','12000'],env=env,capture_output=True,text=True,timeout=20)
    latency=time.monotonic()-start
    server.close(); thread.join(timeout=20)
    assert got.returncode==2 and 'older worker completed' in got.stdout,(got.returncode,got.stdout,got.stderr)
    assert latency<10,('non-latest completion waited for polling interval',latency,got.stderr)
    assert requests and {s['pane_id'] for s in requests[0]['params']['subscriptions']}=={'w:p0','w:p1','w:p2','w:role'},requests
    assert not errors,errors
    print(f'PASS non-latest registered worker subscribed; delivery latency={latency:.3f}s')
PY
python3 -B - "$ROOT" <<'PY'
from process_fixture import TemporaryDirectory, socket_path
from contextlib import ExitStack
import json, os, socket, subprocess, tempfile, threading, time
from pathlib import Path
ROOT=Path(__import__('sys').argv[1])
with TemporaryDirectory(prefix='s-') as tmp, ExitStack() as processes:
    os.environ["TMPDIR"] = tmp
    b=Path(tmp); root=b/'repo'; root.mkdir(); (root/'tasks').mkdir()
    def run(*args,env=None):
        return subprocess.run(list(args),env=env,capture_output=True,text=True,timeout=20)
    assert run('git','init','-q',str(root)).returncode==0
    for k,v in [('user.name','Test'),('user.email','test@example.invalid')]:
        assert run('git','-C',str(root),'config',k,v).returncode==0
    assert run('git','-C',str(root),'commit','-qm','base','--allow-empty').returncode==0
    wt=root/'.worktrees/case'
    assert run('git','-C',str(root),'worktree','add','-qb','case',str(wt)).returncode==0
    task=root/'tasks/case.md'; task.write_text(f'state: verified\nworktree-space: id=wTask root-tab=wTask:t1 path={wt}\n')
    state=b/'state.json'; sockpath=socket_path()
    def w(i):
        return dict(workspace_id=i,focused=i=='wOther',active_tab_id=i+':t1',worktree=dict(repo_root=str(root),checkout_path=str(wt) if i=='wTask' else str(root),is_linked_worktree=i=='wTask'))
    def pane(i):
        return dict(pane_id=i+':p1',workspace_id=i,tab_id=i+':t1',agent=None,agent_status='idle',foreground_cwd=str(wt) if i=='wTask' else str(root))
    initial=dict(workspaces=[w('wTask'),w('wOther')],tabs=[dict(tab_id=i+':t1',workspace_id=i) for i in ['wTask','wOther']],panes=[pane('wTask'),pane('wOther')],focused_workspace_id='wOther',focused_tab_id='wOther:t1',focused_pane_id='wOther:p1')
    state.write_text(json.dumps(initial)); stub=b/'stub'; stub.mkdir(); calls=b/'calls'
    (stub/'herdr').write_text(r'''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
a=sys.argv[1:]; state=Path(os.environ['STATE']); s=json.loads(state.read_text())
with open(os.environ['CALLS'],'a') as f: f.write(json.dumps(a)+'\n')
def out(r): print(json.dumps({'result':r}))
if a[:2]==['status','--json']: print(json.dumps({'server':dict(socket=os.environ['SOCKET'],session=os.environ.get('HERDR_SESSION'))}))
elif a[:2]==['api','snapshot']: out({'snapshot':s})
elif a[:2]==['workspace','list']: out({'workspaces':s['workspaces']})
elif a[:2]==['pane','get']:
    r=next(x for x in s['panes'] if x['pane_id']==a[2]); out({'pane':r})
elif a[:2]==['pane','process-info']:
    pid=int(os.environ['NATIVE_PID']); busy=os.environ.get('BUSY')=='1'
    out({'process_info':dict(pane_id=a[3],shell_pid=42,foreground_process_group_id=pid if busy else 42,
         foreground_processes=[dict(pid=pid if busy else 42,argv0='pi' if busy else 'zsh',cwd=os.environ['WT'])])})
elif a[:2]==['workspace','close']:
    if os.environ.get('CLOSE_UNCONFIRMED')!='1':
        for key in ['workspaces','tabs','panes']: s[key]=[x for x in s[key] if x.get('workspace_id')!=a[2]]
        state.write_text(json.dumps(s))
    out({'type':'workspace_closed'})
else: sys.exit(9)
'''); (stub/'herdr').chmod(0o755)
    api=socket.socket(socket.AF_UNIX); api.bind(sockpath); api.listen(); api.settimeout(.2); stop=threading.Event()
    def serve():
        while not stop.is_set():
            try: c,_=api.accept()
            except socket.timeout: continue
            with c:
                req=json.loads(c.makefile('rb').readline()); s=json.loads(state.read_text()); method=req['method']; params=req['params']
                with calls.open('a') as f: f.write(json.dumps(req)+'\n')
                if method=='workspace.move':
                    ws=params['workspace_id']; item=next(x for x in s['workspaces'] if x['workspace_id']==ws)
                    old=s['workspaces'].index(item); slot=params['insert_index']
                    s['workspaces']=[x for x in s['workspaces'] if x['workspace_id']!=ws]; s['workspaces'].insert(slot-1 if slot>old else slot,item)
                    # Herdr-like layout side effect: require explicit same-pane restore/readback.
                    s.update(focused_workspace_id=ws,focused_tab_id=ws+':t1',focused_pane_id=ws+':p1')
                    if s.get('concurrent_focus'): s.update(focused_workspace_id='wOther',focused_tab_id='wOther:t1',focused_pane_id='wOther:p2')
                    result={'type':'workspace_list','workspaces':s['workspaces']}
                elif method=='pane.focus':
                    pane=params['pane_id']; ws=next(x['workspace_id'] for x in s['panes'] if x['pane_id']==pane)
                    s.update(focused_workspace_id=ws,focused_tab_id=ws+':t1',focused_pane_id=pane); result={'type':'ok'}
                else: result={'type':'ok'}
                state.write_text(json.dumps(s)); c.sendall((json.dumps({'id':req['id'],'result':result})+'\n').encode())
    thread=threading.Thread(target=serve,daemon=True); thread.start()
    native=subprocess.Popen([__import__('sys').executable,'-c','import sys; sys.stdin.read()'],stdin=subprocess.PIPE)
    processes.callback(lambda: (native.terminate() if native.poll() is None else None, native.wait(timeout=10), native.stdin.close()))
    env={**os.environ,'PATH':str(stub)+':'+os.environ['PATH'],'STATE':str(state),'SOCKET':sockpath,'CALLS':str(calls),'NATIVE_PID':str(native.pid),'WT':str(wt)}
    helper=['bash',str(ROOT/'bin/qwb-herdr.sh')]
    base=helper+['move','--project',str(root),'--task',str(task),'--space','wTask','--index','1']
    moved=run(*base,env=env); assert moved.returncode==0,moved.stderr
    s=json.loads(state.read_text()); assert [w['workspace_id'] for w in s['workspaces']]==['wOther','wTask'] and s['focused_pane_id']=='wOther:p1',s
    assert task.read_text().endswith(f'path={wt}\n'),'ordering mutated ticket ownership'
    foreign=run(*[x if x!='wTask' else 'wOther' for x in base],env=env); assert foreign.returncode!=0
    concurrent=dict(initial,concurrent_focus=True); concurrent['panes']=initial['panes']+[dict(pane('wOther'),pane_id='wOther:p2')]
    state.write_text(json.dumps(concurrent))
    conflict=run(*base,env=env); assert conflict.returncode!=0 and json.loads(state.read_text())['focused_pane_id']=='wOther:p2',conflict.stderr
    state.write_text(json.dumps(s))
    # A native idle edge with an outstanding tool call is busy and never closed.
    session=b/'pi.jsonl'; session.write_text('\n'.join(json.dumps(x) for x in [
        dict(type='session',id='session',cwd=str(wt)),
        dict(type='message',id='call',parentId=None,message=dict(role='assistant',stopReason='toolUse',content=[dict(type='toolCall',id='long',name='bash')]))])+'\n')
    s['panes'][0 if s['panes'][0]['workspace_id']=='wTask' else 1].update(agent='pi',agent_session=dict(kind='path',source='herdr:pi',value=str(session)))
    state.write_text(json.dumps(s)); busyenv={**env,'BUSY':'1'}
    observed=run(*helper,'activity','--project',str(root),'--pane','wTask:p1','--dir',str(wt),env=busyenv)
    assert observed.returncode==0 and json.loads(observed.stdout)['activity']=='busy',observed.stderr
    close=helper+['close','--project',str(root),'--task',str(task),'--space','wTask']
    blocked=run(*close,env=busyenv); assert blocked.returncode!=0 and len(json.loads(state.read_text())['workspaces'])==2,blocked.stderr
    # Even a settled native Pi must exit to shell before destructive Space close.
    with session.open('a') as f:
        f.write(json.dumps(dict(type='message',id='result',parentId='call',message=dict(role='toolResult',toolCallId='long')))+'\n')
        f.write(json.dumps(dict(type='message',id='finish',parentId='result',message=dict(role='assistant',stopReason='stop',content=[])))+'\n')
    idle=run(*helper,'activity','--project',str(root),'--pane','wTask:p1','--dir',str(wt),env=busyenv)
    assert idle.returncode==0 and json.loads(idle.stdout)['activity']=='idle',idle.stderr
    # Reuse requires this launch's PID/start/session, not only an idle edge or old dispatch.
    original_ticket=task.read_text(); proof=json.loads(idle.stdout)
    unbound=run(*helper,'activity','--project',str(root),'--pane','wTask:p1','--dir',str(wt),'--task',str(task),env=busyenv)
    assert json.loads(unbound.stdout)['activity']=='unknown'
    task.write_text(original_ticket+'working: worker-activity op=fixture pane=wTask:p1 evidence='+json.dumps(proof)+'\n')
    bound=run(*helper,'activity','--project',str(root),'--pane','wTask:p1','--dir',str(wt),'--task',str(task),env=busyenv)
    assert json.loads(bound.stdout)['activity']=='idle',bound.stdout
    proof['pid_start']='stale incarnation'
    task.write_text(original_ticket+'working: worker-activity op=fixture pane=wTask:p1 evidence='+json.dumps(proof)+'\n')
    stale=run(*helper,'activity','--project',str(root),'--pane','wTask:p1','--dir',str(wt),'--task',str(task),env=busyenv)
    assert json.loads(stale.stdout)['activity']=='unknown'
    task.write_text(original_ticket)
    # Pi recovery omits a transport-error attempt; raw history must stay intact.
    settled_bytes=session.read_bytes()
    header=dict(type='session',id='session',cwd=str(wt))
    failed=dict(type='message',id='failed',parentId=None,message=dict(role='assistant',stopReason='error',errorMessage='WebSocket closed 1012',content=[dict(type='toolCall',id='ghost',name='bash')]))
    finish=dict(type='message',id='finish',parentId='failed',message=dict(role='assistant',stopReason='stop',content=[]))
    omission=dict(type='context_edit',id='omit',parentId='finish',targetId='failed',replacement=None)
    def observe(entries,wanted,pending):
        session.write_text('\n'.join(json.dumps(x) for x in [header,*entries])+'\n'); before=session.read_bytes()
        got=run(*helper,'activity','--project',str(root),'--pane','wTask:p1','--dir',str(wt),env=busyenv)
        assert got.returncode==0,(got.stdout,got.stderr)
        data=json.loads(got.stdout)
        assert (data['activity'],data.get('pending_tools'))==(wanted,pending),(wanted,pending,data)
        assert session.read_bytes()==before,'activity rewrote append-only native history'
    observe([failed,finish],'busy',['ghost'])  # An error or Herdr idle alone never clears a call.
    observe([failed,finish,omission],'idle',[])  # Only the explicit edit condition differs.
    observe([failed,finish,dict(omission,targetId='other-entry')],'busy',['ghost'])
    observe([failed,finish,dict(omission,replacement={'content':'recovered text'})],'idle',[])
    observe([failed,finish,dict(omission,replacement={'content':[]})],'idle',[])
    live=dict(type='toolCall',id='live',name='bash')
    observe([failed,finish,dict(omission,replacement={'content':[live]})],'busy',['live'])
    restored=dict(omission,id='restore',parentId='omit',replacement={'content':failed['message']['content']})
    observe([failed,finish,omission,restored],'busy',['ghost'])
    observe([failed,finish,omission,restored,dict(omission,id='delete-again',parentId='restore')],'idle',[])
    # An edit on an abandoned branch must not alter the selected branch's pending call.
    observe([failed,finish,omission,dict(type='label',id='before-edit',parentId='finish')],'busy',['ghost'])
    observe([failed,finish,dict(omission,replacement={'content':[live]}),dict(type='message',id='other-root',parentId=None,message=dict(role='assistant',stopReason='stop',content=[]))],'idle',[])
    result=dict(type='message',id='result',parentId='failed',message=dict(role='toolResult',toolCallId='ghost',content=[]))
    result_finish=dict(finish,parentId='result')
    result_edit=dict(omission,parentId='finish',targetId='result',replacement={'content':'edited result'})
    observe([failed,result,result_finish,result_edit],'idle',[])  # Content changes preserve role/call ID.
    observe([failed,result,result_finish,dict(result_edit,replacement=None)],'busy',['ghost'])
    pending=dict(type='message',id='live-call',parentId='omit',message=dict(role='assistant',stopReason='toolUse',content=[live]))
    observe([failed,finish,omission,pending,dict(finish,id='idle-edge',parentId='live-call')],'busy',['live'])
    # Compaction is not an execution acknowledgement; preserve unmatched native obligations.
    observe([failed,finish,dict(type='compaction',id='summary',parentId='finish',firstKeptEntryId='summary',summary='history summarized')],'busy',['ghost'])
    working=json.loads(state.read_text());next(x for x in working['panes'] if x['pane_id']=='wTask:p1')['agent_status']='working';state.write_text(json.dumps(working))
    observe([failed,finish,omission],'busy',[])
    state.write_text(json.dumps(s))
    observe([failed,finish,{k:v for k,v in omission.items() if k!='replacement'}],'unknown',None)
    observe([failed,finish,dict(omission,replacement={'content':False})],'unknown',None)
    session.write_bytes(settled_bytes)
    print('PASS context edits omit/replace content on selected branch; latest wins; true pending/error/working/compaction remain busy; raw untouched')
    blocked=run(*close,env=busyenv); assert blocked.returncode!=0,blocked.stderr
    state.write_text(json.dumps(initial))
    # A foreground shell is not death proof for the original bound/background PID.
    proof=json.loads(idle.stdout)
    task.write_text(original_ticket+f'dispatch: now pane=wTask:p1 dir={wt}\n'+'working: worker-activity op=fixture pane=wTask:p1 evidence='+json.dumps(proof)+'\n')
    alive=run(*close,env=env); assert alive.returncode!=0 and len(json.loads(state.read_text())['workspaces'])==2,alive.stderr
    task.write_text(original_ticket)
    uncertain=run(*close,env={**env,'CLOSE_UNCONFIRMED':'1'})
    assert uncertain.returncode!=0 and len(json.loads(state.read_text())['workspaces'])==2,uncertain.stderr
    state.write_text(json.dumps(initial))
    closed=run(*close,env=env); assert closed.returncode==0,closed.stderr
    s=json.loads(state.read_text()); assert [w['workspace_id'] for w in s['workspaces']]==['wOther'] and s['focused_pane_id']=='wOther:p1',s
    assert wt.is_dir() and task.read_text().endswith(f'path={wt}\n')
    actions=[json.loads(x) for x in calls.read_text().splitlines()]
    assert not any(isinstance(x,dict) and x.get('method')=='workspace.move' and x['params']['workspace_id']!='wTask' for x in actions)
    stop.set(); thread.join(timeout=20); api.close()
    print('PASS owned ordering/confirmed close preserve unrelated focus; unknown ownership/long idle tool/live Pi refuse')
PY
python3 -B - "$ROOT" <<'PY'
from process_fixture import TemporaryDirectory, socket_path
import hashlib, json, os, shutil, socket, subprocess, tempfile, threading, time
from pathlib import Path
ROOT=Path(__import__('sys').argv[1])
with TemporaryDirectory(prefix='s-') as tmp:
    os.environ["TMPDIR"] = tmp
    b=Path(tmp); p=b/'project'; p.mkdir(); (p/'tasks').mkdir(); (p/'qwbuddy').mkdir()
    subprocess.run(['git','init','-q',str(p)],check=True)
    lock=p/'qwbuddy/.controller.lock'; lock.mkdir(); (lock/'owner').write_text('now ctl\n')
    (p/'qwbuddy/config.sh').write_text('QWB_REWAKE_MS=60000\n')
    shutil.copytree(ROOT/'bin',p/'qwbuddy/bin')
    shutil.copytree(ROOT/'templates/roles',p/'qwbuddy/roles')
    for name in ['TASK.md','QWBUDDY.md']: shutil.copy(ROOT/'templates'/name,p/'qwbuddy'/name)
    t=p/'tasks/case.md'; t.write_text('state: running\n')
    (p/'tasks/observer.md').write_text(f'state: verified\ndispatch: now pane=w:p0 dir={p}\n')
    stub=b/'stub'; stub.mkdir(); log=b/'calls'; socketpath=socket_path()
    (stub/'lsof').write_text('#!/usr/bin/env bash\nexit 1\n'); (stub/'lsof').chmod(0o755)
    (stub/'herdr').write_text(r'''#!/usr/bin/env python3
import json,os,sys
a=sys.argv[1:]
with open(os.environ['LOG'],'a') as f: f.write(json.dumps(a)+'\n')
if a[:2]==['status','--json']: print(json.dumps({'server':{'socket':os.environ['SOCKET'],'session':os.environ.get('HERDR_SESSION')}}))
else: print(json.dumps({'result':{'type':'ok'}}))
'''); (stub/'herdr').chmod(0o755)
    env={**os.environ,'PATH':str(stub)+':'+os.environ['PATH'],'HERDR_PANE_ID':'ctl','LOG':str(log),'SOCKET':socketpath}
    def call(script,cmd,*args,rc=0):
        r=subprocess.run(['bash',str(ROOT/'bin'/script),cmd,'--project',str(p),'--task',str(t),*args],env=env,capture_output=True,text=True,timeout=20)
        assert r.returncode==rc,(script,cmd,r.returncode,r.stdout,r.stderr); return r.stdout
    proof=b/'migration.json'; proof.write_text(json.dumps(dict(task_sha256=hashlib.sha256(t.read_bytes()).hexdigest(),confirm={k:'temporary fixture; old writers stopped' for k in ['run','wake','worktree','worker','controller','old-fds','external-actions']})))
    call('qwb-ledger.sh','migrate','--',str(proof))
    wake=['bash',str(ROOT/'bin/qwb-wake.sh'),'--project',str(p),'--pane','ctl','--interval','10000']
    prime=subprocess.run(wake+['--once'],env=env,capture_output=True,text=True,timeout=20); assert prime.returncode==0,prime.stderr
    api=socket.socket(socket.AF_UNIX); api.bind(socketpath); api.listen(); api.settimeout(.2)
    stop=threading.Event(); disconnected=threading.Event(); reconnect=threading.Event(); connected=threading.Event(); requests=[]
    def server():
        count=0
        while not stop.is_set():
            try: c,_=api.accept()
            except socket.timeout: continue
            try:
                with c:
                    c.settimeout(20); req=json.loads(c.makefile('rb').readline()); requests.append(req); count+=1
                    if count>1 and not reconnect.wait(1): continue
                    c.sendall((json.dumps({'id':req['id'],'result':{'type':'subscription_started'}})+'\n').encode())
                    if count==1: disconnected.set(); continue
                    connected.set()
                    for _ in range(3):
                        c.sendall((json.dumps(dict(event='pane.agent_status_changed',data=dict(pane_id='w:p0',workspace_id='w',agent_status='done')))+'\n').encode()); time.sleep(.1)
                    stop.wait(5)
            except (BrokenPipeError,ConnectionResetError,socket.timeout): pass
    thread=threading.Thread(target=server,daemon=True); thread.start()
    owner=subprocess.Popen(wake,env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    try:
        assert disconnected.wait(20),'subscription was not established'
        duplicate=subprocess.run(wake+['--once'],env=env,capture_output=True,text=True,timeout=20)
        assert duplicate.returncode==75,('second supervisor not rejected',duplicate.returncode,duplicate.stderr)
        start=time.monotonic()
        call('qwb-ledger.sh','question','--event-id','during-gap-key','--','budget','预算未答')
        call('qwb-ledger.sh','append','--event-id','during-gap-result','--','done: 断流期间结果')
        deadline=time.monotonic()+15
        while time.monotonic()<deadline:
            lines=[json.loads(x) for x in log.read_text().splitlines()]
            if all(any(x[:2]==['pane','run'] and source in x[-1] for x in lines) for source in ['during-gap-key','during-gap-result']): break
            time.sleep(.1)
        else: raise AssertionError('fallback did not deliver all gap facts: '+log.read_text())
        latency=time.monotonic()-start; reconnect.set(); assert connected.wait(20),'not reconnected'
        time.sleep(2)
        data=json.loads(call('qwb-ledger.sh','read')); pending=json.loads(call('qwb-send.sh','pending'))
        assert data['questions']['budget']['answer']=='' and data['questions']['budget']['resumed']==''
        for source in ['during-gap-key','during-gap-result']:
            h=next(x for x in pending if x['source_event']==source); assert not h['handled'],h
            assert h['transport_count']==1,('duplicate event replay repeated transport',h)
        assert len(requests)>=2 and all(r['params']['subscriptions']==[dict(type='pane.agent_status_changed',pane_id='w:p0')] for r in requests)
        print(f'PASS gap facts delivered latency={latency:.3f}s; reconnected level reconcile, one owner, duplicate events keep one transport/unanswered key')
    finally:
        owner.terminate(); out,err=owner.communicate(timeout=20)
        print('reconnect owner output:',out,err)
        stop.set(); thread.join(timeout=20); api.close()
        assert owner.returncode in (0,143),('owner cleanup',owner.returncode,out,err)
    timed=subprocess.run(wake+['--block','--max-ms','150'],env=env,capture_output=True,text=True,timeout=20)
    assert timed.returncode==124 and '--block 到期' in timed.stderr,(timed.returncode,timed.stdout,timed.stderr)
    unchanged=json.loads(call('qwb-ledger.sh','read'))
    assert unchanged['questions']['budget']['answer']=='' and unchanged['questions']['budget']['resumed']==''
    print('PASS normal deadline remains 124 wait, no cancellation/death or unanswered-key consumption')
PY
fi
python3 -B - "$ROOT" <<'PY'
from process_fixture import TemporaryDirectory
from contextlib import ExitStack
import json, os, subprocess, sys, tempfile
from pathlib import Path
ROOT=Path(sys.argv[1]).resolve()
# Reuse the external Herdr contract double/project builder; exercise real writer and finish.
source=(ROOT/'tests/worktree-space.py').read_text()
prefix=source.split("with tempfile.TemporaryDirectory(prefix='s-')")[0]
prefix=prefix.replace('ROOT = Path(__file__).resolve().parents[1]','ROOT = Path(sys.argv[1]).resolve()')
exec(prefix)
for mode in ['live','missing','dead','extra-pane','no-attempt']:
    with TemporaryDirectory(prefix='s-') as d, ExitStack() as processes:
        os.environ["TMPDIR"] = d
        repo,ticket,state,log,env=project(Path(d)); wt=repo/'.worktrees/case'
        assert call('git','-C',str(repo),'worktree','add','-qb','case',str(wt),env=env).returncode==0
        state.write_text(str(wt)); log.write_text('')
        live_child=subprocess.Popen([sys.executable,'-c','import sys; sys.stdin.read()'],stdin=subprocess.PIPE)
        processes.callback(lambda: (live_child.terminate() if live_child.poll() is None else None, live_child.wait(timeout=10), live_child.stdin.close()))
        pid=live_child.pid
        start=call('/bin/ps','-p',str(pid),'-o','lstart=',env=env).stdout.strip()
        evidence=dict(pid=pid,pid_start=start)
        if mode in ('dead','extra-pane'):
            child=subprocess.Popen([sys.executable,'-c','import time; time.sleep(30)'])
            evidence=dict(pid=child.pid,pid_start=call('/bin/ps','-p',str(child.pid),'-o','lstart=',env=env).stdout.strip())
            child.terminate(); child.wait()
        if mode=='missing': evidence=dict(activity='unknown')
        pane='wTask:p2' if mode=='extra-pane' else 'wTask:p1'
        text=f'state: verified\nworktree-space: id=wTask root-tab=wTask:t1 path={wt}\n'
        if mode!='no-attempt':
            dispatch=f'dispatch: now op_id=launch worker=pi agent=case pane={pane} dir={wt}'
            text+=dispatch+'\n'+f'working: worker-activity op=launch pane={pane} evidence='+json.dumps(evidence)+'\n'
            if mode=='extra-pane':
                text+='working: worker-activity op=old-root pane=wTask:p1 evidence='+json.dumps(dict(pid=pid,pid_start=start))+'\n'
                env={**env,'QWB_TEST_MODE':'worker-success'}
        ticket.write_text(text)
        if mode!='no-attempt':
            compensation=call('bash',str(ROOT/'bin/qwb-ledger.sh'),'not-sent','--project',str(repo),'--task',str(ticket),'--legacy','--','launch','blocked: prompt failed',dispatch,env=env)
            assert compensation.returncode==0,compensation.stderr
            assert 'not-sent: now op_id=launch' in ticket.read_text() and '\ndispatch:' not in ticket.read_text()
        result=call('bash',str(ROOT/'bin/qwb-worktree.sh'),'finish','case','--merged','--project',str(repo),env=env)
        closes=[x for x in log.read_text().splitlines() if json.loads(x)==['workspace','close','wTask']]
        if mode in ('live','missing','extra-pane'):
            assert result.returncode!=0 and wt.exists() and state.exists() and not closes,(mode,result.returncode,result.stdout,result.stderr)
            reason='旧启动代PID/start未知' if mode=='missing' else '旧启动代仍活或死亡未知'
            assert reason in result.stderr,(mode,'must hit lifetime refusal, not an unrelated fixture error',result.stderr)
            os.kill(pid,0)
            assert call('git','-C',str(repo),'show-ref','--verify','--quiet','refs/heads/case',env=env).returncode==0
            print('PASS not-sent '+mode+': original launch obligation retained, no Space/Git close')
        else:
            assert result.returncode==0 and not wt.exists() and not state.exists() and len(closes)==1,(mode,result.returncode,result.stdout,result.stderr)
            print('PASS '+mode+': proven-ended/no-start safe finish remains usable')

# F2 public seam: real qwb-run fresh/reuse (including prompt failure), actual process death, then finish.
# Native Pi metadata is an external Herdr double; PID/start belong to a real owned child, not a model CLI.
native_stub=STUB.replace('if args[:2] == ["status", "--json"]:', r'''native = Path(os.environ["QWB_TEST_NATIVE"])
session = os.environ["QWB_TEST_NATIVE_SESSION"]
if args[:2] == ["agent", "start"]:
    native.write_text("started")
    out({"type": "agent_started"})
elif args[:2] == ["agent", "get"] and native.exists():
    out({"agent": {"name": "qwb-case", "agent": "pi", "agent_status": "idle", "pane_id": "wTask:p1", "workspace_id": "wTask", "cwd": wt}})
elif args[:2] == ["pane", "get"] and args[2] == "wTask:p1" and native.exists():
    out({"pane": {"pane_id": "wTask:p1", "tab_id": "wTask:t1", "workspace_id": "wTask", "agent": "pi", "agent_status": "idle", "foreground_cwd": wt,
         "agent_session": {"source": "herdr:pi", "kind": "path", "value": session}}})
elif args[:2] == ["pane", "process-info"] and args[3] == "wTask:p1" and native.exists():
    pid = int(os.environ["QWB_TEST_NATIVE_PID"])
    out({"process_info": {"pane_id": "wTask:p1", "shell_pid": 42, "foreground_process_group_id": pid,
         "foreground_processes": [{"pid": pid, "argv0": "pi", "cwd": wt}]}})
elif args[:2] == ["agent", "prompt"]:
    # Observe the durable receipt at the external transport boundary, before failure compensation.
    text = Path(os.environ["QWB_TEST_NATIVE_TICKET"]).read_text()
    with log.open("a") as f: f.write(json.dumps(["prompt-ticket", text]) + "\n")
    if os.environ.get("QWB_TEST_PROMPT_FAILED") == "1": err("prompt_failed")
    out({"type": "ok"})
elif args[:2] == ["status", "--json"]:''')
for mode in ['reuse','failed-reuse','unknown-start']:
    with TemporaryDirectory(prefix='s-') as d:
        os.environ["TMPDIR"] = d
        b=Path(d); repo,ticket,state,log,env=project(b); wt=repo/'.worktrees/case'
        assert call('git','-C',str(repo),'worktree','add','-qb','case',str(wt),env=env).returncode==0
        child=subprocess.Popen(['sleep','60'],cwd=wt)
        native=b/'native-active'; session=b/'pi.jsonl'
        session.write_text(json.dumps(dict(type='session',cwd=str(wt)))+'\n'+json.dumps(dict(type='message',id='end',message=dict(role='assistant',content=[],stopReason='stop')))+'\n')
        (b/'stub/herdr').write_text(native_stub)
        env={**env,'QWB_TEST_NATIVE':str(native),'QWB_TEST_NATIVE_SESSION':str(session),'QWB_TEST_NATIVE_PID':str(child.pid),'QWB_TEST_NATIVE_TICKET':str(ticket)}
        dispatch=['bash',str(repo/'qwbuddy/bin/qwb-run.sh'),'--project',str(repo),'--task','case','--worker','pi']
        finish=['bash',str(ROOT/'bin/qwb-worktree.sh'),'finish','case','--merged','--project',str(repo)]
        try:
            first=call(*dispatch,env=env); assert first.returncode==0,(first.stdout,first.stderr)
            if mode=='unknown-start':
                ticket.write_text('\n'.join(x for x in ticket.read_text().splitlines() if not x.startswith('working: worker-activity'))+'\n')
            second=call(*dispatch,env={**env,**({'QWB_TEST_PROMPT_FAILED':'1'} if mode=='failed-reuse' else {})})
            assert second.returncode==(0 if mode=='reuse' else 1),(mode,second.stdout,second.stderr)
            if mode!='unknown-start': assert '复用既有工人' in second.stdout,(mode,second.stdout,second.stderr)
            else: assert '本代真实活动为 unknown' in second.stderr,(mode,second.stderr)
            calls=[json.loads(x) for x in log.read_text().splitlines()]
            assert sum(x[:2]==['agent','start'] for x in calls)==1 and not any(x[:2]==['tab','create'] for x in calls),calls
            # Native label can return to shell while its process still lives: must preserve original obligations.
            native.unlink(); alive=call(*finish,env=env)
            reason='启动代死亡证据缺失' if mode=='unknown-start' else '旧启动代仍活或死亡未知'
            assert alive.returncode!=0 and '候选写入者仍持cwd/FD' in alive.stderr and wt.exists() and state.exists(),(mode,alive.stderr)
            child.terminate(); child.wait()
            ended=call(*finish,env=env)
            print('PUBLIC REUSE',mode,'native_pid=',child.pid,'ended_rc=',ended.returncode,'wt=',wt.exists(),'space=',state.exists(),'stderr=',ended.stderr,flush=True)
            if mode=='unknown-start':
                assert ended.returncode!=0 and reason in ended.stderr and wt.exists() and state.exists(),ended.stderr
                assert sum(x[:2]==['agent','prompt'] for x in calls)==1,'unknown reuse must not deliver'
            else:
                assert ended.returncode==0 and not wt.exists() and not state.exists(),(mode,ended.stdout,ended.stderr)
                receipts=[x for x in ticket.read_text().splitlines() if x.startswith(('dispatch:','not-sent:'))]
                assert len(receipts)==2 and ('not-sent:' in receipts[-1])==(mode=='failed-reuse'),receipts
                # Both delivery ops retain the same validated native incarnation before their prompts.
                proofs=[]
                for _,text in [x for x in calls if x[0]=='prompt-ticket']:
                    receipt=next(x for x in reversed(text.splitlines()) if x.startswith('dispatch:'))
                    op=next(x.split('=',1)[1] for x in receipt.split() if x.startswith('op_id='))
                    bound=next(x for x in text.splitlines() if x.startswith('working: worker-activity op='+op+' pane=wTask:p1 evidence='))
                    proofs.append(json.loads(bound.split(' evidence=',1)[1]))
                assert len(proofs)==2 and all((p['pid'],p['pid_start'],p['session'])==(proofs[0]['pid'],proofs[0]['pid_start'],proofs[0]['session']) for p in proofs),proofs
                assert call('git','-C',str(repo),'show-ref','--verify','--quiet','refs/heads/case',env=env).returncode!=0
            print('PASS public run '+mode+': '+('unknown start never redelivers or closes' if mode=='unknown-start' else 'verified incarnation persists before prompt; alive preserves, proven-ended reuse finishes'))
        finally:
            if child.poll() is None: child.terminate(); child.wait()
PY
