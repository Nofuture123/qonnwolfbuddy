#!/usr/bin/env bash
# Visible standing roles. No dispatch, ledger mutation, watcher or automatic work.
set -euo pipefail
BINDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$PWD"
# Project posture is Markdown owned only by the ledger writer, not role JSON.
if [[ "${1:-}" == mode ]]; then
  shift; MODE_COMMAND="${1:-}"; shift || true
  exec bash "$BINDIR/qwb-ledger.sh" "mode-$MODE_COMMAND" "$@"
fi
args=("$@")
for ((i=0; i<${#args[@]}; i++)); do
  [[ "${args[i]}" != --project ]] || PROJECT_ROOT="${args[i+1]:-}"
done
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  echo '用法: qwb-role.sh start|status|reconcile|retire --project <根> [--actor <id>] [--expect-gen <代次>]'
  echo 'start另需 --role 门禁|规划|测试体系 --worker <已配置工人> --dir <既有目录>；变更操作仅实际绑定主控。'
  echo '控制: qwb-control.sh interrupt|exit|relaunch --actor <id> --expect-gen <代次> --project <根>'
  echo '模式: mode enter|exit|status|summary --project <根> -- <参数>；详见qwb-ledger.sh --help'
  echo 'Pi须显式配置QWB_ROLE_PI_CONTROL=verified；Claude/Codex控制未验证，拒绝。原工人派发配置不变。'
  exit 0
fi
[[ -d "$PROJECT_ROOT" ]] || { echo '错误：项目根不存在' >&2; exit 2; }
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd -P)"
# shellcheck source=/dev/null
. "$BINDIR/qwb-lib.sh"
QWB_ROLE_PI_CONTROL=""; QWB_WORKSPACE=""; QWB_WORKERS=""
QWB_ROLE_PI_INTEGRATION="${HOME}/.pi/agent/extensions/herdr-agent-state.ts"
if [[ -f "$PROJECT_ROOT/qwbuddy/config.sh" ]]; then
  # shellcheck source=/dev/null
  . "$PROJECT_ROOT/qwbuddy/config.sh"
fi
PROFILE='[]'
if [[ "${1:-}" == start || "${1:-}" == relaunch ]]; then
  qwb_load_workers "$PROJECT_ROOT" || exit 1
  PROFILE="$({
    for i in "${!QWB_CONFIG_NAMES[@]}"; do
      offset="${QWB_CONFIG_OFFSETS[i]}"; count="${QWB_CONFIG_COUNTS[i]}"
      argv=()
      for ((j=0; j<count; j++)); do argv+=("${QWB_CONFIG_ARGV[offset+j]}"); done
      python3 -c 'import json,sys; print(json.dumps(dict(worker=sys.argv[1],mode=sys.argv[2],harness=sys.argv[3],argv=sys.argv[4:])))' \
        "${QWB_CONFIG_NAMES[i]}" "${QWB_CONFIG_MODES[i]}" "${QWB_CONFIG_HARNESSES[i]}" "${argv[@]+"${argv[@]}"}"
    done
  } | python3 -c 'import json,sys; print(json.dumps([json.loads(s) for s in sys.stdin]))')"
fi
export QWB_ROLE_BINDIR="$BINDIR" QWB_ROLE_ROOT="$PROJECT_ROOT" QWB_ROLE_PROFILE="$PROFILE"
export QWB_ROLE_PI_CONTROL QWB_ROLE_PI_INTEGRATION QWB_WORKSPACE QWB_WORKERS
python3 -B - "$@" <<'PY'
import argparse, contextlib, fcntl, hashlib, json, os, re, subprocess, sys, tempfile, time, uuid
from pathlib import Path

parser = argparse.ArgumentParser(description='角色与保留现场控制；同UID防误用，不是OS沙箱')
parser.add_argument('command', choices=['start','status','reconcile','retire','interrupt','exit','relaunch'])
parser.add_argument('--project')
parser.add_argument('--actor')
parser.add_argument('--role', choices=['门禁','规划','测试体系'])
parser.add_argument('--worker')
parser.add_argument('--dir')
parser.add_argument('--expect-gen', type=int)
a = parser.parse_args()
root = Path(os.environ['QWB_ROLE_ROOT'])
bindir = Path(os.environ['QWB_ROLE_BINDIR'])
base = root / 'qwbuddy'
state = base / '.roles'
r = None

