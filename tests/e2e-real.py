"""Implementation of e2e-real.sh; only invoked by the foreground shell entrypoint."""
import datetime as dt
import json
import os
from pathlib import Path
import re
import secrets
import shlex
import subprocess
import sys
import time
import traceback

ROOT = Path(os.environ["QWB_E2E_ROOT"])
SHA = os.environ["QWB_E2E_SHA"]
BASE = Path(os.environ["QWB_E2E_BASE"])
SESSION = os.environ["QWB_E2E_SESSION"]
SOCKET = os.environ["QWB_E2E_SOCKET"]
WORKER = os.environ["QWB_E2E_WORKER"]
MODEL = os.environ["QWB_E2E_MODEL"]
EFFORT = os.environ["QWB_E2E_EFFORT"]
TIMEOUT_MS = int(os.environ["QWB_E2E_TIMEOUT_MS"])
REPORT = Path(os.environ["QWB_E2E_REPORT"])
REPO = BASE / "project"
TICKET = REPO / "tasks/2099-01-01-e2e.md"
WT = REPO / ".worktrees/e2e"
NONCE = secrets.token_hex(8)
EXPECTED = f"QWB E2E OK {NONCE}\n".encode()
TIMELINE = []
CHECKS = {}
ERROR = ""
VERSIONS = {}
CONTROL_PANE = ""
WORKER_PANE = ""
TASK_SPACE = ""
BASE_SPACES = []
LAST_SPACES = []
DONE = False
BLOCKED = False
NAMED_ENV = os.environ.copy()
for key in ("HERDR_PANE_ID", "HERDR_TAB_ID", "HERDR_WORKSPACE_ID"):
    NAMED_ENV.pop(key, None)
NAMED_ENV["HERDR_SOCKET_PATH"] = SOCKET


def event(message):
    now = dt.datetime.now(dt.timezone.utc).isoformat()
    TIMELINE.append(f"{now} {message}")
    print(message, flush=True)


def run(args, *, cwd=None, env=None, timeout=60, check=True):
    result = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True,
                            errors="replace", timeout=timeout)
    with (BASE / "commands.jsonl").open("a") as file:
        file.write(json.dumps({"argv": args, "cwd": str(cwd) if cwd else None,
                               "rc": result.returncode, "stdout": result.stdout,
                               "stderr": result.stderr}, ensure_ascii=False) + "\n")
    if check and result.returncode:
        raise RuntimeError(f"命令 rc={result.returncode}: {args!r}: {result.stderr[-1200:]}")
    return result


def h(*args, timeout=60, check=True):
    status = run(["herdr", "status", "server"], env=NAMED_ENV, timeout=10)
    if f"socket: {SOCKET}" not in status.stdout or "status: running" not in status.stdout:
        raise RuntimeError(f"Herdr socket 身份不符：{status.stdout}")
    return run(["herdr", *args], env=NAMED_ENV, timeout=timeout, check=check)


def hjson(*args, timeout=60, check=True):
    result = h(*args, timeout=timeout, check=check)
    return json.loads(result.stdout) if result.returncode == 0 else None


def spaces():
    return hjson("workspace", "list")["result"]["workspaces"]


def pane_read(pane, path, lines=130):
    result = h("pane", "read", pane, "--source", "recent-unwrapped", "--lines", str(lines),
               check=False)
    if result.returncode == 0:
        with path.open("a") as file:
            file.write(f"\n--- {dt.datetime.now(dt.timezone.utc).isoformat()} ---\n{result.stdout}\n")
        return result.stdout
    return ""


def wait_idle(pane, seconds=120):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = hjson("agent", "wait", pane, "--until", "idle", "--until", "blocked",
                       "--timeout", "15000", timeout=25, check=False)
        if result:
            state = result["result"]["agent"]["agent_status"]
            if state == "blocked":
                view = pane_read(pane, BASE / "controller-transcript.txt", 90)
                if trust_prompt_is_current(view):
                    h("pane", "send-keys", pane, "enter")
                    continue
                raise RuntimeError(f"主控 pane {pane} 进入 blocked；见 controller-transcript.txt")
            if state == "idle":
                return
        view = pane_read(pane, BASE / "controller-transcript.txt", 90)
        if trust_prompt_is_current(view):
            h("pane", "send-keys", pane, "enter")
    raise RuntimeError(f"主控 pane {pane} 启动后未进入 idle")


