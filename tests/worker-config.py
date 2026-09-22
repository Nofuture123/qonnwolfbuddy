#!/usr/bin/env python3
"""Public qwb-run / qwb-init worker configuration contract with isolated HOME."""
import json
import os
import shutil
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TASK = """# worker config
state: blocked

## 1. 验收场景

### user_正常
Given 工人配置合法
When 主控派发
Then 参数逐项保真

### user_失败
Given 工人配置歧义
When 主控派发
Then 拒绝且无副作用
"""


def call(cmd, env):
    return subprocess.run(cmd, text=True, capture_output=True, env=env)


def check(ok, message):
    if not ok:
        raise AssertionError(message)


with tempfile.TemporaryDirectory(prefix="qwb-worker-config-") as tmp:
    base = Path(tmp)
    project = base / "project"
    project.mkdir()
    home = base / "home"
    home.mkdir()
    stub = base / "stub"
    stub.mkdir()
    log = base / "herdr.jsonl"
    argv_log = base / "pane-argv.json"
    marker = base / "unexpected-command"
    env = os.environ.copy()
    env.update(HOME=str(home), PATH=f"{stub}:{env['PATH']}", QWB_STUB_LOG=str(log),
               QWB_STUB_ARGV=str(argv_log), HERDR_WORKSPACE_ID="wTest",
               HERDR_PANE_ID="wTest:pCtl")
    (stub / "herdr").write_text('''#!/usr/bin/env python3
import json, os, subprocess, sys
from pathlib import Path
args=sys.argv[1:]
with open(os.environ["QWB_STUB_LOG"],"a") as f: f.write(json.dumps(args)+"\\n")
if args[:2]==["workspace","list"]:
    print(json.dumps({"result":{"workspaces":[]}}))
elif args[:2]==["agent","get"] and args[2].startswith("qwb-"):
    print(json.dumps({"error":{"code":"agent_not_found"}}),file=sys.stderr); sys.exit(1)
elif args[:2]==["tab","create"]:
    print(json.dumps({"result":{"root_pane":{"pane_id":"wTest:p7","tab_id":"wTest:t7"}}}))
elif args[:2]==["pane","run"] and args[3].startswith("'fake-exec'"):
    p=subprocess.run(["bash","-c",args[3]],env=os.environ.copy(),capture_output=True,text=True)
    if p.returncode: print(p.stderr,file=sys.stderr); sys.exit(p.returncode)
else:
    print(json.dumps({"result":{"type":"ok"}}))
''')
    (stub / "fake-exec").write_text('''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
Path(os.environ["QWB_STUB_ARGV"]).write_text(json.dumps(sys.argv[1:]))
''')
    for name in ("herdr", "fake-exec"):
        (stub / name).chmod(0o755)
    p = call(["bash", str(ROOT / "bin/qwb-init.sh"), str(project)], env)
    check(p.returncode == 0, f"init failed: {p.stderr}")
    config = project / "qwbuddy/config.sh"
    workers = project / "qwbuddy/workers.sh"
    ticket = project / "tasks/2099-01-01-config.md"
    config.write_text(config.read_text() + '\nQWB_WORKERS="pi cmd"\nQWB_AGENT_START_MS=300\n')

    def reset():
        log.write_text("")
        argv_log.unlink(missing_ok=True)
        ticket.write_text(TASK)
        shutil.rmtree(project / "qwbuddy/.controller.lock", ignore_errors=True)

    def run(worker="pi", here=True):
        args = ["bash", str(project / "qwbuddy/bin/qwb-run.sh"), "--project", str(project),
                "--task", str(ticket), "--worker", worker]
        if here:
            args.append("--here")
        return call(args, env)

    literal = "$(touch " + str(marker) + ")"
    workers.write_text("qwb_worker pi herdr 'space value' '' '" + literal + "'\n"
                       "qwb_worker cmd pane-run fake-exec 'space value' '' '" + literal
                       + "' '~' '{a,b}' '#' \"a'b\"\n")
    reset()
    p = run()
    check(p.returncode == 0, f"herdr run failed: {p.stderr}")
    calls = [json.loads(x) for x in log.read_text().splitlines()]
    starts = [x for x in calls if x[:2] == ["agent", "start"]]
    check(len(starts) == 1 and starts[0][-4:] == ["--", "space value", "", literal],
          f"herdr argv wrong: {starts}")
    check(not marker.exists() and "dispatch:" in ticket.read_text(), "herdr literal or dispatch wrong")
    print("PASS public qwb-run herdr argv")

    reset()
    p = run("cmd")
    check(p.returncode == 0, f"pane run failed: {p.stderr}")
    check(argv_log.exists(), f"pane-run did not call fake executable: {calls} {p.stdout} {p.stderr}")
    check(json.loads(argv_log.read_text()) == ["space value", "", literal, "~", "{a,b}", "#", "a'b"],
          "pane-run argv wrong")
    check(not marker.exists() and "dispatch:" in ticket.read_text(), "pane literal or dispatch wrong")
    print("PASS public qwb-run pane-run argv")

    for name, body, fragment in (
        ("unknown", "qwb_worker ghost herdr\n", "未知工人"),
        ("duplicate", "qwb_worker pi herdr\nqwb_worker pi herdr\nqwb_worker cmd pane-run fake-exec\n", "重复启动定义"),
        ("headless", "qwb_worker pi herdr --print\nqwb_worker cmd pane-run fake-exec\n", "headless"),
    ):
        workers.write_text(body)
        reset()
        p = run(here=False)
        check(p.returncode != 0 and fragment in p.stderr, f"{name} diagnostic: {p.stderr}")
        check(not log.read_text() and not argv_log.exists() and "dispatch:" not in ticket.read_text()
              and not (project / ".worktrees").exists()
              and not (project / "qwbuddy/.controller.lock").exists(), f"{name} side effect")
        print(f"PASS public qwb-run {name} preflight")

    # Simulate an old installed project; ordinary upgrade preserves user configuration.
    workers.unlink()
    old = config.read_text() + ('\nQWB_WORKER_LAUNCH="cmd=pane-run:fake-exec --trust"\n'
                                'QWB_WORKER_ARGS="pi=--approve ~ {a,b} # a\'b"\n')
    config.write_text(old)
    config.chmod(0o600)
    p = call(["bash", str(ROOT / "bin/qwb-init.sh"), str(project)], env)
    check(p.returncode == 0 and config.read_text() == old and not workers.exists(), "upgrade overwrote custom config")
    reset()
    p = run(here=False)
    check(p.returncode != 0 and "--migrate-worker-config" in p.stderr and not log.read_text()
          and not argv_log.exists() and "dispatch:" not in ticket.read_text()
          and not (project / ".worktrees").exists()
          and not (project / "qwbuddy/.controller.lock").exists(),
          "old config dispatched before migration")
    p = call(["bash", str(ROOT / "bin/qwb-init.sh"), "--migrate-worker-config", str(project)], env)
    backup = Path(str(config) + ".worker-config.bak")
    check(p.returncode == 0 and backup.read_text() == old and config.stat().st_mode & 0o777 == 0o600,
          f"migration failed or mode widened: {p.stderr}")
    check("qwb_worker 'pi' 'herdr'" in workers.read_text()
          and "qwb_worker 'cmd' 'pane-run'" in workers.read_text(),
          "migrated declaration missing")
    after = (config.read_bytes(), workers.read_bytes(), backup.read_bytes())
    p = call(["bash", str(ROOT / "bin/qwb-init.sh"), "--migrate-worker-config", str(project)], env)
    check(p.returncode == 0 and after == (config.read_bytes(), workers.read_bytes(), backup.read_bytes()),
          "migration not idempotent")
    reset()
    p = run("pi")
    migrated_calls = [json.loads(x) for x in log.read_text().splitlines()]
    starts = [x for x in migrated_calls if x[:2] == ["agent", "start"]]
    check(p.returncode == 0 and len(starts) == 1
          and starts[0][-6:] == ["--", "--approve", "~", "{a,b}", "#", "a'b"],
          f"migrated herdr argv wrong: {starts} {p.stderr}")
    reset()
    p = run("cmd")
    check(p.returncode == 0 and json.loads(argv_log.read_text()) == ["--trust"],
          f"migrated pane argv wrong: {p.stderr}")
    print("PASS explicit migration backup, mode, argv, idempotence")

    migrated_config = config.read_bytes()
    config.write_bytes(migrated_config + b'QWB_WORKER_ARGS="cmd=--second-place"\n')
    reset()
    p = run("cmd", here=False)
    check(p.returncode != 0 and "--migrate-worker-config" in p.stderr and not log.read_text()
          and not argv_log.exists() and "dispatch:" not in ticket.read_text()
          and not (project / ".worktrees").exists()
          and not (project / "qwbuddy/.controller.lock").exists(),
          "old key plus new workers dispatched")
    config.write_bytes(migrated_config)
    print("PASS old key plus workers.sh preflight refusal")

    # Old pane-run was interpreted by a shell; these forms change argv if naively split.
    for label, command, expected in (
        ("brace", "fake-exec {a,b}", ["a", "b"]),
        ("comment", "fake-exec value # trailing", ["value"]),
        ("tilde", "fake-exec ~", [str(home)]),
    ):
        argv_log.unlink(missing_ok=True)
        p = call(["bash", "-c", command], env)
        check(p.returncode == 0 and json.loads(argv_log.read_text()) == expected,
              f"old {label} command did not demonstrate shell semantics")
        workers.unlink(missing_ok=True)
        backup.unlink(missing_ok=True)
        config.write_text('QWB_WORKERS="pi cmd"\nQWB_WORKER_LAUNCH="cmd=pane-run:' + command + '"\n')
        before = config.read_bytes()
        p = call(["bash", str(ROOT / "bin/qwb-init.sh"), "--migrate-worker-config", str(project)], env)
        check(p.returncode != 0 and config.read_bytes() == before
              and not workers.exists() and not backup.exists(),
              f"old pane-run {label} shell semantics silently migrated: {p.stdout} {p.stderr}")
        print(f"PASS old pane-run {label} semantics refused")

    for label, line in (
        ("unknown", 'QWB_WORKER_ARGS="pi=--approve ghost=--x"'),
        ("glob", 'QWB_WORKER_ARGS="pi=*"'),
        ("empty-launch", 'QWB_WORKER_LAUNCH="pi="'),
        ("two-parameter-places", 'QWB_WORKER_LAUNCH="cmd=pane-run:fake-exec --trust"\nQWB_WORKER_ARGS="cmd=--second-place"'),
        ("compound", 'QWB_WORKER_ARGS="pi=--approve"; QWB_GATE_FAST=bad'),
        ("multiline", 'QWB_WORKER_ARGS="pi=--approve\n --x"'),
    ):
        workers.unlink(missing_ok=True)
        backup.unlink(missing_ok=True)
        config.write_text('QWB_WORKERS="pi cmd"\nQWB_GATE_FAST="true"\n' + line + '\n')
        before = config.read_bytes()
        p = call(["bash", str(ROOT / "bin/qwb-init.sh"), "--migrate-worker-config", str(project)], env)
        check(p.returncode != 0 and config.read_bytes() == before and not workers.exists()
              and not backup.exists(), f"{label} was silently migrated: {p.stdout} {p.stderr}")
        print(f"PASS ambiguous migration {label} refusal")

    custom = base / "custom-upgrade"
    (custom / "qwbuddy").mkdir(parents=True)
    custom_conf = custom / "qwbuddy/config.sh"
    custom_workers = custom / "qwbuddy/workers.sh"
    sentinel = base / "ordinary-init-sourced-config"
    env["QWB_CONFIG_SENTINEL"] = str(sentinel)
    custom_conf.write_text('QWB_WORKERS="pi"\nQWB_GATE_FAST=":"\nQWB_GATE_FULL=":"\n'
                           ': > "$QWB_CONFIG_SENTINEL"\n')
    original = custom_conf.read_bytes()
    p = call(["bash", str(ROOT / "bin/qwb-init.sh"), str(custom)], env)
    check(p.returncode == 0 and custom_conf.read_bytes() == original
          and not custom_workers.exists() and "workers.sh" in p.stderr
          and not sentinel.exists(),
          f"custom upgrade installed mismatched defaults: {p.stdout} {p.stderr}")
    custom_ticket = custom / "tasks/2099-01-01-custom.md"
    custom_ticket.write_text(TASK)
    log.write_text("")
    p = call(["bash", str(custom / "qwbuddy/bin/qwb-run.sh"), "--project", str(custom),
              "--task", str(custom_ticket), "--worker", "pi"], env)
    check(p.returncode != 0 and "workers.sh" in p.stderr and not log.read_text()
          and "dispatch:" not in custom_ticket.read_text() and not (custom / ".worktrees").exists(),
          "custom upgrade dispatched with missing definitions")
    sentinel.unlink(missing_ok=True)
    custom_workers.write_text("qwb_worker pi herdr --approve\n")
    before = custom_workers.read_bytes()
    p = call(["bash", str(ROOT / "bin/qwb-init.sh"), str(custom)], env)
    check(p.returncode == 0 and custom_workers.read_bytes() == before
          and custom_conf.read_bytes() == original and not sentinel.exists(),
          "ordinary upgrade overwrote or sourced complete custom config")
    print("PASS customized ordinary upgrade reports missing workers and preserves complete config")

    git_project = base / "git-project"
    git_project.mkdir()
    p = call(["bash", str(ROOT / "bin/qwb-init.sh"), str(git_project)], env)
    check(p.returncode == 0, f"git fixture init failed: {p.stderr}")
    first = git_project / "tasks/2099-01-01-gitwork.md"
    first.write_text(TASK)
    for cmd in (["git", "init", "-q", str(git_project)],
                ["git", "-C", str(git_project), "add", "."],
                ["git", "-C", str(git_project), "-c", "user.email=test@example.invalid",
                 "-c", "user.name=Test", "commit", "-qm", "init"]):
        p = call(cmd, env)
        check(p.returncode == 0, f"git fixture failed: {cmd}: {p.stderr}")
    (git_project / ".worktrees/orphan").mkdir(parents=True)
    p = call(["bash", str(git_project / "qwbuddy/bin/qwb-run.sh"), "--project", str(git_project),
              "--task", str(first), "--worker", "pi", "--create-worktree"], env)
    worktree = git_project / ".worktrees/gitwork"
    check(p.returncode == 0 and "残留" in p.stderr and worktree.is_dir()
          and f"dir={worktree}" in first.read_text(),
          f"git fixture create-worktree failed: {p.stdout} {p.stderr}")
    second = git_project / "tasks/2099-01-02-gitreuse.md"
    second.write_text(TASK)
    p = call(["bash", str(git_project / "qwbuddy/bin/qwb-run.sh"), "--project", str(git_project),
              "--task", str(second), "--worker", "pi", "--worktree", str(worktree)], env)
    check(p.returncode == 0 and f"dir={worktree}" in second.read_text(),
          f"git fixture worktree reuse failed: {p.stdout} {p.stderr}")
    print("PASS public qwb-run git worktree create, residue warning, and reuse")
