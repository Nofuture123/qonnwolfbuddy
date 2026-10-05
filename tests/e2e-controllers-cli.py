"""真实 E2E 入口与纯函数回归；不启动付费主控或连接真 Herdr。"""
import ast
import json
from pathlib import Path
import os
import re
import subprocess
import tempfile

os.environ["HERDR_SOCKET_PATH"] = "/dev/null/qwb-test.sock"
ROOT = Path(__file__).resolve().parent.parent
ENTRY = ROOT / "tests/e2e-real.sh"
TEST_TMP_ROOT = ROOT / ".qwb-tmp"
TEST_TMP_ROOT.mkdir(exist_ok=True)


def invoke(*args):
    return subprocess.run(["bash", str(ENTRY), *args], cwd=ROOT,
                          capture_output=True, text=True)


help_result = invoke("--worker", "pi", "--controller", "claude", "--help")
assert help_result.returncode == 0, help_result.stderr
for expected in ("--worker pi|claude", "--controller claude|pi", "claude-opus-5-5/medium",
                 "claude-opus-5-5/medium", "magpie/codex/gpt-6.1-sol/high",
                 "~/.pi/agent/trust.json", "~/.claude.json"):
    assert expected in help_result.stdout, expected
for option, value, expected in (
    ("--worker", "devin", "--worker 只接受 pi|claude"),
    ("--worker", "cmdc", "--worker 只接受 pi|claude"),
    ("--controller", "codex", "--controller 只接受 claude|pi"),
    ("--controller", "other", "--controller 只接受 claude|pi"),
):
    args = ["--worker", "pi"] if option == "--controller" else []
    invalid = invoke(*args, option, value)
    assert invalid.returncode == 2 and expected in invalid.stderr, (invalid.returncode, invalid.stderr)

# Import only selected functions: the real runner reads live E2E environment at module load.
source = ast.parse((ROOT / "tests/e2e-real.py").read_text())
names = {"controller_model_visible", "snapshot_global_state", "check_global_state",
         "claude_projects", "claude_trust_prompt", "accept_claude_trust", "setup", "start_controller",
         "git_runtime_clean"}
functions = [node for node in source.body if isinstance(node, ast.FunctionDef) and node.name in names]
namespace = {"re": re, "json": json, "os": os}
exec(compile(ast.Module(body=functions, type_ignores=[]), str(ENTRY.with_suffix(".py")), "exec"), namespace)
# Render the real controller prompt without executing its live startup boundaries.
controller_start = next(node for node in functions if node.name == "start_controller")
prompt_assignment = next(node for node in controller_start.body if isinstance(node, ast.Assign) and
                         any(isinstance(target, ast.Name) and target.id == "prompt" for target in node.targets))
prompt_context = {"WORKER": "pi", "TASK_ID": "offline-task"}
exec(compile(ast.Module(body=[prompt_assignment], type_ignores=[]), str(ENTRY.with_suffix(".py")), "exec"), prompt_context)
prompt = prompt_context["prompt"]
assert "收尾后提交应入库的任务书等产物" in prompt, prompt
assert "qwb-worktree.sh finish offline-task --merged" in prompt, prompt
assert "qwb-lock" not in prompt, prompt
assert "运行态" not in prompt and "git status" not in prompt, prompt
print("PASS real E2E controller prompt: normal cleanup requirements retained, runtime assertions not disclosed")
visible = namespace["controller_model_visible"]
pi_view = "░▒▓ 🔌 magpie 🤖 codex/gpt-6.1-sol 🧠 high 📁 project 🌿 main 🪟 ctx 0.0%/512k\n"
for view in (pi_view, "magpie/codex/gpt-6.1-sol · high\n"):
    assert visible(view, "pi", "magpie/codex/gpt-6.1-sol", "high"), view
    assert not visible(view.replace("gpt-6.1-sol", "other-model"), "pi", "magpie/codex/gpt-6.1-sol", "high")
    assert not visible(view.replace("magpie", "other-provider"), "pi", "magpie/codex/gpt-6.1-sol", "high")
    assert not visible(view.replace("high", "low"), "pi", "magpie/codex/gpt-6.1-sol", "high")
    assert not visible(view.replace("high", "high-other"), "pi", "magpie/codex/gpt-6.1-sol", "high")