def trust_prompt_is_current(view):
    text = view.lower()
    prompt_at = max(text.rfind("trust this folder?"), text.rfind("trust this directory"))
    return (prompt_at >= 0 and "trust and continue" in text[prompt_at:]
            and prompt_at > text.rfind("ask codex to do anything"))


def setup():
    global CONTROL_PANE, BASE_SPACES
    for name in ("herdr", "codex", "devin", "cmdc"):
        if name == "codex":
            VERSIONS[name] = [os.environ["QWB_E2E_CODEX_VERSION"]]
        else:
            result = run([name, "--version"], check=False, timeout=30)
            VERSIONS[name] = (result.stdout or result.stderr).strip().splitlines()[:2]
    REPO.mkdir()
    run(["git", "init", "-q", "-b", "main", str(REPO)])
    run(["git", "-C", str(REPO), "config", "user.name", "QWB E2E"])
    run(["git", "-C", str(REPO), "config", "user.email", "qwb-e2e@example.invalid"])
    run(["bash", str(ROOT / "bin/qwb-init.sh"), str(REPO)])
    config = REPO / "qwbuddy/config.sh"
    config.write_text(
        f"QWB_WORKERS='{WORKER}'\nQWB_WORKSPACE=''\nQWB_AGENT_START_MS=120000\n"
        "QWB_WAKE_INTERVAL_MS=1000\nQWB_REWAKE_MS=30000\n"
        "QWB_GATE_FAST='test -f e2e/hello.txt'\n"
        f"QWB_GATE_FULL=\"cmp -s e2e/hello.txt <(printf 'QWB E2E OK {NONCE}\\n')\"\n"
    )
    workers = REPO / "qwbuddy/workers.sh"
    if WORKER == "devin":
        workers.write_text("qwb_worker devin herdr --model swe-2-max --permission-mode dangerous --respect-workspace-trust false\n")
    else:
        workers.write_text("qwb_worker cmdc pane-run cmdc --yolo --trust --skip-onboarding -m deepseek/deepseek-v4-flash\n")
    TICKET.write_text(
        f"# e2e\nstate: running\n\n## 背景与范围\n只在本隔离项目的任务 worktree 新建 e2e/hello.txt，不访问其他项目。\n"
        f"\n## 验收场景\n### 正常\nGiven 默认任务 worktree\nWhen 新增 e2e/hello.txt，内容恰为 QWB E2E OK {NONCE} 后跟一个换行，并提交\nThen 主控从 Git 提交与文件字节独立核对\n"
        "### 失败\nGiven 文件缺失、内容不符或没有提交\nWhen 主控验收\nThen 拒绝合并与收尾\n"
        "\n## 硬约束\n只改 e2e/hello.txt；工作完成后向主账本追加 done: 行，含提交 SHA 与实际检查退出码。\n"
    )
    run(["git", "-C", str(REPO), "add", "."])
    run(["git", "-C", str(REPO), "commit", "-qm", "seed"])
    made = hjson("workspace", "create", "--cwd", str(REPO), "--label", "qwb-e2e-main", "--no-focus")
    CONTROL_PANE = made["result"]["root_pane"]["pane_id"]
    BASE_SPACES = spaces()
    event(f"主 workspace 已创建；controller pane={CONTROL_PANE}")


def start_controller():
    trust = f'projects."{REPO.resolve()}".trust_level="trusted"'
    argv = ["codex", "-m", MODEL, "-c", f"model_reasoning_effort={EFFORT}", "-c", trust,
            "--dangerously-bypass-approvals-and-sandbox"]
    h("pane", "run", CONTROL_PANE, shlex.join(argv))
    model_line = re.compile(rf"(?im)^.*model:\s*{re.escape(MODEL)}\s+{re.escape(EFFORT)}\b")
    trust_sent = False
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        time.sleep(1)
        view = pane_read(CONTROL_PANE, BASE / "controller-transcript.txt", 120)
        if model_line.search(view):
            break
        if trust_prompt_is_current(view) and not trust_sent:
            h("pane", "send-keys", CONTROL_PANE, "enter")
            trust_sent = True
            event("识别到 Codex 的 Trust this folder?，仅按一次 Enter")
    else:
        raise RuntimeError(f"Codex TUI 未显示请求的模型与推理档：{MODEL}/{EFFORT}；见 controller-transcript.txt")
    wait_idle(CONTROL_PANE)
    event(f"Codex TUI 已核对模型={MODEL} 推理档={EFFORT}")
    prompt = (
        "你现在是 QW buddy。按 qwbuddy/QWBUDDY.md 开局；账本里的未结票派给 " + WORKER +
        " 工人（默认新建 worktree），按 Codex 宿主规则前台值守。工人报 done 后独立验收"
        "（跑 qwb-test.sh fast/full 并核对产出），合格则合并进 main、把 state 改为 verified、"
        "执行 qwb-worktree.sh finish e2e --merged。全部完成后单独输出一行 "
        "QWB_E2E_CONTROLLER_DONE；无法完成则输出 QWB_E2E_CONTROLLER_BLOCKED <原因>。"
    )
    h("pane", "run", CONTROL_PANE, prompt)
    event("主控提示已投递一次；后续派发、验收与收尾只由该交互主控执行")


