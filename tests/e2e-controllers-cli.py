"""真实 E2E 入口参数的公开 CLI 回归，不启动付费主控。"""
import ast
from pathlib import Path
import os
import re
import subprocess

os.environ["HERDR_SOCKET_PATH"] = "/dev/null/qwb-test.sock"

ROOT = Path(__file__).resolve().parent.parent
ENTRY = ROOT / "tests/e2e-real.sh"


def invoke(*args):
    return subprocess.run(["bash", str(ENTRY), *args], cwd=ROOT,
                          capture_output=True, text=True)


help_result = invoke("--help")
assert help_result.returncode == 0, help_result.stderr
for expected in ("--controller codex|claude|pi", "gpt-6-luna/max", "opus/high",
                 "magpie/codex/gpt-6.1-sol/high", "~/.codex/config.toml",
                 'service_tier="default"', "TUI 模型/状态行出现 fast 即失败",
                 "~/.pi/agent/trust.json", "~/.claude.json"):
    assert expected in help_result.stdout, expected

invalid = invoke("--worker", "devin", "--controller", "other")
assert invalid.returncode == 2, (invalid.returncode, invalid.stderr)
assert "--controller 只接受 codex|claude|pi" in invalid.stderr

# Load only the pure checker: importing the real runner would require live E2E state.
source = ast.parse((ROOT / "tests/e2e-real.py").read_text())
checker = next(node for node in source.body
               if isinstance(node, ast.FunctionDef) and node.name == "controller_model_visible")
namespace = {"re": re}
exec(compile(ast.Module(body=[checker], type_ignores=[]), str(ENTRY.with_suffix(".py")), "exec"), namespace)
visible = namespace["controller_model_visible"]

# Key status lines copied from the controller's real transcripts, independent of .qwb-tmp.
codex_view = "  GPT-6-Luna max · Context 100% left · weekly 19% left · 450K window\n"
pi_view = "░▒▓ 🔌 magpie 🤖 codex/gpt-6.1-sol 🧠 high 📁 project 🌿 main 🪟 ctx 0.0%/512k 🔢 tok 0 💸 $0.000 🕒 16:18\n"
for controller, model, effort, views in (
    ("codex", "gpt-6-luna", "max", (codex_view, "model: gpt-6-luna max\nContext 100% left\n")),
    ("pi", "magpie/codex/gpt-6.1-sol", "high", (pi_view, "magpie/codex/gpt-6.1-sol · high\n")),
):
    for view in views:
        assert visible(view, controller, model, effort), (controller, view)
        wrong_model = re.sub(re.escape(model.split("/")[-1]), "other-model", view, flags=re.I)
        assert not visible(wrong_model, controller, model, effort), controller
        assert not visible(view.replace(effort, "low"), controller, model, effort), controller
        assert not visible(view.replace(effort, effort + "-other"), controller, model, effort), controller
assert not visible(pi_view.replace("magpie", "other-provider"), "pi", "magpie/codex/gpt-6.1-sol", "high")
assert not visible("model: gpt-6-luna max\n", "codex", "gpt-6-luna", "max")
assert visible("Opus with high effort", "claude", "opus", "high")
assert not visible("Opus with low effort", "claude", "opus", "high")
for view in (codex_view, "model: gpt-6-luna max\nContext 100% left\n"):
    try:
        visible(view.replace("max", "max fast"), "codex", "gpt-6-luna", "max")
    except RuntimeError as error:
        assert str(error) == "Codex TUI 模型/状态行出现 fast，拒绝运行真实 E2E"
    else:
        raise AssertionError("Codex fast was accepted")
assert visible("fast appears in conversation\n" + codex_view, "codex", "gpt-6-luna", "max")

print("E2E CONTROLLERS CLI PASS: help declarations, invalid controller, current/legacy TUI identity and fast rejection")
