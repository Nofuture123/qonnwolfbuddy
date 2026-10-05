#!/usr/bin/env bash
# Thin local transport/presentation helper. MD owns business facts; no watcher per role.
set -euo pipefail
BINDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
export QWB_HERDR_BINDIR="$BINDIR"
exec python3 -B - "$@" <<'PY'
import argparse, json, os, re, signal as signals, socket, subprocess, sys, time
from pathlib import Path

p=argparse.ArgumentParser(description='Herdr hints, owned Space ordering and focus-safe close')
p.add_argument('command',choices=['subscribe','move','close','activity'])
p.add_argument('--project',required=True); p.add_argument('--task'); p.add_argument('--space')
p.add_argument('--index',type=int); p.add_argument('--notice'); p.add_argument('--pane'); p.add_argument('--dir')
p.add_argument('--writer-proof-missing')
a=p.parse_args(); root=Path(a.project).resolve(); bindir=Path(os.environ['QWB_HERDR_BINDIR'])
if a.writer_proof_missing is not None and (a.command!='close' or not a.writer_proof_missing.strip()):
    p.error('--writer-proof-missing 仅 close 支持且原因必须非空')

def require(ok,why):
    if not ok: raise ValueError(why)

def reap_command(child,check_group):
    # A query may itself fork; only its own newly-created session may be terminated.
    try: os.killpg(child.pid,signals.SIGKILL)
    except ProcessLookupError: pass
    child.wait()
    if check_group:
        deadline=time.monotonic()+.75
        while True:
            rows=subprocess.run(['/bin/ps','-axo','pgid=,stat='],capture_output=True,text=True,check=True).stdout
            if not any(int(row[0])==child.pid and not row[1].startswith('Z')
                       for line in rows.splitlines() if (row:=line.split())): break
            if time.monotonic()>=deadline: raise RuntimeError('subscription command descendants did not exit')
            time.sleep(.005)
    child.stdout.close(); child.stderr.close()

def command(argv):
    if a.command!='subscribe':
        v=subprocess.run(argv,capture_output=True,text=True,timeout=2)
        require(v.returncode==0,'query/action failed: '+(v.stderr or v.stdout).strip())
        return v.stdout
    child=None; check_group=True
    try:
        # Parent signals stay pending until the handle is registered; the single-threaded
        # child restores the original mask before exec, so it remains normally interruptible.
        mask=signals.pthread_sigmask(signals.SIG_BLOCK,{signals.SIGTERM,signals.SIGINT})
        try:
            child=subprocess.Popen(argv,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,
                start_new_session=True,preexec_fn=lambda:signals.pthread_sigmask(signals.SIG_SETMASK,mask))
        finally: signals.pthread_sigmask(signals.SIG_SETMASK,mask)
        out,err=child.communicate(timeout=2)
        require(child.returncode==0,'query/action failed: '+(err or out).strip())
        check_group=False
        return out
    except BaseException:
        check_group=True
        raise
    finally:
        if child is not None:
            mask=signals.pthread_sigmask(signals.SIG_BLOCK,{signals.SIGTERM,signals.SIGINT})
            try: reap_command(child,check_group)
            finally: signals.pthread_sigmask(signals.SIG_SETMASK,mask)

def herdr(*argv):
    v=json.loads(command(['herdr',*argv])); require(not v.get('error') and isinstance(v.get('result'),dict),'Herdr result unknown')
    return v['result']

def socket_path():
    v=json.loads(command(['herdr','status','--json']))['server']
    session=os.environ.get('HERDR_SESSION')
    require(not session or v.get('session')==session,'Herdr session mismatch')
    path=v['socket']; require(isinstance(path,str) and Path(path).is_absolute(),'socket unknown')
    return path

# Same newline-delimited protocol as local api schema. Bounded wire reads, no new dependency.
def connect(path):
    s=socket.socket(socket.AF_UNIX); s.settimeout(.8)
    try: s.connect(path)
    except Exception: s.close(); raise
    return s