def monitor():
    global WORKER_PANE, TASK_SPACE, LAST_SPACES, DONE, BLOCKED
    deadline = time.monotonic() + TIMEOUT_MS / 1000
    controller_started_working = False
    while time.monotonic() < deadline:
        current = spaces()
        LAST_SPACES = current
        for ws in current:
            wt = ws.get("worktree") or {}
            if wt.get("is_linked_worktree") and Path(wt.get("checkout_path", "/")).resolve() == WT.resolve():
                if Path(wt.get("repo_root", "/")).resolve() != REPO.resolve():
                    raise RuntimeError("任务 Space repo_root 不符")
                TASK_SPACE = ws["workspace_id"]
        raw = TICKET.read_bytes() if TICKET.exists() else b""
        (BASE / "ledger-tail.bin").write_bytes(raw[-8192:])
        lines = raw.decode("utf-8", "replace").splitlines()
        dispatch = [line for line in lines if line.startswith("dispatch:") and f"worker={WORKER}" in line]
        if dispatch:
            match = re.search(r" pane=([^ ]+) dir=", dispatch[-1])
            if match:
                WORKER_PANE = match.group(1)
        statuses = {}
        for label, pane in (("controller", CONTROL_PANE), ("worker", WORKER_PANE)):
            if not pane:
                continue
            info = hjson("pane", "get", pane, check=False)
            if info:
                obj = info["result"]["pane"]
                statuses[label] = obj.get("agent_status", "unknown")
                if label == "controller" and statuses[label] == "working":
                    controller_started_working = True
                if label == "worker" and TASK_SPACE:
                    if obj.get("workspace_id") != TASK_SPACE:
                        raise RuntimeError(f"工人 pane {pane} 不在任务 Space {TASK_SPACE}")
                    CHECKS["worker_space_observed"] = True
                    pane_read(pane, BASE / "worker-transcript.txt", 100)
        ctl = pane_read(CONTROL_PANE, BASE / "controller-transcript.txt", 140)
        lines = [line.strip() for line in ctl.splitlines()]
        controller_finished = controller_started_working and statuses.get("controller") in ("idle", "done")
        if controller_finished and ctl.count("QWB_E2E_CONTROLLER_BLOCKED") >= 2:
            BLOCKED = True
            event("主控输出 BLOCKED")
            break
        if controller_finished and ctl.count("QWB_E2E_CONTROLLER_DONE") >= 2:
            DONE = True
            event("主控输出 DONE")
            break
        if any(value == "blocked" for value in statuses.values()):
            BLOCKED = True
            event(f"agent 进入 blocked：{statuses}")
            break
        with (BASE / "monitor.jsonl").open("a") as file:
            file.write(json.dumps({"time": dt.datetime.now(dt.timezone.utc).isoformat(),
                                   "workspaces": current, "statuses": statuses,
                                   "ledger_tail": raw[-900:].hex()}, ensure_ascii=False) + "\n")
        time.sleep(5)
    if not DONE and not BLOCKED:
        event("等待超时")