assert visible("Opus 5.5 with medium effort", "claude", "claude-opus-5-5", "medium")
assert not visible("Opus 5.5 with low effort", "claude", "claude-opus-5-5", "medium")
assert not visible("Opus 5.4 with medium effort", "claude", "claude-opus-5-5", "medium")
assert not visible("Sonnet with medium effort", "claude", "claude-opus-5-5", "medium")

with tempfile.TemporaryDirectory(dir=TEST_TMP_ROOT, prefix="e2e-cli-") as tmp:
    base = Path(tmp)
    pi_state, claude_state = base / "trust.json", base / "claude.json"
    pi_state.write_bytes(b'{"trusted":[]}\n')
    claude_state.write_bytes(b'{"projects":{"old":{}}}')
    namespace.update(STATE_PATHS={"pi": pi_state, "claude": claude_state},
                     CHECKS={}, event=lambda message: None, CLAUDE_PROJECTS_BEFORE={"old"})
    for controller, worker in (("pi", "pi"), ("pi", "claude"), ("claude", "pi"), ("claude", "claude")):
        namespace.update(CONTROLLER=controller, WORKER=worker)
        namespace["STATE_BEFORE"] = namespace["snapshot_global_state"]()
        assert set(namespace["STATE_BEFORE"]) == {controller, worker}
        namespace["check_global_state"]()
        if "pi" in (controller, worker):
            assert namespace["CHECKS"]["global_state_unchanged"]
            pi_state.write_bytes(b'changed')
            namespace["check_global_state"]()
            assert not namespace["CHECKS"]["global_state_unchanged"]
            pi_state.write_bytes(namespace["STATE_BEFORE"]["pi"])
    namespace.update(CONTROLLER="claude", WORKER="pi")
    pi_state.unlink()
    namespace["STATE_BEFORE"] = namespace["snapshot_global_state"]()
    namespace["check_global_state"]()
    assert namespace["CHECKS"]["global_state_unchanged"]
    pi_state.write_bytes(b'created')
    namespace["check_global_state"]()
    assert not namespace["CHECKS"]["global_state_unchanged"]
    claude_state.write_bytes(b'{"projects":{"old":{},"new":{}}}')
    namespace["check_global_state"]()
    assert namespace["CLAUDE_PROJECTS_ADDED"] == ["new"]

    # Invoke real setup with only git/init/Herdr boundaries stubbed; inspect generated worker argv.
    import shlex
    namespace.update(BASE=base, ROOT=ROOT, shlex=shlex, NONCE="offline", VERSIONS={},
                     run=lambda *args, **kwargs: None, spaces=lambda: [],
                     hjson=lambda *args: {"result": {"root_pane": {"pane_id": "offline"}}})
    os.environ["QWB_E2E_CONTROLLER_VERSION"] = "offline"
    for worker in ("pi", "claude"):
        repo = base / worker
        (repo / "qwbuddy").mkdir(parents=True)
        (repo / "tasks").mkdir()
        # setup owns the repository mkdir; remove the empty outer shell and recreate through its run stub.
        def fake_run(args, **kwargs):
            if repo.exists():
                (repo / "qwbuddy").mkdir(exist_ok=True)
                (repo / "tasks").mkdir(exist_ok=True)
            return subprocess.CompletedProcess(args, 0, "offline", "")
        namespace.update(REPO=repo, TICKET=repo / "tasks/task.md", WORKER=worker,
                         CONTROLLER="claude", run=fake_run)
        (repo / "qwbuddy").rmdir()
        (repo / "tasks").rmdir()
        repo.rmdir()
        namespace["setup"]()
        ticket_text = namespace["TICKET"].read_text()
        assert re.search(r"(?m)^implementation-authorized: .+", ticket_text), ticket_text
        assert re.search(r"(?m)^dispatch-budget: [1-9][0-9]*$", ticket_text), ticket_text
        argv = shlex.split((repo / "qwbuddy/workers.sh").read_text())
        assert argv[:5] == ["qwb_worker", worker, "herdr", worker, "--"]
        if worker == "pi":
            assert argv[argv.index("--provider") + 1] == "magpie"
            assert argv[argv.index("--model") + 1] == "codex/gpt-6.1-sol"
            assert argv[argv.index("--thinking") + 1] == "high"
            session = Path(argv[argv.index("--session-dir") + 1])
            assert session.parent == base and session.is_dir()
        else:
            assert argv[argv.index("--model") + 1] == "claude-opus-5-5"
            assert argv[argv.index("--effort") + 1] == "medium"
            assert argv[argv.index("--add-dir") + 1] == str(repo.resolve())
        view = (f"Accessing workspace:\n\n {repo.resolve()}\n"
                "Quick safety check: Is this a project you created or one you trust?\n"
                "❯ No, exit\nYes, I trust this folder\nEnter to confirm · Esc to cancel")
        assert namespace["claude_trust_prompt"](view, repo)
        assert not namespace["claude_trust_prompt"](view, base / "other")
        import types
        frames = iter((view, view.replace("❯ No, exit", "No, exit").replace("Yes, I trust this folder", "❯ Yes, I trust this folder")))
        keys = []
        namespace.update(time=types.SimpleNamespace(monotonic=lambda: 0),
                         pane_read=lambda *args: next(frames),
                         h=lambda *args: keys.append(args))
        namespace["accept_claude_trust"]("offline-worker", repo)
        assert keys == [("pane", "send-keys", "offline-worker", "Down"),
                        ("pane", "send-keys", "offline-worker", "Enter")]
        frames = iter((view, "unconfirmed selection"))
        keys.clear()
        try:
            namespace["accept_claude_trust"]("offline-worker", repo)
        except RuntimeError as error:
            assert "不按 Enter" in str(error)
        else:
            raise AssertionError("unconfirmed trust selection accepted")
        assert keys == [("pane", "send-keys", "offline-worker", "Down")]

