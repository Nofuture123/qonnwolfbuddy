"""Public dispatch/finish failures with an isolated Herdr contract double."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TASK = """# Space contract
state: blocked

## 验收场景
### 正常
Given worktree 已登记
When 派发
Then 工人进入该 Space
### 失败
Given Space 身份不明
When 派发或收尾
Then 拒绝且不删除工作
"""
STUB = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path

args = sys.argv[1:]
root = Path(os.environ["QWB_TEST_PROJECT"])
state = Path(os.environ["QWB_TEST_SPACE_STATE"])
log = Path(os.environ["QWB_TEST_HERDR_LOG"])
mode = os.environ.get("QWB_TEST_MODE", "")
with log.open("a") as f: f.write(json.dumps(args) + "\n")
wt = state.read_text() if state.exists() else ""
def out(result): print(json.dumps({"result": result}))
def err(code):
    print(json.dumps({"error": {"code": code}}), file=sys.stderr)
    sys.exit(1)
if args[:2] == ["workspace", "list"]:
    if mode == "query-fail" or (mode in ("query-fail-after-open", "close-fail-after-open") and wt): err("io_error")
    repo_root = os.environ.get("QWB_TEST_REPO_ROOT", str(root))
    spaces = [{"workspace_id": "wRoot", "focused": True, "worktree": {
        "repo_root": repo_root, "checkout_path": str(root), "is_linked_worktree": False}}]
    if wt:
        spaces.append({"workspace_id": "wTask", "focused": False, "worktree": {
            "repo_root": repo_root, "checkout_path": wt, "is_linked_worktree": True}})
    if mode == "duplicate":
        path = str(root / ".worktrees/case")
        for name in ("wTask", "wOther"):
            spaces.append({"workspace_id": name, "focused": False, "worktree": {
                "repo_root": str(root), "checkout_path": path, "is_linked_worktree": True}})
    out({"workspaces": spaces})
elif args[:2] == ["worktree", "open"]:
    if mode == "open-fail": err("worktree_open_failed")
    path = args[args.index("--path") + 1]
    already = state.exists()
    state.write_text(path)
    out({"already_open": already, "workspace": {"workspace_id": "wTask"},
         "root_pane": {} if mode == "open-missing-root-tab" else {"tab_id": "wTask:t1"}})
elif args[:2] == ["agent", "get"]:
    err("agent_not_found")
elif args[:2] == ["tab", "create"]:
    out({"root_pane": {"pane_id": "wTask:p2", "tab_id": "wTask:t2"}})
elif args[:2] == ["pane", "get"]:
    pane = args[2]
    if pane == "wRoot:p9":
        out({"pane": {"pane_id": pane, "foreground_cwd": os.environ["QWB_TEST_WT"],
                      "workspace_id": "wRoot", "tab_id": "wRoot:t9"}})
    elif pane == "wTask:p2":
        out({"pane": {"pane_id": pane, "agent": "pi", "foreground_cwd": os.environ["QWB_TEST_WT"],
                      "workspace_id": "wRoot" if mode == "worker-foreign-space" else "wTask",
                      "tab_id": "wTask:t2"}})
    else: err("pane_not_found")
elif args[:2] == ["pane", "process-info"]:
    out({"process_info": {"foreground_process_group_id": 42, "shell_pid": 42}})
elif args[:2] == ["tab", "list"]:
    tabs = [{"tab_id": "wTask:t1"}]
    if mode == "foreign-tab": tabs.append({"tab_id": "wTask:t3"})
    if mode in ("worker-success", "worker-foreign-space"):
        tabs.append({"tab_id": "wTask:t2"})
    out({"tabs": tabs})
elif args[:2] == ["pane", "list"]:
    panes = [{"pane_id": "wTask:p1", "agent_status": "working" if mode == "busy" else "unknown"}]
    if mode in ("worker-success", "worker-foreign-space"):
        panes.append({"pane_id": "wTask:p2", "agent_status": "idle"})
    out({"panes": panes})
elif args[:2] == ["workspace", "close"]:
    if mode in ("close-fail", "close-fail-after-open"): err("io_error")
    state.unlink(missing_ok=True)
    out({"type": "workspace_closed"})
else:
    out({"type": "ok"})
'''


def call(*args, env):
    return subprocess.run(args, capture_output=True, text=True, env=env)


def project(base):
    repo = base / "project"
    repo.mkdir()
    assert call("git", "init", "-q", str(repo), env=os.environ).returncode == 0
    for key, value in (("user.name", "Test"), ("user.email", "test@example.invalid")):
        assert call("git", "-C", str(repo), "config", key, value, env=os.environ).returncode == 0
    assert call("bash", str(ROOT / "bin/qwb-init.sh"), str(repo), env=os.environ).returncode == 0
    (repo / "qwbuddy/config.sh").write_text("QWB_WORKERS='pi'\nQWB_WORKSPACE=''\nQWB_GATE_FAST=':'\nQWB_GATE_FULL=':'\n")
    (repo / "qwbuddy/workers.sh").write_text("qwb_worker pi herdr\n")
    ticket = repo / "tasks/2099-01-01-case.md"
    ticket.write_text(TASK)
    assert call("git", "-C", str(repo), "add", ".", env=os.environ).returncode == 0
    assert call("git", "-C", str(repo), "commit", "-qm", "seed", env=os.environ).returncode == 0
    stub = base / "stub"
    stub.mkdir()
    herdr = stub / "herdr"
    herdr.write_text(STUB)
    herdr.chmod(0o755)
    state = base / "space-path"
    log = base / "herdr.jsonl"
    env = os.environ.copy()
    env.update(PATH=f"{stub}:{env['PATH']}", HOME=str(base), HERDR_PANE_ID="wRoot:pCtl",
               HERDR_WORKSPACE_ID="wRoot", QWB_TEST_PROJECT=str(repo),
               QWB_TEST_SPACE_STATE=str(state), QWB_TEST_HERDR_LOG=str(log),
               QWB_TEST_WT=str(repo / ".worktrees/case"))
    return repo, ticket, state, log, env


with tempfile.TemporaryDirectory(prefix="qwb-space-dispatch-") as d:
    repo, ticket, state, log, env = project(Path(d))
    dispatch = ["bash", str(repo / "qwbuddy/bin/qwb-run.sh"), "--project", str(repo),
                "--task", "case", "--worker", "pi"]
    for mode in ("open-fail", "duplicate"):
        ticket.write_text(TASK)
        before = ticket.read_bytes()
        log.write_text("")
        bad = env | {"QWB_TEST_MODE": mode}
        result = call(*dispatch, env=bad)
        assert result.returncode != 0 and ticket.read_bytes() == before, (mode, result.stderr)
        calls = log.read_text()
        assert "tab\", \"create" not in calls and "agent\", \"start" not in calls
        assert (repo / ".worktrees/case").is_dir(), result.stderr
    ticket.write_text(TASK)
    before = ticket.read_bytes()
    log.write_text("")
    git = Path(d) / "stub/git"
    git.write_text('#!/usr/bin/env bash\nif [[ "$*" == *"worktree list --porcelain"* ]]; then exit 9; fi\nexec "$QWB_REAL_GIT" "$@"\n')
    git.chmod(0o755)
    failed_git = env | {"QWB_REAL_GIT": shutil.which("git")}
    result = call(*dispatch, "--worktree", str(repo / ".worktrees/case"), env=failed_git)
    assert result.returncode != 0 and ticket.read_bytes() == before, result.stderr
    calls = log.read_text()
    assert "tab\", \"create" not in calls and "agent\", \"start" not in calls
    assert (repo / ".worktrees/case").is_dir()
    git.unlink()
    ticket.write_text(TASK)
    result = call(*dispatch, env=env)
    assert result.returncode == 0, result.stderr
    baseline = next(x for x in ticket.read_text().splitlines() if x.startswith("scenarios-fp:"))
    assert "worktree-space: id=wTask" in ticket.read_text()
    result = call(*dispatch, env=env)
    assert result.returncode == 0 and baseline in ticket.read_text(), result.stderr
    assert ticket.read_text().count("worktree-space:") == 1
    for mode in ("", "space-missing"):
        if mode: state.unlink()
        other = repo / "tasks/2099-01-02-other.md"
        other.write_text(TASK)
        before = other.read_bytes()
        result = call("bash", str(repo / "qwbuddy/bin/qwb-run.sh"), "--project", str(repo),
                      "--task", str(other), "--worker", "pi", "--worktree", str(repo / ".worktrees/case"),
                      "--pane", "wRoot:p9", env=env)
        assert result.returncode != 0 and other.read_bytes() == before, result.stderr
    print("SPACE DISPATCH PASS: open/list failure, duplicate, retry fingerprint, foreign/missing pane Space")

for mode in ("unowned", "foreign-tab", "busy", "query-fail", "close-fail", "tag-exists", "partial"):
    with tempfile.TemporaryDirectory(prefix=f"qwb-space-{mode}-") as d:
        base = Path(d)
        repo, ticket, state, log, env = project(base)
        wt = repo / ".worktrees/case"
        assert call("git", "-C", str(repo), "worktree", "add", "-qb", "case", str(wt), env=env).returncode == 0
        state.write_text(str(wt))
        ticket.write_text("state: verified\n" + ("" if mode == "unowned" else
                          f"worktree-space: id=wTask root-tab=wTask:t1 path={wt}\n"))
        if mode == "tag-exists":
            assert call("git", "-C", str(repo), "tag", "archive/case", env=env).returncode == 0
            assert call("git", "-C", str(wt), "commit", "-qm", "new", "--allow-empty",
                        env=env).returncode == 0
        check_env = env | {"QWB_TEST_MODE": mode}
        if mode == "partial":
            git = base / "stub/git"
            real_git = shutil.which("git")
            git.write_text('#!/usr/bin/env bash\nif [[ "$*" == *"worktree remove"* ]]; then exit 9; fi\nexec "$QWB_REAL_GIT" "$@"\n')
            git.chmod(0o755)
            check_env["QWB_REAL_GIT"] = real_git
        action = "--archive" if mode == "tag-exists" else "--merged"
        result = call("bash", str(ROOT / "bin/qwb-worktree.sh"), "finish", "case", action,
                      "--project", str(repo), env=check_env)
        assert result.returncode != 0 and wt.is_dir(), (mode, result.stdout, result.stderr)
        assert call("git", "-C", str(repo), "show-ref", "--verify", "--quiet", "refs/heads/case",
                    env=os.environ).returncode == 0
        assert ("worktree: partial" in ticket.read_text()) == (mode == "partial")
        assert state.exists() == (mode != "partial")
print("SPACE FINISH PASS: unowned, foreign tab, busy agent, query/close failure, existing tag, partial receipt")

# 审点 1：打开成功后任何身份核对失败，都不能留下无主 Space。
for mode in ("query-fail-after-open", "open-missing-root-tab", "close-fail-after-open"):
    with tempfile.TemporaryDirectory(prefix=f"qwb-r1-open-{mode}-") as d:
        repo, ticket, state, log, env = project(Path(d))
        before = ticket.read_bytes()
        result = call("bash", str(repo / "qwbuddy/bin/qwb-run.sh"), "--project", str(repo),
                      "--task", "case", "--worker", "pi", env=env | {"QWB_TEST_MODE": mode})
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        assert result.returncode != 0 and ticket.read_bytes() == before, result.stderr
        assert calls.count(["workspace", "close", "wTask"]) == 1, (mode, calls, result.stderr)
        if mode == "close-fail-after-open":
            assert state.exists() and "herdr workspace close wTask" in result.stderr, result.stderr
        else:
            assert not state.exists(), (mode, result.stderr)
        assert not any(c[:2] == ["tab", "create"] for c in calls), calls
print("R1 OPEN CLEANUP PASS: failed post-open query/root tab closes Space; close failure names manual command")

# 项目根不是 Git 主工作树根时，派发应在建树前拒绝；收尾必须看见 linked checkout 并拒绝身份不符。
with tempfile.TemporaryDirectory(prefix="qwb-r1-nested-") as d:
    base = Path(d)
    repo, ticket, state, log, env = project(base)
    main = base / "main"
    repo.rename(main)
    nested = main / "app"
    nested.mkdir()
    assert call("bash", str(ROOT / "bin/qwb-init.sh"), str(nested), env=os.environ).returncode == 0
    (nested / "qwbuddy/config.sh").write_text("QWB_WORKERS='pi'\nQWB_WORKSPACE=''\nQWB_GATE_FAST=':'\nQWB_GATE_FULL=':'\n")
    (nested / "qwbuddy/workers.sh").write_text("qwb_worker pi herdr\n")
    nested_ticket = nested / "tasks/2099-01-01-case.md"
    nested_ticket.write_text(TASK)
    assert call("git", "-C", str(main), "add", ".", env=os.environ).returncode == 0
    assert call("git", "-C", str(main), "commit", "-qm", "nested", env=os.environ).returncode == 0
    env.update(QWB_TEST_PROJECT=str(nested), QWB_TEST_REPO_ROOT=str(main),
               QWB_TEST_WT=str(nested / ".worktrees/case"))
    result = call("bash", str(nested / "qwbuddy/bin/qwb-run.sh"), "--project", str(nested),
                  "--task", "case", "--worker", "pi", env=env)
    assert result.returncode != 0 and not (nested / ".worktrees/case").exists(), result.stderr
    assert not any(json.loads(line)[:2] == ["worktree", "open"] for line in log.read_text().splitlines())
    wt = nested / ".worktrees/case"
    assert call("git", "-C", str(main), "worktree", "add", "-qb", "case", str(wt), env=os.environ).returncode == 0
    log.write_text("")
    result = call("bash", str(nested / "qwbuddy/bin/qwb-run.sh"), "--project", str(nested),
                  "--task", "case", "--worker", "pi", "--worktree", str(wt), env=env)
    assert result.returncode != 0 and wt.is_dir(), result.stderr
    assert not any(json.loads(line)[:2] == ["worktree", "open"] for line in log.read_text().splitlines())
    state.write_text(str(wt))
    nested_ticket.write_text(f"state: verified\nworktree-space: id=wTask root-tab=wTask:t1 path={wt}\n")
    before = nested_ticket.read_bytes()
    log.write_text("")
    result = call("bash", str(ROOT / "bin/qwb-worktree.sh"), "finish", "case", "--merged",
                  "--project", str(nested), env=env)
    calls = [json.loads(line) for line in log.read_text().splitlines()]
    assert result.returncode != 0 and wt.is_dir() and nested_ticket.read_bytes() == before, result.stderr
    assert not any(c[:2] == ["workspace", "close"] for c in calls), calls
print("R1 NESTED ROOT PASS: dispatch refuses before creation and finish preserves linked checkout")

# 审点 2：公开 finish 路径必须认根 tab 与最后派发工人 tab，并先关 Space 后删 Git。
for mode in ("worker-success", "worker-foreign-space"):
    with tempfile.TemporaryDirectory(prefix=f"qwb-r1-finish-{mode}-") as d:
        base = Path(d)
        repo, ticket, state, log, env = project(base)
        wt = repo / ".worktrees/case"
        assert call("git", "-C", str(repo), "worktree", "add", "-qb", "case", str(wt), env=os.environ).returncode == 0
        state.write_text(str(wt))
        ticket.write_text(f"state: verified\nworktree-space: id=wTask root-tab=wTask:t1 path={wt}\n"
                          f"dispatch: worker=pi pane=wTask:p2 dir={wt}\n")
        git = base / "stub/git"
        git.write_text('#!/usr/bin/env bash\nif [[ "$*" == *"worktree remove"* ]]; then '
                       'printf \'["git", "worktree", "remove"]\\n\' >> "$QWB_TEST_HERDR_LOG"; fi\n'
                       'exec "$QWB_REAL_GIT" "$@"\n')
        git.chmod(0o755)
        check_env = env | {"QWB_REAL_GIT": shutil.which("git"), "QWB_TEST_MODE": mode}
        result = call("bash", str(ROOT / "bin/qwb-worktree.sh"), "finish", "case", "--merged",
                      "--project", str(repo), env=check_env)
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        closes = [i for i, c in enumerate(calls) if c == ["workspace", "close", "wTask"]]
        removes = [i for i, c in enumerate(calls) if c == ["git", "worktree", "remove"]]
        if mode == "worker-success":
            assert result.returncode == 0, result.stderr
            assert len(closes) == 1 and len(removes) == 1 and closes[0] < removes[0], calls
            assert not state.exists() and not wt.exists()
            assert call("git", "-C", str(repo), "show-ref", "--verify", "--quiet",
                        "refs/heads/case", env=os.environ).returncode != 0
            assert "worktree: merged" in ticket.read_text()
        else:
            assert result.returncode != 0 and wt.is_dir() and state.exists(), result.stderr
            assert not closes and not removes, calls
            assert "worktree: merged" not in ticket.read_text()
print("R1 WORKER FINISH PASS: own worker tab closes once before Git; foreign workspace preserves checkout")

# 审点 3：一次性 Git 失败留下 OID 收据；同 OID 归档可重跑，删分支失败给可执行条件命令。
for stage in ("worktree-remove", "branch-delete"):
    with tempfile.TemporaryDirectory(prefix=f"qwb-r1-partial-{stage}-") as d:
        base = Path(d)
        repo, ticket, state, log, env = project(base)
        wt = repo / ".worktrees/case"
        assert call("git", "-C", str(repo), "worktree", "add", "-qb", "case", str(wt), env=os.environ).returncode == 0
        assert call("git", "-C", str(wt), "commit", "-qm", "archive", "--allow-empty",
                    env=os.environ).returncode == 0
        oid = call("git", "-C", str(wt), "rev-parse", "HEAD", env=os.environ).stdout.strip()
        ticket.write_text("state: verified\n")
        git = base / "stub/git"
        target = "worktree remove" if stage == "worktree-remove" else "update-ref -d"
        git.write_text('#!/usr/bin/env bash\nif [[ "$*" == *"' + target + '"* && '
                       '! -e "$QWB_TEST_GIT_FAILED" ]]; then '
                       'touch "$QWB_TEST_GIT_FAILED"; exit 9; fi\nexec "$QWB_REAL_GIT" "$@"\n')
        git.chmod(0o755)
        check_env = env | {"QWB_REAL_GIT": shutil.which("git"),
                           "QWB_TEST_GIT_FAILED": str(base / "git-failed")}
        cmd = ("bash", str(ROOT / "bin/qwb-worktree.sh"), "finish", "case", "--archive",
               "--project", str(repo))
        first = call(*cmd, env=check_env)
        assert first.returncode != 0, first.stderr
        assert f"stage={stage}" in ticket.read_text() and f"oid={oid}" in ticket.read_text()
        assert "恢复命令：" in first.stderr and oid in first.stderr, first.stderr
        assert call("git", "-C", str(repo), "rev-parse", "refs/tags/archive/case",
                    env=os.environ).stdout.strip() == oid
        if stage == "worktree-remove":
            assert wt.is_dir()
            second = call(*cmd, env=check_env)
            assert second.returncode == 0 and not wt.exists(), second.stderr
            assert "worktree: archive" in ticket.read_text()
        else:
            assert not wt.exists()
            recovery = next(line.split("恢复命令：", 1)[1].strip() for line in first.stderr.splitlines()
                            if line.startswith("恢复命令："))
            assert call("bash", "-c", recovery, env=os.environ).returncode == 0, recovery
        assert call("git", "-C", str(repo), "show-ref", "--verify", "--quiet", "refs/heads/case",
                    env=os.environ).returncode != 0
print("R1 ARCHIVE RECOVERY PASS: retry same-OID tag and execute conditional branch deletion")
