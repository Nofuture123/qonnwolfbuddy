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

# 运行时脚本装进目标项目；qwb-init.sh 是母本仓专用安装器，不复制进目标
for s in "$SRC"/qwb-*.sh; do
  [[ "$(basename "$s")" == "qwb-init.sh" ]] && continue
  cp "$s" "$ROOT/qwbuddy/bin/"
done
chmod +x "$ROOT/qwbuddy/bin"/qwb-*.sh

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

echo "完成：QW buddy 已装进 ${ROOT}（账本：${ROOT}/tasks/）"