class Refusal(Exception): pass

def require(test, reason):
    if not test: raise Refusal(reason)

def run(argv, check=True):
    p = subprocess.run(argv, capture_output=True, text=True)
    if check: require(p.returncode == 0, '命令失败/状态未知: ' + ' '.join(argv[:3]) + ': ' + p.stderr.strip())
    return p

def herdr(*args):
    p = run(['herdr', *args])
    try: j = json.loads(p.stdout)
    except ValueError: raise Refusal('Herdr响应不是JSON，不能确认状态')
    require(isinstance(j, dict) and isinstance(j.get('result'), dict), 'Herdr响应不符合契约')
    return j['result']

def safe(path, directory=False):
    require(not path.is_symlink(), '拒绝符号链接: ' + str(path))
    if path.exists():
        require(path.is_dir() if directory else path.is_file(), '路径类型非法: ' + str(path))
        require(path.resolve() == path.absolute(), '路径经符号链接重定向: ' + str(path))

def save():
    target = state / (r['actor'] + '.json'); safe(target)
    fd, tmp = tempfile.mkstemp(prefix='.role-', dir=state)
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(r, f, ensure_ascii=False, sort_keys=True); f.write('\n'); f.flush(); os.fsync(f.fileno())
        os.replace(tmp, target)
        fd = os.open(state, os.O_RDONLY)
        try: os.fsync(fd)
        finally: os.close(fd)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)

def phase(value, **changes):
    r.update(changes, phase=value, updated_at=int(time.time())); save()

def load(path):
    safe(path)
    try: d = json.loads(path.read_text())
    except (ValueError, OSError): raise Refusal('角色记录损坏: ' + str(path))
    require(isinstance(d, dict) and d.get('version') == 1 and d.get('actor') == path.stem and
            d.get('root') == str(root) and isinstance(d.get('incarnation'), int), '角色记录身份/schema未知')
    return d

def pane_info(pane):
    p = herdr('pane','get',pane).get('pane')
    require(isinstance(p,dict) and p.get('pane_id') == pane, 'pane身份未知/不匹配')
    return p

def process_info(pane):
    p = herdr('pane','process-info','--pane',pane).get('process_info')
    require(isinstance(p,dict) and p.get('pane_id') == pane and isinstance(p.get('foreground_processes'),list), '前台进程身份未知')
    return p

def stamp(pid):
    require(isinstance(pid,int) and pid > 0, 'PID非法')
    p = run(['ps','-p',str(pid),'-o','lstart='], check=False)
    require(p.returncode == 0 and bool(p.stdout.strip()), 'PID启动时间不可验证')
    return p.stdout.strip()

def native_process(proc, kind='pi'):
    matches = [p for p in proc['foreground_processes'] if isinstance(p,dict) and
               Path(p.get('argv0','')).name == kind and isinstance(p.get('pid'),int)]
    require(len(matches) == 1, '实际工具/PID未知或有多个实例')
    p = matches[0]; p['start'] = stamp(p['pid'])
    return p

def authorize():
    lock = base / '.controller.lock'; safe(lock, True)
    ownerfile = lock / 'owner'; safe(ownerfile)
    raw = ownerfile.read_text()
    match = re.fullmatch(r'\S+\s+(\S+)\s*', raw)
    require(match and match[1] == os.environ.get('HERDR_PANE_ID') and not match[1].startswith('pid:'), '调用者不是本项目实际主控锁owner')
    p = pane_info(match[1]); proc = process_info(match[1])
    require(p.get('agent') in ('pi','claude','codex') and p.get('agent_status') in ('idle','done','working','blocked'), '实际主控工具/运行态未知')
    native = native_process(proc, p['agent'])
    # Environment pane IDs are not authority: the native controller PID must be our ancestor.
    pid = os.getpid(); ancestors = set()
    for _ in range(64):
        if pid <= 1 or pid in ancestors: break
        ancestors.add(pid)
        if pid == native['pid']: break
        parent = run(['ps','-p',str(pid),'-o','ppid=']).stdout.strip()
        require(parent.isdigit(), '调用者进程祖先无法确认')
        pid = int(parent)
    require(native['pid'] in ancestors, '主控pane环境声明与真实调用者PID不匹配')
    return match[1], hashlib.sha256(raw.encode()).hexdigest()

