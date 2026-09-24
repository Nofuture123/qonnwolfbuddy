"""Implementation of e2e-real.sh; only invoked by the foreground shell entrypoint."""
import datetime as dt
import hashlib
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
CONTROLLER = os.environ["QWB_E2E_CONTROLLER"]
MODEL = os.environ["QWB_E2E_MODEL"]
EFFORT = os.environ["QWB_E2E_EFFORT"]
TIMEOUT_MS = int(os.environ["QWB_E2E_TIMEOUT_MS"])
REPORT = Path(os.environ["QWB_E2E_REPORT"])
REPO = BASE / "project"
TASK_ID = "真实闭环-e2e"
TICKET = REPO / f"tasks/2099-01-01-{TASK_ID}.md"
WT = REPO / f".worktrees/{TASK_ID}"
AGENT_PREFIX = re.sub(r"[^a-z0-9_-]", "", ("qwb-" + TASK_ID)[:32].lower())[:23]
EXPECTED_AGENT = f"{AGENT_PREFIX}-{hashlib.sha1(TASK_ID.encode('utf-8')).hexdigest()[:8]}"
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
INVALID_UTF8_OBSERVED = False
STATE_PATH = {"codex": Path.home() / ".codex/config.toml",
              "pi": Path.home() / ".pi/agent/trust.json",
              "claude": Path.home() / ".claude.json"}[CONTROLLER]
STATE_BEFORE = None
CLAUDE_PROJECTS_BEFORE = set()
CLAUDE_PROJECTS_ADDED = []
SESSION_PATH = None
HOST_WAKE_EXCERPT = ""
NAMED_ENV = os.environ.copy()
for key in ("HERDR_PANE_ID", "HERDR_TAB_ID", "HERDR_WORKSPACE_ID"):
    NAMED_ENV.pop(key, None)
NAMED_ENV["HERDR_SOCKET_PATH"] = SOCKET


def event(message):
    now = dt.datetime.now(dt.timezone.utc).isoformat()
    TIMELINE.append(f"{now} {message}")
    print(message, flush=True)


def claude_projects(raw):
    projects = json.loads(raw).get("projects", {})
    if not isinstance(projects, dict):
        raise RuntimeError("Claude ~/.claude.json 的 projects 不是对象")
    return set(projects)


def check_global_state():
    global CLAUDE_PROJECTS_ADDED
    if STATE_BEFORE is None:
        return
    if CONTROLLER == "claude":
        CLAUDE_PROJECTS_ADDED = sorted(claude_projects(STATE_PATH.read_bytes()) - CLAUDE_PROJECTS_BEFORE)
        event(f"Claude ~/.claude.json projects 新增键：{CLAUDE_PROJECTS_ADDED}")
    else:
        CHECKS["global_state_unchanged"] = STATE_PATH.read_bytes() == STATE_BEFORE
        if not CHECKS["global_state_unchanged"]:
            event(f"全局文件字节变化：{STATE_PATH}")


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


def controller_session_path():
    info = hjson("pane", "get", CONTROL_PANE, check=False)
    session = ((info or {}).get("result") or {}).get("pane", {}).get("agent_session") or {}
    if CONTROLLER == "pi" and session.get("kind") == "path":
        return Path(session["value"])
    if CONTROLLER == "claude" and session.get("kind") == "id":
        matches = list((Path.home() / ".claude/projects").glob(f"*/{session['value']}.jsonl"))
        return matches[0] if len(matches) == 1 else None
    if CONTROLLER == "codex" and session.get("kind") == "id":
        matches = list((Path.home() / ".codex/sessions").glob(f"**/*{session['value']}.jsonl"))
        return matches[0] if len(matches) == 1 else None
    return None


def session_entries():
    path = controller_session_path()
    if not path or not path.exists():
        return []
    with path.open(errors="replace") as file:
        lines = file.read().splitlines()
    entries = []
    for line in lines:
        try:
            entries.append(json.loads(line))
        except json.JSONDecodeError:
            pass  # 正在追加的最后一行可能暂时不完整。
    return entries


def message_text(entry, role):
    if entry.get("type") not in ("message", role):
        return ""
    message = entry.get("message") or {}
    if message.get("role", entry.get("type")) != role:
        return ""
    content = message.get("content", "")
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return "\n".join(item.get("text", "") for item in content if item.get("type") == "text")
    return ""


