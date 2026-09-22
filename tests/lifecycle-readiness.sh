#!/usr/bin/env bash
# 生产生命周期定向回归；临时项目与子进程由 Python finally 回收。
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="${QWB_LIFECYCLE_SOURCE:-$REPO}"
python3 - "$ROOT" "$REPO" <<'PY'
import hashlib
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time

source = Path(sys.argv[1])
repo = Path(sys.argv[2])
with tempfile.TemporaryDirectory(prefix="qwb-lifecycle-") as tmp:
    project = Path(tmp)
    qwb = project / "qwbuddy"
    (qwb / "bin").mkdir(parents=True)
    (project / "tasks").mkdir()
    for name in ("qwb-wake.sh", "qwb-lib.sh", "qwb-hook-claude-stop.sh"):
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

    # 两个 hook 同时接管残留死锁；只有一个真实子进程进入值守。
    hooklock = qwb / ".hook.lock"
    hooklock.mkdir()
    (hooklock / "pid").write_text("99999999\n")
    stub = qwb / "bin" / "qwb-wake.sh"
    stub.write_text('#!/usr/bin/env bash\necho "$$" >> "' + str(project / 'entered') + '"\nsleep 0.6\nexit 124\n')
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
        assert entered.exists() and len(entered.read_text().splitlines()) == 1, "并发 hook 启动了多个值守"
        assert not hooklock.exists(), "hook 正常退出后遗留锁"
        print("PASS  A 判死回收暂停、B 竞争：单飞且正常释放")
    finally:
        for h in hooks:
            if h.poll() is None: h.kill(); h.wait(timeout=2)

    # 假 Herdr：主控在 A，项目值守在 B。三次 ensure 验证创建、复用、失活重启。
    import json
    shutil.copy2(source / "bin" / "qwb-wake.sh", stub)
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