def snapshot_dir(directory):
    d = Path(directory)
    require(d.is_dir() and str(d.resolve()) == directory, '原工作目录不存在或路径归属变化')
    top = run(['git','-C',directory,'rev-parse','--show-toplevel']).stdout.strip()
    require(Path(top).resolve() == d, '工作目录不是Git副本根')
    common = run(['git','-C',directory,'rev-parse','--path-format=absolute','--git-common-dir']).stdout.strip()
    parent_common = run(['git','-C',str(root),'rev-parse','--path-format=absolute','--git-common-dir']).stdout.strip()
    require(Path(common).resolve() == Path(parent_common).resolve(), '工作目录不属于本项目')
    return {'head':run(['git','-C',directory,'rev-parse','HEAD']).stdout.strip(),
            'status':run(['git','-C',directory,'status','--porcelain=v1','--untracked-files=all']).stdout}

def model_profile(profile):
    require(profile['mode'] == 'herdr' and profile['harness'] == 'pi', '仅Pi Herdr控制路径已核验；其他adapter明确拒绝，不改原派发配置')
    argv = profile['argv']
    # Accept explicit pins only; positional prompts, CLI/session overrides and unknown flags refuse.
    values = {}; i = 0
    while i < len(argv):
        token = argv[i]
        if token in ('--approve','--no-approve','--offline'): i += 1; continue
        require(token in ('--provider','--model','--thinking') and i+1 < len(argv) and token not in values, '角色worker须仅包含明确provider/model/thinking与批准参数，拒绝未知/重复/提示词参数')
        values[token] = argv[i+1]; i += 2
    model = values.get('--model',''); provider = values.get('--provider','')
    if '/' in model:
        prefix, model = model.split('/',1)
        require(not provider or prefix == provider, 'model/provider冲突'); provider = prefix
    require(provider and re.fullmatch(r'[a-zA-Z0-9_.-]+', provider) and re.fullmatch(r'[a-zA-Z0-9_.-]+', model), '模型不是精确provider/id')
    effort = values.get('--thinking','')
    require(effort in ('off','minimal','low','medium','high','xhigh','max'), '必须显式固定effort')
    return provider, model, effort

def adapter():
    require(os.environ.get('QWB_ROLE_PI_CONTROL') == 'verified', 'Pi控制尚未在本项目批准启用（QWB_ROLE_PI_CONTROL=verified）；不安装/自动启用')
    integration = Path(os.environ['QWB_ROLE_PI_INTEGRATION']); safe(integration)
    require(integration.is_file() and 'HERDR_INTEGRATION_ID=pi' in integration.read_text(), '缺已安装原生Herdr Pi集成，拒绝未知绑定')
    return str(integration)