def assert_result():
    raw = TICKET.read_bytes()
    text = raw.decode("utf-8", "replace")
    (BASE / "ticket.raw.md").write_bytes(raw)
    CHECKS["ledger"] = all((
        "scenarios-fp:" in text, "worktree-space:" in text,
        bool(re.search(rf"(?m)^dispatch: .*worker={WORKER}\b", text)),
        bool(re.search(r"(?m)^done:", text)), bool(re.search(r"(?m)^wake:", text)),
        "worktree: merged" in text, bool(re.search(r"(?m)^state: verified\s*$", text)),
    ))
    CHECKS["main_content"] = (REPO / "e2e/hello.txt").read_bytes() == EXPECTED if (REPO / "e2e/hello.txt").exists() else False
    branch = run(["git", "-C", str(REPO), "show-ref", "--verify", "--quiet", "refs/heads/e2e"], check=False)
    config = run(["git", "-C", str(REPO), "config", "--local", "--get-regexp", r"^branch\.e2e\."], check=False)
    CHECKS["git_cleanup"] = not WT.exists() and branch.returncode != 0 and config.returncode != 0
    CHECKS["space_observed"] = bool(TASK_SPACE and CHECKS.get("worker_space_observed"))
    final = spaces()
    (BASE / "spaces-before.json").write_text(json.dumps(BASE_SPACES, ensure_ascii=False, indent=2))
    (BASE / "spaces-after.json").write_text(json.dumps(final, ensure_ascii=False, indent=2))
    baseline_ids = {s["workspace_id"] for s in BASE_SPACES}
    final_ids = {s["workspace_id"] for s in final}
    CHECKS["space_cleanup"] = (
        final_ids == baseline_ids and
        all(s["workspace_id"] != TASK_SPACE for s in final) and
        all((a.get("worktree") or {}).get("checkout_path") == (b.get("worktree") or {}).get("checkout_path")
            for a in BASE_SPACES for b in final if a["workspace_id"] == b["workspace_id"])
    )
    CHECKS["controller_done"] = DONE and not BLOCKED
    default_env = os.environ.copy()
    default_env.pop("HERDR_SOCKET_PATH", None)
    default_ws = run(["herdr", "--session", "default", "workspace", "list"], env=default_env, check=False)
    default_panes = run(["herdr", "--session", "default", "pane", "list"], env=default_env, check=False)
    CHECKS["default_untouched"] = (default_ws.returncode == default_panes.returncode == 0
                                   and str(BASE) not in default_ws.stdout + default_panes.stdout)
    try:
        raw.decode("utf-8")
        CHECKS["invalid_utf8_observed"] = False
    except UnicodeDecodeError:
        CHECKS["invalid_utf8_observed"] = True
    event("断言：" + ", ".join(f"{key}={'PASS' if value else 'FAIL'}" for key, value in CHECKS.items()))


def report(rc):
    lines = ["# QWB real E2E", "", f"- 候选 SHA：`{SHA}`", f"- 工人：`{WORKER}`",
             f"- 主控模型/推理档：`{MODEL}` / `{EFFORT}`",
             f"- 工人模型：`{'swe-2-max' if WORKER == 'devin' else 'deepseek/deepseek-v4-flash'}`",
             f"- 会话：`{SESSION}`", f"- 临时项目：`{REPO}`", f"- nonce：`{NONCE}`",
             f"- 工具版本：`{json.dumps(VERSIONS, ensure_ascii=False)}`", "",
             "## 时间线", "", *[f"- {line}" for line in TIMELINE], "", "## 断言", "",
             *[f"- {'PASS' if value else 'FAIL'} {key}" for key, value in CHECKS.items()],
             "", f"- 账本含非法 UTF-8：`{CHECKS.get('invalid_utf8_observed', False)}`",
             f"- 主控转录：`{BASE / 'controller-transcript.txt'}`",
             f"- 工人转录：`{BASE / 'worker-transcript.txt'}`",
             f"- Herdr/命令日志：`{BASE / 'commands.jsonl'}`、`{BASE / 'monitor.jsonl'}`",
             f"- 最终 rc：`{rc}`"]
    if ERROR:
        lines.extend([f"- 错误：`{ERROR}`"])
    REPORT.open("x").write("\n".join(lines) + "\n")


def main():
    global ERROR
    rc = 1
    try:
        setup()
        start_controller()
        monitor()
        assert_result()
        if all(value for key, value in CHECKS.items() if key != "invalid_utf8_observed"):
            rc = 0
    except Exception as exc:
        ERROR = str(exc)
        (BASE / "exception.log").write_text(traceback.format_exc())
        event(f"E2E 失败：{exc}")
    finally:
        report(rc)
        event(f"报告已写入：{REPORT}；rc={rc}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