def assistant_tool_calls(entries):
    for entry in entries:
        if entry.get("type") not in ("message", "assistant"):
            continue
        message = entry.get("message") or {}
        if message.get("role", entry.get("type")) != "assistant":
            continue
        for item in message.get("content", []):
            if item.get("type") in ("tool_use", "toolCall"):
                yield json.dumps(item, ensure_ascii=False)


def codex_wake_result(entries):
    for entry in entries:
        if entry.get("type") != "event_msg":
            continue
        item = (entry.get("payload") or {}).get("item") or {}
        if item.get("type") != "CommandExecution":
            continue
        command = item.get("command") or []
        if (len(command) != 3 or command[0] not in ("/bin/zsh", "/bin/bash", "/bin/sh")
                or command[1] not in ("-lc", "-c")):
            continue
        try:
            argv = shlex.split(command[-1])
        except ValueError:
            continue
        wake_argv = (argv[:3] == ["bash", "qwbuddy/bin/qwb-wake.sh", "--block"]
                     and (len(argv) == 3 or
                          (len(argv) == 5 and argv[3] == "--max-ms" and argv[4].isdigit())))
        if (wake_argv and item.get("status") in ("completed", "failed")
                and isinstance(item.get("exit_code"), int)
                and "done:" in (item.get("stdout") or "")):
            return command[-1], item["exit_code"], (item.get("stdout") or "")[-500:]
    return None


def completed_marker(entries, marker):
    return any(re.search(rf"(?m)^\s*{re.escape(marker)}(?:\s|$)", message_text(entry, "assistant"))
               for entry in entries)


def wait_idle(pane, seconds=120):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        result = hjson("agent", "wait", pane, "--until", "idle", "--until", "blocked",
                       "--timeout", "15000", timeout=25, check=False)
        if result:
            state = result["result"]["agent"]["agent_status"]
            if state == "blocked":
                view = pane_read(pane, BASE / "controller-transcript.txt", 90)
                if CONTROLLER == "codex" and trust_prompt_is_current(view):
                    raise RuntimeError("Codex 弹出 Trust this folder?；不接受信任、不写全局配置")
                raise RuntimeError(f"主控 pane {pane} 进入 blocked；见 controller-transcript.txt")
            if state == "idle":
                return
        view = pane_read(pane, BASE / "controller-transcript.txt", 90)
        if CONTROLLER == "codex" and trust_prompt_is_current(view):
            raise RuntimeError("Codex 弹出 Trust this folder?；不接受信任、不写全局配置")
    raise RuntimeError(f"主控 pane {pane} 启动后未进入 idle")


def trust_prompt_is_current(view):
    text = view.lower()
    prompt_at = max(text.rfind("trust this folder?"), text.rfind("trust this directory"))
    return (prompt_at >= 0 and "trust and continue" in text[prompt_at:]
            and prompt_at > text.rfind("ask codex to do anything"))


def claude_trust_prompt(view):
    return (f"Accessing workspace:\n\n {REPO.resolve()}" in view
            and "Quick safety check: Is this a project you created or one you trust?" in view
            and "❯ No, exit" in view and "Yes, I trust this folder" in view
            and "Enter to confirm · Esc to cancel" in view)


def accept_claude_trust():
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        view = pane_read(CONTROL_PANE, BASE / "controller-transcript.txt", 90)
        if claude_trust_prompt(view):
            h("pane", "send-keys", CONTROL_PANE, "Down")
            selected = pane_read(CONTROL_PANE, BASE / "controller-transcript.txt", 90)
            if "❯ Yes, I trust this folder" not in selected or "Enter to confirm · Esc to cancel" not in selected:
                raise RuntimeError("Claude 信任框选择未确认，不按 Enter")
            h("pane", "send-keys", CONTROL_PANE, "Enter")
            event("Claude 已识别信任框并选择 Yes，仅按一次 Enter")
            return
        if "Claude Code v" in view and "❯" in view:
            raise RuntimeError("Claude 未出现预期信任框；隔离项目可能已有全局信任")
        time.sleep(1)
    raise RuntimeError("Claude 启动时未识别到确定的信任框")