def current(d, pending=False):
    require(bool(d.get('pane')), '尚无端点；保留prepared记录，需核对tab创建结果')
    p = pane_info(d['pane']); proc = process_info(d['pane'])
    require(p.get('workspace_id') == d['workspace'] and p.get('terminal_id') == d['terminal'], '端点归属/terminal发生变化')
    require(Path(p.get('foreground_cwd','')).resolve() == Path(d['dir']), 'pane目录与登记副本不符')
    shell = proc.get('shell_pid'); group = proc.get('foreground_process_group_id')
    if isinstance(shell,int) and shell > 0 and group == shell:
        require(any(x.get('pid') == shell and Path(x.get('argv0','')).name in ('bash','zsh','sh','fish') for x in proc['foreground_processes'] if isinstance(x,dict)), '不能确认端点已退回shell')
        # A shell foreground is not candidate death: a delivered Pi may be suspended/backgrounded.
        candidate = d.get('pending', {})
        attempted = candidate.get('attempted', d['phase'] not in ('prepared','pane-ready','stopped'))
        if pending and attempted:
            require(candidate.get('pid') and candidate.get('pid_start'), '候选启动已投递但本代PID归属/死亡证据未知；保留pending，不以shell猜死亡')
        require(d.get('pid') or (not attempted and d['phase'] in ('prepared','pane-ready')), '缺本代PID结束或可验证未投递证据，不能确认停止')
        if d.get('pid'):
            old = run(['ps','-p',str(d['pid']),'-o','lstart='], check=False)
            require((old.returncode == 1 and not old.stdout.strip() and not old.stderr.strip()) or
                    (old.returncode == 0 and bool(old.stdout.strip()) and old.stdout.strip() != d['pid_start']), '旧Pi PID仍在或死亡证据未知，不能认定结束')
        return {'activity':'stopped','proof':'foreground-shell+old-pid-ended' if d.get('pid') else 'owned-new-pane+launch-not-sent'}
    require(p.get('agent') == 'pi', '运行工具未知，拒绝认闲/认死')
    native = native_process(proc)
    require(Path(native.get('cwd','')).resolve() == Path(d['dir']), 'Pi进程目录归属不符')
    bound = not pending or bool(d.get('pending', {}).get('pid'))
    if bound:
        require(native['pid'] == d.get('pid') and native['start'] == d.get('pid_start'), '不是登记启动incarnation；不能采信迟到idle/完成')
    ref = p.get('agent_session')
    require(isinstance(ref,dict) and ref.get('agent') == 'pi' and ref.get('source') == 'herdr:pi' and ref.get('kind') == 'path', '原生session绑定未知')
    session = Path(ref.get('value',''))
    require(session.is_absolute() and session.parent == state / (d['actor']+'.sessions') and session.name.endswith('_'+d['session_id']+'.jsonl'), '原生session与本代登记不符')
    if bound: require(str(session) == d.get('session_path'), '原生session路径变化，拒绝旧事件')
    safe(session)
    require(p.get('agent_status') in ('idle','done','working','blocked'), '运行态未知，不能假报idle')
    require(p.get('scroll',{}).get('offset_from_bottom',0) == 0, 'viewport非末尾，实际模型无法核对')
    visible = run(['herdr','pane','read',d['pane'],'--source','visible']).stdout
    lines = [s.strip() for s in visible.splitlines() if s.strip()]
    require(lines and re.search(r'\('+re.escape(d['provider'])+r'\)\s+'+re.escape(d['model'])+r'\s+•\s+'+re.escape(d['effort'])+r'\s*$', lines[-1]), '当前Pi模型/effort页脚未证实匹配；不以启动argv冒充实际模型')
    return {'activity':p['agent_status'], 'pid':native['pid'], 'pid_start':native['start'], 'session_path':str(session),
            'actual_model':d['provider']+'/'+d['model'], 'actual_effort':d['effort'], 'proof':'native-session+pid-start+visible-footer'}

def obligations(d):
    found = []; panes = set(d.get('pane_history',[]) + [d.get('pane','')])
    for task in sorted((root/'tasks').glob('*.md')):
        safe(task)
        text = task.read_text()
        associated = any(re.search(r'\bpane='+re.escape(p)+r'(?=\s|$)', text) for p in panes if p)
        if '<!-- qwb-collab-' in text:
            p = run(['bash',str(bindir/'qwb-ledger.sh'),'read','--project',str(root),'--task',str(task)], check=False)
            if p.returncode: found.append({'task':str(task),'kind':'protocol-unknown'}); continue
            data = json.loads(p.stdout)
            claim = data.get('claim')
            associated = associated or bool(panes.intersection(data.get('workers',{})))
            if claim and (associated or claim.get('owner') in panes): found.append({'task':str(task),'kind':'claim','op_id':claim['op_id']})
            if associated:
                for key, question in data.get('questions',{}).items():
                    if not question.get('resumed'): found.append({'task':str(task),'kind':'unresolved-question','key':key})
        elif associated:
            match = re.search(r'^state:\s*(\S+)',text,re.M)
            if not match or match[1] not in ('done','verified'): found.append({'task':str(task),'kind':'legacy-unfinished'})
    inbox = state / (d['actor']+'.inbox'); safe(inbox, True)
    if inbox.exists():
        for msg in sorted(inbox.iterdir()):
            if msg.name.endswith('.msg'): found.append({'kind':'unhandled-instruction','path':str(msg)})
    return found