def send(s,method,params):
    s.sendall((json.dumps(dict(id='qwb-herdr',method=method,params=params))+'\n').encode())

def receive(s,buf):
    while b'\n' not in buf:
        chunk=s.recv(65536); require(chunk,'event stream closed'); buf.extend(chunk)
        require(len(buf)<=4*1024*1024,'wire response too large')
    end=buf.index(10); line=bytes(buf[:end]); del buf[:end+1]
    return json.loads(line),buf

def rpc(path,method,params):
    with connect(path) as s:
        send(s,method,params); v,_=receive(s,bytearray())
        require(v.get('id')=='qwb-herdr' and not v.get('error') and isinstance(v.get('result'),dict),'wire action unconfirmed')
        return v['result']

def targets():
    panes=set()
    for f in sorted((root/'tasks').glob('*.md')):
        require(not f.is_symlink(),'task symlink; subscription coverage unknown')
        text=f.read_text()
        if '<!-- qwb-collab-' in text:
            d=json.loads(command(['bash',str(bindir/'qwb-ledger.sh'),'read','--project',str(root),'--task',str(f)]))
            panes.update(d.get('workers',{}))
        else:
            lines=re.findall(r'^dispatch:.*$',text,re.M)
            if lines:
                match=re.search(r'(?:^|\s)pane=(\S+)',lines[-1])
                if match: panes.add(match[1])
    for f in (root/'qwbuddy/.roles').glob('*.json'):
        require(not f.is_symlink(),'role symlink')
        d=json.loads(f.read_text())
        require(d.get('root')==str(root) and d.get('version')==1,'role identity unknown')
        if d.get('phase')!='retired' and d.get('pane'): panes.add(d['pane'])
    return sorted(panes)

def subscribe():
    stop_signal=None
    def interrupted(signum,_frame):
        nonlocal stop_signal
        stop_signal=signum
        raise SystemExit(128+signum)
    signals.signal(signals.SIGTERM,interrupted)
    signals.signal(signals.SIGINT,interrupted)
    notice=Path(a.notice); counter=0; previous=None
    def signal(kind,panes):
        nonlocal counter
        counter+=1; tmp=notice.with_suffix('.tmp')
        tmp.write_text(json.dumps(dict(seq=counter,phase=kind,panes=panes,at=time.time()))+'\n'); tmp.replace(notice)
    while True:
        if stop_signal is not None: raise SystemExit(128+stop_signal)
        panes=[]
        try:
            panes=targets(); require(panes,'no registered targets')
            with connect(socket_path()) as s:
                send(s,'events.subscribe',{'subscriptions':[dict(type='pane.agent_status_changed',pane_id=x) for x in panes]})
                v,buf=receive(s,bytearray())
                require(v.get('id')=='qwb-herdr' and v.get('result',{}).get('type')=='subscription_started' and not v.get('error'),'subscription not acknowledged')
                signal('subscribed',panes); previous=None
                print('Herdr subscription established: '+','.join(panes),file=sys.stderr,flush=True)
                refresh=time.monotonic()+1; s.settimeout(.2)
                while True:
                    if stop_signal is not None: raise SystemExit(128+stop_signal)
                    try:
                        v,buf=receive(s,buf)
                        if v.get('event')=='pane.agent_status_changed' and v.get('data',{}).get('pane_id') in panes:
                            signal('event',panes)
                    except socket.timeout: pass
                    if time.monotonic()>=refresh:
                        if targets()!=panes: break
                        refresh=time.monotonic()+1
        except (OSError,ValueError,KeyError,TypeError,subprocess.TimeoutExpired) as e:
            signal('fallback',panes)
            reason=str(e)
            if reason!=previous:
                print('Herdr timely subscription gap; bounded MD scan: '+reason,file=sys.stderr,flush=True); previous=reason
            time.sleep(1)