def setup():
    global CONTROL_PANE, BASE_SPACES
    for name in ("herdr", CONTROLLER, "devin", "cmdc"):
        if name == CONTROLLER:
            VERSIONS[name] = [os.environ["QWB_E2E_CONTROLLER_VERSION"]]
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
    if CONTROLLER == "codex":
        # Herdr 把 /tmp 解析为 /private/tmp；仅本次启动覆盖信任，不写全局配置。
        trust = f'projects."{REPO.resolve()}".trust_level="trusted"'
        trust_table = f'projects={{{json.dumps(str(REPO.resolve()))}={{trust_level="trusted"}}}}'
        argv = ["codex", "-m", MODEL, "-c", f"model_reasoning_effort={EFFORT}",
                "-c", trust, "-c", trust_table,
                "--no-daemon", "--dangerously-bypass-approvals-and-sandbox"]
    elif CONTROLLER == "claude":
        argv = ["claude", "--model", MODEL, "--effort", EFFORT,
                "--permission-mode", "bypassPermissions"]
    else:
        provider, sep, model = MODEL.partition("/")
        if not sep or not provider or not model:
            raise RuntimeError("pi --controller-model 须为 provider/model")
        session_dir = BASE / "pi-sessions"
        session_dir.mkdir()
        argv = ["pi", "--approve", "--provider", provider, "--model", model,
                "--thinking", EFFORT, "--session-dir", str(session_dir)]
    h("pane", "run", CONTROL_PANE, shlex.join(argv))
    if CONTROLLER == "claude":
        accept_claude_trust()
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        time.sleep(1)
        view = pane_read(CONTROL_PANE, BASE / "controller-transcript.txt", 120)
        if CONTROLLER == "codex" and trust_prompt_is_current(view):
            raise RuntimeError("Codex 弹出 Trust this folder?；不接受信任、不写全局配置")
        if CONTROLLER == "codex":
            model_ok = bool(re.search(rf"(?im)^.*model:\s*{re.escape(MODEL)}\s+{re.escape(EFFORT)}\b", view))
        elif CONTROLLER == "claude":
            model_ok = bool(re.search(rf"(?i)\b{re.escape(MODEL)}\b.*\bwith {re.escape(EFFORT)} effort\b", view))
        else:
            model_ok = bool(re.search(rf"(?i){re.escape(MODEL)}\s*[·•]\s*{re.escape(EFFORT)}\b", view))
        if model_ok:
            break
    else:
        raise RuntimeError(f"{CONTROLLER} TUI 未显示请求的模型与推理档：{MODEL}/{EFFORT}；见 controller-transcript.txt")
    wait_idle(CONTROL_PANE)
    event(f"{CONTROLLER} TUI 已核对模型={MODEL} 推理档={EFFORT}")
    prompt = (
        "你现在是 QW buddy。按 qwbuddy/QWBUDDY.md 开局；账本里的未结票派给 " + WORKER +
        " 工人（默认新建 worktree，不传 --name），按你所在宿主的唯一值守入口等待。工人报 done 后独立验收"
        "（跑 qwb-test.sh fast/full 并核对产出），合格则合并进 main、把 state 改为 verified、"
        f"执行 qwb-worktree.sh finish {TASK_ID} --merged。全部完成后单独输出一行 "
        "QWB_E2E_CONTROLLER_DONE；无法完成则输出 QWB_E2E_CONTROLLER_BLOCKED <原因>。"
    )
    h("pane", "run", CONTROL_PANE, prompt)
    event("主控提示已投递一次；后续派发、验收与收尾只由该交互主控执行")