def result(d):
    out = dict(d)
    try:
        if d.get('pending'):
            out.update(activity='unknown', candidate_observation=current(dict(d,**d['pending']),pending=True))
        else: out.update(current(d))
    except (Refusal, OSError, ValueError, KeyError, TypeError) as e:
        out.pop('actual_model',None); out.pop('actual_effort',None)
        out.update(activity='unknown', conflict=str(e))
    out['obligations'] = obligations(d)
    return out

def launch():
    auth = authorize(); require(auth == (r['controller'],r['owner_fp']), '原启动主控代次已变化，需reconcile后再启动')
    integration = adapter()
    pending = r['pending']; d = dict(r, **pending)
    # Never retry a possibly delivered launch by guessing from a timeout.
    if pending.get('attempted', r['phase'] not in ('prepared','pane-ready','stopped')):
        observation = current(d, pending=True)
        require(observation['activity'] != 'stopped', '启动部分完成，尚无匹配实例；先显式exit核对旧运行，不能重送启动')
    else:
        require(current(r)['activity'] == 'stopped', '旧实例未证实结束，拒绝启动替身')
        sessions = state / (r['actor']+'.sessions'); safe(sessions, True); sessions.mkdir(exist_ok=True)
        argv = list(r['argv']) + ['--no-extensions','-e',integration,'--no-skills','--no-prompt-templates','--no-context-files','--no-approve','--offline',
                                  '--session-dir',str(sessions),'--append-system-prompt',r['charter']]
        if pending.get('resume_path'): argv += ['--session',pending['resume_path']]
        else: argv += ['--session-id',pending['session_id']]
        pending['attempted'] = True
        phase('launch-sent', exit='not-requested')
        p = run(['bash','-c','. "$1"; shift; qwb_start_worker "$@"','qwb-role',str(bindir/'qwb-lib.sh'),
                 r['agent_name'],r['pane'],'pi','30000',*argv], check=False)
        if p.returncode:
            phase('launch-uncertain', last_error=p.stderr.strip()); raise Refusal('启动未确认；记录与现场保留，先reconcile现实，不重发')
        observation = current(d, pending=True)
        require(observation['activity'] != 'stopped', '启动返回但未确认实际Pi')
    require(not r.get('pid') or observation['pid'] != r['pid'] or observation['pid_start'] != r['pid_start'], '仍是旧运行，不能发布新incarnation')
    r.update(pending); r.update(observation); r.pop('pending',None); r.pop('attempted',None); r.pop('last_error',None)
    phase('active')

