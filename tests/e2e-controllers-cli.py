"""真实 E2E 入口参数的公开 CLI 回归，不启动付费主控。"""
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent
ENTRY = ROOT / "tests/e2e-real.sh"


def invoke(*args):
    return subprocess.run(["bash", str(ENTRY), *args], cwd=ROOT,
                          capture_output=True, text=True)


help_result = invoke("--help")
assert help_result.returncode == 0, help_result.stderr
for expected in ("--controller codex|claude|pi", "gpt-6-luna/max", "opus/high",
                 "zai-coding-cn/glm-5.3-flash/high", "~/.codex/config.toml",
                 'service_tier="default"', "TUI 模型/状态行出现 fast 即失败",
                 "~/.pi/agent/trust.json", "~/.claude.json"):
    assert expected in help_result.stdout, expected

invalid = invoke("--worker", "devin", "--controller", "other")
assert invalid.returncode == 2, (invalid.returncode, invalid.stderr)
assert "--controller 只接受 codex|claude|pi" in invalid.stderr

print("E2E CONTROLLERS CLI PASS: help declarations, invalid controller")