def monitor():
    global WORKER_PANE, TASK_SPACE, LAST_SPACES, DONE, BLOCKED
    deadline = time.monotonic() + TIMEOUT_MS / 1000
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
                if label == "worker" and TASK_SPACE:
                    if obj.get("workspace_id") != TASK_SPACE:
                        raise RuntimeError(f"工人 pane {pane} 不在任务 Space {TASK_SPACE}")
                    CHECKS["worker_space_observed"] = True
                    pane_read(pane, BASE / "worker-transcript.txt", 100)
        ctl = pane_read(CONTROL_PANE, BASE / "controller-transcript.txt", 140)
        controller_finished = statuses.get("controller") in ("idle", "done")
        # The submitted prompt contains both markers. Herdr's recent transcript
        # eventually scrolls that prompt away, so counting two occurrences loses
        # a completed answer. Codex prints "Worked for" after its final answer.
        def final_marker(marker):
            return re.search(r"(?m)^\s*" + re.escape(marker) +
                             r"(?:[^\n]*)\n(?:[ \t]*\n)*[ \t]*Worked for\b", ctl) is not None

        entries = session_entries() if CONTROLLER != "codex" else []
        marked_blocked = (final_marker("QWB_E2E_CONTROLLER_BLOCKED") if CONTROLLER == "codex"
                          else completed_marker(entries, "QWB_E2E_CONTROLLER_BLOCKED"))
        marked_done = (final_marker("QWB_E2E_CONTROLLER_DONE") if CONTROLLER == "codex"
                       else completed_marker(entries, "QWB_E2E_CONTROLLER_DONE"))
        if controller_finished and marked_blocked:
            BLOCKED = True
            event("主控输出 BLOCKED")
            break
        if controller_finished and marked_done:
            DONE = True
            event("主控输出 DONE")
            break
        if statuses.get("worker") == "blocked" or (CONTROLLER == "codex" and statuses.get("controller") == "blocked"):
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
    global INVALID_UTF8_OBSERVED, HOST_WAKE_EXCERPT, SESSION_PATH
    raw = TICKET.read_bytes()
    text = raw.decode("utf-8", "replace")
    (BASE / "ticket.raw.md").write_bytes(raw)
    CHECKS["ledger"] = all((
        "scenarios-fp:" in text, "worktree-space:" in text,
        bool(re.search(rf"(?m)^dispatch: .*worker={WORKER}\b", text)),
        bool(re.search(r"(?m)^done:", text)), bool(re.search(r"(?m)^wake:", text)),
        "worktree: merged" in text, bool(re.search(r"(?m)^state: verified\s*$", text)),
    ))
    if WORKER == "devin":
        dispatch = [line for line in text.splitlines()
                    if line.startswith("dispatch:") and f"worker={WORKER}" in line]
        CHECKS["devin_agent_name"] = bool(dispatch and
            re.search(r"(?:^| )agent=" + re.escape(EXPECTED_AGENT) + r"(?: |$)", dispatch[-1]))
    CHECKS["main_content"] = (REPO / "e2e/hello.txt").read_bytes() == EXPECTED if (REPO / "e2e/hello.txt").exists() else False
    branch = run(["git", "-C", str(REPO), "show-ref", "--verify", "--quiet", f"refs/heads/{TASK_ID}"], check=False)
    config = run(["git", "-C", str(REPO), "config", "--local", "--get-regexp", rf"^branch\.{TASK_ID}\."], check=False)
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
        all(((a.get("worktree") or {}).get("checkout_path") or str(REPO.resolve())) ==
            (b.get("worktree") or {}).get("checkout_path")
            for a in BASE_SPACES for b in final if a["workspace_id"] == b["workspace_id"])
    )
    CHECKS["controller_done"] = DONE and not BLOCKED
    if CONTROLLER == "codex":
        SESSION_PATH = controller_session_path()
        wake = codex_wake_result(session_entries())
        CHECKS["host_wake"] = bool(wake)
        HOST_WAKE_EXCERPT = f"前台命令={wake[0]}；rc={wake[1]}；stdout={wake[2]}" if wake else ""
    else:
        SESSION_PATH = controller_session_path()
        entries = session_entries()
        user_texts = [message_text(entry, "user") for entry in entries]
        if CONTROLLER == "claude":
            wake = [value for value in user_texts if "Stop hook blocking error from command \"Stop\"" in value
                    and "done:" in value]
        else:
            wake = [value for value in user_texts if "[qwb-wake]" in value and "done:" in value]
        foreground = any(re.search(r"qwb-wake\.sh.*--block", call) for call in assistant_tool_calls(entries))
        CHECKS["host_wake"] = bool(wake) and not foreground
        HOST_WAKE_EXCERPT = wake[-1][-500:] if wake else ""
        CHECKS["no_foreground_wake"] = not foreground
    default_env = os.environ.copy()
    default_env.pop("HERDR_SOCKET_PATH", None)
    default_ws = run(["herdr", "--session", "default", "workspace", "list"], env=default_env, check=False)
    default_panes = run(["herdr", "--session", "default", "pane", "list"], env=default_env, check=False)
    CHECKS["default_untouched"] = (default_ws.returncode == default_panes.returncode == 0
                                   and str(BASE) not in default_ws.stdout + default_panes.stdout)
    try:
        raw.decode("utf-8")
        INVALID_UTF8_OBSERVED = False
    except UnicodeDecodeError:
        INVALID_UTF8_OBSERVED = True
    event("断言：" + ", ".join(f"{key}={'PASS' if value else 'FAIL'}" for key, value in CHECKS.items()))


