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
    if mode == "query-fail": err("io_error")
    spaces = [{"workspace_id": "wRoot", "focused": True, "worktree": {
        "repo_root": str(root), "checkout_path": str(root), "is_linked_worktree": False}}]
    if wt:
        spaces.append({"workspace_id": "wTask", "focused": False, "worktree": {
            "repo_root": str(root), "checkout_path": wt, "is_linked_worktree": True}})
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
         "root_pane": {"tab_id": "wTask:t1"}})
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
                      "workspace_id": "wTask", "tab_id": "wTask:t2"}})
    else: err("pane_not_found")
elif args[:2] == ["pane", "process-info"]:
    out({"process_info": {"foreground_process_group_id": 42, "shell_pid": 42}})
elif args[:2] == ["tab", "list"]:
    tabs = [{"tab_id": "wTask:t1"}]
    if mode == "foreign-tab": tabs.append({"tab_id": "wTask:t3"})
    out({"tabs": tabs})
elif args[:2] == ["pane", "list"]:
    out({"panes": [{"pane_id": "wTask:p1",
                    "agent_status": "working" if mode == "busy" else "unknown"}]})
elif args[:2] == ["workspace", "close"]:
    if mode == "close-fail": err("io_error")
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
        assert (repo / ".worktrees/case").is_dir()
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