# Exercise the real installer upgrade path with the exact pre-fix ignore segment,
# including project-owned bytes after the marker and a missing final newline.
OLD_RULES = [".worktrees/", "qwbuddy/.controller.lock/", "qwbuddy/.watch", "qwbuddy/.posture.md",
             "qwbuddy/.posture.md.qwb-lock", "qwbuddy/.watch.lock/", "qwbuddy/.hook.lock/",
             "qwbuddy/.hook.err", "qwbuddy/.pi-watch.err"]
RUNTIME_PATHS = [
    "tasks/normal.md.qwb-lock", "tasks/normal.md.qwb-original", "tasks/.qwb-publish-fixture",
    "tasks/.qwb-lsof-fixture", "qwbuddy/.supervisor.guard", "qwbuddy/.roles/gate.json",
    "qwbuddy/.roles/gate.sessions/session.jsonl", "qwbuddy/.roles/gate.inbox/request.msg",
    "qwbuddy/.roles/.role-fixture", "qwbuddy/.qwb-publish-fixture",
    "qwbuddy/.qwb-install.fixture", "qwbuddy/roles/.qwb-install.fixture",
    "qwbuddy/bin/.qwb-install.fixture", "qwbuddy/test-policy/.qwb-install.fixture",
    ".pi/extensions/.qwb-install.fixture", "qwbuddy/.workers.fixture", "qwbuddy/.config.fixture",
    ".qwb-gitignore.fixture", ".qwb-hook.fixture", ".claude/.qwb-settings.fixture",
    "reports/.qwb-reuse-fixture", "reports/.qwb-receipt-fixture",
    "reports/.qwb-test-preflight.fixture", "reports/.qwb-test-report.fixture",
]
USER_PATHS = ["tasks/normal.md", "tasks/lessons/note.md", "qwbuddy/config.sh", "qwbuddy/workers.sh",
              "qwbuddy/roles/门禁.md", "qwbuddy/brief-include.md", "qwbuddy/dispatch-rules.json",
              "qwbuddy/test-policy/qwb-v1.md", "qwbuddy/config.sh.worker-config.bak",
              ".pi/extensions/qwb-watch.ts.bak", "reports/result.json"]