# Process evidence never promotes native idle to tool death.
def activity(pane,directory=None):
    info=herdr('pane','get',pane).get('pane',{})
    proc=herdr('pane','process-info','--pane',pane).get('process_info',{})
    require(info.get('pane_id')==pane and proc.get('pane_id')==pane,'pane/process identity unknown')
    rows=proc.get('foreground_processes'); require(isinstance(rows,list),'foreground processes unknown')
    shell=proc.get('shell_pid'); group=proc.get('foreground_process_group_id')
    if shell and group==shell and not info.get('agent') and any(x.get('pid')==shell and Path(x.get('argv0','')).name in ('sh','bash','zsh','fish') for x in rows):
        return dict(activity='idle',proof='foreground-shell',pane=pane)
    tool=info.get('agent'); native=[x for x in rows if Path(x.get('argv0','')).name==tool] if tool else []
    if len(native)>1: native=[x for x in native if x.get('pid')==group]
    require(len(native)==1 and isinstance(native[0].get('pid'),int),'native tool identity unknown')
    n=native[0]; start=command(['ps','-p',str(n['pid']),'-o','lstart=']).strip(); require(start,'PID start unknown')
    if directory: require(Path(n.get('cwd','')).resolve()==Path(directory).resolve(),'tool cwd mismatch')
    # Unmatched Pi tool calls override an idle edge; all other CLI adapters remain unknown/busy.
    ref=info.get('agent_session',{}) or {}
    if tool=='pi' and ref.get('source')=='herdr:pi' and ref.get('kind')=='path':
        session=Path(ref.get('value','')); require(session.is_absolute() and not session.is_symlink(),'native session unknown')
        if not session.exists():
            return dict(activity='unknown',proof='native-pid+unpersisted-session',pid=n['pid'],pid_start=start,session=str(session))
        require(session.is_file(),'native session not regular')
        entries=[json.loads(x) for x in session.read_text().splitlines() if x.strip()]
        require(entries and entries[0].get('type')=='session' and (not directory or Path(entries[0].get('cwd','')).resolve()==Path(directory).resolve()),'session cwd/header unknown')
        # Follow the current JSONL leaf ancestry, not abandoned branches.
        byid={x['id']:x for x in entries if 'id' in x}; branch=[]; node=entries[-1]; seen=set()
        while node and node.get('id') not in seen:
            seen.add(node.get('id')); branch.append(node); node=byid.get(node.get('parentId'))
        # Pi context edits are branch-relative; latest wins without rewriting raw history.
        edits={x['targetId']:x['replacement'] for x in reversed(branch) if x.get('type')=='context_edit'}
        outstanding=set(); last=None
        for x in reversed(branch):
            m=x.get('message',{}); role=m.get('role')
            if x.get('id') in edits and role in ('user','assistant','toolResult','custom'):
                replacement=edits[x['id']]
                if replacement is None: continue
                require(isinstance(replacement,dict) and isinstance(replacement.get('content'),(str,list)),'context edit content unknown')
                content=replacement['content']
                if role in ('assistant','toolResult') and isinstance(content,str): content=[dict(type='text',text=content)]
                m=dict(m,content=content)  # Only content changes; retain role/call ID/stop metadata.
            if role: last=m
            if role=='assistant':
                outstanding.update(c['id'] for c in m.get('content',[]) if isinstance(c,dict) and c.get('type')=='toolCall' and c.get('id'))
            elif role=='toolResult': outstanding.discard(m.get('toolCallId'))
        active=bool(outstanding) or info.get('agent_status') in ('working','blocked')
        settled=last is None or (last.get('role')=='assistant' and last.get('stopReason') in ('stop','error','aborted'))
        return dict(activity='busy' if active else 'idle' if settled and info.get('agent_status') in ('idle','done') else 'unknown',
                    proof='native-pid-start+session-branch',pid=n['pid'],pid_start=start,session=str(session),pending_tools=sorted(outstanding))
    return dict(activity='busy' if info.get('agent_status') in ('working','blocked') else 'unknown',proof='native-pid; CLI idle not verified',pid=n['pid'],pid_start=start)

