"""R2 regressions through the installed public CLI, using isolated Git and Herdr fixtures."""
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
TASK = """# case
state: blocked

## 验收场景
### 正常
Given 隔离副本
When 工人完成
Then 主控独立验收
### 失败
Given 工人未完成
When 主控检查
Then 拒绝收尾
"""
STUB = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
a=sys.argv[1:]
log=Path(os.environ["R2_HERDR_LOG"])
with log.open("a") as f: f.write(json.dumps(a)+"\n")
root=Path(os.environ["R2_PROJECT"])
state=Path(os.environ["R2_SPACE"])
def out(x): print(json.dumps({"result":x}))
if a[:2]==["workspace","list"]:
    if os.environ.get("R2_MODE") == "query-fail":
        print('{"error":{"code":"io_error"}}',file=sys.stderr); sys.exit(1)
    if os.environ.get("R2_MODE") == "bad-response":
        out({"workspaces":[{}]}); sys.exit(0)
    spaces=[]
    if state.exists():
        spaces=[{"workspace_id":"wTask","worktree":{"repo_root":str(root),
            "checkout_path":state.read_text(),"is_linked_worktree":True}}]
    out({"workspaces":spaces})
elif a[:2]==["agent","get"]:
    print('{"error":{"code":"agent_not_found"}}',file=sys.stderr); sys.exit(1)
elif a[:2]==["worktree","open"]:
    path=a[a.index("--path")+1]; state.write_text(path)
    out({"already_open":False,"workspace":{"workspace_id":"wTask"},
         "root_pane":{"tab_id":"wTask:t1"}})
elif a[:2]==["tab","create"]:
    out({"root_pane":{"pane_id":"wTask:p2","tab_id":"wTask:t2"}})
