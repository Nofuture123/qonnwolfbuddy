#!/usr/bin/env bash
# 生产生命周期定向回归；临时项目与子进程由 Python finally 回收。
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/process-fixture.sh"
qwb_test_scope "$@"
export TMPDIR="${QWB_TEST_SCOPE_DIR}"
mkdir -p "$TMPDIR" || exit 1
export GIT_CEILING_DIRECTORIES="$TMPDIR"
# Fail closed even if the PATH stub disappears.
export HERDR_SOCKET_PATH=/dev/null/qwb-test.sock
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${QWB_LIFECYCLE_SOURCE:-$REPO}"
python3 - "$ROOT" "$REPO" <<'PY'
from process_fixture import TemporaryDirectory
import hashlib
import os
from pathlib import Path
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time

source = Path(sys.argv[1])
repo = Path(sys.argv[2])
with TemporaryDirectory(prefix="qwb-lifecycle-") as tmp:
    os.environ["TMPDIR"] = tmp
    project = Path(tmp)
    qwb = project / "qwbuddy"
    (qwb / "bin").mkdir(parents=True)
    (project / "tasks").mkdir()
    for name in ("qwb-wake.sh", "qwb-lib.sh", "qwb-herdr.sh", "qwb-ledger.sh", "qwb-hook-claude-stop.sh"):
        shutil.copy2(source / "bin" / name, qwb / "bin" / name)
    (qwb / "config.sh").write_text('QWB_WAKE_INTERVAL_MS=100\nQWB_REWAKE_MS=0\n')
    lock = qwb / ".controller.lock"
    lock.mkdir()
    (lock / "owner").write_text("x wT:p1\n")
    task = project / "tasks" / "2099-01-01-case.md"
    old = "working: old"
    fp = hashlib.sha1(("running\n" + old).encode()).hexdigest()
    task.write_text(f"# case\nstate: running\n{old}\nwake: 2026-01-01T00:00:00Z state=running fp={fp}\n")
    host = child = None
    try:
        # 真实 Bash 宿主派生真实 qwb-wake；SIGKILL 宿主后追加新进展。
        pidfile = project / "child.pid"
        host = subprocess.Popen([
            "bash", "-c", 'QWB_WATCH_PARENT_PID=$$ HERDR_PANE_ID=wT:p1 bash "$1" --project "$2" --block & echo $! > "$3"; wait',
            "host", str(qwb / "bin" / "qwb-wake.sh"), str(project), str(pidfile),
        ], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        for _ in range(100):
            if pidfile.exists(): break
            time.sleep(.01)
        assert pidfile.exists(), "真实子进程没有启动"
        child = int(pidfile.read_text())
        time.sleep(.2)
        assert subprocess.run(["kill", "-0", str(child)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0
        os.kill(host.pid, signal.SIGKILL)
        host.wait(timeout=2)
        with task.open("a") as f: f.write("working: after-host-death\n")
        for _ in range(100):
            child_stat = subprocess.run(["ps", "-o", "stat=", "-p", str(child)], capture_output=True, text=True).stdout.strip()
            if not child_stat or child_stat.startswith("Z"):
                break
            time.sleep(.05)
        stat = subprocess.run(["ps", "-o", "stat=", "-p", str(child)], capture_output=True, text=True).stdout.strip()
        assert not stat or stat.startswith("Z"), f"孤儿仍活：pid={child} stat={stat}"
        assert task.read_text().count("wake:") == 1, "宿主死亡后孤儿写了新 wake"
        print("PASS  真实宿主 SIGKILL：子进程退出，后续进展未被消费")
    finally:
        if host and host.poll() is None:
            host.kill(); host.wait(timeout=2)
        if child:
            stat = subprocess.run(["ps", "-o", "stat=", "-p", str(child)], capture_output=True, text=True).stdout.strip()
            if stat and not stat.startswith("Z"):
                os.kill(child, signal.SIGKILL)

    # 真实 Node 扩展宿主：强退后孤儿按实例清登记；新宿主登记不得被旧孤儿删掉。
    host_script = project / "pi-host.mjs"
    host_script.write_text(f'''import watch from "{(source / "templates" / "pi-extensions" / "qwb-watch.ts").as_uri()}";
process.chdir("{project}");
const handlers = {{}};
watch({{ on: (event, cb) => {{ handlers[event] = cb; }}, sendUserMessage: () => {{}} }});
await handlers.session_start();
setInterval(() => {{}}, 1000);
''')
    sleeper = project / "sleep-gate.sh"
    sleeper.write_text('''#!/usr/bin/env bash
touch "$SLEEP_MARKER"
while [[ ! -e "$SLEEP_RELEASE" ]]; do sleep 0.01; done
''')
    sleeper.chmod(0o755)
    for protect_new in (False, True):
        task.write_text(f"# case\nstate: running\n{old}\nwake: 2026-01-01T00:00:00Z state=running fp={fp}\n")
        marker = project / ("sleep-new" if protect_new else "sleep-old")
        release = project / ("release-new" if protect_new else "release-old")
        watchfile = qwb / ".watch"
        if watchfile.exists(): watchfile.unlink()
        (lock / "owner").write_text("x wT:p1\n")
        env = {**os.environ, "HERDR_PANE_ID": "wT:p1", "QWB_WAKE_INTERVAL_MS": "100",
               "QWB_SLEEP_CMD": str(sleeper), "SLEEP_MARKER": str(marker), "SLEEP_RELEASE": str(release)}
        pi_host = subprocess.Popen(["node", str(host_script)], env=env,
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        pi_child = None
        try:
            for _ in range(200):
                if watchfile.exists() and marker.exists(): break
                time.sleep(.01)
            assert watchfile.exists() and marker.exists(), "真实扩展未启动并登记值守"
            registered = watchfile.read_text()
            pi_child = int(re.search(r"pid=(\d+)", registered).group(1))
            assert "kind=pi-ext" in registered
            os.kill(pi_host.pid, signal.SIGKILL)
            assert pi_host.wait(timeout=2) == -signal.SIGKILL
            with task.open("a") as f: f.write("working: after-real-pi-death\n")
            if protect_new:
                (lock / "owner").write_text("x wT:p2\n")
                newer = f"kind=pi-ext pid={os.getpid()} instance=successor started=new cmd=new\n"
                subprocess.run(["perl", "-MFcntl=:flock", "-e", '''
                    my ($dir, $line) = @ARGV;
                    open my $guard, "<", $dir or die $!;
                    flock($guard, LOCK_EX) or die $!;
                    open my $out, ">", "$dir/.watch" or die $!;
                    print {$out} $line;
                ''', str(qwb), newer], check=True)
            release.write_text("go")
            for _ in range(200):
                stat = subprocess.run(["ps", "-o", "stat=", "-p", str(pi_child)], capture_output=True, text=True).stdout.strip()
                if not stat or stat.startswith("Z"): break
                time.sleep(.01)
            assert not stat or stat.startswith("Z"), "真实扩展孤儿未退出"
            if protect_new:
                assert watchfile.read_text() == newer, "旧孤儿清掉了新宿主登记"
            else:
                assert not watchfile.exists(), "宿主 SIGKILL 后仍残留旧 Pi 登记"
            assert task.read_text().count("wake:") == 1, "宿主死亡后写入新 wake"
        finally:
            release.write_text("go")
            if pi_host.poll() is None: pi_host.kill(); pi_host.wait(timeout=2)
            if pi_child:
                stat = subprocess.run(["ps", "-o", "stat=", "-p", str(pi_child)], capture_output=True, text=True).stdout.strip()
                if stat and not stat.startswith("Z"): os.kill(pi_child, signal.SIGKILL)
    print("PASS  真实 Pi 扩展宿主 SIGKILL：孤儿条件清旧登记且保护新实例")
    (lock / "owner").write_text("x wT:p1\n")

    # 两个 hook 同时接管残留死锁；只有一个真实子进程进入值守。
    hooklock = qwb / ".hook.lock"
    hooklock.mkdir()
    (hooklock / "pid").write_text("99999999\n")
    stub = qwb / "bin" / "qwb-wake.sh"
    stub.write_text(f'''#!/usr/bin/env bash
mkdir "{project / 'cycle-active'}" || exit 75
trap 'rmdir "{project / 'cycle-active'}"' EXIT
echo "$$" >> "{project / 'entered'}"
sleep 0.4
[[ $(wc -l < "{project / 'entered'}") -gt 1 ]] && exit 0
exit 124
''')
    racebin = project / "racebin"
    racebin.mkdir()
    race_rm = racebin / "rm"
    race_rm.write_text('''#!/usr/bin/env bash
if [[ "$*" == *".hook.lock"* && ! -e "$HOOK_RACE_DIR/reached" ]]; then
  touch "$HOOK_RACE_DIR/reached"
  while [[ ! -e "$HOOK_RACE_DIR/release" ]]; do sleep 0.01; done
fi
exec /bin/rm "$@"
''')
    race_rm.chmod(0o755)
    hooks = []
    try:
        hook_env = {**os.environ, "HERDR_PANE_ID": "wT:p1", "HOOK_RACE_DIR": str(project),
                    "PATH": str(racebin) + os.pathsep + os.environ["PATH"]}
        hooks.append(subprocess.Popen(["bash", str(qwb / "bin" / "qwb-hook-claude-stop.sh")],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=hook_env))
        for _ in range(100):
            if (project / "reached").exists(): break
            time.sleep(.01)
        assert (project / "reached").exists(), "A 未进入旧锁回收临界区"
        hooks.append(subprocess.Popen(["bash", str(qwb / "bin" / "qwb-hook-claude-stop.sh")],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=hook_env))
        time.sleep(.1)
        assert not (project / "entered").exists(), "A 尚未放行即启动值守"
        (project / "release").write_text("go")
        for h in hooks: assert h.wait(timeout=3) == 0
        entered = project / "entered"
        assert entered.exists() and len(entered.read_text().splitlines()) == 2, "正常124未接续一个周期或并发hook重复启动"
        assert not hooklock.exists(), "hook 正常退出后遗留锁"
        print("PASS  A 判死回收暂停、B 竞争：单飞，正常124排空后接一个周期")
    finally:
        for h in hooks:
            if h.poll() is None: h.kill(); h.wait(timeout=2)

    stub.write_text('#!/usr/bin/env bash\necho cycle >> "' + str(project / 'expired') + '"\nexit 124\n')
    expired=subprocess.run(['bash',str(qwb / 'bin' / 'qwb-hook-claude-stop.sh')],env=hook_env,
        stdin=subprocess.DEVNULL,capture_output=True,text=True,timeout=3)
    assert expired.returncode==2 and '接班未就绪' in expired.stderr
    assert len((project / 'expired').read_text().splitlines())==2, '124接班不是有限修复'
    assert not hooklock.exists() and '连续两周期' in (qwb / '.hook.err').read_text()
    print('PASS  Claude双124有限接班，无健康证据显式故障')

    # 第二次124：真实短周期、旧基点逐字节对照及受控失败；沿用本文件的进程隔离。
    baseline_hook = subprocess.run(
        ['git', '-C', str(repo), 'show', 'd01ddca:bin/qwb-hook-claude-stop.sh'],
        capture_output=True, check=True).stdout
    current_hook = (source / 'bin/qwb-hook-claude-stop.sh').read_bytes()
    clock = project / 'HookClock.pm'
    frozen_at = subprocess.check_output(['date', '-u', '+%Y-%m-%dT%H:%M:%SZ']).decode().strip()
    clock.write_text('''package HookClock;
use POSIX ();
no warnings 'redefine';
my $original = \\&POSIX::strftime;
*POSIX::strftime = sub {
    return $ENV{HOOK_FROZEN_AT} if $_[0] eq '%Y-%m-%dT%H:%M:%SZ';
    return $original->(@_);
};
1;
''')

    def hook_case(name, states):
        p = project / ('hook-' + name)
        (p / 'tasks').mkdir(parents=True)
        shutil.copytree(source / 'bin', p / 'qwbuddy/bin')
        for template in ('TASK.md', 'QWBUDDY.md'):
            shutil.copy2(source / 'templates' / template, p / 'qwbuddy' / template)
        shutil.copytree(source / 'templates/roles', p / 'qwbuddy/roles')
        (p / 'qwbuddy/config.sh').write_text('QWB_HOOK_MAX_MS=200\nQWB_WAKE_INTERVAL_MS=10\nQWB_REWAKE_MS=0\n')
        # 只冻结本组订阅外部边界，避免接入耗时诊断混入逐字节对照；真实值守/扫描仍运行。
        (p / 'qwbuddy/bin/qwb-herdr.sh').write_text('''#!/bin/bash
while [[ $# -gt 0 ]]; do
  if [[ "$1" == --notice ]]; then printf 'fixture-ready\\n' > "$2"; exit 0; fi
  shift
done
exit 77
''')
        owner = p / 'qwbuddy/.controller.lock/owner'
        owner.parent.mkdir(); owner.write_text('fixture wT:p1\n')
        fakebin = p / 'fakebin'; fakebin.mkdir()
        (fakebin / 'herdr').write_text('#!/bin/sh\necho "$@" >> "$HOOK_HERDR_LOG"\nexit 77\n')
        (fakebin / 'lsof').write_text('#!/bin/sh\nexit 1\n')
        (fakebin / 'date').write_text('#!/bin/sh\nif [ "$1" = -u ]; then echo "$HOOK_FROZEN_AT"; else exec /bin/date "$@"; fi\n')
        for f in fakebin.iterdir(): f.chmod(0o755)
        for i, state in enumerate(states):
            effective = state if state in ('running', 'blocked', 'needs-decision', 'done', 'verified') else 'needs-decision'
            fingerprint = hashlib.sha1((effective + '\nworking: old').encode()).hexdigest()
            (p / 'tasks' / f'case-{i}.md').write_text(
                f'# fixture\nstate: {state}\nworking: old\nwake: {frozen_at} state={effective} fp={fingerprint}\n')
        (p / 'qwbuddy/.hook.err').write_bytes(b'previous error\n')
        env = {**os.environ, 'HERDR_PANE_ID': 'wT:p1', 'TMPDIR': str(p),
               'PATH': str(fakebin) + os.pathsep + os.environ['PATH'],
               'HOOK_HERDR_LOG': str(p / 'herdr.log'), 'HOOK_FROZEN_AT': frozen_at,
               'PERL5LIB': str(project), 'PERL5OPT': '-MHookClock'}
        return p, env

    def hook_run(p, env):
        # Popen保留PID；本文件已有监督器登记整个进程组，异常时先排空再删临时目录。
        h = subprocess.Popen(['/bin/bash', str(p / 'qwbuddy/bin/qwb-hook-claude-stop.sh')],
            stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
        try:
            out, err = h.communicate(timeout=15)
        finally:
            if h.poll() is None: h.terminate(); h.wait(timeout=3)
        assert not (p / 'qwbuddy/.hook.lock').exists(), f'{p.name}: hook锁未释放 pid={h.pid}'
        return h.returncode, out, err

    def snapshot(p, result):
        return (result, (p / 'qwbuddy/.hook.err').read_bytes(),
                {f.name: f.read_bytes() if f.is_file() else None for f in (p / 'tasks').iterdir()})

    for name, states in [('decision', ['needs-decision']), ('blocked', ['blocked']),
                         ('mixed-waiting', ['blocked', 'needs-decision']), ('invalid', ['bogus']),
                         ('empty-state', ['']), ('closed', ['needs-decision', 'done', 'verified'])]:
        p, env = hook_case(name, states)
        before = snapshot(p, None)[1:]
        result = hook_run(p, env)
        assert result == (0, b'', b''), (name, result)
        assert snapshot(p, None)[1:] == before, f'{name}: 安静退出改了账本或错误日志'
        print('PASS  hook quiet ' + name + ': rc0/empty streams/unchanged errors and tickets/unlocked')
        if name == 'decision':
            with (p / 'tasks/case-0.md').open('a') as f: f.write('working: new-fact-after-quiet\n')
            result = hook_run(p, env)
            assert result[0] == 2 and result[1] == result[2] and b'case-0' in result[1], result
            assert b'new-fact-after-quiet' in result[1]
            assert (p / 'tasks/case-0.md').read_bytes().count(b'wake:') == 2
            assert (p / 'qwbuddy/.hook.err').read_bytes() == before[0]
            print('PASS  hook quiet then new progress: immediate rc2/ticket named/new wake recorded')

    for damage in ('body', 'state'):
        p, env = hook_case('bad-utf8-' + damage, ['running'])
        env['LC_ALL'] = 'en_US.UTF-8'
        bad = p / 'tasks/case-0.md'
        content = bad.read_bytes().replace(b'state=running fp=', b'state=needs-decision fp=').replace(
            hashlib.sha1(b'running\nworking: old').hexdigest().encode(),
            hashlib.sha1(b'needs-decision\nworking: old').hexdigest().encode())
        bad.write_bytes(content + b'\xff\n' if damage == 'body' else content.replace(b'state: running', b'state: \xff'))
        before = snapshot(p, None)[1:]
        result = hook_run(p, env)
        assert result == (0, b'', b''), (damage, result)
        assert snapshot(p, None)[1:] == before
        print('PASS  hook quiet damaged UTF-8 ' + damage + ': needs-decision even in UTF-8 locale')

    def byte_compare(name, states, configure=None, prepare=None):
        p, env = hook_case(name, states)
        if prepare: prepare(p, env)
        q = p / 'qwbuddy'; hook = q / 'bin/qwb-hook-claude-stop.sh'
        initial = {f.name: f.read_bytes() for f in (p / 'tasks').iterdir()}
        original_lib = (q / 'bin/qwb-lib.sh').read_bytes()
        results = []
        for version in (baseline_hook, current_hook):
            hook.write_bytes(version)
            (q / 'bin/qwb-lib.sh').write_bytes(original_lib)
            for f in (p / 'tasks').iterdir():
                if f.is_dir(): shutil.rmtree(f)
                else: f.unlink()
            for name_, content in initial.items(): (p / 'tasks' / name_).write_bytes(content)
            (q / '.hook.err').write_bytes(b'previous error\n')
            counter = p / 'cycles'
            if counter.exists(): counter.unlink()
            extra = configure(p, env) if configure else {}
            result = hook_run(p, {**env, **(extra or {})})
            if (p / 'tasks-saved').exists():
                (p / 'tasks-saved').rename(p / 'tasks')
            results.append(snapshot(p, result))
        assert results[0] == results[1], (p.name, results)
        print('PASS  hook baseline d01ddca byte equality ' + p.name + ': stdout/stderr/rc/errors/tickets')
        return p, results[1][0]

    for name, states in [('running', ['running']), ('running-mixed', ['running', 'needs-decision'])]:
        p, result = byte_compare(name, states)
        assert result[0] == 2 and result[1] == b'' and '值守接班未就绪'.encode() in result[2]
        assert '连续两周期到期'.encode() in (p / 'qwbuddy/.hook.err').read_bytes()

    def migrated(p, env):
        # 真实迁移和持久transport预算耗尽：无到期可投递事件，真实--block两次124。
        import json
        t = p / 'tasks/case-0.md'; manifest = p / 'migration.json'
        manifest.write_text(json.dumps({'task_sha256': hashlib.sha256(t.read_bytes()).hexdigest(),
            'confirm': {k: 'fixture stopped; no external actions' for k in
                        ['run', 'wake', 'worktree', 'worker', 'controller', 'old-fds', 'external-actions']}}))
        def call(script, *args):
            r = subprocess.run(['/bin/bash', str(p / 'qwbuddy/bin' / script), *args],
                env=env, capture_output=True, text=True, timeout=15)
            assert r.returncode == 0, (r.stdout, r.stderr)
            return r.stdout
        call('qwb-ledger.sh', 'migrate', '--project', str(p), '--task', str(t), '--', str(manifest))
        pending = json.loads(call('qwb-send.sh', 'pending', '--project', str(p), '--task', str(t)))
        assert pending, '已迁夹具缺真实待办'
        for event in pending:
            for _ in range(3):
                call('qwb-send.sh', 'transport', '--project', str(p), '--task', str(t), '--event', event['event_id'])
        assert json.loads(call('qwb-send.sh', 'pending', '--project', str(p), '--task', str(t),
                               '--due', '--retry-ms', '10')) == []
    p, result = byte_compare('migrated', ['needs-decision'], prepare=migrated)
    assert result[0] == 2
    p, result = byte_compare('migrated-done-with-obligations', ['done'], prepare=migrated)
    assert result[0] == 2

    def wake_stub(p, body):
        (p / 'qwbuddy/bin/qwb-wake.sh').write_text(
            '#!/bin/bash\nroot="$(cd "$(dirname "$0")/../.." && pwd)"\n'
            'echo cycle >> "$root/cycles"\n' + body)

    for failure in ('directory', 'scan-error', 'scan-diagnostic', 'unparseable'):
        def inject(p, env, failure=failure):
            if failure == 'directory':
                second = 'mv "$root/tasks" "$root/tasks-saved"\n'
            else:
                definition = {'scan-error': 'qwb_ledger_scan() { return 7; }',
                              'scan-diagnostic': 'qwb_ledger_scan() { echo "scan read error" >&2; return 0; }',
                              'unparseable': 'qwb_ledger_scan() { echo "invalid scan"; }'}[failure]
                second = "printf '%s\\n' '" + definition + "' >> \"$root/qwbuddy/bin/qwb-lib.sh\"\n"
            wake_stub(p, 'if [[ $(wc -l < "$root/cycles") -eq 2 ]]; then\n' + second + 'fi\nexit 124\n')
        p, result = byte_compare('failure-' + failure, ['needs-decision'], inject)
        assert result[0] == 2 and len((p / 'cycles').read_text().splitlines()) == 2
    # scanner原有读错返回0：一张可读旧票加一个.md目录，不能静默忽略读失败。
    def unreadable(p, env):
        (p / 'tasks/unreadable.md').mkdir()
        wake_stub(p, 'exit 124\n')
    p, result = byte_compare('unreadable-file', ['needs-decision'], unreadable)
    assert result[0] == 2

    p, result = byte_compare('empty', [])
    assert result == (0, b'', b'')
    def new_fact(p, env):
        with (p / 'tasks/case-0.md').open('a') as f: f.write('working: new fact\n')
    p, result = byte_compare('new-progress', ['needs-decision'], new_fact)
    assert result[0] == 2 and result[1] == result[2]
    def not_owner(p, env): return {'HERDR_PANE_ID': 'other'}
    p, result = byte_compare('non-owner', ['needs-decision'], not_owner)
    assert result == (0, b'', b'')
    def occupied(p, env):
        d = p / 'qwbuddy/.hook.lock'; d.mkdir()
        (d / 'pid').write_text(str(os.getpid()) + '\n'); (d / 'token').write_text('held\n')
        # 外部活锁必须保留；hook_run仅对自己持有的锁要求释放。
        return {}
    # 单飞在既有竞争测试覆盖；这里逐字节比对活锁且不套用释放自有锁断言。
    p, env = hook_case('occupied', ['needs-decision']); occupied(p, env)
    snapshots = []
    for version in (baseline_hook, current_hook):
        (p / 'qwbuddy/bin/qwb-hook-claude-stop.sh').write_bytes(version)
        r = subprocess.run(['/bin/bash', str(p / 'qwbuddy/bin/qwb-hook-claude-stop.sh')],
            stdin=subprocess.DEVNULL, capture_output=True, env=env, timeout=3)
        assert (p / 'qwbuddy/.hook.lock/pid').read_text() == str(os.getpid()) + '\n'
        snapshots.append(snapshot(p, (r.returncode, r.stdout, r.stderr)))
    assert snapshots[0] == snapshots[1] and snapshots[1][0] == (0, b'', b'')
    print('PASS  hook baseline d01ddca byte equality occupied lock: external owner preserved')
    def abnormal(p, env): wake_stub(p, 'echo actual-error >&2\nexit 7\n')
    p, result = byte_compare('abnormal', ['needs-decision'], abnormal)
    assert result == (0, b'', b'') and b'rc=7' in (p / 'qwbuddy/.hook.err').read_bytes()
    def second_progress(p, env):
        wake_stub(p, '''if [[ $(wc -l < "$root/cycles") -eq 1 ]]; then exit 124; fi
printf 'working: second-cycle progress\\n' >> "$root/tasks/case-0.md"
exec /bin/bash "$root/qwbuddy/bin/qwb-wake-real.sh" "$@"
''')
        shutil.copy2(source / 'bin/qwb-wake.sh', p / 'qwbuddy/bin/qwb-wake-real.sh')
    p, result = byte_compare('second-cycle-progress', ['needs-decision'], second_progress)
    assert result[0] == 2 and b'second-cycle progress' in result[1]
    assert len((p / 'cycles').read_text().splitlines()) == 2

    # 假 Herdr：主控在 A，项目值守在 B。三次 ensure 验证创建、复用、失活重启。
    import json
    shutil.copy2(Path(os.environ.get("QWB_LIFECYCLE_CROSS_WAKE", source / "bin" / "qwb-wake.sh")), stub)
    (qwb / "config.sh").write_text('QWB_WORKSPACE="wB"\nQWB_WAKE_INTERVAL_MS=100\n')
    fakebin = project / "fakebin"
    fakebin.mkdir()
    statefile = project / "herdr-state.json"
    statefile.write_text(json.dumps({"created": False, "active": False, "creates": 0, "runs": 0, "target": "wA:pCtl"}))
    fake = fakebin / "herdr"
    fake.write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
sfile = Path(os.environ["FAKE_HERDR_STATE"])
s = json.loads(sfile.read_text())
a = sys.argv[1:]
project = os.environ["FAKE_PROJECT"]
if a[:2] == ["workspace", "list"]:
    out = {"result": {"workspaces": [{"workspace_id": "wA"}, {"workspace_id": "wB"}]}}
elif a[:2] == ["pane", "get"]:
    pane = a[2]
    if pane == "wB:pWatch" and os.getenv("FAKE_FAIL_WATCH_GET"):
        print("query failure", file=sys.stderr); sys.exit(1)
    if pane == "wA:pCtl": ws = "wA"
    elif pane == "wB:pWatch" and s["created"]: ws = "wB"
    else: print("pane_not_found", file=sys.stderr); sys.exit(1)
    out = {"result": {"pane": {"workspace_id": ws, "cwd": project}}}
elif a[:2] == ["pane", "list"]:
    if os.getenv("FAKE_FAIL_LIST"): print("query failure", file=sys.stderr); sys.exit(1)
    panes = [{"pane_id": "wA:pCtl", "workspace_id": "wA", "agent": "pi"}]
    if s["created"]: panes.append({"pane_id": "wB:pWatch", "workspace_id": "wB"})
    out = {"result": {"panes": panes}}
elif a[:2] == ["pane", "process-info"]:
    if not s["created"]: print("pane_not_found", file=sys.stderr); sys.exit(1)
    pi = {"foreground_process_group_id": 1, "shell_pid": 1, "foreground_processes": []}
    if s["active"]:
        pi["foreground_process_group_id"] = 2
        pi["foreground_processes"] = [{"pid": 123, "argv0": "bash", "cwd": project,
            "cmdline": f"bash {project}/qwbuddy/bin/qwb-wake.sh --project {project} --pane {s['target']} --interval 100",
            "argv": ["bash", f"{project}/qwbuddy/bin/qwb-wake.sh", "--project", project, "--pane", s["target"], "--interval", "100"]}]
    out = {"result": {"process_info": pi}}
elif a[:2] == ["tab", "create"]:
    assert a[a.index("--workspace") + 1] == "wB"
    s["created"] = True; s["creates"] += 1
    out = {"result": {"root_pane": {"pane_id": "wB:pWatch"}}}
elif a[:2] == ["pane", "run"]:
    s["active"] = True; s["runs"] += 1
    out = {"result": {}}
else:
    print("unexpected herdr args: " + repr(a), file=sys.stderr); sys.exit(1)
sfile.write_text(json.dumps(s))
print(json.dumps(out))
''')
    fake.chmod(0o755)
    env = {**os.environ, "PATH": str(fakebin) + os.pathsep + os.environ["PATH"],
           "HERDR_WORKSPACE_ID": "wA", "HERDR_PANE_ID": "wA:pCtl",
           "FAKE_HERDR_STATE": str(statefile), "FAKE_PROJECT": str(project)}
    cmd = ["bash", str(stub), "--project", str(project), "--ensure", "--pane", "wA:pCtl"]
    def ensure(): return subprocess.run(cmd, env=env, capture_output=True, text=True)
    first = ensure()
    assert first.returncode == 0, f"跨 workspace 首次创建失败：{first.stdout} {first.stderr}"
    assert "workspace=wB" in (qwb / ".watch").read_text()
    second = ensure()
    assert second.returncode == 0 and "复用" in second.stdout, f"二次复用失败：{second.stdout} {second.stderr}"
    checked = subprocess.run(["bash", str(stub), "--project", str(project), "--check"], env=env, capture_output=True, text=True)
    assert checked.returncode == 0 and "wB:pWatch" in checked.stdout, "跨 workspace check 未找到本项目值守"
    s = json.loads(statefile.read_text()); assert s["creates"] == 1 and s["runs"] == 1
    (qwb / ".watch").unlink()
    unknown_identity = subprocess.run(cmd, env={**env, "FAKE_FAIL_WATCH_GET": "1"}, capture_output=True, text=True)
    assert unknown_identity.returncode != 0, "缺登记时 pane get 失败仍误认领"
    assert not (qwb / ".watch").exists(), "关键查询失败仍写了登记"
    restored = ensure()
    assert restored.returncode == 0 and "workspace=wB" in (qwb / ".watch").read_text(), \
        "查询恢复后应登记真实目标 workspace"
    s["active"] = False; statefile.write_text(json.dumps(s))
    third = ensure()
    assert third.returncode == 0, f"失活恢复失败：{third.stdout} {third.stderr}"
    s = json.loads(statefile.read_text()); assert s["creates"] == 1 and s["runs"] == 2
    s["target"] = "wOther:pWrong"; statefile.write_text(json.dumps(s))
    wrong = ensure()
    assert wrong.returncode != 0 and "错误" in wrong.stderr, "错误主控目标被误认领"
    unknown = subprocess.run(cmd, env={**env, "FAKE_FAIL_LIST": "1"}, capture_output=True, text=True)
    assert unknown.returncode != 0, "Herdr 查询失败却继续 ensure"
    print("PASS  跨 workspace 创建、复用、失活恢复、错误目标与未知查询")

    # 直接抽取 smoke 的真实函数，用 stub 区分能力预检与实际测试，防止重试掩盖失败。
    smoke = (repo / "tests" / "smoke.sh").read_text()
    start = smoke.index("run_pi_ext() {")
    end = smoke.index("\nextout=", start)
    driver = project / "pi-driver.sh"
    driver.write_text(f'ROOT="{repo}"\nTMP="{project}"\n' + smoke[start:end] + '\nrun_pi_ext\n')
    runnerbin = project / "runnerbin"
    runnerbin.mkdir()
    node = runnerbin / "node"
    node.write_text('''#!/usr/bin/env bash
printf 'node %s\\n' "$*" >> "$PI_STUB_LOG"
if [[ "$*" == *probe.ts* ]]; then
  [[ "$PI_STUB_MODE" == bun ]] && exit 1
  [[ "$PI_STUB_MODE" == flag && "$*" != *--experimental-strip-types* ]] && exit 1
  exit 0
fi
if [[ "$*" == *pi-ext.test.mjs* ]]; then
  [[ "$PI_STUB_MODE" == oldmask && "$*" == *--experimental-strip-types* ]] && exit 0
  echo 'forced test failure'
  exit 1
fi
exit 1
''')
    node.chmod(0o755)
    bun = runnerbin / "bun"
    bun.write_text('''#!/usr/bin/env bash
printf 'bun %s\\n' "$*" >> "$PI_STUB_LOG"
if [[ "$*" == *probe.ts* ]]; then exit 0; fi
echo 'forced bun test failure'
exit 1
''')
    bun.chmod(0o755)
    stublog = project / "pi-runner.log"
    for mode in ("oldmask", "flag", "bun"):
        stublog.write_text("")
        pi_env = {**os.environ, "PATH": str(runnerbin) + os.pathsep + os.environ["PATH"],
                  "PI_STUB_LOG": str(stublog), "PI_STUB_MODE": mode}
        result = subprocess.run(["bash", str(driver)], env=pi_env, capture_output=True, text=True)
        calls = stublog.read_text().splitlines()
        actual = [line for line in calls if "pi-ext.test.mjs" in line]
        assert result.returncode != 0, f"实际测试失败被换运行器掩盖：mode={mode}, calls={calls}"
        assert len(actual) == 1, \
            f"实际测试执行超过一次：mode={mode}, calls={calls}"
        assert actual[0].startswith("bun ") == (mode == "bun"), f"能力预检选错运行器：{calls}"
    print("PASS  Pi 执行器能力预检后实际测试恰一次，失败不换运行器")
print("LIFECYCLE READINESS PASS")
PY
