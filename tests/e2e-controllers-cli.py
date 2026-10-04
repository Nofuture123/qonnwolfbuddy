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
for expected in ("--worker pi|claude", "--controller claude|pi", "sonnet/low",
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
         "claude_projects", "claude_trust_prompt", "accept_claude_trust", "setup", "start_controller"}
functions = [node for node in source.body if isinstance(node, ast.FunctionDef) and node.name in names]
namespace = {"re": re, "json": json, "os": os}
exec(compile(ast.Module(body=functions, type_ignores=[]), str(ENTRY.with_suffix(".py")), "exec"), namespace)
visible = namespace["controller_model_visible"]
pi_view = "░▒▓ 🔌 magpie 🤖 codex/gpt-6.1-sol 🧠 high 📁 project 🌿 main 🪟 ctx 0.0%/512k\n"
for view in (pi_view, "magpie/codex/gpt-6.1-sol · high\n"):
    assert visible(view, "pi", "magpie/codex/gpt-6.1-sol", "high"), view
    assert not visible(view.replace("gpt-6.1-sol", "other-model"), "pi", "magpie/codex/gpt-6.1-sol", "high")
    assert not visible(view.replace("magpie", "other-provider"), "pi", "magpie/codex/gpt-6.1-sol", "high")
    assert not visible(view.replace("high", "low"), "pi", "magpie/codex/gpt-6.1-sol", "high")
    assert not visible(view.replace("high", "high-other"), "pi", "magpie/codex/gpt-6.1-sol", "high")
assert visible("Sonnet with low effort", "claude", "sonnet", "low")
assert not visible("Sonnet with high effort", "claude", "sonnet", "low")
assert not visible("Opus with low effort", "claude", "sonnet", "low")

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

print("E2E CONTROLLERS CLI PASS: two-tool CLI, TUI identity, both participants' global state, worker argv/session/trust boundaries")
