#!/usr/bin/env bash
# qwb-init.sh —— 把 QW buddy 装进一个项目（幂等：已装过不重复追加）
set -euo pipefail

usage() {
  cat <<'EOF'
用法: qwb-init.sh <项目根目录>

把 templates/ 与 bin/ 装进 <项目>/qwbuddy/，建 tasks/ 与 tasks/lessons/，
并把钩子片段追加进 AGENTS.md / CLAUDE.md（幂等，可重复运行）。

选项:
  -h, --help    显示本帮助
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0 ;;
esac
[[ $# -eq 1 ]] || { usage >&2; exit 2; }

[[ -d "$1" ]] || { echo "错误：项目目录不存在：$1" >&2; exit 1; }
ROOT="$(cd "$1" && pwd)"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL="$SRC/../templates"

[[ -d "$TPL" ]] || { echo "错误：找不到模板目录 ${TPL}——本脚本只在 QW buddy 母本仓运行（安装副本里的同名文件属历史残留，请改用母本仓 bin/qwb-init.sh 的绝对路径）" >&2; exit 1; }

mkdir -p "$ROOT/qwbuddy/roles" "$ROOT/qwbuddy/bin" "$ROOT/tasks/lessons"

cp "$TPL/QWBUDDY.md" "$ROOT/qwbuddy/QWBUDDY.md"
cp "$TPL/TASK.md" "$ROOT/qwbuddy/TASK.md"
cp "$TPL"/roles/*.md "$ROOT/qwbuddy/roles/"

# config.sh 可能被主控填过 QWB_CONTROLLER_PANE——已存在就不覆盖；只检测到旧版配置时提示手动迁移
OLD_CONF_NAME="config.json"
if [[ -f "$ROOT/qwbuddy/config.sh" ]]; then
  echo "保留：qwbuddy/config.sh 已存在，不覆盖"
else
  OLD_CONF="$ROOT/qwbuddy/$OLD_CONF_NAME"
  if [[ -f "$OLD_CONF" ]]; then
    echo "提示：检测到旧版 ${OLD_CONF}——新版配置为 bash 可直接 source 的 config.sh，旧文件不自动转换，请手动迁移后删除" >&2
  fi
  cp "$TPL/config.sh" "$ROOT/qwbuddy/config.sh"
fi

# 常驻附页模板：目标已有则不覆盖（可能已被项目主人改成自己的常驻规则），幂等
if [[ -f "$ROOT/qwbuddy/brief-include.md" ]]; then
  echo "保留：qwbuddy/brief-include.md 已存在，不覆盖"
else
  cp "$TPL/brief-include.md" "$ROOT/qwbuddy/brief-include.md"
fi

# 运行时脚本装进目标项目；qwb-init.sh 是母本仓专用安装器，不复制进目标
for s in "$SRC"/qwb-*.sh; do
  [[ "$(basename "$s")" == "qwb-init.sh" ]] && continue
  cp "$s" "$ROOT/qwbuddy/bin/"
done
chmod +x "$ROOT/qwbuddy/bin"/qwb-*.sh

# 派工规则模板：目标已有不覆盖（可能已被项目主人改成自己的派工规则），幂等（同 brief-include 做法）
if [[ -f "$ROOT/qwbuddy/dispatch-rules.json" ]]; then
  echo "保留：qwbuddy/dispatch-rules.json 已存在，不覆盖"
else
  cp "$TPL/dispatch-rules.json" "$ROOT/qwbuddy/dispatch-rules.json"
fi

# 运行态不进 git：往 <项目根>/.gitignore 追加一段（幂等：已有标记行则跳过；文件不存在则新建）。
# 只追加不重排——项目原有条目字节不变。
GITIGN="$ROOT/.gitignore"
if [[ -f "$GITIGN" ]] && grep -qF '# QW buddy 运行态（qwb-init.sh 写入，勿手改本段）' "$GITIGN"; then
  echo "跳过：.gitignore 已有"
else
  if [[ -s "$GITIGN" && -n "$(tail -c1 "$GITIGN")" ]]; then printf '\n' >> "$GITIGN"; fi
  cat >> "$GITIGN" <<'EOF'
# QW buddy 运行态（qwb-init.sh 写入，勿手改本段）
.worktrees/
qwbuddy/.controller.lock/
qwbuddy/.watch
qwbuddy/.watch.lock/
qwbuddy/.hook.lock/
qwbuddy/.hook.err
EOF
  echo "写入：.gitignore 追加 QW buddy 运行态"
fi

# 钩子：已含 qwbuddy/QWBUDDY.md 引用视为已装，跳过
append_hook() {
  local target="$1" hook="$2"
  if [[ -f "$target" ]] && grep -qF 'qwbuddy/QWBUDDY.md' "$target"; then
    echo "跳过：$(basename "$target") 已有 QW buddy 钩子"
  else
    { echo; cat "$TPL/$hook"; } >> "$target"
    echo "写入：$(basename "$target") 追加 QW buddy 钩子"
  fi
}

append_hook "$ROOT/AGENTS.md" agents-hook.md
append_hook "$ROOT/CLAUDE.md" claude-hook.md

# Claude Code Stop hook（值守隐形化）：合并进 .claude/settings.json。
# 幂等（按 command 含 qwb-hook-claude-stop.sh 判重）、不覆盖已有 hooks（其他键原样）；
# 文件不存在则新建；非法 JSON 拒绝写入（qwbuddy/ 其余安装已照常完成，stderr 说明）。
# 用 python3：dict 保插入序 + indent=2 重写后别人的内容字节级不变；不用 jq（不保证装了）。
merge_claude_hook() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "错误：本机无 python3，无法安全合并 .claude/settings.json——该文件未写入；qwbuddy/ 其余部分已装好，可装 python3 后重跑 qwb-init.sh（幂等）或手动添加 Stop hook" >&2
    return 1
  fi
  CLAUDE_SETTINGS="$ROOT/.claude/settings.json" python3 - <<'PYEOF'
import json, os, sys

path = os.environ["CLAUDE_SETTINGS"]
marker = "qwb-hook-claude-stop.sh"
entry = {
    "type": "command",
    "command": 'bash "$CLAUDE_PROJECT_DIR"/qwbuddy/bin/qwb-hook-claude-stop.sh',
    "asyncRewake": True,
    "timeout": 7200,
}

def die(msg):
    sys.stderr.write(
        f"错误：{msg}\n未写入：{path}\n"
        "说明：qwbuddy/ 其余安装已照常完成，仅 Claude Code Stop hook 未写入；"
        "修复该文件后重跑 qwb-init.sh（幂等）即可补上。\n"
    )
    sys.exit(1)

if os.path.exists(path):
    with open(path, encoding="utf-8") as f:
        raw = f.read()
    try:
        data = json.loads(raw)
    except ValueError as e:
        die(f"{path} 不是合法 JSON（{e}）——拒绝写入，原文件保持逐字节不变")
    if not isinstance(data, dict):
        die(f"{path} 顶层不是 JSON 对象，拒绝写入")
else:
    data = {}

hooks = data.setdefault("hooks", {})
if not isinstance(hooks, dict):
    die(f"{path} 的 hooks 不是 JSON 对象，拒绝写入")
stop = hooks.setdefault("Stop", [])
if not isinstance(stop, list):
    die(f"{path} 的 hooks.Stop 不是 JSON 数组，拒绝写入")

def has_qwb(groups):
    for g in groups:
        if isinstance(g, dict):
            for h in g.get("hooks") or []:
                if isinstance(h, dict) and marker in (h.get("command") or ""):
                    return True
    return False

if has_qwb(stop):
    print("跳过：.claude/settings.json 已有 qwb-hook-claude-stop.sh Stop hook（幂等）")
else:
    stop.append({"hooks": [entry]})
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".qwbtmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    os.replace(tmp, path)
    print("写入：.claude/settings.json 合并 Claude Code Stop hook（值守，asyncRewake）")
PYEOF
}

if ! merge_claude_hook; then
  exit 1
fi

echo "完成：QW buddy 已装进 ${ROOT}（账本：${ROOT}/tasks/）"