def ended(pid,start):
    require(type(pid) is int and pid>0 and isinstance(start,str) and start,'old launch PID/start unknown')
    try: v=subprocess.run(['/bin/ps','-p',str(pid),'-o','lstart='],capture_output=True,text=True,timeout=2)
    except subprocess.TimeoutExpired: raise ValueError('old native PID still alive or death unknown')
    require(not v.stderr.strip() and ((v.returncode==1 and not v.stdout.strip()) or
            (v.returncode==0 and v.stdout.strip() and v.stdout.strip()!=start)),
            'old native PID still alive or death unknown')

def snapshot():
    s=herdr('api','snapshot').get('snapshot'); require(isinstance(s,dict),'snapshot missing')
    ws=s.get('workspaces'); require(isinstance(ws,list),'workspace order unknown')
    order=[x.get('workspace_id') for x in ws]; require(all(isinstance(x,str) and x for x in order) and len(set(order))==len(order),'workspace IDs unknown')
    focus=(s.get('focused_workspace_id'),s.get('focused_tab_id'),s.get('focused_pane_id'))
    require(not order or all(isinstance(x,str) and x for x in focus),'focus identity unknown')
    return s,order,focus

def presentation():
    require(a.task and a.space,'exact task and registered Space required')
    task=Path(a.task).resolve(); require(task.parent==root/'tasks' and not Path(a.task).is_symlink(),'task outside project')
    text=task.read_text(); records=re.findall(r'^worktree-space: id=(\S+) root-tab=(\S+) path=(.+)$',text,re.M)
    require(records and records[-1][0]==a.space,'unowned Space')
    _,tab,directory=records[-1]; directory=str(Path(directory).resolve())
    verified=command(['bash','-c','. "$1"; qwb_is_project_worktree "$2" "$3" && qwb_worktree_space "$2" "$3"','qwb-herdr',str(bindir/'qwb-lib.sh'),str(root),directory]).strip()
    require(verified==a.space,'registered project worktree identity mismatch')
    before,order,focus=snapshot(); require(a.space in order,'owned Space absent')
    path=socket_path(); index=a.index
    if a.command=='close':
        lines=re.findall(r'^(?:dispatch|not-sent):.*$',text,re.M); allowed={tab}; attempts={}
        waived=set()
        if a.writer_proof_missing is not None:
            # Independently check every old generation, including absent panes and later launches.
            launches=set(); bound={}
            for line in lines:
                match=re.search(r'\spane=(\S+) dir=(.+)$',line); op=re.search(r'\sop_id=(\S+)',line)
                require(match and op,'启动代死亡证据缺失；保留Space')
                require(str(Path(match[2]).resolve())==directory,'启动代目录不符；保留Space')
                launches.add((match[1],op[1]))
            for op,pane,raw in re.findall(r'^working: worker-activity op=(\S+) pane=(\S+) evidence=(.+)$',text,re.M):
                evidence=json.loads(raw); key=(pane,op)
                if isinstance(evidence,dict):
                    require(len(json.loads(raw,object_pairs_hook=list))==len(evidence),'old launch PID/start unknown')
                require(key not in bound or bound[key]==evidence,'启动代死亡证据冲突')
                bound[key]=evidence
            require(launches.issubset(bound),'启动代死亡证据缺失；保留Space')
            for (pane,op),evidence in bound.items():
                unknown=(isinstance(evidence,dict) and set(evidence)=={'activity','proof','conflict'} and
                         evidence['activity']=='unknown' and evidence['proof']=='unverified' and
                         isinstance(evidence['conflict'],str) and bool(evidence['conflict'].strip()))
                if unknown and (pane,op) in launches:
                    query=subprocess.run(['herdr','pane','get',pane],capture_output=True,text=True,timeout=2)
                    if query.returncode:
                        raw=query.stdout if query.stdout.strip() else query.stderr
                        other=query.stderr if query.stdout.strip() else query.stdout
                        try: reply=json.loads(raw)
                        except ValueError: reply={}
                        require(not other.strip() and isinstance(reply,dict) and isinstance(reply.get('error'),dict) and
                                reply['error'].get('code')=='pane_not_found','缺PID兑底：pane '+pane+' 查询失败或身份未知')
                    else:
                        try: reply=json.loads(query.stdout); info=reply.get('result',{}).get('pane',{})
                        except (ValueError,AttributeError): info={}; reply={}
                        require(not query.stderr.strip() and not reply.get('error') and isinstance(info,dict) and
                                info.get('pane_id')==pane and (info.get('agent') is None or isinstance(info.get('agent'),str) and bool(info['agent'])),'缺PID兑底：pane '+pane+' 身份未知')
                        require(info.get('agent') is None,'缺PID兑底：pane '+pane+' 仍有agent，保留Space')
                        observed=activity(pane,directory)
                        require(observed.get('activity')=='idle' and observed.get('proof')=='foreground-shell' and
                                observed.get('pane')==pane,'缺PID兑底：pane '+pane+' 前台不是空闲shell或查询未知')
                    waived.add((pane,op))
                else: ended(evidence.get('pid'),evidence.get('pid_start'))
            if waived:
                probe=subprocess.run(['lsof','-nP','-Fpfan','+D',directory],capture_output=True,text=True,timeout=10)
                require(probe.returncode in (0,1) and not probe.stderr.strip(),'候选写入者资源探针未知')
                require(not probe.stdout.strip(),'候选写入者仍持cwd/FD，保留Space')
                require(probe.returncode==1,'候选写入者资源探针空响应未知')
            registered_panes={key[0] for key in bound}|{key[0] for key in launches}
            for record in (root/'qwbuddy/.roles').glob('*.json'):
                require(not record.is_symlink(),'role record symlink; close ownership unknown')
                d=json.loads(record.read_text())
                if d.get('pane') in registered_panes:
                    require(d.get('root')==str(root) and d.get('version')==1,'role ownership unknown')
                    candidate=d.get('pending') or d
                    if candidate.get('attempted',d.get('phase') not in ('prepared','pane-ready')):
                        ended(candidate.get('pid'),candidate.get('pid_start'))
        current_panes={x.get('pane_id'):x for x in before.get('panes',[]) if x.get('workspace_id')==a.space}
        for line in lines:
            match=re.search(r'\spane=(\S+) dir=(.+)$',line); require(match,'launch receipt identity unknown')
            if match[1] not in current_panes: continue  # Stable absent IDs are not panes this close will control.
            require(str(Path(match[2]).resolve())==directory,'launch receipt directory mismatch')
            op=re.search(r'\sop_id=(\S+)',line); require(op,'launch generation unknown; preserve pane')
            attempts.setdefault(match[1],set()).add(op[1]); allowed.add(current_panes[match[1]].get('tab_id'))
        tabs=[x for x in before.get('tabs',[]) if x.get('workspace_id')==a.space]
        require(tabs and all(x.get('tab_id') in allowed for x in tabs),'foreign/unknown tab')
        panes=[x for x in before.get('panes',[]) if x.get('workspace_id')==a.space]
        require(panes,'Space panes unknown')
        for pane in panes:
            observation=activity(pane['pane_id'],directory)
            require(observation['proof']=='foreground-shell','exit not confirmed; preserve Space: '+json.dumps(observation))
            # A foreground shell cannot prove that a delivered/backgrounded CLI has died.
            bound=re.findall(r'^working: worker-activity op=(\S+) pane=(\S+) evidence=(.+)$',text,re.M)
            by_op={op:json.loads(raw) for op,target,raw in bound if target==pane['pane_id']}
            require(attempts.get(pane['pane_id'],set()).issubset(by_op),'launch attempt has no matching death evidence; preserve pane')
            # Failed compensation changes transport permission, never native process lifetime.
            # Every bound launch on every closing pane is an obligation, even without a dispatch row.
            for op,evidence in by_op.items():
                if (pane['pane_id'],op) not in waived: ended(evidence.get('pid'),evidence.get('pid_start'))
            for record in (root/'qwbuddy/.roles').glob('*.json'):
                require(not record.is_symlink(),'role record symlink; close ownership unknown')
                d=json.loads(record.read_text())
                if d.get('pane')==pane['pane_id']:
                    require(d.get('root')==str(root) and d.get('version')==1,'role ownership unknown')
                    candidate=d.get('pending') or d
                    attempted=candidate.get('attempted',d.get('phase') not in ('prepared','pane-ready'))
                    if attempted: ended(candidate.get('pid'),candidate.get('pid_start'))
        index=len(order)-1  # Avoid Herdr close-neighbor focus bug, moving only our owned Space.
    require(index is not None and 0<=index<len(order),'index out of range')
    expected=[x for x in order if x!=a.space]; expected.insert(index,a.space)
    failure=None
    try:
        # Herdr insert_index names a pre-removal slot, not the final ordinal (local protocol 22).
        wire_index=index+1 if index>order.index(a.space) else index
        rpc(path,'workspace.move',dict(workspace_id=a.space,insert_index=wire_index))
        _,moved,_=snapshot(); require(moved==expected,'ordering readback mismatch; preserve locator')
        if a.command=='close':
            herdr('workspace','close',a.space)
            _,closed,_=snapshot(); require(closed==[x for x in order if x!=a.space],'close not confirmed/order changed; preserve Git')
    except Exception as e: failure=e
    # Never restore a stale target over a user's concurrent focus change.
    after,after_order,after_focus=snapshot()
    if failure and a.command=='close' and a.space in after_order and [x for x in order if x!=a.space]==[x for x in after_order if x!=a.space]:
        old=order.index(a.space); wire=old+1 if old>after_order.index(a.space) else old
        rpc(path,'workspace.move',dict(workspace_id=a.space,insert_index=wire))
        after,after_order,after_focus=snapshot(); require(after_order==order,'failed close original order restore unconfirmed')
    if focus[2] and focus!=after_focus and focus[0] in after_order:
        require(after_focus[0] == a.space and any(x.get('pane_id')==focus[2] and x.get('workspace_id')==focus[0] and x.get('tab_id')==focus[1] for x in after.get('panes',[])),'focus changed concurrently or old target absent; no focus overwrite')
        rpc(path,'pane.focus',{'pane_id':focus[2]})
        _,after_order,after_focus=snapshot(); require(after_focus==focus,'focus restore unconfirmed')
    require(not focus[0] or focus[0]==a.space or after_focus==focus,'unrelated focus not preserved')
    print(json.dumps(dict(before_order=order,after_order=after_order,before_focus=focus,after_focus=after_focus,space=a.space,command=a.command)))
    if failure: raise failure