def main():
    global r
    require(a.command == 'status' or (a.actor and re.fullmatch(r'[a-z][a-z0-9_-]{0,31}',a.actor)), 'actor须为英文slug')
    if a.actor: require(re.fullmatch(r'[a-z][a-z0-9_-]{0,31}',a.actor), 'actor非法')
    safe(base, True); require(base.is_dir(), '缺qwbuddy目录；不自动安装')
    safe(state, True)
    if not state.exists():
        if a.command == 'status': print(json.dumps({'roles':[]})); return
        authorize(); state.mkdir(mode=0o700, exist_ok=True); safe(state, True)
    # ponytail: serial role control, per-actor locks if launch concurrency matters.
    # Not the controller directory: ledger writers lock task then controller, reads here must not invert that order.
    with contextlib.ExitStack() as cleanup:
        guard = os.open(state, os.O_RDONLY); cleanup.callback(os.close, guard)
        fcntl.flock(guard, fcntl.LOCK_EX)
        require(os.fstat(guard).st_ino == state.stat().st_ino, '角色锁目录被替换')
        owner = authorize() if a.command != 'status' else None
        files = sorted(state.glob('*.json')) if not a.actor else [state/(a.actor+'.json')]
        if a.command == 'status':
            rows = [result(load(f)) for f in files if f.exists()]
            require(not a.actor or rows, '角色未登记')
            print(json.dumps(rows[0] if a.actor else {'roles':rows},ensure_ascii=False)); return
        target = files[0]
        if target.exists(): r = load(target)
        if a.command == 'start':
            require(a.role and a.worker and a.dir, 'start需role/worker/dir')
            profile = next((x for x in json.loads(os.environ['QWB_ROLE_PROFILE']) if x['worker'] == a.worker),None)
            require(profile is not None, '工人未配置')
            provider, model, effort = model_profile(profile); adapter()
            directory = str(Path(a.dir).resolve()); checkpoint = snapshot_dir(directory)
            if r:
                require(r['role'] == a.role and r['worker'] == a.worker and r['dir'] == directory and r['argv'] == profile['argv'], '重复start的角色/worker/目录/argv冲突')
                require(r['phase'] != 'retired', '已退休actor不能复用旧ID获得权限')
                if r.get('pending'): launch()
                else: require(current(r)['activity'] != 'stopped', '实例已结束；使用带expect-gen的relaunch保留现场恢复')
            else:
                charter_source = base/'roles'/(a.role+'.md'); safe(charter_source)
                charter_text = charter_source.read_text()
                workspace_script = '. "$1"; if [[ "$2" == "$3" ]]; then resolve_workspace "$2"; else qwb_is_project_worktree "$2" "$3" || exit 1; qwb_worktree_space "$2" "$3"; fi'
                workspace = run(['bash','-c',workspace_script,'qwb-role',str(bindir/'qwb-lib.sh'),str(root),directory]).stdout.strip()
                require(workspace, '须有唯一已登记workspace，不回退focused默认窗口')
                r = dict(version=1,actor=a.actor,root=str(root),role=a.role,scope='single-project',
                         allowed_actions=['status','proposal','test'] if a.role=='测试体系' else ['status','proposal'],
                         worker=a.worker,argv=profile['argv'],tool='pi',provider=provider,model=model,effort=effort,
                         dir=directory,workspace=workspace,controller=owner[0],owner_fp=owner[1],incarnation=0,
                         agent_name='qwb-role-'+a.actor,checkpoint=checkpoint,pane_history=[],
                         pending=dict(incarnation=1,session_id=uuid.uuid4().hex))
                charter = state/(a.actor+'.charter.md'); safe(charter)
                require(not charter.exists(), '孤立charter保留待核对，拒绝覆盖')
                charter.write_text(charter_text+'\n## 实际角色绑定与恢复\n'+
                                   f'actor={a.actor}，登记={target}；未处理指令={state/(a.actor+".inbox")}。\n'+
                                   f'任务与持久义务从{root}/tasks及qwb-ledger read核对。启动/恢复先读登记及原义务，不丢WIP。\n'+
                                   '仅主控派工；闲置不造票、不调用模型、不派工、不起全项目watcher；未授权验收/合并。\n')
                r['charter'] = str(charter); r['charter_sha256'] = hashlib.sha256(charter.read_bytes()).hexdigest()
                phase('prepared')
                tab = herdr('tab','create','--workspace',workspace,'--cwd',directory,'--label',a.role,'--no-focus').get('root_pane')
                require(isinstance(tab,dict) and all(isinstance(tab.get(k),str) and tab[k] for k in ('pane_id','tab_id','terminal_id')), '建tab响应缺身份；prepared记录保留，禁止重建')
                phase('pane-ready',pane=tab['pane_id'],tab=tab['tab_id'],terminal=tab['terminal_id'],pane_history=[tab['pane_id']])
                launch()
        else:
            require(r is not None, '角色未登记')
            require(a.expect_gen is not None and a.expect_gen == r['incarnation'], '旧代际/缺expect-gen，拒绝推进当前实例')
            require(r['phase'] != 'retired' or a.command == 'retire', '已退休角色不可控制/恢复')
            control_target = dict(r, **r.get('pending',{}))
            observation = current(control_target, pending=bool(r.get('pending')))
            if observation['activity'] != 'stopped':
                control_target.update(observation)
                if r.get('pending'):
                    r['pending'].update(observation); save()  # 本代原生PID证据独立保存，不能借前代PID确认死亡。
            if a.command == 'reconcile':
                if r.get('pending'): launch()
                else: phase(r['phase'], activity=observation['activity'], controller=owner[0],owner_fp=owner[1])
            elif a.command == 'retire':
                require(not obligations(r), '角色仍持claim/未交接问题或指令，拒绝退休')
                require(observation['activity'] == 'stopped', '角色仍活，退休不会自动关闭它')
                phase('retired',activity='retired')
            elif a.command == 'interrupt':
                adapter(); require(observation['activity'] != 'stopped', '原Pi已结束，不能送键到shell')
                phase('interrupt-sent', cancel='unconfirmed')
                herdr('pane','send-keys',r['pane'],'esc')
                phase('interrupt-delivered', cancel='unconfirmed')
            elif a.command == 'exit':
                adapter()
                if observation['activity'] != 'stopped':
                    require(observation['activity'] in ('idle','done'), '先interrupt并核对idle，不能把退出文字输入工作中的agent')
                    visible = run(['herdr','pane','read',r['pane'],'--source','visible']).stdout
                    borders = [i for i,s in enumerate(visible.splitlines()) if re.fullmatch(r'\s*─{8,}\s*',s)]
                    require(len(borders) >= 2 and all(not s.strip() for s in visible.splitlines()[borders[-2]+1:borders[-1]]), 'composer未证实为空，拒绝覆盖/拼接未提交输入')
                    require(current(control_target)['pid'] == observation['pid'], '送退出前PID发生变化')
                    phase('exit-sent',exit='unconfirmed')
                    herdr('pane','run',r['pane'],'/quit')
                    for _ in range(20):
                        time.sleep(.1)
                        observation = current(control_target)
                        if observation['activity'] == 'stopped': break
                    require(observation['activity'] == 'stopped', '退出已投递但原PID结束未确认；端点/记录保留')
                r.pop('pending',None)
                for key in ('session_id','session_path','pid','pid_start'):
                    if key in control_target: r[key] = control_target[key]
                phase('stopped',activity='stopped',exit='confirmed',cancel=r.get('cancel','not-requested'))
            elif a.command == 'relaunch':
                adapter(); require(observation['activity'] == 'stopped', '旧运行死亡未证实，不启动替身')
                require(not r.get('pending'), '已有部分启动，先reconcile/exit核对，不换gen重启')
                blocked = [x for x in obligations(r) if x['kind'] in ('claim','protocol-unknown','legacy-unfinished')]
                require(not blocked, '旧claim归属/旧写者未处理，拒绝新gen；不清claim')
                profile = next((x for x in json.loads(os.environ['QWB_ROLE_PROFILE']) if x['worker'] == r['worker']),None)
                require(profile is not None and profile['argv'] == r['argv'], '原worker配置变化，不擅改模型/effort')
                model_profile(profile)
                checkpoint = snapshot_dir(r['dir'])
                require(hashlib.sha256(Path(r['charter']).read_bytes()).hexdigest() == r['charter_sha256'], '持久职责已变化，需主控核对')
                pending = dict(incarnation=r['incarnation']+1,session_id=uuid.uuid4().hex)
                session = Path(r['session_path']) if r.get('session_path') else None
                if session is not None: safe(session)
                if session is not None and session.exists():
                    header = json.loads(session.read_text().splitlines()[0])
                    require(header.get('type') == 'session' and header.get('id') == r['session_id'] and Path(header.get('cwd','')).resolve() == Path(r['dir']), '原session文件身份未知，拒绝恢复')
                    pending.update(session_id=r['session_id'],resume_path=str(session))
                phase('stopped',controller=owner[0],owner_fp=owner[1],checkpoint=checkpoint,pending=pending)
                launch()
        print(json.dumps(result(r),ensure_ascii=False))

try: main()
except (Refusal,OSError,ValueError,KeyError,TypeError) as e:
    # Keep a locator and partial phase; never erase the old generation, claims, pane or checkout.
    if r is not None and a.command != 'status':
        try: r['last_error'] = str(e); save()
        except OSError: pass
    print('拒绝: '+str(e), file=sys.stderr); sys.exit(1)
PY