with tempfile.TemporaryDirectory(dir=TEST_TMP_ROOT, prefix="ignore-cli-") as tmp:
    repo = Path(tmp)
    def git(*args):
        return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, text=True)
    def install():
        result = subprocess.run(["/bin/bash", str(ROOT / "bin/qwb-init.sh"), str(repo)],
                                capture_output=True, text=True)
        assert result.returncode == 0, (result.stdout, result.stderr)
    assert git("init", "-q").returncode == 0
    install()
    fresh = (repo / ".gitignore").read_bytes()
    old = ("# project prefix\r\nnode_modules/\r\n"
           "# QW buddy 运行态（qwb-init.sh 写入，勿手改本段）\n" +
           "\n".join(OLD_RULES) + "\n# project suffix\nuser-local/").encode()
    (repo / ".gitignore").write_bytes(old)
    install()
    upgraded = (repo / ".gitignore").read_bytes()
    added = b"".join(line + b"\n" for line in fresh.splitlines()[1:]
                     if line.decode() not in OLD_RULES)
    assert upgraded == old + b"\n" + added, (old, upgraded)
    install()
    assert (repo / ".gitignore").read_bytes() == upgraded
    print("PASS runtime ignore upgrade: original project bytes preserved, missing rules appended, reinstall byte-identical")
    for path in RUNTIME_PATHS + USER_PATHS:
        target = repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        if not target.exists(): target.write_text("fixture\n")
    for path in RUNTIME_PATHS:
        result = git("check-ignore", "--no-index", path)
        assert result.returncode == 0, (path, result.stdout, result.stderr)
    for path in USER_PATHS:
        result = git("check-ignore", "--no-index", path)
        assert result.returncode == 1 and result.stdout == "", (path, result.stdout, result.stderr)
    status = git("status", "--short", "--untracked-files=all")
    assert status.returncode == 0, status.stderr
    assert all(path in status.stdout for path in ("tasks/normal.md", "qwbuddy/config.sh", "qwbuddy/workers.sh"))
    assert not any(path in status.stdout for path in RUNTIME_PATHS), status.stdout
    print("PASS runtime ignore boundaries: runtime/transient paths hidden, tickets/config/workers/roles/backups/reports visible")
    namespace["run"] = lambda args: subprocess.run(args, capture_output=True, text=True, check=True)
    assert git("add", ".").returncode == 0
    assert git("-c", "user.name=Test", "-c", "user.email=test@invalid", "commit", "-qm", "seed").returncode == 0
    assert namespace["git_runtime_clean"](repo)
    (repo / "tasks/normal.md").write_text("changed\n")
    assert not namespace["git_runtime_clean"](repo), "dirty final checkout passed real E2E assertion"
    assert git("add", "tasks/normal.md").returncode == 0
    assert git("-c", "user.name=Test", "-c", "user.email=test@invalid", "commit", "-qm", "Record ticket").returncode == 0
    historical_lock = "tasks/中文票.md.qwb-lock"
    (repo / historical_lock).write_text("lock\n")
    assert git("add", "-f", historical_lock).returncode == 0
    assert git("-c", "user.name=Test", "-c", "user.email=test@invalid", "commit", "-qm", "Record lock counterexample").returncode == 0
    assert not namespace["git_runtime_clean"](repo), "tracked lock passed real E2E assertion"
    assert git("rm", historical_lock).returncode == 0
    assert git("-c", "user.name=Test", "-c", "user.email=test@invalid", "commit", "-qm", "Remove lock counterexample").returncode == 0
    assert git("status", "--short").stdout == ""
    assert not namespace["git_runtime_clean"](repo), "historically committed lock passed clean final checkout"
    print("PASS real E2E runtime assertion: clean success, dirty checkout rejected, removed historical lock still rejected")
assert any(isinstance(node, ast.Assign) and
           any(isinstance(target, ast.Subscript) and isinstance(target.value, ast.Name) and
               target.value.id == "CHECKS" and isinstance(target.slice, ast.Constant) and
               target.slice.value == "git_runtime_clean" for target in node.targets) and
           isinstance(node.value, ast.Call) and isinstance(node.value.func, ast.Name) and
           node.value.func.id == "git_runtime_clean" for node in ast.walk(source)), "real E2E runtime assertion not wired"
print("E2E CONTROLLERS CLI PASS: two-tool CLI, TUI identity, both participants' global state, worker argv/session/trust boundaries")