try:
    if a.command=='subscribe': require(a.notice,'notice path required'); subscribe()
    elif a.command=='activity':
        observed=activity(a.pane,a.dir)
        if a.task:
            task=Path(a.task).resolve(); require(task.parent==root/'tasks' and not Path(a.task).is_symlink(),'activity ticket outside project')
            records=re.findall(r'^working: worker-activity op=(\S+) pane=(\S+) evidence=(.+)$',task.read_text(),re.M)
            records=[json.loads(x[2]) for x in records if x[1]==a.pane]
            require(not (records and observed.get('session') and not records[-1].get('session')),'startup session not recorded; refuse stale idle')
            require(records and observed.get('pid') and all(observed.get(k)==records[-1].get(k) for k in ('pid','pid_start','session')),'startup incarnation/session not bound; refuse stale idle')
        print(json.dumps(observed))
    else: presentation()
except (OSError,ValueError,KeyError,TypeError,subprocess.TimeoutExpired) as e:
    if a.command=='activity':
        print(json.dumps(dict(activity='dead' if 'pane_not_found' in str(e) else 'unknown',proof='pane-not-found' if 'pane_not_found' in str(e) else 'unverified',conflict=str(e)))); sys.exit(0)
    print('Herdr refusal/unknown: '+str(e),file=sys.stderr); sys.exit(1)
PY