else: out({"type":"ok"})
'''


def call(*args, env=None, umask=None):
    kw = {"capture_output": True, "text": True, "env": env or os.environ.copy()}
    if umask is not None:
        kw["preexec_fn"] = lambda: os.umask(umask)
    return subprocess.run(args, **kw)


def git(*args, env=None):
    p = call("git", *map(str, args), env=env)
    assert p.returncode == 0, (args, p.stderr)
    return p.stdout.strip()


def fixture(base, layout="normal"):
    repo = base / "repo"
    if layout == "separate":
        git("init", "-q", "--separate-git-dir", base / "metadata", repo)
    elif layout == "submodule":
        source = base / "source"; source.mkdir()
        git("init", "-q", source)
        git("-C", source, "config", "user.name", "Test")
        git("-C", source, "config", "user.email", "test@example.invalid")
        (source / "base").write_text("base\n")
        git("-C", source, "add", "base"); git("-C", source, "commit", "-qm", "base")
        superrepo = base / "super"; superrepo.mkdir()
        git("init", "-q", superrepo)
        git("-C", superrepo, "config", "user.name", "Test")
        git("-C", superrepo, "config", "user.email", "test@example.invalid")
        git("-C", superrepo, "-c", "protocol.file.allow=always", "submodule", "add", "-q", str(source), "sub")
        repo = superrepo / "sub"
    else:
        repo.mkdir(); git("init", "-q", repo)
    git("-C", repo, "config", "user.name", "Test")
    git("-C", repo, "config", "user.email", "test@example.invalid")
    init = call("bash", str(ROOT / "bin/qwb-init.sh"), str(repo))
    assert init.returncode == 0, init.stderr
    (repo / "qwbuddy/config.sh").write_text("QWB_WORKERS='pi'\nQWB_WORKSPACE=''\nQWB_GATE_FAST=':'\nQWB_GATE_FULL=':'\n")
    (repo / "qwbuddy/workers.sh").write_text("qwb_worker pi herdr\n")
    ticket = repo / "tasks/2099-01-01-case.md"; ticket.write_text(TASK)
    git("-C", repo, "add", "."); git("-C", repo, "commit", "-qm", "seed")
    stub = base / "stub"; stub.mkdir()
    h = stub / "herdr"; h.write_text(STUB); h.chmod(0o755)
    log = base / "herdr.jsonl"
    env = os.environ.copy()
    env.update(PATH=f"{stub}:{env['PATH']}", R2_PROJECT=str(repo), R2_SPACE=str(base / "space"),
               R2_HERDR_LOG=str(log), HERDR_PANE_ID="wRoot:p1", HERDR_WORKSPACE_ID="wRoot")
    return repo, ticket, env, log


def permissions():
    paths = [".gitignore", "AGENTS.md", "CLAUDE.md", ".claude/settings.json"]
    for mask in (0o022, 0o027):
        for existing in (False, True):
            with tempfile.TemporaryDirectory(prefix="qwb-r2-mode-") as d:
                repo = Path(d) / "project"; repo.mkdir()
                if existing:
                    (repo / ".claude").mkdir()
                    for name in paths:
                        p = repo / name
                        p.write_text("{}\n" if name.endswith(".json") else "existing\n")
                        p.chmod(0o644)
                result = call("bash", str(ROOT / "bin/qwb-init.sh"), str(repo), umask=mask)
                assert result.returncode == 0, result.stderr
                expected = 0o644 if existing else 0o666 & ~mask
                modes = {name: stat.S_IMODE((repo / name).stat().st_mode) for name in paths}
                assert all(mode == expected for mode in modes.values()), (oct(mask), existing, modes)
    with tempfile.TemporaryDirectory(prefix="qwb-r2-hook-fail-") as d:
        base = Path(d); repo = base / "project"; repo.mkdir()
        stub = base / "stub"; stub.mkdir()
        mv = stub / "mv"
        mv.write_text('#!/usr/bin/env bash\nif [[ "$2" == *".qwb-hook."* ]]; then exit 9; fi\n'
                      'exec "$R2_REAL_MV" "$@"\n')
        mv.chmod(0o755)
        env = os.environ.copy(); env.update(PATH=f"{stub}:{env['PATH']}", R2_REAL_MV=shutil.which("mv"))
        result = call("bash", str(ROOT / "bin/qwb-init.sh"), str(repo), env=env)
        assert result.returncode != 0 and not list(repo.glob(".qwb-hook.*")), result.stderr
    print("R2 PERMISSIONS PASS: existing 0644 preserved; new files honor umask 022/027; hook temp cleaned on failure")


def layout():
    for kind in ("separate", "submodule"):
        with tempfile.TemporaryDirectory(prefix="qwb-r2-layout-") as d:
            repo, ticket, env, log = fixture(Path(d), kind)
            result = call("bash", str(repo / "qwbuddy/bin/qwb-run.sh"), "--project", str(repo),
                          "--task", "case", "--worker", "pi", env=env)
            assert result.returncode == 0 and (repo / ".worktrees/case").is_dir(), (kind, result.stderr)
            assert "worktree-space:" in ticket.read_text() and "dispatch:" in ticket.read_text()
    for kind in ("nested", "linked"):
        with tempfile.TemporaryDirectory(prefix="qwb-r2-layout-") as d:
            base = Path(d); main, _, _, _ = fixture(base)
            if kind == "nested":
                repo = main / "nested"; repo.mkdir()
            else:
                repo = base / "linked"
                git("-C", main, "worktree", "add", "-qb", "linked", repo)
            init = call("bash", str(ROOT / "bin/qwb-init.sh"), str(repo))
            assert init.returncode == 0, init.stderr
            (repo / "qwbuddy/config.sh").write_text("QWB_WORKERS='pi'\nQWB_WORKSPACE=''\n")
            (repo / "qwbuddy/workers.sh").write_text("qwb_worker pi herdr\n")
            (repo / "tasks/2099-01-01-case.md").write_text(TASK)
            env = os.environ.copy(); env.update(PATH=f"{base / 'stub'}:{env['PATH']}",
                R2_PROJECT=str(repo), R2_SPACE=str(base / "space"), R2_HERDR_LOG=str(base / "herdr.jsonl"),
                HERDR_PANE_ID="wRoot:p1", HERDR_WORKSPACE_ID="wRoot")
            result = call("bash", str(repo / "qwbuddy/bin/qwb-run.sh"), "--project", str(repo),
                          "--task", "case", "--worker", "pi", env=env)
            assert result.returncode != 0 and not (repo / ".worktrees/case").exists(), (kind, result.stderr)
            assert not (base / "herdr.jsonl").exists() or not any(
                json.loads(line)[:2] == ["worktree", "open"] for line in (base / "herdr.jsonl").read_text().splitlines())
    print("R2 LAYOUT PASS: separate git dir and submodule dispatch; nested and linked roots reject")


def branch_config():
    for fail_cleanup in (False, True):
      with tempfile.TemporaryDirectory(prefix="qwb-r2-config-") as d:
        repo, ticket, env, _ = fixture(Path(d))
        wt = repo / ".worktrees/case"
        git("-C", repo, "worktree", "add", "-qb", "case", wt)
        git("-C", repo, "config", "branch.case.remote", "origin")
        git("-C", repo, "config", "branch.case.merge", "refs/heads/old")
        if fail_cleanup:
            shim = Path(d) / "stub/git"
            shim.write_text('#!/usr/bin/env bash\nif [[ "$*" == *"config --local --remove-section"* ]]; '
                            'then exit 9; fi\nexec "$R2_REAL_GIT" "$@"\n')
            shim.chmod(0o755)
            env["R2_REAL_GIT"] = shutil.which("git")
        result = call("bash", str(ROOT / "bin/qwb-worktree.sh"), "finish", "case", "--merged",
                      "--project", str(repo), env=env)
        assert result.returncode == 0 and not wt.exists(), result.stderr
        config_remains = call("git", "-C", str(repo), "config", "--get-regexp", "^branch\\.case\\.").returncode == 0
        assert config_remains == fail_cleanup, result.stderr
        if fail_cleanup:
            assert "配置节清理失败" in result.stderr and "config --local --remove-section" in result.stderr
        assert "worktree: merged" in ticket.read_text()
    print("R2 BRANCH CONFIG PASS: completed finish removes section; cleanup failure warns without rollback")


def recovery():
    for action, changed in (("archive", False), ("archive", True), ("merged", False)):
        with tempfile.TemporaryDirectory(prefix="qwb-r2-recovery-") as d:
            base = Path(d); repo, ticket, env, _ = fixture(base)
            wt = repo / ".worktrees/case"
            git("-C", repo, "worktree", "add", "-qb", "case", wt)
            if action == "archive":
                git("-C", wt, "commit", "-qm", "new", "--allow-empty")
            oid = git("-C", wt, "rev-parse", "HEAD")
            git("-C", repo, "config", "branch.case.remote", "origin")
            git("-C", repo, "config", "branch.case.merge", "refs/heads/old")
            shim = base / "stub/git"
            shim.write_text('#!/usr/bin/env bash\nif [[ "$*" == *"update-ref -d"* && '
                            '! -e "$R2_FAIL_ONCE" ]]; then touch "$R2_FAIL_ONCE"; exit 9; fi\n'
                            'exec "$R2_REAL_GIT" "$@"\n')
            shim.chmod(0o755)
            env.update(R2_FAIL_ONCE=str(base / "failed"), R2_REAL_GIT=shutil.which("git"))
            cmd = ("bash", str(ROOT / "bin/qwb-worktree.sh"), "finish", "case", "--" + action,
                   "--project", str(repo))
            first = call(*cmd, env=env)
            assert first.returncode != 0 and not wt.exists(), first.stderr
            assert f"stage=branch-delete" in ticket.read_text() and f"oid={oid}" in ticket.read_text()
            if changed:
                base_oid = git("-C", repo, "rev-parse", "HEAD")
                git("-C", repo, "update-ref", "refs/heads/case", base_oid)
            resumed = call(*cmd, env=env)
            if changed:
                assert resumed.returncode != 0 and ticket.read_text().split("worktree:")[-1].startswith(
                    f" partial action={action}"), resumed.stderr
                assert git("-C", repo, "rev-parse", "refs/heads/case") != oid
            else:
                assert resumed.returncode == 0, resumed.stderr
                last = [line for line in ticket.read_text().splitlines() if line.startswith("worktree:")][-1]
                assert last.startswith(f"worktree: {action} "), last
                assert call("git", "-C", str(repo), "show-ref", "--verify", "--quiet",
                            "refs/heads/case").returncode != 0
                assert call("git", "-C", str(repo), "config", "--get-regexp", "^branch\\.case\\.").returncode != 0
    print("R2 RECOVERY PASS: same OID resumes to final ledger and config cleanup; advanced ref rejects")


def warning():
    with tempfile.TemporaryDirectory(prefix="qwb-r2-warning-") as d:
        repo, ticket, env, log = fixture(Path(d))
        result = call("bash", str(repo / "qwbuddy/bin/qwb-run.sh"), "--project", str(repo),
                      "--task", "case", "--worker", "pi", env=env)
        assert result.returncode == 0, result.stderr
        assert "工人 tab 开在调用者 workspace" not in result.stderr, result.stderr
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        assert any(c[:2] == ["tab", "create"] and "wTask" in c for c in calls), calls
        ticket2 = repo / "tasks/2099-01-02-reuse.md"; ticket2.write_text(TASK)
        reused = call("bash", str(repo / "qwbuddy/bin/qwb-run.sh"), "--project", str(repo),
                      "--task", "reuse", "--worker", "pi", "--worktree",
                      str(repo / ".worktrees/case"), env=env)
        assert reused.returncode == 0 and "工人 tab 开在调用者 workspace" not in reused.stderr, reused.stderr
        ticket2 = repo / "tasks/2099-01-02-here.md"; ticket2.write_text(TASK)
        here = call("bash", str(repo / "qwbuddy/bin/qwb-run.sh"), "--project", str(repo),
                    "--task", "here", "--worker", "pi", "--here", env=env)
        assert here.returncode == 0 and "工人 tab 开在调用者 workspace" in here.stderr, here.stderr
    for mode in ("query-fail", "bad-response"):
        with tempfile.TemporaryDirectory(prefix="qwb-r2-warning-fail-") as d:
            repo, ticket, env, log = fixture(Path(d))
            env["R2_MODE"] = mode
            before = ticket.read_bytes()
            rejected = call("bash", str(repo / "qwbuddy/bin/qwb-run.sh"), "--project", str(repo),
                            "--task", "case", "--worker", "pi", env=env)
            assert rejected.returncode != 0 and ticket.read_bytes() == before, (mode, rejected.stderr)
            assert not (repo / ".worktrees/case").exists()
            assert not any(json.loads(line)[:2] in (["worktree", "open"], ["tab", "create"])
                           for line in log.read_text().splitlines())
    print("R2 WARNING PASS: default/reused Space dispatch quiet; --here warns; bad query refuses before side effects")


if __name__ == "__main__":
    cases = {"permissions": permissions, "layout": layout, "branch_config": branch_config,
             "recovery": recovery, "warning": warning}
    selected = sys.argv[1:] or list(cases)
    for name in selected:
        cases[name]()