def report(rc):
    lines = ["# QWB real E2E", "", f"- 候选 SHA：`{SHA}`", f"- 主控：`{CONTROLLER}`",
             f"- 工人：`{WORKER}`",
             f"- 中文票 id：`{TASK_ID}`", f"- 默认工人名预期：`{EXPECTED_AGENT}`",
             f"- 主控模型/推理档：`{MODEL}` / `{EFFORT}`",
             f"- 工人模型：`{'swe-2-max' if WORKER == 'devin' else 'deepseek/deepseek-v4-flash'}`",
             f"- 会话：`{SESSION}`", f"- 临时项目：`{REPO}`", f"- nonce：`{NONCE}`",
             f"- 工具版本：`{json.dumps(VERSIONS, ensure_ascii=False)}`", "",
             "## 时间线", "", *[f"- {line}" for line in TIMELINE], "", "## 断言", "",
             *[f"- {'PASS' if value else 'FAIL'} {key}" for key, value in CHECKS.items()],
             "", f"- 账本含非法 UTF-8：`{INVALID_UTF8_OBSERVED}`",
             f"- 主控转录：`{BASE / 'controller-transcript.txt'}`",
             f"- 工人转录：`{BASE / 'worker-transcript.txt'}`",
             f"- Herdr/命令日志：`{BASE / 'commands.jsonl'}`、`{BASE / 'monitor.jsonl'}`",
             f"- 主控会话 JSONL：`{SESSION_PATH}`",
             f"- 宿主唤醒证据：`{HOST_WAKE_EXCERPT}`",
             f"- 最终 rc：`{rc}`"]
    if CONTROLLER == "claude":
        lines.append(f"- ~/.claude.json projects 新增键：`{CLAUDE_PROJECTS_ADDED}`")
    else:
        lines.extend([f"- 全局文件：`{STATE_PATH}`",
                      f"- 跑前 SHA-256：`{hashlib.sha256(STATE_BEFORE).hexdigest() if STATE_BEFORE is not None else '未取得'}`",
                      f"- 跑后 SHA-256：`{hashlib.sha256(STATE_PATH.read_bytes()).hexdigest() if STATE_PATH.exists() else '文件不存在'}`"])
    if ERROR:
        lines.extend([f"- 错误：`{ERROR}`"])
    REPORT.open("x").write("\n".join(lines) + "\n")


def main():
    global ERROR, STATE_BEFORE, CLAUDE_PROJECTS_BEFORE
    rc = 1
    try:
        STATE_BEFORE = STATE_PATH.read_bytes()
        if CONTROLLER == "claude":
            CLAUDE_PROJECTS_BEFORE = claude_projects(STATE_BEFORE)
        setup()
        start_controller()
        monitor()
        assert_result()
        check_global_state()
        if all(CHECKS.values()):
            rc = 0
    except Exception as exc:
        ERROR = str(exc)
        (BASE / "exception.log").write_text(traceback.format_exc())
        event(f"E2E 失败：{exc}")
    finally:
        try:
            check_global_state()
            if CONTROLLER != "claude" and not CHECKS.get("global_state_unchanged", False):
                rc = 1
        except Exception as exc:
            CHECKS["global_state_unchanged"] = False
            ERROR = f"{ERROR}; 全局状态核对失败：{exc}" if ERROR else f"全局状态核对失败：{exc}"
            rc = 1
        report(rc)
        event(f"报告已写入：{REPORT}；rc={rc}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
